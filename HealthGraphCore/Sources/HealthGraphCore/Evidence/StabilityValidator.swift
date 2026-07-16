import Foundation

/// Out-of-sample replication: a genuine association holds across time; a chance
/// one does not. Splits exposures at their median time and requires BOTH halves
/// to be directional in the full-data direction. Reuses CooccurrenceAnalyzer.
public enum StabilityValidator {
    public static func isStable(exposure: [ExposureOccurrence], outcome: [OutcomeOccurrence],
                                window: ClosedRange<Double>, fullDirection: TailDirection,
                                config: EvidenceConfig) -> Bool {
        let sorted = exposure.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 * config.stabilityMinExposuresPerHalf else { return false }
        let mid = sorted.count / 2
        let early = Array(sorted[0..<mid])
        let late = Array(sorted[mid...])
        guard early.count >= config.stabilityMinExposuresPerHalf,
              late.count >= config.stabilityMinExposuresPerHalf else { return false }
        let analyzer = CooccurrenceAnalyzer(config: config)

        func directional(_ half: [ExposureOccurrence]) -> Bool {
            let times = half.map(\.timestamp)
            guard let lo = times.min(), let hi = times.max() else { return false }
            let obsEnd = hi.addingTimeInterval(window.upperBound * 3600)
            let halfOutcomes = outcome.filter { $0.timestamp >= lo && $0.timestamp <= obsEnd }
            guard let stats = analyzer.analyze(exposure: half, outcome: halfOutcomes, window: window,
                                               observation: DateInterval(start: lo, end: obsEnd)) else { return false }
            switch fullDirection {
            case .upper: return stats.ratio >= config.candidateRatioTrigger
            case .lower: return stats.ratio <= config.candidateRatioProtective
            }
        }
        return directional(early) && directional(late)
    }
}
