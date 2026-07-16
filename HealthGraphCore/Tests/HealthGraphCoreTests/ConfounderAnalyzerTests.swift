import Testing
import Foundation
@testable import HealthGraphCore

struct ConfounderAnalyzerTests {
    func days(_ offsets: [Int]) -> Set<Date> {
        Set(offsets.map { Date(timeIntervalSince1970: Double($0) * 86_400) })
    }
    @Test func penalizesHighCoOccurrence() {
        let target = days([1, 2, 3, 4, 5])
        let coffee = ExposureKey.object(UUID(), .food)
        let others = [coffee: days([1, 2, 3, 4])]   // 4/5 = 0.8 > 0.6
        let (penalty, confounders) = ConfounderAnalyzer().penalty(targetDays: target, others: others)
        #expect(penalty > 0)
        #expect(confounders == [coffee])
    }
    @Test func noPenaltyWhenIndependent() {
        let target = days([1, 2, 3, 4, 5])
        let other = ExposureKey.derived(.highStress)
        let (penalty, confounders) = ConfounderAnalyzer()
            .penalty(targetDays: target, others: [other: days([9, 10])])   // 0/5
        #expect(penalty == 0)
        #expect(confounders.isEmpty)
    }
}
