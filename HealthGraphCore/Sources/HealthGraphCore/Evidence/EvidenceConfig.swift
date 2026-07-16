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

    // Derived-exposure thresholds.
    public var shortSleepThresholdMinutes: Double = 360   // < 6h asleep
    public var highStressThreshold: Double = 7            // value ≥ 7 on 1–10
    public var lowMoodThreshold: Double = 3               // mood value ≤ 3 → low mood
    public var lutealWindowDays: Int = 5                  // days before next period start

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
    // Benjamini-Hochberg false-discovery rate for activation. Tuned to 5e-6 (P5):
    // with 400 days of dense synthetic data the 8 planted signals are astronomically
    // significant (p ≤ 6.4e-8), yet spurious noise correlations still reach nominal
    // p ~ 1e-5…1e-2, so a conventional 0.05 FDR lets ~9 false positives activate.
    // The genuine/noise p-value gap is clean (weakest planted 6.4e-8 vs strongest
    // noise 5.1e-5, ~800×). Any alpha in [1.6e-7, 1.1e-4] puts the BH cutoff in that
    // gap → exactly the 8 planted pairs active, 0 noise; 5e-6 sits at the log-center
    // of that plateau (31× above the recall cliff, 23× below the precision cliff).
    public var fdrAlpha: Double = 5e-6

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
            }
        }
    }
}
