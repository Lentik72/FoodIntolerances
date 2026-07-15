import Foundation

public struct ClassifiedEdge: Sendable, Equatable {
    public let type: RelationshipType
    public let status: RelStatus
}

/// Turns a scored pair into an edge type + status, or nil when it isn't worth a
/// row (weak and undirected, without enough evidence for a null-effect claim).
public struct RelationshipClassifier {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    public func classify(stats: PairStats, confidence: Double, now: Date) -> ClassifiedEdge? {
        let spanDays = stats.lastExposure.timeIntervalSince(stats.firstExposure) / 86_400
        if stats.exposureCount >= config.noEffectMinExposures,
           spanDays >= config.noEffectMinSpanDays,
           config.noEffectRatioBand.contains(stats.ratio) {
            return ClassifiedEdge(type: .noEffect, status: .confirmedNoEffect)
        }
        let type: RelationshipType?
        if stats.ratio >= config.candidateRatioTrigger {
            type = .possibleTrigger
        } else if stats.ratio <= config.candidateRatioProtective && stats.followCount >= 1 {
            // A protective claim needs the outcome to have followed the exposure at
            // least once; zero co-occurrence is "unrelated / different phase", not
            // protection (guards against e.g. a false menstrual→cramps `improves`).
            type = .improves
        } else {
            type = nil
        }
        guard let type else { return nil }
        let status: RelStatus =
            confidence >= config.activationThreshold ? .active
            : confidence < config.decayThreshold ? .decayed
            : .candidate
        return ClassifiedEdge(type: type, status: status)
    }
}
