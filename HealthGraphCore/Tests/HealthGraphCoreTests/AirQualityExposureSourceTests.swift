import Testing
import Foundation
@testable import HealthGraphCore

struct AirQualityExposureSourceTests {
    private func aq(_ v: Double, _ i: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                    category: .environment, subtype: "airQuality", value: v, source: .weatherAPI,
                    metadata: try? JSONEncoder().encode(["provenance": "observedCompletedDay"]))
    }
    @Test func poorAirDayOnlyAtOrAbove101ByEvent() {
        let good = aq(42, 0), poor1 = aq(101, 1), poor2 = aq(175, 2), boundaryBelow = aq(100, 3)
        let occ = AirQualityExposureSource().occurrences(from: [good, poor1, poor2, boundaryBelow])
        #expect(occ.allSatisfy { $0.key == .derived(.poorAirDay) })
        // Exactly the ≥101 events fired — 100 (boundary-below) and 42 excluded. Pins the
        // threshold AND that the RIGHT events keyed (not just a count).
        #expect(Set(occ.map(\.sourceEventID)) == Set([poor1.id, poor2.id]))
    }
    @Test func ignoresNonAirQualitySubtypeAndNonEnvironmentCategory() {
        let humidity = HealthEvent(timestamp: Date(timeIntervalSince1970: 0), timezoneID: "UTC",
                                   category: .environment, subtype: "humidity", value: 500, source: .weatherAPI)
        let mislabeled = HealthEvent(timestamp: Date(timeIntervalSince1970: 0), timezoneID: "UTC",
                                     category: .symptom, subtype: "airQuality", value: 300, source: .manual)
        #expect(AirQualityExposureSource().occurrences(from: [humidity, mislabeled]).isEmpty)   // subtype + category guards
    }
    // Self-contained: observed → occurrences; forecast → none; NO-flag (legacy) → none.
    @Test func airQualityMinedOnlyWhenObserved() {
        func aqDay(_ v: Double, _ i: Int, _ provenance: String?) -> HealthEvent {
            var meta: [String: String] = [:]; if let p = provenance { meta["provenance"] = p }
            return HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                               category: .environment, subtype: "airQuality", value: v, source: .weatherAPI,
                               metadata: try? JSONEncoder().encode(meta))
        }
        func run(_ p: String?) -> [ExposureOccurrence] {
            AirQualityExposureSource().occurrences(from: [aqDay(175, 0, p)])
        }
        #expect(run("observedCompletedDay").contains { $0.key == .derived(.poorAirDay) })   // gate isn't just `return []`
        #expect(run("forecast").isEmpty)                                                     // forecast never mined
        #expect(run(nil).isEmpty)                                                            // fail-closed: no flag → not mined
    }
}
