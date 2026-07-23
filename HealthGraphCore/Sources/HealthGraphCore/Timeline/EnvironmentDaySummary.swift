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

    /// Weather subtypes where an observed completed-day reading supersedes the
    /// morning forecast IN DISPLAY for the same local day ("observed wins").
    public static let observedPrecedenceSubtypes: Set<String> = ["temperature", "humidity"]

    /// Presentation-only precedence: per local day + subtype, when at least one
    /// `.observedCompletedDay` event exists, that day+subtype's `.forecast` events
    /// are dropped and duplicate observed events resolve deterministically (latest
    /// `createdAt`, then `id.uuidString`). ONLY those two drops are licensed —
    /// any other or missing provenance passes through untouched. Resolved
    /// independently per day+subtype — an observed temperature never suppresses
    /// humidity or another day. Stored events are untouched; mining reads the
    /// store, not this filter.
    public static func observedPrecedenceFiltered(_ events: [HealthEvent], timeZone: TimeZone) -> [HealthEvent] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        struct Key: Hashable { let day: Date; let subtype: String }
        var winner: [Key: HealthEvent] = [:]
        for e in events where e.category == .environment
            && observedPrecedenceSubtypes.contains(e.subtype ?? "")
            && e.temporalProvenance == .observedCompletedDay {
            let key = Key(day: calendar.startOfDay(for: e.timestamp), subtype: e.subtype ?? "")
            if let cur = winner[key] {
                if (e.createdAt, e.id.uuidString) > (cur.createdAt, cur.id.uuidString) { winner[key] = e }
            } else {
                winner[key] = e
            }
        }
        guard !winner.isEmpty else { return events }
        return events.filter { e in
            guard e.category == .environment,
                  let subtype = e.subtype, observedPrecedenceSubtypes.contains(subtype),
                  let w = winner[Key(day: calendar.startOfDay(for: e.timestamp), subtype: subtype)]
            else { return true }               // not a precedence subtype, or no observed that day → untouched
            switch e.temporalProvenance {
            case .forecast?:             return false          // superseded by the observed sibling
            case .observedCompletedDay?: return e.id == w.id   // deterministic winner among observed
            default:                     return true           // .currentSnapshot / nil / future kinds: not ours to drop
            }
        }
    }

    /// Folds `.environment` events into one summary per local calendar day, newest
    /// day first. Pure; accepts any unsorted slice; input order never affects the
    /// result. Non-environment events are ignored. (All env events for a day share
    /// one timestamp, so any event's timestamp is the day's row-sort key.)
    public static func summaries(from events: [HealthEvent], timeZone: TimeZone) -> [EnvironmentDaySummary] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let env = observedPrecedenceFiltered(events, timeZone: timeZone)
            .filter { $0.category == .environment
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
