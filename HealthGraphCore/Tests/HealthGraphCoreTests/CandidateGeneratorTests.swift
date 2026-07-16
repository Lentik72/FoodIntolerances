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
}
