import Foundation

/// One night or nap: a display-time aggregation of contiguous raw `.sleep`
/// stage events. Sessions are never persisted — the raw segments stay the
/// source of truth in the graph (spec 2026-07-15, Approach A).
public struct SleepSession: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case night, nap }

    public let start: Date               // earliest segment start (bed time)
    public let end: Date                 // latest segment end (wake time)
    public let kind: Kind
    public let coreMinutes: Double
    public let deepMinutes: Double
    public let remMinutes: Double
    public let unspecifiedMinutes: Double
    public let awakeMinutes: Double
    public let inBedMinutes: Double
    public let segmentCount: Int

    /// Time actually asleep. `inBed` overlaps the stages and is never included.
    public var asleepMinutes: Double { coreMinutes + deepMinutes + remMinutes + unspecifiedMinutes }

    /// Deterministic across rebuilds of the same slice — drives SwiftUI row
    /// identity and the Timeline's expansion state.
    public var id: String { "sleep-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))" }

    public init(start: Date, end: Date, kind: Kind,
                coreMinutes: Double, deepMinutes: Double, remMinutes: Double,
                unspecifiedMinutes: Double, awakeMinutes: Double, inBedMinutes: Double,
                segmentCount: Int) {
        self.start = start; self.end = end; self.kind = kind
        self.coreMinutes = coreMinutes; self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes; self.unspecifiedMinutes = unspecifiedMinutes
        self.awakeMinutes = awakeMinutes; self.inBedMinutes = inBedMinutes
        self.segmentCount = segmentCount
    }
}

public enum SleepSessionBuilder {
    /// A hole in the sleep data of at least this long starts a new session.
    /// Recorded `awake` segments are data, not holes — they extend the chain.
    public static let sessionGap: TimeInterval = 3600

    /// Folds raw `.sleep` duration events into sessions, sorted ascending by
    /// `end`. Point `.sleep` events (no `endTimestamp`) are ignored here and
    /// pass through as raw rows in `TimelineDayBuilder`. Pure; accepts any
    /// unsorted slice; input order never affects the result.
    public static func sessions(from events: [HealthEvent], timeZone: TimeZone) -> [SleepSession] {
        let segments = events
            .filter { $0.category == .sleep && $0.endTimestamp != nil }
            .sorted { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }
        guard !segments.isEmpty else { return [] }

        var groups: [[HealthEvent]] = []
        var current = [segments[0]]
        var furthestEnd = segments[0].endTimestamp!
        for segment in segments.dropFirst() {
            if segment.timestamp.timeIntervalSince(furthestEnd) < sessionGap {
                current.append(segment)
                furthestEnd = max(furthestEnd, segment.endTimestamp!)
            } else {
                groups.append(current)
                current = [segment]
                furthestEnd = segment.endTimestamp!
            }
        }
        groups.append(current)
        return groups.map { session(from: $0, timeZone: timeZone) }.sorted { $0.end < $1.end }
    }

    private static func session(from segments: [HealthEvent], timeZone: TimeZone) -> SleepSession {
        var totals: [String: Double] = [:]
        var start = segments[0].timestamp
        var end = segments[0].endTimestamp!
        for segment in segments {
            let segmentEnd = segment.endTimestamp!
            start = min(start, segment.timestamp)
            end = max(end, segmentEnd)
            // Real interval, not the stored `value` (Int-truncated at ingest).
            totals[segment.subtype ?? "", default: 0] += segmentEnd.timeIntervalSince(segment.timestamp) / 60
        }
        let core = totals["asleepCore"] ?? 0
        let deep = totals["asleepDeep"] ?? 0
        let rem = totals["asleepREM"] ?? 0
        let unspecified = totals["asleepUnspecified"] ?? 0
        let inBed = totals["inBed"] ?? 0
        let asleep = core + deep + rem + unspecified
        return SleepSession(start: start, end: end,
                            kind: kind(start: start, end: end,
                                       asleepBasis: asleep > 0 ? asleep : inBed,
                                       timeZone: timeZone),
                            coreMinutes: core, deepMinutes: deep, remMinutes: rem,
                            unspecifiedMinutes: unspecified,
                            awakeMinutes: totals["awake"] ?? 0,
                            inBedMinutes: inBed,
                            segmentCount: segments.count)
    }

    /// Nap iff short (< 3 h), fully inside one local day, starting 06:00 or
    /// later and ending by 21:00. Everything else — including a 2 h
    /// crash-sleep at 1 AM — is a night (spec §4.4).
    private static func kind(start: Date, end: Date, asleepBasis: Double,
                             timeZone: TimeZone) -> SleepSession.Kind {
        guard asleepBasis < 180 else { return .night }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard calendar.isDate(start, inSameDayAs: end) else { return .night }
        let s = calendar.dateComponents([.hour, .minute], from: start)
        let e = calendar.dateComponents([.hour, .minute], from: end)
        let startMinutes = (s.hour ?? 0) * 60 + (s.minute ?? 0)
        let endMinutes = (e.hour ?? 0) * 60 + (e.minute ?? 0)
        return startMinutes >= 6 * 60 && endMinutes <= 21 * 60 ? .nap : .night
    }
}
