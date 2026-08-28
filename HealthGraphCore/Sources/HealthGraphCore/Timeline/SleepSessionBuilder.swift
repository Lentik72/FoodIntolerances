import Foundation

/// One night or nap: a display-time aggregation of contiguous raw `.sleep`
/// stage events. Sessions are never persisted — the raw segments stay the
/// source of truth in the graph (spec 2026-07-15, Approach A).
public struct SleepSession: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case night, nap }

    public let start: Date               // earliest segment start (bed time)
    public let end: Date                 // latest segment end (wake time)
    public let kind: Kind
    /// Per-stage totals for display. Each is the naive sum of that stage's
    /// segments and is NOT deduplicated: two sources both recording e.g.
    /// `asleepCore` over the same hour double-count it here. Approximate
    /// when sources overlap — do not derive `asleepMinutes` from these.
    public let coreMinutes: Double
    public let deepMinutes: Double
    public let remMinutes: Double
    public let unspecifiedMinutes: Double
    public let awakeMinutes: Double
    public let inBedMinutes: Double
    public let segmentCount: Int

    /// Time actually asleep: the union of every asleep-stage segment
    /// (core/deep/rem/unspecified), overlapping segments merged so a second
    /// tracker covering the same hours never adds to the total. `inBed`
    /// overlaps the stages and is never included.
    public let asleepMinutes: Double

    /// Deterministic across rebuilds of the same slice — drives SwiftUI row
    /// identity and the Timeline's expansion state.
    public var id: String { "sleep-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))" }

    public init(start: Date, end: Date, kind: Kind,
                coreMinutes: Double, deepMinutes: Double, remMinutes: Double,
                unspecifiedMinutes: Double, awakeMinutes: Double, inBedMinutes: Double,
                asleepMinutes: Double, segmentCount: Int) {
        self.start = start; self.end = end; self.kind = kind
        self.coreMinutes = coreMinutes; self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes; self.unspecifiedMinutes = unspecifiedMinutes
        self.awakeMinutes = awakeMinutes; self.inBedMinutes = inBedMinutes
        self.asleepMinutes = asleepMinutes
        self.segmentCount = segmentCount
    }
}

public enum SleepSessionBuilder {
    /// A hole in the sleep data of at least this long starts a new session.
    /// Recorded `awake` segments are data, not holes — they extend the chain.
    public static let sessionGap: TimeInterval = 3600

    /// Subtypes that count as time asleep. `inBed` and `awake` are excluded.
    private static let asleepStageSubtypes: Set<String> = [
        "asleepCore", "asleepDeep", "asleepREM", "asleepUnspecified"
    ]

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
        // Two sources can each claim the same hour of sleep (same stage from
        // two devices, or different stages — e.g. a watch's staged sleep and
        // a ring's `asleepUnspecified` — over the same window). Union the
        // raw segments rather than summing the per-stage totals above, and
        // clamp to the session's own span as a last-resort guard: you cannot
        // be asleep longer than the night lasted.
        let asleep = min(unionMinutes(ofAsleepStages: segments), end.timeIntervalSince(start) / 60)
        return SleepSession(start: start, end: end,
                            kind: kind(start: start, end: end,
                                       asleepBasis: asleep > 0 ? asleep : inBed,
                                       timeZone: timeZone),
                            coreMinutes: core, deepMinutes: deep, remMinutes: rem,
                            unspecifiedMinutes: unspecified,
                            awakeMinutes: totals["awake"] ?? 0,
                            inBedMinutes: inBed,
                            asleepMinutes: asleep,
                            segmentCount: segments.count)
    }

    /// Merges overlapping (or touching) asleep-stage intervals, regardless of
    /// subtype or source, and returns the total covered minutes.
    private static func unionMinutes(ofAsleepStages segments: [HealthEvent]) -> Double {
        let intervals = segments
            .filter { asleepStageSubtypes.contains($0.subtype ?? "") }
            .map { ($0.timestamp, $0.endTimestamp!) }
            .sorted { $0.0 < $1.0 }
        guard var runStart = intervals.first?.0, var runEnd = intervals.first?.1 else { return 0 }

        var total = 0.0
        for (segStart, segEnd) in intervals.dropFirst() {
            if segStart <= runEnd {
                runEnd = max(runEnd, segEnd)
            } else {
                total += runEnd.timeIntervalSince(runStart) / 60
                runStart = segStart
                runEnd = segEnd
            }
        }
        total += runEnd.timeIntervalSince(runStart) / 60
        return total
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
