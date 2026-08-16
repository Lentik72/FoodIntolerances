import Foundation

public enum CyclePhase: String, Sendable, Equatable, Hashable { case menstrual, luteal }

public enum DerivedExposureKind: Sendable, Equatable, Hashable {
    case shortSleep, highStress, pressureDrop
    case cyclePhase(CyclePhase)
    case fullMoon, mercuryRetrograde
    case hotDay, coldDay, humidDay, swingDay
    case poorAirDay
}

public enum ExposureKey: Sendable, Equatable, Hashable {
    case object(UUID, EventCategory)
    case derived(DerivedExposureKind)
}

public struct ExposureOccurrence: Sendable, Equatable {
    public let key: ExposureKey
    public let timestamp: Date
    public let timezoneID: String
    public let sourceEventID: UUID
    public init(key: ExposureKey, timestamp: Date, timezoneID: String, sourceEventID: UUID) {
        self.key = key; self.timestamp = timestamp
        self.timezoneID = timezoneID; self.sourceEventID = sourceEventID
    }
}

public enum OutcomeKey: Sendable, Equatable, Hashable {
    case symptom(String)   // subtype
    case lowMood
    case goodMood
}

public struct OutcomeOccurrence: Sendable, Equatable {
    public let key: OutcomeKey
    public let timestamp: Date
    public let value: Double?
    public let sourceEventID: UUID
    public init(key: OutcomeKey, timestamp: Date, value: Double?, sourceEventID: UUID) {
        self.key = key; self.timestamp = timestamp
        self.value = value; self.sourceEventID = sourceEventID
    }
}

/// Which exposures are derived FROM outcome events, and therefore must never be
/// tested against them.
///
/// A stress log is both an exposure (`derived:highStress`) and an outcome
/// (`symptom("stress")`) — the SAME event on both sides. Pairing them yields a
/// perfect co-occurrence by construction, which clears every evidence gate and
/// surfaces as a confident "High stress → Stress". Not a crash; a statistically
/// immaculate tautology sitting beside real findings and devaluing them.
///
/// Declared rather than written as an `if` at the call site so the REASON lives
/// with the model: the next exposure derived from an outcome event adds itself
/// here and is correct automatically, instead of reproducing this bug and
/// waiting for someone to notice a suspiciously perfect result.
///
/// Deliberately per-KEY, not per-event. Both occurrence types carry a
/// `sourceEventID`, so this could exclude only the same log — but that would
/// still permit "your 9am stress predicts your 3pm stress", which is
/// autocorrelation dressed as insight. Any stress→stress edge is uninformative.
public enum ExposureDerivation {
    public static func isDerived(_ exposure: ExposureKey, from outcome: OutcomeKey) -> Bool {
        switch (exposure, outcome) {
        case (.derived(.highStress), .symptom(let subtype)):
            return subtype == HighStressExposureSource.symptomSubtype
        default:
            return false
        }
    }
}

/// Pure extractor: raw events → normalized exposure occurrences.
public protocol ExposureSource {
    func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence]
}

public extension ExposureKey {
    /// Stable, human-readable token for DEBUG diagnostics and device-gate diffs.
    /// The reserved illness confounder sentinel prints as `illness` rather than
    /// its UUID — it is not a real object and its id carries no meaning.
    ///
    /// DELEGATES to `EdgeIdentity.fromToken` rather than re-switching over
    /// `DerivedExposureKind`. A copy would be a second exhaustive switch to
    /// update when a case is added, and if the two ever drifted the dump's
    /// confounder labels would stop matching the `edgeKey` column printed
    /// beside them — silently mis-attributing the very baseline↔after diff the
    /// device gate depends on.
    var diagnosticLabel: String {
        self == EvidenceEngine.illnessConfounderKey ? "illness" : EdgeIdentity.fromToken(self)
    }
}
