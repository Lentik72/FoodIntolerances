import Foundation

/// One day's auto-logged environment readings, aggregated for a single collapsed
/// Timeline row. A display-time aggregate — the raw `.environment` events stay the
/// source of truth in the graph. Read-only (never editable or deletable).
public struct EnvironmentDaySummary: Equatable, Sendable, Identifiable {
    public let dayStart: Date          // local start-of-day bucket
    public let timestamp: Date         // the shared per-day env timestamp (row sort key)
    public let events: [HealthEvent]   // the day's .environment events, canonical subtype order

    /// Deterministic across rebuilds of the same slice — drives SwiftUI row
    /// identity and the Timeline's expansion state.
    public var id: String { "env-\(Int(dayStart.timeIntervalSince1970))" }

    public init(dayStart: Date, timestamp: Date, events: [HealthEvent]) {
        self.dayStart = dayStart
        self.timestamp = timestamp
        self.events = events
    }
}

public enum EnvironmentDaySummaryBuilder {
    /// Canonical detail/display order. Unknown subtypes sort last (stable).
    public static let subtypeOrder = ["temperature", "humidity", "airQuality", "pressure",
                                      "pressureDrop", "moonPhase", "mercuryRetrograde"]

    /// Subtypes that may still exist as stored rows but must never display.
    /// `season` is retired: it was never mined (no exposure source exists) and its
    /// calculation was Northern-Hemisphere-only. It is a pure date-fact, so a future
    /// hemisphere-aware exposure could regenerate the history via backfill.
    public static let retiredSubtypes: Set<String> = ["season"]

    /// Folds `.environment` events into one summary per local calendar day, newest
    /// day first. Pure; accepts any unsorted slice; input order never affects the
    /// result. Non-environment events are ignored. (All env events for a day share
    /// one timestamp, so any event's timestamp is the day's row-sort key.)
    public static func summaries(from events: [HealthEvent], timeZone: TimeZone) -> [EnvironmentDaySummary] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let env = events.filter { $0.category == .environment
            && !retiredSubtypes.contains($0.subtype ?? "") }
        guard !env.isEmpty else { return [] }
        let byDay = Dictionary(grouping: env) { calendar.startOfDay(for: $0.timestamp) }
        return byDay.map { day, evs in
            let sorted = evs.sorted { (orderIndex($0), $0.id.uuidString) < (orderIndex($1), $1.id.uuidString) }
            return EnvironmentDaySummary(dayStart: day, timestamp: sorted.first?.timestamp ?? day, events: sorted)
        }.sorted { $0.dayStart > $1.dayStart }
    }

    private static func orderIndex(_ e: HealthEvent) -> Int {
        subtypeOrder.firstIndex(of: e.subtype ?? "") ?? subtypeOrder.count
    }
}
