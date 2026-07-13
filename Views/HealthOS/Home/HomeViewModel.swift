import Foundation
import HealthGraphCore

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var sleepSummary: String?
    @Published private(set) var stepsSummary: String?
    @Published private(set) var backfillSummary: (events: Int, categories: Int)?

    private let store: any EventStore
    private let timeZone: TimeZone
    private let now: () -> Date
    private static let dismissKey = "hg.home.backfillCardDismissed"
    private static let firstSeenKey = "hg.home.backfillFirstSeen"

    init(store: any EventStore, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.timeZone = timeZone
        self.now = now
    }

    func refresh() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now())

        // Sleep: 18:00 yesterday -> 12:00 today, asleep stages only.
        let sleepWindow = DateInterval(start: today.addingTimeInterval(-6 * 3600),
                                       end: today.addingTimeInterval(12 * 3600))
        let asleep: Set<String> = ["asleepCore", "asleepDeep", "asleepREM", "asleepUnspecified"]
        if let sleepEvents = try? await store.events(in: sleepWindow, category: .sleep) {
            let minutes = sleepEvents
                .filter { asleep.contains($0.subtype ?? "") }
                .compactMap(\.value)
                .reduce(0, +)
            sleepSummary = minutes > 0 ? EventDisplay.durationString(minutes: minutes) : nil
        } else {
            sleepSummary = nil
        }

        // Steps: today's daily stat.
        let dayWindow = DateInterval(start: today, end: today.addingTimeInterval(86_400))
        if let exercise = try? await store.events(in: dayWindow, category: .exercise),
           let steps = exercise.first(where: { $0.subtype == "steps" })?.value {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            // Deterministic grouping regardless of locale (tests assert "8,214").
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            stepsSummary = formatter.string(from: NSNumber(value: Int(steps)))
        } else {
            stepsSummary = nil
        }

        // Backfill summary card: first-week-only welcome (spec §2), dismissible.
        let defaults = UserDefaults.standard
        let firstSeen = (defaults.object(forKey: Self.firstSeenKey) as? Date) ?? {
            let stamp = now()
            defaults.set(stamp, forKey: Self.firstSeenKey)
            return stamp
        }()
        let withinFirstWeek = now().timeIntervalSince(firstSeen) < 7 * 86_400
        if !defaults.bool(forKey: Self.dismissKey), withinFirstWeek,
           let counts = try? await store.countsByCategory() {
            let total = counts.values.reduce(0, +)
            backfillSummary = total > 0 ? (total, counts.filter { $0.value > 0 }.count) : nil
        } else {
            backfillSummary = nil
        }
    }

    func dismissBackfillCard() {
        UserDefaults.standard.set(true, forKey: Self.dismissKey)
        backfillSummary = nil
    }
}
