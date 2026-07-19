import Foundation

public enum CyclePhase: String, Sendable, Equatable, Hashable { case menstrual, luteal }

public enum DerivedExposureKind: Sendable, Equatable, Hashable {
    case shortSleep, highStress, pressureDrop
    case cyclePhase(CyclePhase)
    case fullMoon, mercuryRetrograde
}

public enum ExposureKey: Sendable, Equatable, Hashable {
    case object(UUID, EventCategory)
    case derived(DerivedExposureKind)
}

public struct ExposureOccurrence: Sendable, Equatable {
    public let key: ExposureKey
    public let timestamp: Date
    public let timezoneID: String
    public let sourceEventID: UUID
    public init(key: ExposureKey, timestamp: Date, timezoneID: String, sourceEventID: UUID) {
        self.key = key; self.timestamp = timestamp
        self.timezoneID = timezoneID; self.sourceEventID = sourceEventID
    }
}

public enum OutcomeKey: Sendable, Equatable, Hashable {
    case symptom(String)   // subtype
    case lowMood
    case goodMood
}

public struct OutcomeOccurrence: Sendable, Equatable {
    public let key: OutcomeKey
    public let timestamp: Date
    public let value: Double?
    public let sourceEventID: UUID
    public init(key: OutcomeKey, timestamp: Date, value: Double?, sourceEventID: UUID) {
        self.key = key; self.timestamp = timestamp
        self.value = value; self.sourceEventID = sourceEventID
    }
}

/// Pure extractor: raw events → normalized exposure occurrences.
public protocol ExposureSource {
    func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence]
}
