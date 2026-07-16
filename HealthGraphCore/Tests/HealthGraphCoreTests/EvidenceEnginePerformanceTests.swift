import Testing
import Foundation
@testable import HealthGraphCore

struct EvidenceEnginePerformanceTests {
    @Test func recomputeOverLargeCorpusIsBounded() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        // ~85k events (2500 days × ~30 noise + derived + patterns) — near the 100k NFR target.
        var cfg = SyntheticConfig(
            startDate: now.addingTimeInterval(-2500 * 86_400), days: 2500, seed: 7,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food,
                                      outcomeSubtype: "bloating", lagHours: 8, lagJitterHours: 3,
                                      followProbability: 0.7, exposureProbabilityPerDay: 0.6)],
            outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 20...40)
        cfg.derivedScenarios = DerivedScenarios(shortSleepFatigue: true, pressureHeadache: true,
                                                stressSymptom: true, lutealSymptom: true)
        let db = try AppDatabase.inMemory()
        try await SyntheticDataGenerator.generate(config: cfg).insert(into: db)
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            _ = try await EvidenceEngine(database: db).recompute(asOf: now)
        }
        // Loose CI tripwire — the on-device budget is 30s at 100k events; this
        // catches an accidental O(n²) blow-up, not micro-perf.
        #expect(elapsed < .seconds(60))
    }
}
