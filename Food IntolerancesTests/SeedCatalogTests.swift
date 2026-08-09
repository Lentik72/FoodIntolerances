import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct SeedCatalogTests {
    /// Iterates the NAMES, not the mapped keys. Asserting over the keys would
    /// only re-check whatever `offered` was built from and could not fail.
    @Test func everyOfferedNameIsARealCatalogEntry() {
        let known = Set(HealthGraphCore.SymptomCatalog.all.map(\.canonicalKey))
        #expect(!SeedSymptomGrid.offeredNames.isEmpty)   // non-vacuous
        for name in SeedSymptomGrid.offeredNames {
            let key = HealthGraphCore.SymptomCatalog.canonicalKey(for: name)
            #expect(known.contains(key), "\(name) does not exist in SymptomCatalog")
        }
    }

    @Test func nothingIsDroppedBetweenNamesAndKeys() {
        #expect(SeedSymptomGrid.offered.count == SeedSymptomGrid.offeredNames.count)
    }

    @Test func noRedFlagKeyIsOffered() {
        let redFlags = Set(RedFlagCatalog.allSymptomKeys)
        #expect(!redFlags.isEmpty)
        for key in SeedSymptomGrid.offered {
            #expect(!redFlags.contains(key))
        }
    }

    @Test func offeredKeysAreUnique() {
        #expect(Set(SeedSymptomGrid.offered).count == SeedSymptomGrid.offered.count)
    }

    @Test func everyOfferedKeySurvivesSeedValidation() {
        // The grid and the persistence path must agree. `markCompleted` runs
        // SymptomSeeds.validate over the picks, and `FirstRunState.seeds`
        // re-validates on every read — so a key the grid offers but validation
        // drops would let a user pick a chip that silently never appears.
        let offered = Array(SeedSymptomGrid.offered.prefix(SeedSelection.limit))
        #expect(SymptomSeeds.validate(offered, limit: SeedSelection.limit) == offered)
    }
}
