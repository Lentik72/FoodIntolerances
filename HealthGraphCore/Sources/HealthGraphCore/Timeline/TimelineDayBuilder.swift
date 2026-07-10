import Foundation

public struct SeverityPoint: Equatable, Sendable {
    public let time: Date
    public let value: Double
    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

public struct TimelineDay: Identifiable, Equatable, Sendable {
    public let dayStart: Date
    public let events: [HealthEvent]
    public let severityPoints: [SeverityPoint]
    public var id: Date { dayStart }
    public init(dayStart: Date, events: [HealthEvent], severityPoints: [SeverityPoint]) {
        self.dayStart = dayStart
        self.events = events
        self.severityPoints = severityPoints
    }
}

public enum TimelineDayBuilder {
    /// Groups a newest-first slice of events into local-calendar days,
    /// newest day first. Duration events group by their start timestamp.
    public static func days(from events: [HealthEvent], timeZone: TimeZone) -> [TimelineDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var order: [Date] = []
        var buckets: [Date: [HealthEvent]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.timestamp)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(event)
        }
        // Input is newest-first, so first-seen day order is already newest-first;
        // sort defensively in case a caller passes an unordered slice.
        return order.sorted(by: >).map { day in
            let dayEvents = buckets[day]!.sorted { ($0.timestamp, $0.id.uuidString) > ($1.timestamp, $1.id.uuidString) }
            let points = dayEvents
                .filter { $0.category == .symptom && $0.value != nil }
                .map { SeverityPoint(time: $0.timestamp, value: $0.value!) }
                .sorted { $0.time < $1.time }
            return TimelineDay(dayStart: day, events: dayEvents, severityPoints: points)
        }
    }
}
