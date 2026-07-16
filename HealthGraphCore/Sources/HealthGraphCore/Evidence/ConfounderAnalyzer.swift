import Foundation

/// Measures whether another exposure shadows the target — if some other
/// exposure is present on more than `threshold` of the target's days, we can't
/// tell them apart yet, so confidence is penalized. Cycle-phase and illness
/// day-sets are always supplied in `others` by the engine (spec §6).
public struct ConfounderAnalyzer {
    public init() {}
    public func penalty(targetDays: Set<Date>, others: [ExposureKey: Set<Date>],
                        threshold: Double = 0.6) -> (penalty: Double, confounders: [ExposureKey]) {
        guard !targetDays.isEmpty else { return (0, []) }
        var confounders: [ExposureKey] = []
        var maxFraction = 0.0
        for (key, days) in others {
            let overlap = Double(targetDays.intersection(days).count) / Double(targetDays.count)
            if overlap > threshold { confounders.append(key) }
            maxFraction = max(maxFraction, overlap)
        }
        let penalty = max(0, maxFraction - threshold) / (1 - threshold)
        // Stable order for determinism when the engine records confounders.
        confounders.sort { String(describing: $0) < String(describing: $1) }
        return (min(1, penalty), confounders)
    }
}
