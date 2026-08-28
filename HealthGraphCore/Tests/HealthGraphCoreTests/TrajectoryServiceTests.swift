import Foundation
import Testing
@testable import HealthGraphCore

struct TrajectoryServiceTests {
    /// 2025-08-12 12:00:00 UTC — a Tuesday noon, fixed so every fixture below
    /// derives its dates from `WeeklyBucketing.windowStart` rather than
    /// hand-computed epoch offsets.
    static let now = Date(timeIntervalSince1970: 1_755_000_000)

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // MARK: - Fixtures (deterministic, anchored to `now`, no RNG)

    /// A night that begins 23:00 the calendar day BEFORE the 13-week window
    /// opens and ends 8 hours later, squarely inside the window's first day.
    /// If the fetch started exactly at the window boundary (instead of one
    /// day early) this segment would never be read at all, and the session
    /// would lose its first-night data entirely.
    private func nightSpanningWindowStart() -> [HealthEvent] {
        let windowStart = WeeklyBucketing.windowStart(weeksBack: TrendWindow.weeks13.rawValue,
                                                       asOf: Self.now, calendar: utc)
        let bedTime = windowStart.addingTimeInterval(-3_600)      // 23:00 the day before
        let wake = bedTime.addingTimeInterval(8 * 3_600)          // 8 hours later
        return [HealthEvent(timestamp: bedTime, endTimestamp: wake, category: .sleep,
                            subtype: "asleepCore", value: 8 * 3_600, unit: "s", source: .healthKit)]
    }

    /// One weight reading per week for the first 6 of the 13-week window —
    /// thin but real data, six distinct weeks.
    private func sixWeeksWeight() -> [HealthEvent] {
        let windowStart = WeeklyBucketing.windowStart(weeksBack: TrendWindow.weeks13.rawValue,
                                                       asOf: Self.now, calendar: utc)
        return (0..<6).map { week in
            let day = windowStart.addingTimeInterval(Double(week) * 7 * 86_400 + 12 * 3_600)
            return HealthEvent(timestamp: day, category: .bodyMetric, subtype: "weight",
                               value: 70.0 + Double(week), unit: "kg", source: .healthKit)
        }
    }

    /// A daily HRV reading across the ENTIRE 13-week window — dense, co-seeded
    /// alongside thin fixtures so an assertion that "some series is present"
    /// cannot pass by accident over an empty result set.
    private func fullHRV() -> [HealthEvent] {
        let windowStart = WeeklyBucketing.windowStart(weeksBack: TrendWindow.weeks13.rawValue,
                                                       asOf: Self.now, calendar: utc)
        let dayCount = TrendWindow.weeks13.rawValue * 7
        return (0..<dayCount).map { offset in
            let day = windowStart.addingTimeInterval(Double(offset) * 86_400 + 12 * 3_600)
            return HealthEvent(timestamp: day, category: .vitals, subtype: "hrv",
                               value: 45.0, unit: "ms", source: .healthKit)
        }
    }

    /// Three steady weeks of ~70 kg weight, except one day (inside the first
    /// week) where the scale reads 200 kg — a suitcase left on it. Six of
    /// that week's seven days stay at 70, so the week's DAY-MEDIAN-of-medians
    /// still lands at 70; only a raw-value range would surface the 200.
    private func steadyWeightWithOneOutlierDay() -> [HealthEvent] {
        let windowStart = WeeklyBucketing.windowStart(weeksBack: TrendWindow.weeks13.rawValue,
                                                       asOf: Self.now, calendar: utc)
        return (0..<21).map { day in
            let value = day == 3 ? 200.0 : 70.0
            let ts = windowStart.addingTimeInterval(Double(day) * 86_400 + 12 * 3_600)
            return HealthEvent(timestamp: ts, category: .bodyMetric, subtype: "weight",
                               value: value, unit: "kg", source: .healthKit)
        }
    }

    // MARK: - Store/service fixture helpers

    private func store(_ events: [HealthEvent] = []) async throws -> GRDBEventStore {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        try await store.save(events)
        return store
    }

    private func service(_ events: [HealthEvent]) async throws -> TrajectoryService {
        TrajectoryService(eventStore: try await store(events), calendar: utc)
    }

    // MARK: - Tests

    @Test func theCorpusIsReadOncePerCategoryRegardlessOfSeriesCount() async throws {
        // Call-count guarded, following InsightsViewModelTests. Exactly four,
        // with distinct non-nil categories: six would be the N+1, one would be a
        // nil-category fetch of the whole corpus.
        let counting = CountingEventStore(wrapping: try await store())
        _ = try await TrajectoryService(eventStore: counting, calendar: utc)
            .snapshots(window: .weeks52, asOf: Self.now)
        #expect(counting.calls.value.count == 4)
        #expect(Set(counting.calls.value.map(\.category)).count == 4)
        #expect(!counting.calls.value.contains { $0.category == nil })
    }

