import Foundation

public struct Candidate: Sendable, Equatable {
    public let exposure: ExposureKey
    public let outcome: OutcomeKey
}

/// Bounds the exposure×outcome space to pairs worth scoring: the exposure must
/// have enough occurrences to compare, and the outcome must exist enough in the
/// corpus to associate with. Deliberately direction-agnostic — a low ratio is
/// exactly what `improves`/`noEffect` need to observe (spec §5).
public struct CandidateGenerator {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    public func candidates(exposuresByKey: [ExposureKey: [ExposureOccurrence]],
                           outcomesByKey: [OutcomeKey: [OutcomeOccurrence]]) -> [Candidate] {
        let exposures = exposuresByKey.filter { $0.value.count >= config.minExposures }.keys
        let outcomes = outcomesByKey.filter { $0.value.count >= config.minOutcomeOccurrences }.keys
        var out: [Candidate] = []
        for e in exposures { for o in outcomes { out.append(Candidate(exposure: e, outcome: o)) } }
        return out
    }
}
