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

    @Test func v2AddsDedupKeyColumnAndUniqueIndex() throws {
        let db = try AppDatabase.inMemory()
        try db.dbWriter.read { d in
            let cols = try d.columns(in: "health_events").map(\.name)
            #expect(cols.contains("dedupKey"))
            let indexes = try d.indexes(on: "health_events").map(\.name)
            #expect(indexes.contains("idx_events_dedupKey"))
            #expect(indexes.contains("idx_events_category_subtype_timestamp"))
        }
    }

    @Test func dedupKeyUniqueIndexRejectsSecondInsert() throws {
        let db = try AppDatabase.inMemory()
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        try db.dbWriter.write { d in
            try HealthEvent(timestamp: t, category: .sleep, subtype: "asleepCore",
                            source: .healthKit, createdAt: t,
                            dedupKey: "sleep|asleepCore|29166666").insert(d)
        }
        #expect(throws: DatabaseError.self) {
            try db.dbWriter.write { d in
                try HealthEvent(timestamp: t, category: .sleep, subtype: "asleepCore",
                                source: .healthExportFile, createdAt: t,
                                dedupKey: "sleep|asleepCore|29166666").insert(d)
            }
        }
    }

    @Test func nilDedupKeysDoNotCollide() throws {
        let db = try AppDatabase.inMemory()
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        try db.dbWriter.write { d in
            try HealthEvent(timestamp: t, category: .food, source: .manual, createdAt: t).insert(d)
            try HealthEvent(timestamp: t, category: .food, source: .manual, createdAt: t).insert(d)
        }
        let count = try db.dbWriter.read { try HealthEvent.fetchCount($0) }
        #expect(count == 2) // partial index: NULL keys are exempt
    }

    @Test func v3CreatesFTSTableAndTriggersAndBackfills() throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try db.dbWriter.write { d in
            try HealthEvent(timestamp: now, category: .symptom, subtype: "headache",
                            source: .manual, createdAt: now).insert(d)
        }
        let ftsCount = try db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT count(*) FROM health_events_fts WHERE health_events_fts MATCH 'headache'") ?? -1
        }
        #expect(ftsCount == 1)
        // Trigger keeps FTS in sync on UPDATE
        try db.dbWriter.write { d in
            try d.execute(sql: "UPDATE health_events SET subtype = 'migraine'")
        }
        let after = try db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT count(*) FROM health_events_fts WHERE health_events_fts MATCH 'migraine'") ?? -1
        }
        #expect(after == 1)
    }

    @Test func v4CreatesObjectFTSAndBackfills() throws {
        let db = try AppDatabase.inMemory()
        let obj = HealthObject(kind: .supplement, name: "Magnesium Glycinate")
        try db.dbWriter.write { d in try obj.insert(d) }
        let n = try db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT count(*) FROM health_objects_fts WHERE health_objects_fts MATCH 'magnesium'") ?? -1
        }
        #expect(n == 1)
        try db.dbWriter.write { d in try d.execute(sql: "UPDATE health_objects SET name = 'Zinc'") }
        let after = try db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT count(*) FROM health_objects_fts WHERE health_objects_fts MATCH 'zinc'") ?? -1
        }
        #expect(after == 1)
    }

    @Test func reopeningPreservesRowsAcrossMigrations() async throws {
        // Two AppDatabase instances over the same on-disk file: reopening runs the
        // migrator again and must NOT erase existing rows. NOTE: open(at:) takes a URL.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hg-1c-\(UInt64(1_750_000_000)).sqlite")
        try? FileManager.default.removeItem(at: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        do {
            let db = try AppDatabase.open(at: dir)
            try await GRDBEventStore(database: db).save(
                HealthEvent(timestamp: base, category: .note, subtype: "keep me", source: .manual, createdAt: base))
        }
        let db2 = try AppDatabase.open(at: dir)
        #expect(try await GRDBEventStore(database: db2).count() == 1)
    }

    @Test func migrationV5AddsEdgeKeyColumns() async throws {
        let db = try AppDatabase.inMemory()
        try await db.dbWriter.read { database in
            let columns = try database.columns(in: "relationships").map(\.name)
            #expect(columns.contains("edgeKey"))
            #expect(columns.contains("toSubtype"))
        }
    }
}
