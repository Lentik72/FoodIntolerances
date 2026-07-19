import Testing
import Foundation
@testable import HealthGraphCore

struct EdgeIdentityTests {
    func roundTrip(_ from: ExposureKey, _ to: OutcomeKey) {
        let key = EdgeIdentity.edgeKey(from: from, to: to, type: .possibleTrigger)
        let cols = EdgeIdentity.columns(from: from, to: to)
        let r = Relationship(fromObjectID: cols.fromObjectID, fromCategory: cols.fromCategory,
                             toCategory: cols.toCategory, type: .possibleTrigger,
                             firstSeen: Date(), lastSeen: Date(), lastRecomputed: Date(),
                             status: .active, edgeKey: key, toSubtype: cols.toSubtype)
        let parsed = EdgeIdentity.parse(r)
        #expect(parsed?.exposure == from)
        #expect(parsed?.outcome == to)
    }
    @Test func objectExposureRoundTrips() {
        roundTrip(.object(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, .food), .symptom("bloating"))
    }
    @Test func derivedExposuresRoundTrip() {
        roundTrip(.derived(.shortSleep), .symptom("fatigue"))
        roundTrip(.derived(.pressureDrop), .symptom("headache"))
        roundTrip(.derived(.cyclePhase(.luteal)), .symptom("cramps"))
        roundTrip(.derived(.highStress), .lowMood)
        roundTrip(.derived(.pressureDrop), .goodMood)
        roundTrip(.derived(.fullMoon), .symptom("headache"))
        roundTrip(.derived(.mercuryRetrograde), .lowMood)
    }
    @Test func goodMoodColumns() {
        let cols = EdgeIdentity.columns(from: .derived(.shortSleep), to: .goodMood)
        #expect(cols.toCategory == "mood")
        #expect(cols.toSubtype == "good")
        #expect(EdgeIdentity.parse(Relationship(
            fromObjectID: cols.fromObjectID, fromCategory: cols.fromCategory,
            toCategory: cols.toCategory, type: .possibleTrigger, firstSeen: Date(), lastSeen: Date(),
            lastRecomputed: Date(), status: .active,
            edgeKey: EdgeIdentity.edgeKey(from: .derived(.shortSleep), to: .goodMood, type: .possibleTrigger),
            toSubtype: cols.toSubtype))?.outcome == .goodMood)
    }
    @Test func objectColumnsCarryStructuredPointers() {
        let oid = UUID()
        let cols = EdgeIdentity.columns(from: .object(oid, .supplement), to: .symptom("headache"))
        #expect(cols.fromObjectID == oid)
        #expect(cols.fromCategory == "supplement")
        #expect(cols.toCategory == "symptom")
        #expect(cols.toSubtype == "headache")
    }
}
