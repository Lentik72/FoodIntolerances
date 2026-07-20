import Foundation

/// Every tunable number for the Evidence Engine in one place. Weights are
/// harness-tuned in the acceptance task; nothing here is a magic constant
/// buried in a stage.
public struct EvidenceConfig: Sendable {
    // Lag windows (hours, absolute time).
    public var foodLagHours: ClosedRange<Double> = 0...24
    public var interventionLagHours: ClosedRange<Double> = 0...48   // med/supplement/peptide
    public var shortSleepLagHours: ClosedRange<Double> = 0...18
    public var stressLagHours: ClosedRange<Double> = 0...24
    public var pressureLagHours: ClosedRange<Double> = 0...24
    public var cyclePhaseLagHours: ClosedRange<Double> = 0...24
    public var outsideFactorLagHours: ClosedRange<Double> = 0...24   // moon/mercury: same-day

    // Derived-exposure thresholds.
    public var shortSleepThresholdMinutes: Double = 360   // < 6h asleep
    public var highStressThreshold: Double = 7            // value ≥ 7 on 1–10
    public var lowMoodThreshold: Double = 1               // mood value ≤ 1 (Rough on the 1–3 scale) → low mood
    public var goodMoodThreshold: Double = 3              // mood value ≥ 3 (Good on the 1–3 scale) → good mood
    public var lutealWindowDays: Int = 5                  // days before next period start
    public var weatherHighPercentile: Double = 0.75
    public var weatherLowPercentile: Double = 0.25
    public var minWeatherReadings: Int = 20

    // Candidate evaluation gate.
    public var minExposures: Int = 5
    public var minOutcomeOccurrences: Int = 3

    // Direction thresholds (ratio = P(Y|X)/P(Y|¬X)).
    public var candidateRatioTrigger: Double = 1.5
    public var candidateRatioProtective: Double = 0.67

    // Negative learning.
    public var noEffectMinExposures: Int = 20
    public var noEffectMinSpanDays: Double = 90
    public var noEffectRatioBand: ClosedRange<Double> = 0.83...1.2

    // Status thresholds.
    public var activationThreshold: Double = 0.35
    public var decayThreshold: Double = 0.3
    public var stalenessHalfLifeDays: Double = 60
    public var observationalCeiling: Double = 0.75
    // Benjamini-Hochberg false-discovery rate for activation, at the conventional
    // level (P6). Significance alone catches small-n noise; dense data can make
    // spurious day-level correlations genuinely significant, so activation also
    // requires the effect-size floor below (large-n small-lift noise guard).
    public var fdrAlpha = 0.05   // conventional Benjamini-Hochberg FDR for significance
    public var activationRatioTrigger = 2.0      // trigger must ≥ double the base rate to activate
    public var activationRatioProtective = 0.55  // protective must ≤ this fraction of base to activate
    public var stabilityMinExposuresPerHalf = 5   // each temporal half must carry this much evidence

    // Confidence weights (direction-symmetric): sigmoid(
    //   w1·log(exposureCount) + w2·signalStrength
    //   − w4·confounderPenalty − w5·staleness + bias)
    // signalStrength = min(1, |ln(ratio)|/ln(3)) — a 3×/⅓× shift is full signal,
    // so `improves` (ratio<1) scores like `possibleTrigger` (ratio>1). See
    // spec §6: §7's literal follows-based formula is trigger-biased and can't
    // activate protective edges.
    public var w1 = 0.4    // amount of evidence (log exposureCount)
    public var w2 = 1.5    // effect magnitude (signalStrength)
    public var w4 = 1.5    // confounder penalty
    public var w5 = 1.5    // staleness
    public var bias = -2.0

    public init() {}
    public static let `default` = EvidenceConfig()

    public func lagWindow(for key: ExposureKey) -> ClosedRange<Double> {
        switch key {
        case let .object(_, category):
            switch category {
            case .food: return foodLagHours
            case .medication, .supplement, .peptide: return interventionLagHours
            default: return foodLagHours
            }
        case let .derived(kind):
            switch kind {
            case .shortSleep: return shortSleepLagHours
            case .highStress: return stressLagHours
            case .pressureDrop: return pressureLagHours
            case .cyclePhase: return cyclePhaseLagHours
            case .fullMoon, .mercuryRetrograde: return outsideFactorLagHours
            case .hotDay, .coldDay, .humidDay: return outsideFactorLagHours
            }
        }
    }
}
