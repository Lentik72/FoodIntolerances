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
        // Skip pairs where the exposure was derived from the outcome's own
        // events — excluded HERE so the tautology is never scored, never
        // stored, and never displayed. Hiding it at the Insights layer would
        // leave the engine believing something false.
        for e in exposures {
            for o in outcomes where !ExposureDerivation.isDerived(e, from: o) {
                out.append(Candidate(exposure: e, outcome: o))
            }
        }
        return out
    }
}
