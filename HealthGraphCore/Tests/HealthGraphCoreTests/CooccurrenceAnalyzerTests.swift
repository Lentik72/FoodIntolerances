import Testing
import Foundation
@testable import HealthGraphCore

struct CooccurrenceAnalyzerTests {
    let day = 86_400.0
    let base = 1_700_000_000.0

    @Test func countsFollowsAndMissesWithinWindow() {
        // 3 exposures; outcome follows the 1st (+6h) and 3rd (+2h), not the 2nd.
        let exposures = [0, 1, 2].map {
            ExposureOccurrence(key: .object(UUID(), .food),
                               timestamp: Date(timeIntervalSince1970: base + Double($0) * day + 9 * 3600),
                               timezoneID: "UTC", sourceEventID: UUID())
        }
        let outcomes = [
            OutcomeOccurrence(key: .symptom("bloating"),
                              timestamp: Date(timeIntervalSince1970: base + 0 * day + 15 * 3600),
                              value: 5, sourceEventID: UUID()),   // +6h after exp0
            OutcomeOccurrence(key: .symptom("bloating"),
                              timestamp: Date(timeIntervalSince1970: base + 2 * day + 11 * 3600),
                              value: 7, sourceEventID: UUID()),   // +2h after exp2
        ]
        let obs = DateInterval(start: Date(timeIntervalSince1970: base),
                               end: Date(timeIntervalSince1970: base + 3 * day))
        let stats = CooccurrenceAnalyzer(config: .default)
            .analyze(exposure: exposures, outcome: outcomes, window: 0...24, observation: obs)
        #expect(stats?.exposureCount == 3)
        #expect(stats?.followCount == 2)
        #expect(stats?.missCount == 1)
        #expect(stats?.avgEffect == 6)                 // mean of 5 and 7
        #expect((stats?.ratio ?? 0) > 1.5)             // no spontaneous outcomes → high ratio
        #expect(stats?.pairs.filter { $0.outcomeFollowed }.count == 2)
    }

    @Test func returnsNilWithoutExposures() {
        let stats = CooccurrenceAnalyzer(config: .default)
            .analyze(exposure: [], outcome: [], window: 0...24,
                     observation: DateInterval(start: Date(timeIntervalSince1970: base),
                                               end: Date(timeIntervalSince1970: base + day)))
        #expect(stats == nil)
    }
}
