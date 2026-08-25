import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct ExperimentPresentationTests {
    private func result(_ kind: ExperimentOutcomeKind, days: Int = 18) -> ExperimentResult {
        ExperimentResult(kind: kind,
                         adherence: ExperimentAdherence(doseDays: days, doses: days, windowDays: 21),
                         relationship: nil)
    }

    @Test func noDetectableEffectNeverReadsAsDoesNotWork() {
        // Absence of a detectable effect in one person's logs is not proof of
        // absence. This is the single wording rule most likely to be softened by
        // a later edit, so it is pinned across the whole surface, not one string.
        let all = [ExperimentPresentation.headline(for: result(.noDetectableEffect),
                                                   interventionName: "Magnesium"),
                   ExperimentPresentation.detail(for: result(.noDetectableEffect))]
        for text in all {
            #expect(!text.localizedCaseInsensitiveContains("doesn't work"))
            #expect(!text.localizedCaseInsensitiveContains("does not work"))
            #expect(!text.localizedCaseInsensitiveContains("ineffective"))
        }
        #expect(all[0].localizedCaseInsensitiveContains("no detectable effect"))
    }

    @Test func everyMedicationResultCarriesBothSafetyLines() {
        // Required on EVERY outcome, not only the discouraging ones: a "helps"
        // result is exactly when someone feels licensed to self-manage.
        for kind in [ExperimentOutcomeKind.helps, .worsens, .noDetectableEffect, .pictureOnly] {
            let caveats = ExperimentPresentation.caveats(for: result(kind), interventionKind: .medication)
            let joined = caveats.joined(separator: " ")
            #expect(joined.localizedCaseInsensitiveContains("prescriber")
                    || joined.localizedCaseInsensitiveContains("doctor"))
            #expect(joined.localizedCaseInsensitiveContains("kidney")
                    || joined.localizedCaseInsensitiveContains("organ"))
        }
    }

    @Test func aSelfChosenSupplementDoesNotGetThePrescriberLine() {
        // The line has to mean something. On every result it becomes wallpaper.
        let caveats = ExperimentPresentation.caveats(for: result(.helps), interventionKind: .supplement)
        #expect(!caveats.joined().localizedCaseInsensitiveContains("prescriber"))
    }

    @Test func everyVerdictSaysItIsObservational() {
        for kind in [ExperimentOutcomeKind.helps, .worsens] {
            let joined = ExperimentPresentation.caveats(for: result(kind),
                                                        interventionKind: .supplement).joined(separator: " ")
            #expect(joined.localizedCaseInsensitiveContains("not a trial")
                    || joined.localizedCaseInsensitiveContains("observation"))
        }
    }

    @Test func aPictureSaysWhyThereIsNoVerdict() {
        // "Nothing to show" would read as a malfunction. The honest version says
        // a single course has nothing to compare against.
        let text = ExperimentPresentation.detail(for: result(.pictureOnly, days: 12))
        #expect(text.localizedCaseInsensitiveContains("can't be evaluated")
                || text.localizedCaseInsensitiveContains("nothing to compare"))
    }

    @Test func adherenceIsStatedInDaysOnEveryOutcome() {
        for kind in [ExperimentOutcomeKind.helps, .worsens, .noDetectableEffect, .pictureOnly] {
            #expect(ExperimentPresentation.detail(for: result(kind, days: 18)).contains("18"))
        }
    }
}
