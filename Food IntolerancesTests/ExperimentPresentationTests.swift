import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct ExperimentPresentationTests {
    private func result(_ kind: ExperimentOutcomeKind, days: Int = 18, windowDays: Int = 21) -> ExperimentResult {
        ExperimentResult(kind: kind,
                         adherence: ExperimentAdherence(doseDays: days, doses: days, windowDays: windowDays),
                         relationship: nil)
    }

    @Test func noDetectableEffectNeverReadsAsDoesNotWork() {
        // Absence of a detectable effect in one person's logs is not proof of
        // absence. This is the single wording rule most likely to be softened by
        // a later edit, so it is pinned across the whole surface, not one string.
        let all = [ExperimentPresentation.headline(for: result(.noDetectableEffect),
                                                   interventionName: "Magnesium"),
                   ExperimentPresentation.detail(for: result(.noDetectableEffect), shape: .repeated)]
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
        // Two DISTINCT lines. Asserting over a joined string let the organ line —
        // which itself says "Ask your doctor" — satisfy the prescriber assertion
        // too, so deleting the prescriber line passed unnoticed.
        for kind in [ExperimentOutcomeKind.helps, .worsens, .noDetectableEffect, .pictureOnly] {
            let caveats = ExperimentPresentation.caveats(for: result(kind), interventionKind: .medication)
            let prescriber = caveats.filter { $0.localizedCaseInsensitiveContains("prescriber") }
            let organs = caveats.filter { $0.localizedCaseInsensitiveContains("kidney")
                                          || $0.localizedCaseInsensitiveContains("organ") }
            #expect(prescriber.count == 1)
            #expect(organs.count == 1)
            #expect(prescriber.first != organs.first)
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
        // a single course has nothing to compare against. This is the .course
        // wording specifically — see aRepeatedPictureDoesNotClaimASingleCourse
        // below for why .repeated must NOT say this.
        let text = ExperimentPresentation.detail(for: result(.pictureOnly, days: 12), shape: .course)
        #expect(text.localizedCaseInsensitiveContains("can't be evaluated")
                || text.localizedCaseInsensitiveContains("nothing to compare"))
    }

    @Test func aRepeatedPictureDoesNotClaimASingleCourseIsTheReason() {
        // .repeated is the ONLY shape that can ever earn a verdict. Telling a
        // fresh, still-accumulating repeated experiment "a single course can't
        // be evaluated" misstates why it has no answer yet — it isn't a course,
        // and it isn't precluded from ever getting a verdict.
        let text = ExperimentPresentation.detail(for: result(.pictureOnly, days: 3, windowDays: 21),
                                                  shape: .repeated)
        #expect(!text.localizedCaseInsensitiveContains("single course"))
        #expect(text.contains("3 of 21"))   // still states adherence, same as every other branch
    }

    @Test func adherenceIsStatedInDaysOnEveryOutcome() {
        for kind in [ExperimentOutcomeKind.helps, .worsens, .noDetectableEffect, .pictureOnly] {
            let detail = ExperimentPresentation.detail(for: result(kind, days: 18, windowDays: 21), shape: .course)
            // Asserts the fraction framing: both numerator and denominator in the
            // "X of Y" shape, e.g. "18 of 21", to prevent reintroducing the
            // dose-versus-day confound that ExperimentAdherence's doc comment calls out.
            #expect(detail.contains("18 of 21"))
        }
    }

    @Test func noDetectableEffectOnSupplementGetsCaveat() {
        // A supplement with .noDetectableEffect gets no observational caveat
        // (those are only for .helps/.worsens) and no medication caveat. Without
        // the noDetectableEffect-specific caveat, the result reads as "it doesn't work".
        let caveats = ExperimentPresentation.caveats(for: result(.noDetectableEffect), interventionKind: .supplement)
        let joined = caveats.joined(separator: " ")
        #expect(!caveats.isEmpty)
        #expect(joined.localizedCaseInsensitiveContains("rule an effect out"))
    }

    @Test func edgeCaseWindowDaysOneIsSingular() {
        // windowDays == 1 is reachable for a same-day experiment.
        // Pluralise the unit.
        let detail = ExperimentPresentation.detail(for: result(.helps, days: 1, windowDays: 1), shape: .course)
        #expect(detail.contains("1 of 1 day"))
        #expect(!detail.contains("1 of 1 days"))
    }
}
