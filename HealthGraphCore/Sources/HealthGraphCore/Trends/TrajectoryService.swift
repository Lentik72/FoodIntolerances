import Foundation

/// Assembles `TrajectorySnapshot`s for every catalog series that has data in
/// the requested window. The only type in this package that knows about both
/// the database (`EventStore`) and the bucketing (`WeeklyBucketing`) — chart
/// assembly is extract → bucket → range → package, no further computation
/// (see the round's decision record:
/// docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md).
public struct TrajectoryService: Sendable {
    private let eventStore: any EventStore
    private let calendar: Calendar

    /// `calendar` is injected, not implied: production passes the user's
    /// current calendar, because a 23:30 weigh-in belongs to different days
    /// — and different weeks — in UTC vs. local time, and this app
    /// timezone-stamps events precisely because it cares.
    public init(eventStore: any EventStore, calendar: Calendar) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    /// Reads the corpus ONCE per distinct `EventCategory` the catalog needs
    /// — four calls (`.bodyMetric`, `.sleep`, `.exercise`, `.vitals`; three
    /// series share `.vitals`), never once per series (six calls would be
    /// the N+1 shape this package already paid ~6.9 s per ten Insights cards
    /// to fix — see `InsightsViewModelTests`), and never a single
    /// nil-category fetch (that reads the ENTIRE corpus — symptoms, mood,
    /// environment, tens of thousands of events — just to chart six series).
    ///
    /// Any data in the window produces a snapshot; there is no coverage
    /// gate — chartable was decoupled from verdict-eligible, and there is no
    /// verdict here. A series with nothing in the window is simply omitted.
    /// Output is in catalog order (`TrajectorySeries.allCases`).
    public func snapshots(window: TrendWindow, asOf: Date) async throws -> [TrajectorySnapshot] {
        let windowStart = WeeklyBucketing.windowStart(weeksBack: window.rawValue, asOf: asOf, calendar: calendar)

        // The fetch interval starts one calendar day before the window
        // start, not at the window start itself: a night session that
        // begins the evening before the window opens (e.g. 23:00) must keep
        // its earlier segments, or SleepSessionBuilder never sees them and
        // that first night's session is truncated or lost. WeeklyBucketing's
        // own window filter (inside `bucket`) then drops that extra day for
        // every other series — a raw .bodyMetric/.exercise/.vitals reading
        // has no cross-boundary session to protect.
        let fetchStart = calendar.date(byAdding: .day, value: -1, to: windowStart)!
        let interval = DateInterval(start: fetchStart, end: asOf)

        var eventsByCategory: [EventCategory: [HealthEvent]] = [:]
        for category in Self.categoriesInCatalogOrder {
            eventsByCategory[category] = try await eventStore.events(in: interval, category: category)
        }

        return TrajectorySeries.allCases.compactMap { series in
            let events = eventsByCategory[series.category] ?? []
            let dailyPoints = series.dailyPoints(from: events, calendar: calendar)
            let (weeks, coverage) = WeeklyBucketing.bucket(
                dailyPoints, weeksBack: window.rawValue, asOf: asOf, calendar: calendar
            )
            guard !weeks.isEmpty else { return nil }
            let medians = weeks.map(\.value)
            return TrajectorySnapshot(
                series: series, window: window, weeks: weeks, coverage: coverage,
                rangeLow: medians.min()!, rangeHigh: medians.max()!
            )
        }
    }

    /// The catalog's distinct `EventCategory` values, in first-occurrence
    /// (catalog) order — this list IS the read budget: exactly one
    /// `events(in:category:)` call per entry, four total.
    private static let categoriesInCatalogOrder: [EventCategory] = {
        var seen = Set<EventCategory>()
        return TrajectorySeries.allCases.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }()
}
