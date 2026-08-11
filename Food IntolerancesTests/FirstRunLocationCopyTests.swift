import Foundation
import CoreLocation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct FirstRunLocationCopyTests {
    private func keys(_ names: [String]) -> [String] {
        names.map { HealthGraphCore.SymptomCatalog.canonicalKey(for: $0) }
    }

    @Test func namesTwoPickedSymptoms() {
        let copy = FirstRunLocationView.explanation(for: keys(["Migraine", "Bloating"]))
        #expect(copy.contains("You picked Migraine and Bloating."))
    }

    @Test func threePicksAreAllNamedBecauseSummarizingOneSavesNothing() {
        // "Fatigue, Joint Pain and 1 more" is absurd when the one more would
        // fit in the same space it took to not name it.
        let copy = FirstRunLocationView.explanation(for: keys(["Fatigue", "Joint Pain", "Nausea"]))
        #expect(copy.contains("You picked Fatigue, Joint Pain and Nausea."))
        #expect(!copy.contains("1 more"))
    }

    @Test func namesTwoAndCountsTheRestRatherThanSilentlyDroppingThem() {
        // Naming two of eight and saying nothing about the other six reads as
        // arbitrary — the first person to see it asked where the rest went.
        let copy = FirstRunLocationView.explanation(
            for: keys(["Migraine", "Bloating", "Nausea", "Fatigue", "Headache",
                       "Dizziness", "Anxiety", "Congestion"]))
        #expect(copy.contains("You picked Migraine, Bloating and 6 more."))
        #expect(!copy.contains("Nausea"))
    }

    @Test func theCopyDoesNotClaimTheseSymptomsTrackTheWeather() {
        // Every weather exposure is .contested in PlausibilityCatalog, so
        // "we'll watch <weather> against them" asserts a link the Insights
        // surface would then refuse to state. The picks are context; the
        // watching is a capability, not a claim about those picks.
        let copy = FirstRunLocationView.explanation(for: keys(["Hard Stool", "Bloating"]))
        #expect(!copy.contains("against them"))
        #expect(!copy.localizedCaseInsensitiveContains("against your"))
        #expect(copy.contains("if a pattern is there"))   // conditional, not promised
    }

    @Test func fallsBackWhenNothingWasPicked() {
        let copy = FirstRunLocationView.explanation(for: [])
        #expect(!copy.contains("You picked"))
        #expect(copy.contains("your symptoms"))
    }

    @Test func neverPromisesDiscovery() {
        // Every weather exposure is .contested in PlausibilityCatalog, so the
        // copy must say "watch", never "find".
        for seeds in [[], ["headache"]] {
            let copy = FirstRunLocationView.explanation(for: seeds)
            #expect(copy.contains("watch"))
            #expect(!copy.localizedCaseInsensitiveContains("we'll find"))
        }
    }

    @Test func stripsInvalidSeedsBeforeNamingThem() {
        // The screen receives the flow's in-memory selection, which has not been
        // through markCompleted's validation yet.
        let redFlag = RedFlagCatalog.allSymptomKeys.first!
        let copy = FirstRunLocationView.explanation(for: [redFlag, "notAKey",
                                                          HealthGraphCore.SymptomCatalog.canonicalKey(for: "Migraine")])
        #expect(copy.contains("Migraine"))
    }

    @Test func aSingleSeedReadsAsOneNameWithNoDanglingConjunction() {
        // prefix(2).joined(separator: " and ") on one element must not leave
        // "Migraine and ." — the one-seed case is the common one for a user who
        // picked a single symptom.
        let copy = FirstRunLocationView.explanation(
            for: [HealthGraphCore.SymptomCatalog.canonicalKey(for: "Migraine")])
        #expect(copy.contains("You picked Migraine."))
    }

    @Test func aRedFlagOnlySelectionFallsBackInsteadOfNamingNothing() {
        // Validation can empty a non-empty selection. The guard must key off the
        // VALIDATED list, or the copy reads "You picked ." on this path.
        let copy = FirstRunLocationView.explanation(for: [RedFlagCatalog.allSymptomKeys.first!])
        #expect(!copy.contains("You picked"))
        #expect(copy.contains("your symptoms"))
    }

    // MARK: - Status note

    @Test func anAuthorizedDeviceSaysSoInsteadOfRenderingNothing() {
        // Previously this state rendered EmptyView, leaving the screen with a
        // headline, one paragraph and a void — and telling a user who had
        // already granted location precisely nothing about it.
        let note = FirstRunLocationView.statusNote(for: .authorizedWhenInUse)
        #expect(note?.contains("Location is on") == true)
        #expect(FirstRunLocationView.statusNote(for: .authorizedAlways) == note)
    }

    @Test func aDeniedDeviceIsToldWhereTheSwitchIs() {
        #expect(FirstRunLocationView.statusNote(for: .denied) == "Location is turned off for this app.")
        #expect(FirstRunLocationView.statusNote(for: .restricted) == "Location is turned off for this app.")
    }

    @Test func anUndecidedDeviceGetsNoNoteBecauseTheButtonIsTheMessage() {
        #expect(FirstRunLocationView.statusNote(for: .notDetermined) == nil)
    }
}
