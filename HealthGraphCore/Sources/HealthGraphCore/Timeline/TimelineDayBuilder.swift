import Foundation

public struct SeverityPoint: Equatable, Sendable {
    public let time: Date
    public let value: Double
    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

/// One visible Timeline row: a raw event or an aggregated sleep session.
public enum TimelineItem: Identifiable, Equatable, Sendable {
    case event(HealthEvent)
    case sleepSession(SleepSession)
    case environmentSummary(EnvironmentDaySummary)

    public var id: String {
        switch self {
        case .event(let e): e.id.uuidString
        case .sleepSession(let s): s.id
        case .environmentSummary(let s): s.id
        }
    }

    /// Where the row sorts within its day: events by start, sessions by wake,
    /// environment summaries by their shared per-day env timestamp.
    public var sortDate: Date {
        switch self {
        case .event(let e): e.timestamp
        case .sleepSession(let s): s.end
        case .environmentSummary(let s): s.timestamp
        }
    }
}

public struct TimelineDay: Identifiable, Equatable, Sendable {
    public let dayStart: Date
    public let items: [TimelineItem]
    public let severityPoints: [SeverityPoint]
    public var id: Date { dayStart }

    /// The raw events among `items` (sessions excluded) — the accessor most
    /// existing consumers (detail lookup by id, tests) still want.
    public var events: [HealthEvent] {
        items.compactMap { if case .event(let e) = $0 { e } else { nil } }
    }

    public init(dayStart: Date, items: [TimelineItem], severityPoints: [SeverityPoint]) {
        self.dayStart = dayStart
        self.items = items
        self.severityPoints = severityPoints
    }
}

public enum TimelineDayBuilder {
    /// Groups a slice of events into local-calendar days, newest day first.
    ///
    /// With `sessionizeSleep` (browse mode, the default) `.sleep` DURATION
    /// events leave the row stream and come back as ONE `SleepSession` item
    /// bucketed under the wake-up day (`startOfDay(session.end)`) — so a
    /// session row can live in a different day bucket than some of its
    /// segments started in. Point `.sleep` events pass through as raw rows.
    /// Search passes `false`: results are a filtered subset, and sessionizing
    /// a subset would display wrong totals.
    ///
    /// With `groupEnvironment` (browse mode, the default) `.environment` events
    /// leave the row stream and come back as ONE `EnvironmentDaySummary` item
    /// per local calendar day. Search passes `false`: results are a filtered
    /// subset, and summarizing a subset would misrepresent the day.
    public static func days(from events: [HealthEvent], timeZone: TimeZone,
                            sessionizeSleep: Bool = true,
                            groupEnvironment: Bool = true) -> [TimelineDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        // Stored rows of retired env subtypes (season) must never display, in ANY
        // mode — raw/search rows included. Filtered here so no caller can leak
        // them; the summary builder re-filters for its own public callers.
        let visibleEvents = events.filter {
            !($0.category == .environment &&
              EnvironmentDaySummaryBuilder.retiredSubtypes.contains($0.subtype ?? ""))
        }

        // Sleep duration events feed the session builder INCLUDING sub-minute
        // fragments — totals must be exact even though such rows never render.
        let isSessionizable: (HealthEvent) -> Bool = { $0.category == .sleep && $0.endTimestamp != nil }
        let sessions = sessionizeSleep
            ? SleepSessionBuilder.sessions(from: visibleEvents.filter(isSessionizable), timeZone: timeZone)
                // Parity with the >=60s row filter below: an isolated sub-minute
                // fragment must not become a permanent "0m" session row.
                .filter { $0.end.timeIntervalSince($0.start) >= 60 }
            : []
        let summaries = groupEnvironment
            ? EnvironmentDaySummaryBuilder.summaries(from: visibleEvents, timeZone: timeZone)
            : []
        var rowEvents = sessionizeSleep ? visibleEvents.filter { !isSessionizable($0) } : visibleEvents
        if groupEnvironment { rowEvents = rowEvents.filter { $0.category != .environment } }

        // HealthKit emits sub-30-second stages that would otherwise render as
        // cluttering "0m" rows; drop those while keeping all point-in-time events.
        let kept = rowEvents.filter { e in
            guard let end = e.endTimestamp else { return true }        // point events kept
            return end.timeIntervalSince(e.timestamp) >= 60            // duration >= 1 min
        }

        var buckets: [Date: [TimelineItem]] = [:]
        for event in kept {
            buckets[calendar.startOfDay(for: event.timestamp), default: []].append(.event(event))
        }
        for session in sessions {
            buckets[calendar.startOfDay(for: session.end), default: []].append(.sleepSession(session))
        }
        for summary in summaries {
            buckets[summary.dayStart, default: []].append(.environmentSummary(summary))
        }

        return buckets.keys.sorted(by: >).map { day in
            let items = buckets[day]!.sorted { ($0.sortDate, $0.id) > ($1.sortDate, $1.id) }
            let points = items
                .compactMap { item -> SeverityPoint? in
                    guard case .event(let e) = item, e.category == .symptom, let v = e.value else { return nil }
                    return SeverityPoint(time: e.timestamp, value: v)
                }
                .sorted { $0.time < $1.time }
            return TimelineDay(dayStart: day, items: items, severityPoints: points)
        }
    }
}
