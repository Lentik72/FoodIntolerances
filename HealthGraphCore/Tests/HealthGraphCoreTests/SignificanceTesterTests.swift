import Testing
import Foundation
@testable import HealthGraphCore

struct SignificanceTesterTests {
    @Test func strongLiftIsTinyPValue() {
        // 30/30 successes when background is 5% → astronomically significant.
        let p = SignificanceTester.pValue(successes: 30, trials: 30, baseRate: 0.05, direction: .upper)
        #expect(p < 1e-6)
    }
    @Test func atExpectationIsLargePValue() {
        // a == n*p0 → roughly a coin-flip's worth of tail, not significant.
        let p = SignificanceTester.pValue(successes: 10, trials: 100, baseRate: 0.10, direction: .upper)
        #expect(p > 0.3)
    }
    @Test func handChecked_n10_a8_p0_20_upper() {
        // P(Binomial(10, 0.2) >= 8) = 0.0000779... (sum of k=8,9,10).
        let p = SignificanceTester.pValue(successes: 8, trials: 10, baseRate: 0.20, direction: .upper)
        #expect(abs(p - 0.0000779) < 1e-5)
    }
    @Test func lowerTailForProtective() {
        // Far FEWER successes than background → significant in the lower tail.
        let p = SignificanceTester.pValue(successes: 1, trials: 100, baseRate: 0.30, direction: .lower)
        #expect(p < 1e-6)
    }
    @Test func zeroTrialsIsOne() {
        #expect(SignificanceTester.pValue(successes: 0, trials: 0, baseRate: 0.1, direction: .upper) == 1.0)
    }
    @Test func bhThresholdPicksLargestPassingP() {
        // m=4, alpha=0.05: bounds are .0125, .025, .0375, .05.
        // sorted p = [0.001, 0.01, 0.2, 0.9]; 0.001<=.0125 ✓, 0.01<=.025 ✓, 0.2>.0375, 0.9>.05.
        // Largest passing p = 0.01.
        let t = SignificanceTester.benjaminiHochbergThreshold(pValues: [0.9, 0.2, 0.01, 0.001], alpha: 0.05)
        #expect(abs(t - 0.01) < 1e-12)
    }
    @Test func bhThresholdZeroWhenNonePass() {
        let t = SignificanceTester.benjaminiHochbergThreshold(pValues: [0.5, 0.9], alpha: 0.05)
        #expect(t == 0)
    }
}
