import Testing
import Foundation
@testable import HealthGraphCore

struct CandidateGeneratorTests {
    func exp(_ key: ExposureKey, _ n: Int) -> [ExposureOccurrence] {
        (0..<n).map { ExposureOccurrence(key: key, timestamp: Date(timeIntervalSince1970: Double($0) * 86_400),
                                         timezoneID: "UTC", sourceEventID: UUID()) }
    }
    func out(_ key: OutcomeKey, _ n: Int) -> [OutcomeOccurrence] {
        (0..<n).map { OutcomeOccurrence(key: key, timestamp: Date(timeIntervalSince1970: Double($0) * 3600),
                                        value: 5, sourceEventID: UUID()) }
    }
    @Test func gatesOnMinCounts() {
        let dairy = ExposureKey.object(UUID(), .food)
        let rareFood = ExposureKey.object(UUID(), .food)
        let exposures = [dairy: exp(dairy, 6), rareFood: exp(rareFood, 3)]   // rareFood < 5 → excluded
        let outcomes = [OutcomeKey.symptom("bloating"): out(.symptom("bloating"), 4),
                        OutcomeKey.symptom("rare"): out(.symptom("rare"), 2)] // rare < 3 → excluded
        let cands = CandidateGenerator(config: .default)
            .candidates(exposuresByKey: exposures, outcomesByKey: outcomes)
        #expect(cands.count == 1)
        #expect(cands.first?.exposure == dairy)
        #expect(cands.first?.outcome == .symptom("bloating"))
    }

    @Test func neverPairsHighStressWithTheStressOutcomeItIsDerivedFrom() {
        // The same log produces both sides, so this pair co-occurs perfectly by
        // construction and would pass every gate as "High stress → Stress".
        let exposures = [ExposureKey.derived(.highStress): exp(.derived(.highStress), 8)]
        let outcomes = [OutcomeKey.symptom("stress"): out(.symptom("stress"), 8)]
        let cands = CandidateGenerator(config: .default)
            .candidates(exposuresByKey: exposures, outcomesByKey: outcomes)
        #expect(cands.isEmpty)
    }

    @Test func stillPairsHighStressWithEveryOtherSymptom() {
        // The exclusion must be surgical. "Stress exposures don't pair with
        // symptoms" would delete the entire feature.
        let exposures = [ExposureKey.derived(.highStress): exp(.derived(.highStress), 8)]
        let outcomes = [OutcomeKey.symptom("stress"): out(.symptom("stress"), 8),
                        OutcomeKey.symptom("headache"): out(.symptom("headache"), 8)]
        let cands = CandidateGenerator(config: .default)
            .candidates(exposuresByKey: exposures, outcomesByKey: outcomes)
        #expect(cands == [Candidate(exposure: .derived(.highStress), outcome: .symptom("headache"))])
    }

    @Test func otherExposuresAreUnaffectedByTheRule() {
        // Only an exposure DERIVED FROM an outcome's events is excluded from it. A food
        // trigger has no such relationship to the stress outcome.
        let dairy = ExposureKey.object(UUID(), .food)
        let cands = CandidateGenerator(config: .default)
            .candidates(exposuresByKey: [dairy: exp(dairy, 8)],
                        outcomesByKey: [OutcomeKey.symptom("stress"): out(.symptom("stress"), 8)])
        #expect(cands == [Candidate(exposure: dairy, outcome: .symptom("stress"))])
    }

    @Test func derivationIsDeclaredNotInferred() {
        // Direct unit coverage of the declaration, so the rule is pinned even if
        // CandidateGenerator is later restructured.
        #expect(ExposureDerivation.isDerived(.derived(.highStress), from: .symptom("stress")))
        #expect(!ExposureDerivation.isDerived(.derived(.highStress), from: .symptom("headache")))
        #expect(!ExposureDerivation.isDerived(.derived(.shortSleep), from: .symptom("stress")))
        #expect(!ExposureDerivation.isDerived(.derived(.highStress), from: .lowMood))
    }
}
