import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct FirstRunLocationCopyTests {
    @Test func namesTheFirstTwoPickedSymptoms() {
        let seeds = ["Migraine", "Bloating", "Nausea"]
            .map { HealthGraphCore.SymptomCatalog.canonicalKey(for: $0) }
        let copy = FirstRunLocationView.explanation(for: seeds)
        #expect(copy.contains("Migraine and Bloating"))
        #expect(!copy.contains("Nausea"))          // only the first two
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
}
