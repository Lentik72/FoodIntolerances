import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

@Suite struct SyntheticBatchMigrationTests {

    @Test func columnsExistAndDefaultToNilForPreExistingRows() async throws {
        let db = try AppDatabase.inMemory()
        // A row inserted through the normal path carries no batch.
        let store = GRDBEventStore(database: db)
        try await store.save(HealthEvent(timestamp: Date(), category: .symptom,
                                         subtype: "headache", source: .manual))
        let fetched = try await store.recentEvents(limit: 1)
        #expect(fetched.count == 1)
        #expect(fetched[0].syntheticBatch == nil)

        let obj = try await GRDBObjectStore(database: db)
            .findOrCreate(name: "Coffee", kind: .food, metadata: nil)
        #expect(obj.syntheticBatch == nil)
    }

    @Test func partialIndexesExistOnBothTables() throws {
        let db = try AppDatabase.inMemory()
        try db.dbWriter.read { database in
            let names = try String.fetchAll(database, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'index' AND name IN
                ('idx_events_syntheticBatch','idx_objects_syntheticBatch')
                ORDER BY name
                """)
            #expect(names == ["idx_events_syntheticBatch", "idx_objects_syntheticBatch"])
            // Both are partial (conditioned on the column being non-null).
            let sqls = try String.fetchAll(database, sql: """
                SELECT sql FROM sqlite_master WHERE type = 'index'
                AND name IN ('idx_events_syntheticBatch','idx_objects_syntheticBatch')
                """)
            for s in sqls { #expect(s.contains("syntheticBatch IS NOT NULL")) }
        }
    }

    @Test func v7PreservesPopulatedPreV7RowsWithNilBatch() throws {
        // Build a genuinely populated pre-v7 store: migrate ONLY through v6, insert
        // an event AND an object, THEN run the full migrator (through v7). v7 must
        // preserve both rows and read their new column as nil. Migrating up to a
        // named migration is the established pattern (EnvProvenanceMigrationTests:30).
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v6")   // stop at v6 — column absent
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO health_objects (id, kind, name, normalizedName, isArchived, createdAt)
                VALUES (randomblob(16), 'food', 'Coffee', 'coffee', 0, 0)
                """)
            try db.execute(sql: """
                INSERT INTO health_events (id, timestamp, timezoneID, category, source, confidence, createdAt)
                VALUES (randomblob(16), 0, 'UTC', 'symptom', 'manual', 1.0, 0)
                """)
        }

        _ = try AppDatabase(queue)                            // full migrator → adds v7

        try queue.read { db in
            // `try`-inside-comparison directly in #expect fails to compile when
            // nested in this closure on this toolchain (swift-testing macro
            // expansion issue) — bind first, matching the pattern already used
            // in partialIndexesExistOnBothTables above.
            let eventCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM health_events")
            let objectCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM health_objects")
            let eventBatch = try String.fetchOne(db, sql: "SELECT syntheticBatch FROM health_events LIMIT 1")
            let objectBatch = try String.fetchOne(db, sql: "SELECT syntheticBatch FROM health_objects LIMIT 1")
            #expect(eventCount == 1)
            #expect(objectCount == 1)
            #expect(eventBatch == nil)
            #expect(objectBatch == nil)
        }
    }
}
