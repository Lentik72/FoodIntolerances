import Testing
import Foundation
@testable import HealthGraphCore

struct SyntheticMoodPatternTests {
    @Test func moodPatternEmitsMoodOutcomes() {
        let config = SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 1_700_000_000), days: 30, seed: 9,
            patterns: [PlantedPattern(exposureName: "Magnesium", exposureCategory: .supplement,
                                      outcomeSubtype: "mood", lagHours: 6, lagJitterHours: 2,
                                      followProbability: 1.0, exposureProbabilityPerDay: 1.0,
                                      moodOutcomeValue: 3)],
            outcomeBaseRatePerDay: 0, noiseFoodsPerDay: 0...0)
        let ds = SyntheticDataGenerator.generate(config: config)
        let moods = ds.events.filter { $0.category == .mood }
        #expect(!moods.isEmpty)
        #expect(moods.allSatisfy { $0.value == 3 && $0.subtype == "mood" })   // Good-mood outcome
        #expect(ds.events.contains { $0.category == .supplement && $0.subtype == "Magnesium" })
        #expect(!ds.events.contains { $0.category == .symptom })              // mood pattern → no symptom outcome
    }

    @Test func symptomPatternUnchangedByDefault() {
        let config = SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 1_700_000_000), days: 20, seed: 9,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food,
                                      outcomeSubtype: "bloating", lagHours: 8, lagJitterHours: 2,
                                      followProbability: 1.0, exposureProbabilityPerDay: 1.0)],
            outcomeBaseRatePerDay: 0, noiseFoodsPerDay: 0...0)
        let ds = SyntheticDataGenerator.generate(config: config)
        #expect(ds.events.contains { $0.category == .symptom && $0.subtype == "bloating" })
        #expect(!ds.events.contains { $0.category == .mood })                // default nil → no mood outcomes
    }
}
