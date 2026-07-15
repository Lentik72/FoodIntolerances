import Foundation

/// One exposure occurrence and whether its outcome followed — the drill-down row.
public struct ExposurePairDetail: Sendable, Equatable {
    public let exposureEventID: UUID
    public let exposureTime: Date
    public let outcomeFollowed: Bool
    public let outcomeEventID: UUID?
    public let outcomeValue: Double?
    public let lagHours: Double?
}

/// Result of scoring one (exposure, outcome) pair.
public struct PairStats: Sendable, Equatable {
    public let exposureCount: Int
    public let followCount: Int
    public let missCount: Int
    public let baseRate: Double        // P(Y | ¬X), per non-exposure day
    public let ratio: Double           // P(Y|X) / P(Y|¬X), per-day
    public let avgEffect: Double?      // mean outcome value among follows
    public let medianLagHours: Double?
    public let firstExposure: Date
    public let lastExposure: Date
    public let pairs: [ExposurePairDetail]
}

public struct CooccurrenceAnalyzer {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }

    public func analyze(exposure: [ExposureOccurrence], outcome: [OutcomeOccurrence],
                        window: ClosedRange<Double>, observation: DateInterval) -> PairStats? {
        guard !exposure.isEmpty else { return nil }
        let cal = Self.utc
        let sortedExposures = exposure.sorted { $0.timestamp < $1.timestamp }
        let sortedOutcomes = outcome.sorted { $0.timestamp < $1.timestamp }
        let outcomeSecs = sortedOutcomes.map { $0.timestamp.timeIntervalSince1970 }

        // Per-occurrence pairs (drives dots + evidenceCount). Binary-search the window
        // per exposure → O(N log M) not O(N·M), so recompute meets the <30s NFR at scale.
        var pairs: [ExposurePairDetail] = []
        pairs.reserveCapacity(sortedExposures.count)
        var effects: [Double] = []
        var lags: [Double] = []
        for e in sortedExposures {
            let lo = e.timestamp.timeIntervalSince1970 + window.lowerBound * 3600
            let hi = e.timestamp.timeIntervalSince1970 + window.upperBound * 3600
            var l = 0, r = outcomeSecs.count
            while l < r { let m = (l + r) / 2; if outcomeSecs[m] < lo { l = m + 1 } else { r = m } }
            let hit = (l < outcomeSecs.count && outcomeSecs[l] <= hi) ? sortedOutcomes[l] : nil
            if let hit {
                let lag = hit.timestamp.timeIntervalSince(e.timestamp) / 3600
                lags.append(lag); if let v = hit.value { effects.append(v) }
                pairs.append(ExposurePairDetail(exposureEventID: e.sourceEventID, exposureTime: e.timestamp,
                                                outcomeFollowed: true, outcomeEventID: hit.sourceEventID,
                                                outcomeValue: hit.value, lagHours: lag))
            } else {
                pairs.append(ExposurePairDetail(exposureEventID: e.sourceEventID, exposureTime: e.timestamp,
                                                outcomeFollowed: false, outcomeEventID: nil,
                                                outcomeValue: nil, lagHours: nil))
            }
        }
        let followCount = pairs.filter(\.outcomeFollowed).count

        // Per-day base rate & ratio.
        let exposureDays = Set(exposure.map { cal.startOfDay(for: $0.timestamp) })
        let outcomeDays = Set(sortedOutcomes.map { cal.startOfDay(for: $0.timestamp) })
        // Derived from `pairs` (O(exposures)) — avoids an O(days·exposures·outcomes) rescan.
        let exposureDaysWithOutcome = Set(pairs.filter(\.outcomeFollowed)
                                             .map { cal.startOfDay(for: $0.exposureTime) }).count
        let totalDays = max(1, Int(observation.duration / 86_400) + 1)
        let nonExposureDays = max(1, totalDays - exposureDays.count)
        let spontaneousOutcomeDays = outcomeDays.subtracting(exposureDays).count
        let baseRate = Double(spontaneousOutcomeDays) / Double(nonExposureDays)   // per calendar day
        let pYgivenX = Double(exposureDaysWithOutcome) / Double(max(1, exposureDays.count))
        // The exposure numerator spans the lag window; scale the per-day base rate
        // to the window length so a 48h window isn't compared against a 24h base.
        // Without this, supplement ratios inflate ~2× and `improves`/`confirmedNoEffect`
        // misfire (e.g. a real protective effect never crosses the 0.67 threshold).
        let windowDays = max((window.upperBound - window.lowerBound) / 24.0, 1e-6)
        let eps = 0.001
        let ratio = pYgivenX / max(baseRate * windowDays, eps)

        let sortedLags = lags.sorted()
        let medianLag = sortedLags.isEmpty ? nil : sortedLags[sortedLags.count / 2]
        let avgEffect = effects.isEmpty ? nil : effects.reduce(0, +) / Double(effects.count)
        let times = exposure.map(\.timestamp).sorted()

        return PairStats(exposureCount: exposure.count, followCount: followCount,
                         missCount: exposure.count - followCount, baseRate: baseRate, ratio: ratio,
                         avgEffect: avgEffect, medianLagHours: medianLag,
                         firstExposure: times.first!, lastExposure: times.last!, pairs: pairs)
    }
}