    @Test func theFetchStartsOneDayEarlyForBoundarySpanningSleep() async throws {
        // A night beginning 23:00 the day before the window starts must keep its
        // full duration on the first wake-day inside the window.
        let r = try await service(nightSpanningWindowStart())
            .snapshots(window: .weeks13, asOf: Self.now).first { $0.series == .sleepDuration }!
        #expect(abs(r.weeks.first!.value - 8.0) < 0.01)
    }

    @Test func thinDataStillGetsASnapshotAndItsCoverageSaysSo() async throws {
        // Six weeks of weight in a 13-week window: charted, with honest coverage.
        // Co-seeded with a dense series so the assertion cannot pass over [].
        let rs = try await service(sixWeeksWeight() + fullHRV())
            .snapshots(window: .weeks13, asOf: Self.now)
        let weight = rs.first { $0.series == .weight }!
        #expect(weight.coverage.weeksWithData == 6)
        #expect(rs.contains { $0.series == .hrv })
    }

    @Test func aSeriesWithNoDataIsAbsent() async throws {
        let rs = try await service(fullHRV()).snapshots(window: .weeks13, asOf: Self.now)
        #expect(!rs.isEmpty)
        #expect(!rs.contains { $0.series == .weight })
    }

    @Test func theRangeIsOverWeeklyMediansNotRawReadings() async throws {
        // One 200 kg suitcase-on-the-scale day must not become the range.
        let r = try await service(steadyWeightWithOneOutlierDay())
            .snapshots(window: .weeks13, asOf: Self.now).first { $0.series == .weight }!
        #expect(r.rangeHigh < 100)
    }
}

/// Wraps a real `EventStore` and records every `events(in:category:)` call
/// (interval + category) in a thread-safe box, following the call-count
/// precedent in `InsightsViewModelTests.evidenceIsFetchedOnceForTheWholeFeedNotOncePerCard`.
/// Every other protocol method is forwarded untouched — `TrajectoryService`
/// only ever calls `events(in:category:)`, but this must still satisfy the
/// full `EventStore` conformance.
final class CountingEventStore: EventStore {
    struct Call: Sendable {
        let interval: DateInterval
        let category: EventCategory?
    }

    /// `@unchecked Sendable`: safety comes from the internal lock, not from
    /// the compiler proving isolation — the same pattern as `Counter` in
    /// `InsightsViewModelTests`, extended with a lock since this box records
    /// a growing array rather than incrementing a single value.
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Call] = []
        var value: [Call] {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
        func append(_ call: Call) {
            lock.lock(); defer { lock.unlock() }
            storage.append(call)
        }
    }

    let calls = Box()
    private let wrapped: any EventStore

    init(wrapping store: any EventStore) {
        self.wrapped = store
    }

    func events(in interval: DateInterval, category: EventCategory?) async throws -> [HealthEvent] {
        calls.append(Call(interval: interval, category: category))
        return try await wrapped.events(in: interval, category: category)
    }

    // MARK: Forwarded, unrecorded

    func save(_ event: HealthEvent) async throws { try await wrapped.save(event) }
    func save(_ events: [HealthEvent]) async throws { try await wrapped.save(events) }
    func event(id: UUID) async throws -> HealthEvent? { try await wrapped.event(id: id) }
    func recentEvents(limit: Int) async throws -> [HealthEvent] { try await wrapped.recentEvents(limit: limit) }
    func softDelete(id: UUID) async throws { try await wrapped.softDelete(id: id) }
    func count() async throws -> Int { try await wrapped.count() }
    func countsByCategory() async throws -> [String: Int] { try await wrapped.countsByCategory() }
    func countsBySource() async throws -> [String: Int] { try await wrapped.countsBySource() }
    func eventsPage(before cursor: TimelineCursor?, limit: Int,
                    categories: Set<EventCategory>?, sources: Set<EventSource>?) async throws -> [HealthEvent] {
        try await wrapped.eventsPage(before: cursor, limit: limit, categories: categories, sources: sources)
    }
    func restore(id: UUID) async throws { try await wrapped.restore(id: id) }
    func searchEvents(matching query: String, limit: Int) async throws -> [HealthEvent] {
        try await wrapped.searchEvents(matching: query, limit: limit)
    }
    func environmentEvents(subtypes: Set<String>, from: Date, through: Date) async throws -> [HealthEvent] {
        try await wrapped.environmentEvents(subtypes: subtypes, from: from, through: through)
    }
}
