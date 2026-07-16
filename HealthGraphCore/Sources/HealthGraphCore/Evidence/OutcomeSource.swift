import Foundation

/// Outcomes to test exposures against: every distinct symptom subtype, plus
/// low mood (a mood event at or below the configured threshold). "Energy"
/// folds in as the symptom subtype "fatigue".
public struct OutcomeSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [OutcomeOccurrence] {
        events.compactMap { e in
            switch e.category {
            case .symptom:
                guard let subtype = e.subtype else { return nil }
                return OutcomeOccurrence(key: .symptom(subtype), timestamp: e.timestamp,
                                         value: e.value, sourceEventID: e.id)
            case .mood:
                guard let v = e.value, v <= config.lowMoodThreshold else { return nil }
                return OutcomeOccurrence(key: .lowMood, timestamp: e.timestamp,
                                         value: v, sourceEventID: e.id)
            default:
                return nil
            }
        }
    }
}
