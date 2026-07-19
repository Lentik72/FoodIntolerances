import SwiftUI
import HealthGraphCore

@MainActor
final class MoodCheckInModel: ObservableObject {
    @Published private(set) var todaysMood: (level: MoodLevel, at: Date)?
    @Published private(set) var dismissedToday: Bool

    private let capture: CaptureService
    private let store: GRDBEventStore
    private let defaults: UserDefaults
    private let calendar: Calendar   // injectable so "today" is timezone-deterministic in tests
    private let now: () -> Date
    private var lastLoggedID: UUID?
    private static let dismissKey = "hg.home.moodDismissedDay"

    init(database: AppDatabase, defaults: UserDefaults = .standard,
         calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.capture = CaptureService(database: database)
        self.store = GRDBEventStore(database: database)
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.dismissedToday = (defaults.string(forKey: Self.dismissKey) == Self.dayKey(now(), calendar))
    }

    // Static (takes the calendar) so it's callable while `self` is still initializing.
    private static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    private var todayInterval: DateInterval {
        let n = now()
        return calendar.dateInterval(of: .day, for: n)
            ?? DateInterval(start: calendar.startOfDay(for: n), end: n)
    }

    /// Load the latest mood logged today (so the confirmed state survives app relaunch within the day).
    func load() async {
        dismissedToday = (defaults.string(forKey: Self.dismissKey) == Self.dayKey(now(), calendar))
        let events = (try? await store.events(in: todayInterval, category: .mood)) ?? []
        if let latest = events.max(by: { $0.timestamp < $1.timestamp }),
           let v = latest.value, let level = MoodLevel(rawValue: Int(v)) {
            todaysMood = (level, latest.timestamp)
            lastLoggedID = latest.id
        } else {
            todaysMood = nil; lastLoggedID = nil
        }
    }

    func log(_ level: MoodLevel) async {
        guard let e = try? await capture.logMood(level: level, at: now(), note: nil) else { return }
        todaysMood = (level, e.timestamp)
        lastLoggedID = e.id
    }

    func undo() async {
        guard let id = lastLoggedID else { return }
        try? await store.softDelete(id: id)
        lastLoggedID = nil
        await load()
    }

    func dismissForToday() {
        defaults.set(Self.dayKey(now(), calendar), forKey: Self.dismissKey)
        dismissedToday = true
    }
}

/// Ambient Home "How are you feeling?" quick-check — the primary, low-friction mood surface.
/// One tap logs; never nags; "not now" tucks it away for the day.
struct MoodCheckInView: View {
    @StateObject private var model = MoodCheckInModel(database: HealthGraphProvider.shared)
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator

    var body: some View {
        Group {
            if !model.dismissedToday {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("How are you feeling?")
                            .font(HealthTheme.sectionHeader()).foregroundStyle(HealthTheme.ink)
                        Spacer()
                        Button { model.dismissForToday() } label: {
                            Image(systemName: "xmark").font(.footnote).foregroundStyle(HealthTheme.inkMuted)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Not now")
                    }
                    if let today = model.todaysMood {
                        HStack {
                            Text("Felt \(today.level.label) \(today.at.formatted(date: .omitted, time: .shortened)) — tap to update")
                                .font(.subheadline).foregroundStyle(HealthTheme.inkSecondary)
                            Spacer()
                            Button("Undo") { Task { await model.undo(); captureCoordinator.saveCompleted() } }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(HealthTheme.accent)
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(MoodLevel.allCases, id: \.rawValue) { level in
                            Button {
                                Task { await model.log(level); captureCoordinator.saveCompleted() }
                            } label: {
                                Text(level.emoji).font(.largeTitle)
                                    .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                            }
                            .accessibilityLabel(level.label)
                        }
                    }
                }
                .padding(16).hgCard()
            }
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .onChange(of: captureCoordinator.lastCaptureAt) { _, _ in
            Task { await model.load() }
        }
    }
}

#Preview {
    MoodCheckInView().environmentObject(CaptureCoordinator())
        .padding().background(HealthTheme.paper)
}
