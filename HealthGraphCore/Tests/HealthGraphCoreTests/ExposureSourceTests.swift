import Testing
import Foundation
@testable import HealthGraphCore

struct EvidenceConfigTests {
    @Test func lagWindowsByExposureKind() {
        let c = EvidenceConfig.default
        #expect(c.lagWindow(for: .object(UUID(), .food)) == 0...24)
        #expect(c.lagWindow(for: .object(UUID(), .supplement)) == 0...48)
        #expect(c.lagWindow(for: .derived(.shortSleep)) == 0...18)
        #expect(c.lagWindow(for: .derived(.cyclePhase(.luteal))) == 0...24)
    }
    @Test func defaultsAreSane() {
        let c = EvidenceConfig.default
        #expect(c.minExposures == 5)
        #expect(c.observationalCeiling == 0.75)
        #expect(c.candidateRatioTrigger > 1.0)
        #expect(c.candidateRatioProtective < 1.0)
    }
}

struct ObjectExposureSourceTests {
    @Test func extractsObjectLinkedFoodMedSupplementPeptide() {
        let oid = UUID()
        let events = [
            HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .food,
                        subtype: "dairy", objectID: oid, source: .manual),
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .food,
                        subtype: "rice", objectID: nil, source: .manual),     // no object → skipped
            HealthEvent(timestamp: Date(timeIntervalSince1970: 300), category: .symptom,
                        subtype: "bloating", source: .manual),                 // outcome → skipped
        ]
        let occ = ObjectExposureSource().occurrences(from: events)
        #expect(occ.count == 1)
        #expect(occ.first?.key == .object(oid, .food))
        #expect(occ.first?.sourceEventID == events[0].id)
    }
}

struct OutcomeSourceTests {
    @Test func extractsSymptomsAndLowMood() {
        let events = [
            HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .symptom,
                        subtype: "headache", value: 6, source: .manual),
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .mood,
                        subtype: "mood", value: 2, source: .manual),           // ≤3 → low mood
            HealthEvent(timestamp: Date(timeIntervalSince1970: 300), category: .mood,
                        subtype: "mood", value: 8, source: .manual),           // high → skipped
        ]
        let occ = OutcomeSource(config: .default).occurrences(from: events)
        #expect(occ.contains { $0.key == .symptom("headache") && $0.value == 6 })
        #expect(occ.contains { $0.key == .lowMood })
        #expect(occ.count == 2)
    }
}
