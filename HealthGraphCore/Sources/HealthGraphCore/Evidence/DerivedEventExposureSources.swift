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

/// Mercury-retrograde exposures. EnvironmentalEventFactory emits a
/// `subtype: "mercuryRetrograde"` event on retrograde days.
public struct MercuryRetrogradeExposureSource: ExposureSource {
    public init() {}
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .environment, e.subtype == "mercuryRetrograde" else { return nil }
            return ExposureOccurrence(key: .derived(.mercuryRetrograde), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}

/// Full-moon exposures. The factory emits a daily `subtype: "moonPhase"` event with
/// the cleaned phase name in metadata; the "Full Moon" bucket spans ~2 days/cycle.
public struct FullMoonExposureSource: ExposureSource {
    public init() {}
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .environment, e.subtype == "moonPhase", let data = e.metadata,
                  let meta = try? JSONDecoder().decode([String: String].self, from: data),
                  meta["phase"] == "Full Moon" else { return nil }
            return ExposureOccurrence(key: .derived(.fullMoon), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
