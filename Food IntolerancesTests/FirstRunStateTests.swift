import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct FirstRunStateTests {
    private func makeState() throws -> (FirstRunState, UserDefaults) {
        let d = UserDefaults(suiteName: "first-run-state-\(UUID().uuidString)")!
        let db = try AppDatabase.inMemory()
        return (FirstRunState(defaults: d, store: GRDBEventStore(database: db)), d)
    }

    @Test func seedsAreRevalidatedOnRead() throws {
        let (state, d) = try makeState()
        // Written directly, bypassing markCompleted's write-time validation —
        // this is the stale-store case the read-time guard exists for.
        let redFlag = try #require(RedFlagCatalog.allSymptomKeys.first)
        let good = HealthGraphCore.SymptomCatalog.canonicalKey(for: "Headache")
        d.set([redFlag, "notARealCatalogKey", good], forKey: FirstRunKeys.symptomSeeds)
        #expect(state.seeds == [good])
    }

    @Test func completionValidatesAndClearsTheInProgressMarker() throws {
        let (state, d) = try makeState()
        state.markStarted()
        #expect(d.integer(forKey: FirstRunKeys.startedVersion) == FirstRunState.currentVersion)

        let redFlag = try #require(RedFlagCatalog.allSymptomKeys.first)
        let good = HealthGraphCore.SymptomCatalog.canonicalKey(for: "Bloating")
        state.markCompleted(seeds: [good, redFlag])

        #expect(d.integer(forKey: FirstRunKeys.completedVersion) == FirstRunState.currentVersion)
        #expect(d.object(forKey: FirstRunKeys.startedVersion) == nil)   // marker cleared
        #expect(state.seeds == [good])                                  // red flag stripped at write
    }

    @Test func theSeedCapIsEnforcedAtCompletionNotJustInTheGrid() throws {
        // The cap of 8 lives in THREE unlinked places: the grid's selection
        // guard, markCompleted's limit, and the getter's limit. Only
        // SymptomSeeds.validate was tested, so widening the grid alone would
        // let a user pick 20 and silently drop 12 here.
        let (state, _) = try makeState()
        let keys = HealthGraphCore.SymptomCatalog.all.map(\.canonicalKey)
            .filter { !Set(RedFlagCatalog.allSymptomKeys).contains($0) }
        state.markCompleted(seeds: Array(keys.prefix(20)))
        #expect(state.seeds.count == 8)
    }
}
