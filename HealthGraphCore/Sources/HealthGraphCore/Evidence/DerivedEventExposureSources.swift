import Foundation

/// High-stress exposures: stress events at or above the threshold.
public struct HighStressExposureSource: ExposureSource {
    /// Shape 1 — a dedicated stress rating. Currently DORMANT: nothing in the
    /// app writes it. Kept because it is already tested and documents the exact
    /// shape any future writer must produce (a dedicated capture surface, or an
    /// Apple State of Mind import).
    public static let ratingSubtype = "stressRating"
    /// Unit guard. Not redundant with the subtype: it is what makes a future
    /// producer that reuses the subtype with different units fail closed
    /// rather than silently mis-scale, which is exactly how minutes got in.
    public static let ratingUnit = "score"

    /// Shape 2 — the "Stress" entry that already exists in SymptomCatalog,
    /// logged through symptom capture. This is the log people actually make;
    /// before it was mined here it fed outcomes only. `logSymptom` writes this
    /// unit only when a severity was given, so an unrated stress log has a nil
    /// value and is rejected by the range check below.
    public static let symptomSubtype = "stress"
    public static let symptomUnit = "severity"

    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard Self.isRatedStress(e),
                  let v = e.value, (1...10).contains(v),
                  v >= config.highStressThreshold else { return nil }
            return ExposureOccurrence(key: .derived(.highStress), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }

    /// TWO positive allowlists, each with its own unit guard — never a denylist.
    /// The previous rule accepted any `.stress` event, and the only real
    /// producer was HealthKit Mindful Sessions carrying duration in MINUTES, so
    /// every meditation of 7+ min was mined as a high-stress exposure with
    /// inverted semantics. Keeping the units pinned per shape is what stops
    /// that class of defect returning through either door.
    private static func isRatedStress(_ e: HealthEvent) -> Bool {
        (e.category == .stress && e.subtype == ratingSubtype && e.unit == ratingUnit)
            || (e.category == .symptom && e.subtype == symptomSubtype && e.unit == symptomUnit)
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
