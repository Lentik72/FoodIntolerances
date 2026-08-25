import Testing
import Foundation
@testable import HealthGraphCore

struct ExperimentResultTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func exp(_ shape: ExperimentShape) -> Experiment {
        Experiment(interventionObjectID: UUID(), outcomeSubtype: "migraine", shape: shape,
                   startedAt: t0, intendedEndAt: t0.addingTimeInterval(21 * 86_400), createdAt: t0)
    }

    private func adherence(_ days: Int = 18) -> ExperimentAdherence {
        ExperimentAdherence(doseDays: days, doses: days, windowDays: 21)
    }

    private func rel(_ type: RelationshipType, status: RelStatus = .active) -> Relationship {
        Relationship(fromObjectID: UUID(), fromCategory: "supplement", toCategory: "symptom",
                     type: type, evidenceCount: 12, contradictionCount: 4, confidence: 0.7,
                     firstSeen: t0, lastSeen: t0, lastRecomputed: t0, status: status,
                     edgeKey: "obj:x|symptom:migraine|\(type.rawValue)", toSubtype: "migraine")
    }

    @Test func aCourseNeverGetsAVerdictEvenWithAStrongRelationship() {
        // Fourteen consecutive antibiotic days during one illness cannot be
        // separated from recovering anyway. This is the rule the whole shape
        // distinction exists to enforce.
        let r = ExperimentResult.derive(experiment: exp(.course), adherence: adherence(),
                                        relationship: rel(.improves))
        #expect(r.kind == .pictureOnly)
    }

    @Test func anImprovesRelationshipReadsAsHelps() {
        #expect(ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(),
                                        relationship: rel(.improves)).kind == .helps)
    }

    @Test func aWorsensRelationshipIsReportedNotSwallowed() {
        // Analgesic overuse genuinely causes rebound headaches — this may be the
        // most valuable result the feature produces, so it must not be collapsed
        // into "no effect" for comfort.
        #expect(ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(),
                                        relationship: rel(.worsens)).kind == .worsens)
    }

    @Test func aConfirmedNoEffectIsADistinctOutcome() {
        let r = ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(),
                                        relationship: rel(.noEffect, status: .confirmedNoEffect))
        #expect(r.kind == .noDetectableEffect)
    }

    @Test func noRelationshipMeansNoVerdict() {
        // The engine did not clear its gates for this pair — thin adherence, too
        // few exposures, or clumped ones. The experiment reports a picture rather
        // than inventing a threshold of its own.
        #expect(ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(4),
                                        relationship: nil).kind == .pictureOnly)
    }

    @Test func aCandidateRelationshipIsNotAVerdict() {
        // `candidate` means the engine has NOT cleared its gates. Reporting it as
        // a verdict would be exactly the second statistics path this design
        // refuses to build.
        #expect(ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(),
                                        relationship: rel(.improves, status: .candidate)).kind == .pictureOnly)
    }

    @Test func theAdherenceIsCarriedOntoEveryResult() {
        // Every output shows what the person actually did, including the pictures.
        for shape in ExperimentShape.allCases {
            let r = ExperimentResult.derive(experiment: exp(shape), adherence: adherence(11),
                                            relationship: rel(.improves))
            #expect(r.adherence.doseDays == 11)
        }
    }
}
