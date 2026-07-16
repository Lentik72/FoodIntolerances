import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct InsightsRefreshCoordinatorTests {
    @Test func recomputesOnceForUnchangedDataWithinInterval() async throws {
        let db = try AppDatabase.inMemory()
        // Seed a strong dairy→bloating signal so recompute produces an edge.
        try await SyntheticDataGenerator.generate(config: SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 1_700_000_000), days: 120, seed: 42,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food, outcomeSubtype: "bloating",
                                      lagHours: 8, lagJitterHours: 3, followProbability: 0.8, exposureProbabilityPerDay: 0.6)],
            outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 1...2)).insert(into: db)
        var t = Date(timeIntervalSince1970: 1_750_000_000)
        let coord = InsightsRefreshCoordinator(database: db, minInterval: 900, now: { t })
        await coord.refreshIfNeeded()
        let firstRun = coord.lastRecomputeAt
        #expect(firstRun != nil)
        let rels = try await GRDBRelationshipStore(database: db).count()
        #expect(rels > 0)                                  // recompute actually ran

        // Second call soon after, no data change → skipped (lastRecomputeAt unchanged).
        t = t.addingTimeInterval(60)
        await coord.refreshIfNeeded()
        #expect(coord.lastRecomputeAt == firstRun)
    }
}
