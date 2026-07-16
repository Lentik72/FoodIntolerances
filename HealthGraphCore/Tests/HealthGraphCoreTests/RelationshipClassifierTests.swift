import Testing
import Foundation
@testable import HealthGraphCore

struct RelationshipClassifierTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    func stats(ratio: Double, exposures: Int, spanDays: Double) -> PairStats {
        let last = now
        let first = now.addingTimeInterval(-spanDays * 86_400)
        return PairStats(exposureCount: exposures, followCount: exposures / 2, missCount: exposures / 2,
                         baseRate: 0.1, ratio: ratio, avgEffect: 5, medianLagHours: 6,
                         firstExposure: first, lastExposure: last, pairs: [],
                         exposureDayCount: exposures, exposureDaysWithOutcome: exposures / 2)
    }
    let c = RelationshipClassifier(config: .default)

    @Test func triggerAtHighRatioAndConfidence() {
        let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30), confidence: 0.6, significant: true, now: now)
        #expect(e?.type == .possibleTrigger)
        #expect(e?.status == .active)
    }
    @Test func protectiveAtLowRatio() {
        let e = c.classify(stats: stats(ratio: 0.4, exposures: 10, spanDays: 30), confidence: 0.5, significant: true, now: now)
        #expect(e?.type == .improves)
    }
    @Test func noEffectAfterLongNullExposure() {
        let e = c.classify(stats: stats(ratio: 1.0, exposures: 25, spanDays: 120), confidence: 0.1, significant: true, now: now)
        #expect(e?.type == .noEffect)
        #expect(e?.status == .confirmedNoEffect)
    }
    @Test func weakUndirectedReturnsNil() {
        let e = c.classify(stats: stats(ratio: 1.1, exposures: 8, spanDays: 20), confidence: 0.2, significant: true, now: now)
        #expect(e == nil)
    }
    @Test func lowConfidenceTriggerIsCandidate() {
        let e = c.classify(stats: stats(ratio: 2, exposures: 8, spanDays: 20), confidence: 0.32, significant: true, now: now)
        #expect(e?.status == .candidate)
    }
    @Test func veryLowConfidenceTriggerIsDecayed() {
        // Below the 0.3 decay threshold — the staleness path (spec §8 test #5).
        let e = c.classify(stats: stats(ratio: 2, exposures: 8, spanDays: 20), confidence: 0.2, significant: true, now: now)
        #expect(e?.status == .decayed)
    }
    @Test func nonSignificantTriggerIsCappedToCandidate() {
        let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30),
                           confidence: 0.6, significant: false, now: now)
        #expect(e?.type == .possibleTrigger)
        #expect(e?.status == .candidate)   // would be .active if significant
    }
    @Test func significantTriggerActivatesNormally() {
        let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30),
                           confidence: 0.6, significant: true, now: now)
        #expect(e?.status == .active)
    }
    @Test func nonSignificantDoesNotResurrectDecayed() {
        // low confidence → decayed regardless of significance.
        let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30),
                           confidence: 0.2, significant: false, now: now)
        #expect(e?.status == .decayed)
    }
    @Test func noEffectIgnoresSignificance() {
        let e = c.classify(stats: stats(ratio: 1.0, exposures: 25, spanDays: 120),
                           confidence: 0.1, significant: false, now: now)
        #expect(e?.status == .confirmedNoEffect)
    }
    @Test func tailDirectionByRatio() {
        #expect(c.tailDirection(stats: stats(ratio: 3, exposures: 10, spanDays: 30)) == .upper)
        #expect(c.tailDirection(stats: stats(ratio: 0.4, exposures: 10, spanDays: 30)) == .lower)
        #expect(c.tailDirection(stats: stats(ratio: 1.0, exposures: 10, spanDays: 30)) == nil)
    }
}
