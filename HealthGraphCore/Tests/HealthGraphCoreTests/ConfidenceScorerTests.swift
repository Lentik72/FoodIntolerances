import Testing
import Foundation
@testable import HealthGraphCore

struct ConfidenceScorerTests {
    func stats(follows: Int, exposures: Int, baseRate: Double, lastExposure: Date) -> PairStats {
        PairStats(exposureCount: exposures, followCount: follows, missCount: exposures - follows,
                  baseRate: baseRate, ratio: 3, avgEffect: 5, medianLagHours: 6,
                  firstExposure: Date(timeIntervalSince1970: 0), lastExposure: lastExposure, pairs: [])
    }
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func strongRecentPatternIsHighButClampedTo075() {
        let s = stats(follows: 140, exposures: 200, baseRate: 0.05, lastExposure: now)
        let c = ConfidenceScorer(config: .default).confidence(stats: s, confounderPenalty: 0, now: now)
        #expect(c <= 0.75)
        #expect(c > 0.6)
    }
    @Test func confounderLowersConfidence() {
        let s = stats(follows: 140, exposures: 200, baseRate: 0.05, lastExposure: now)
        let clean = ConfidenceScorer(config: .default).confidence(stats: s, confounderPenalty: 0, now: now)
        let confounded = ConfidenceScorer(config: .default).confidence(stats: s, confounderPenalty: 1, now: now)
        #expect(confounded < clean)
    }
    @Test func stalenessLowersConfidence() {
        let recent = stats(follows: 140, exposures: 200, baseRate: 0.05, lastExposure: now)
        let old = stats(follows: 140, exposures: 200, baseRate: 0.05,
                        lastExposure: now.addingTimeInterval(-200 * 86_400))
        let scorer = ConfidenceScorer(config: .default)
        #expect(scorer.confidence(stats: old, confounderPenalty: 0, now: now)
                < scorer.confidence(stats: recent, confounderPenalty: 0, now: now))
    }
}
