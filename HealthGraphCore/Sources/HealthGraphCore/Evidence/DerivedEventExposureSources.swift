import Foundation

/// High-stress exposures: stress events at or above the threshold.
public struct HighStressExposureSource: ExposureSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .stress, let v = e.value, v >= config.highStressThreshold else { return nil }
            return ExposureOccurrence(key: .derived(.highStress), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}

/// Pressure-drop exposures. EnvironmentalEventFactory already emits a
/// `subtype: "pressureDrop"` event when pressure falls ≥ its threshold, so this
/// extractor simply reads those — no delta math here.
public struct PressureDropExposureSource: ExposureSource {
    public init() {}
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .environment, e.subtype == "pressureDrop" else { return nil }
            return ExposureOccurrence(key: .derived(.pressureDrop), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
