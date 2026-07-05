import Testing
import Foundation
@testable import HealthGraphCore

struct SyntheticDataTests {
    var config: SyntheticConfig {
        SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            days: 400,
            seed: 42,
            patterns: [PlantedPattern(
                exposureName: "dairy", exposureCategory: .food,
                outcomeSubtype: "bloating", lagHours: 12, lagJitterHours: 3,
                followProbability: 0.7, exposureProbabilityPerDay: 0.5
            )],
            outcomeBaseRatePerDay: 0.05,
            noiseFoodsPerDay: 1...3
        )
    }

    @Test func sameSeedProducesIdenticalContent() {
        let a = SyntheticDataGenerator.generate(config: config)
        let b = SyntheticDataGenerator.generate(config: config)
        #expect(a.events.count == b.events.count)
        #expect(a.events.map(\.timestamp) == b.events.map(\.timestamp))
        #expect(a.events.map(\.subtype) == b.events.map(\.subtype))
        #expect(a.objects.map(\.name) == b.objects.map(\.name))
    }

    @Test func plantedPatternIsStatisticallyPresent() {
        let data = SyntheticDataGenerator.generate(config: config)
        let exposures = data.events.filter { $0.subtype == "dairy" }
        let outcomes = data.events.filter { $0.subtype == "bloating" }
        #expect(exposures.count > 150) // ~200 expected over 400 days at p=0.5

        // conditional rate: outcome within 12±3h (+1h slack) after exposure
        var followed = 0
        for e in exposures {
            let hit = outcomes.contains {
                let dt = $0.timestamp.timeIntervalSince(e.timestamp) / 3600
                return dt >= 8 && dt <= 16
            }
            if hit { followed += 1 }
        }
        let conditional = Double(followed) / Double(exposures.count)
        #expect(conditional > 0.55 && conditional < 0.85) // planted 0.7

        // base rate on non-exposure days stays low
        let cal = Calendar(identifier: .gregorian)
        let exposureDays = Set(exposures.map { cal.startOfDay(for: $0.timestamp) })
        let spontaneous = outcomes.filter { outcome in
            !exposureDays.contains(cal.startOfDay(for: outcome.timestamp.addingTimeInterval(-12 * 3600)))
        }
        let nonExposureDayCount = max(1, config.days - exposureDays.count)
        let baseRate = Double(spontaneous.count) / Double(nonExposureDayCount)
        #expect(baseRate < 0.2) // planted 0.05, generous ceiling
    }

    @Test func datasetInsertsIntoDatabase() async throws {
        let db = try AppDatabase.inMemory()
        let data = SyntheticDataGenerator.generate(config: config)
        try await data.insert(into: db)
        let eventCount = try await GRDBEventStore(database: db).count()
        #expect(eventCount == data.events.count)
        let objectCount = try await GRDBObjectStore(database: db).count()
        #expect(objectCount == data.objects.count)
    }
}
