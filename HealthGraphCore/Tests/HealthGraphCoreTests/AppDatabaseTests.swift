import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

struct AppDatabaseTests {
    @Test func migrationCreatesCoreTables() throws {
        let db = try AppDatabase.inMemory()
        try db.dbWriter.read { d in
            #expect(try d.tableExists("health_objects"))
            #expect(try d.tableExists("health_events"))
            #expect(try d.tableExists("relationships"))
            let eventCols = try d.columns(in: "health_events").map(\.name)
            #expect(eventCols.contains("timezoneID"))
            #expect(eventCols.contains("deletedAt"))
            #expect(eventCols.contains("attachmentPath"))
            let objCols = try d.columns(in: "health_objects").map(\.name)
            #expect(objCols.contains("normalizedName"))
            let relCols = try d.columns(in: "relationships").map(\.name)
            #expect(relCols.contains("contradictionCount"))
            #expect(relCols.contains("lagHours"))
            let eventIndexes = try d.indexes(on: "health_events").map(\.name)
            #expect(eventIndexes.contains("idx_events_category_timestamp"))
            #expect(eventIndexes.contains("idx_events_object_timestamp"))
        }
    }

    @Test func migrationIsIdempotentOnReopen() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("test.sqlite")
        _ = try AppDatabase.open(at: url)
        _ = try AppDatabase.open(at: url) // must not throw on second open
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func relationshipCheckConstraintsRejectEmptyEndpoints() throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        // No fromObjectID/fromCategory: violates the "one endpoint per side" CHECK.
        let bad = Relationship(
            toCategory: "symptom", type: .possibleTrigger,
            firstSeen: now, lastSeen: now, lastRecomputed: now
        )
        #expect(throws: DatabaseError.self) {
            try db.dbWriter.write { try bad.insert($0) }
        }
    }

    @Test func eraseAllRowsEmptiesEveryTable() async throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        // async test context -> GRDB resolves to the async write/read overloads,
        // so both calls need `await` (unlike the sync throws-tests above).
        try await db.dbWriter.write { d in
            try HealthObject(kind: .food, name: "milk", createdAt: now).insert(d)
            try HealthEvent(timestamp: now, category: .food, subtype: "milk",
                            source: .manual, createdAt: now).insert(d)
            try Relationship(fromCategory: "food", toCategory: "symptom",
                             type: .possibleTrigger, firstSeen: now,
                             lastSeen: now, lastRecomputed: now).insert(d)
        }
        try await db.eraseAllRows()
        let counts = try await db.dbWriter.read { d in
            try (HealthEvent.fetchCount(d), HealthObject.fetchCount(d), Relationship.fetchCount(d))
        }
        #expect(counts == (0, 0, 0))
    }
}
