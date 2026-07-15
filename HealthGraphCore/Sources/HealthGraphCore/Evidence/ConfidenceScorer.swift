import Foundation

/// The confidence formula (spec §6). Deterministic in `now`. Clamps to the
/// observational ceiling — exceeding it needs Phase 4 experiments.
public struct ConfidenceScorer {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    public func confidence(stats: PairStats, confounderPenalty: Double, now: Date) -> Double {
        // Direction-symmetric: score by amount of data + effect magnitude, so a
        // protective edge (ratio<1, few follows) scores like a trigger. See spec §6.
        let signalStrength = min(1, abs(log(max(stats.ratio, 1e-6))) / log(3))
        let ageDays = now.timeIntervalSince(stats.lastExposure) / 86_400
        let staleness = min(1, max(0, ageDays / config.stalenessHalfLifeDays))
        let score = config.w1 * log(Double(max(1, stats.exposureCount)))
                  + config.w2 * signalStrength
                  - config.w4 * confounderPenalty
                  - config.w5 * staleness
                  + config.bias
        let sigmoid = 1 / (1 + exp(-score))
        return min(config.observationalCeiling, sigmoid)
    }
}
