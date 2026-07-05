import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

struct RecordRoundtripTests {
    @Test func healthEventRoundtrips() throws {
        let db = try AppDatabase.inMemory()
        // createdAt is explicit integer seconds: GRDB stores Date as text with
        // millisecond precision, so a sub-millisecond Date() default would
        // break whole-struct equality after the roundtrip.
        let event = HealthEvent(
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            category: .symptom, subtype: "headache",
            value: 6, source: .manual,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        try db.dbWriter.write { try event.insert($0) }
        let fetched = try db.dbWriter.read { try HealthEvent.fetchOne($0, key: event.id) }
        #expect(fetched == event)
        #expect(fetched?.timezoneID == TimeZone.current.identifier)
        #expect(fetched?.deletedAt == nil)
    }

    @Test func healthObjectComputesNormalizedName() throws {
        let db = try AppDatabase.inMemory()
        let object = HealthObject(kind: .supplement, name: "Magnesium Glycinate 400mg",
                                  createdAt: Date(timeIntervalSince1970: 1_750_000_000))
        #expect(object.normalizedName == "magnesium glycinate")
        try db.dbWriter.write { try object.insert($0) }
        let fetched = try db.dbWriter.read { try HealthObject.fetchOne($0, key: object.id) }
        #expect(fetched == object)
    }

    @Test func relationshipRoundtrips() throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let rel = Relationship(
            fromCategory: "food", toCategory: "symptom",
            type: .possibleTrigger, firstSeen: now, lastSeen: now, lastRecomputed: now
        )
        try db.dbWriter.write { try rel.insert($0) }
        let fetched = try db.dbWriter.read { try Relationship.fetchOne($0, key: rel.id) }
        #expect(fetched == rel)
        #expect(fetched?.status == .candidate)
    }
}
