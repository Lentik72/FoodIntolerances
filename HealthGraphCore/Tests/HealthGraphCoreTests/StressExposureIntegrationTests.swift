import Testing
import Foundation
@testable import HealthGraphCore

/// End-to-end over the REAL extraction path: a rated "Stress" symptom log is
/// simultaneously a high-stress exposure and a stress outcome, and the pair
/// they would form with each other is never generated — while the pair that
/// matters, high stress against another symptom, still is.
struct StressExposureIntegrationTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)
    private func day(_ i: Int) -> Date { t0.addingTimeInterval(Double(i) * 86_400) }

    private func corpus() -> [HealthEvent] {
        var events: [HealthEvent] = []
        for i in 0..<8 {
            events.append(HealthEvent(timestamp: day(i), timezoneID: "UTC", category: .symptom,
                                      subtype: "stress", value: 8, unit: "severity",
                                      source: .manual, createdAt: day(i)))
            events.append(HealthEvent(timestamp: day(i).addingTimeInterval(3 * 3600),
                                      timezoneID: "UTC", category: .symptom, subtype: "headache",
                                      value: 6, unit: "severity", source: .manual,
                                      createdAt: day(i)))
        }
        return events
    }

    @Test func aRatedStressLogIsBothAnExposureAndAnOutcome() throws {
        let engine = EvidenceEngine(database: try AppDatabase.inMemory())
        let extracted = engine.extract(corpus())
        #expect(extracted.exposures[.derived(.highStress)]?.count == 8)
        #expect(extracted.outcomes[.symptom("stress")]?.count == 8)
    }

    @Test func theSelfPairIsExcludedWhileTheRealPairSurvives() throws {
        let engine = EvidenceEngine(database: try AppDatabase.inMemory())
        let extracted = engine.extract(corpus())
        let cands = CandidateGenerator(config: .default)
            .candidates(exposuresByKey: extracted.exposures, outcomesByKey: extracted.outcomes)
        #expect(cands.contains(Candidate(exposure: .derived(.highStress),
                                         outcome: .symptom("headache"))))
        #expect(!cands.contains(Candidate(exposure: .derived(.highStress),
                                          outcome: .symptom("stress"))))
    }
}
