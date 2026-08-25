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

    @Test func theTypeTheEngineActuallyEmitsForWorseningIsMapped() {
        // RelationshipClassifier.classify emits .possibleTrigger for the "worsens"
        // direction (analgesic overuse → rebound headaches), not .worsens. This test
        // verifies the actual production type is mapped distinctly and never collapsed
        // into "no effect" or "picture".
        #expect(ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(),
                                        relationship: rel(.possibleTrigger)).kind == .worsens)
    }

    @Test func aConfirmedNoEffectIsADistinctOutcome() {
        let r = ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(),
                                        relationship: rel(.noEffect, status: .confirmedNoEffect))
        #expect(r.kind == .noDetectableEffect)
    }

    @Test func noRelationshipMeansNoVerdict() {
        // Passes because `relationship` is nil, not because of adherence — the
        // engine did not settle a relationship for this pair at all, so there is
        // nothing to report but a picture.
        #expect(ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(4),
                                        relationship: nil).kind == .pictureOnly)
    }

    @Test func aWindowWithZeroDosesNeverGetsAVerdictEvenWithASettledRelationship() {
        // The defect this gate closes: two years of magnesium history settles an
        // `.improves` relationship over the WHOLE history, computed by
        // `EvidenceEngine.recompute` over `.distantPast...distantFuture`, not this
        // window. Declaring a 21-day experiment and logging zero doses must not
        // borrow that history's verdict for a window in which nothing was tested.
        let r = ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(0),
                                        relationship: rel(.improves))
        #expect(r.kind == .pictureOnly)
    }

    @Test func aWindowBelowTheEnginesOwnExposureFloorNeverGetsAVerdict() {
        // 4 dose days is one below EvidenceConfig.default.minExposures (5) — still
        // gated, even with an active, settled relationship handed in.
        let r = ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(4),
                                        relationship: rel(.improves))
        #expect(r.kind == .pictureOnly)
    }

    @Test func aWindowAtTheEnginesOwnExposureFloorCanEarnAVerdict() {
        // 5 dose days meets EvidenceConfig.default.minExposures exactly — the gate
        // reuses the engine's own floor, not a new threshold invented here.
        let r = ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(5),
                                        relationship: rel(.improves))
        #expect(r.kind == .helps)
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
        // Verify adherence is carried through all decision branches, not just verdicts.
        for shape in ExperimentShape.allCases {
            let r = ExperimentResult.derive(experiment: exp(shape), adherence: adherence(11),
                                            relationship: rel(.improves))
            #expect(r.adherence.doseDays == 11)
        }
        // Verify adherence is carried through pictureOnly paths.
        let nilRelResult = ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(7),
                                                   relationship: nil)
        #expect(nilRelResult.adherence.doseDays == 7)
        let candidateResult = ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(9),
                                                      relationship: rel(.improves, status: .candidate))
        #expect(candidateResult.adherence.doseDays == 9)
    }
}
