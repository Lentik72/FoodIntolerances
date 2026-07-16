import Foundation

/// Which tail of the binomial we test: a trigger over-produces the outcome
/// (upper), a protective effect under-produces it (lower).
public enum TailDirection: Sendable, Equatable { case upper, lower }

/// Engine-side false-positive control. Deterministic; all math in log-space.
public enum SignificanceTester {
    /// One-sided binomial tail: with X ~ Binomial(n, p0), returns P(X >= a) for
    /// `.upper` and P(X <= a) for `.lower`. `n == 0` → 1.0 (no evidence).
    public static func pValue(successes a: Int, trials n: Int, baseRate p0: Double,
                              direction: TailDirection) -> Double {
        guard n > 0 else { return 1.0 }
        let clampedA = min(max(a, 0), n)
        let p = min(max(p0, 1e-9), 1 - 1e-9)
        let lnP = log(p), ln1mP = log(1 - p)
        func logPMF(_ k: Int) -> Double {
            lgamma(Double(n + 1)) - lgamma(Double(k + 1)) - lgamma(Double(n - k + 1))
                + Double(k) * lnP + Double(n - k) * ln1mP
        }
        let ks: [Int]
        switch direction {
        case .upper: ks = Array(clampedA...n)
        case .lower: ks = Array(0...clampedA)
        }
        let total = ks.reduce(0.0) { $0 + exp(logPMF($1)) }
        return min(1.0, max(0.0, total))
    }

    /// Benjamini-Hochberg: the largest p-value that is significant at FDR `alpha`.
    /// Returns 0 when nothing qualifies. Caller: `significant = pValue <= threshold`.
    public static func benjaminiHochbergThreshold(pValues: [Double], alpha: Double) -> Double {
        let m = pValues.count
        guard m > 0 else { return 0 }
        var threshold = 0.0
        for (i, p) in pValues.sorted().enumerated() {   // rank = i + 1
            if p <= Double(i + 1) / Double(m) * alpha { threshold = p }
        }
        return threshold
    }
}
