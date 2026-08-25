import Foundation

public enum ExperimentOutcomeKind: String, Equatable, Sendable {
    case helps, worsens, noDetectableEffect, pictureOnly
}

/// What an experiment is allowed to conclude.
///
/// The relationship arrives as an INPUT. This type never queries, scores or
/// thresholds anything: every statistical decision stays inside EvidenceEngine,
/// where it already is. A second statistics path here would be a second opinion
/// the app could contradict itself with.
public struct ExperimentResult: Equatable, Sendable {
    public let kind: ExperimentOutcomeKind
    public let adherence: ExperimentAdherence
    /// The engine's edge, when there is one. nil for every picture.
    public let relationship: Relationship?

    /// Public because the presentation tests live in the APP target, which
    /// imports HealthGraphCore normally rather than @testable — without it the
    /// synthesised memberwise init is internal and those tests cannot compile.
    public init(kind: ExperimentOutcomeKind, adherence: ExperimentAdherence,
                relationship: Relationship?) {
        self.kind = kind; self.adherence = adherence; self.relationship = relationship
    }

    public static func derive(experiment: Experiment, adherence: ExperimentAdherence,
                              relationship: Relationship?) -> ExperimentResult {
        // A course never gets a verdict, however strong the edge looks. Fourteen
        // consecutive days during one illness cannot be separated from recovering
        // anyway, and the engine's stability gate cannot see that it is one block.
        guard experiment.shape == .repeated else {
            return ExperimentResult(kind: .pictureOnly, adherence: adherence, relationship: nil)
        }
        guard let r = relationship else {
            return ExperimentResult(kind: .pictureOnly, adherence: adherence, relationship: nil)
        }
        // `candidate` means the engine has NOT cleared its gates. Only a settled
        // status speaks.
        switch (r.type, r.status) {
        case (.improves, .active):
            return ExperimentResult(kind: .helps, adherence: adherence, relationship: r)
        case (.worsens, .active), (.possibleTrigger, .active):
            return ExperimentResult(kind: .worsens, adherence: adherence, relationship: r)
        // RelationshipClassifier always pairs .confirmedNoEffect with .noEffect type,
        // an invariant enforced elsewhere. Matching on status alone is safe.
        case (_, .confirmedNoEffect):
            return ExperimentResult(kind: .noDetectableEffect, adherence: adherence, relationship: r)
        default:
            // Includes .precedes (temporal order has no helps/worsens valence) and
            // any unsettled status (.decayed, .userDismissed).
            return ExperimentResult(kind: .pictureOnly, adherence: adherence, relationship: nil)
        }
    }
}
