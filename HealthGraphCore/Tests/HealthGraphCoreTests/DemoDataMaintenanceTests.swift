import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

@Suite struct DemoDataMaintenanceTests {

    // Helpers ---------------------------------------------------------------

    private func seedEvent(_ db: AppDatabase, batch: String?, subtype: String) async throws {
        try await GRDBEventStore(database: db).save(
            HealthEvent(timestamp: Date(), category: .symptom, subtype: subtype,
                        source: .manual, syntheticBatch: batch))
    }
    private func seedObject(_ db: AppDatabase, batch: String?, name: String) async throws {
        _ = try await GRDBObjectStore(database: db)
            .findOrCreate(name: name, kind: .food, metadata: nil, syntheticBatch: batch)
    }
    private func insertRelationship(_ db: AppDatabase, status: RelStatus) throws {
        try db.dbWriter.write { database in
            try database.execute(sql: """
                INSERT INTO relationships
                (id, fromCategory, toCategory, type, evidenceCount, contradictionCount,
                 confidence, firstSeen, lastSeen, lastRecomputed, status)
                VALUES (randomblob(16), 'food', 'symptom', 'possibleTrigger', 1, 0,
                        0.9, 0, 0, 0, ?)
                """, arguments: [status.rawValue])
        }
    }
    private func relationshipCount(_ db: AppDatabase) throws -> Int {
        try db.dbWriter.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM relationships") ?? 0 }
    }
    private func eventCount(_ db: AppDatabase) async throws -> Int {
        try await GRDBEventStore(database: db).count()
    }
    private func objectCount(_ db: AppDatabase) throws -> Int {
        try db.dbWriter.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM health_objects") ?? 0 }
    }

    // Tests -----------------------------------------------------------------

    @Test func purgeOnCleanDatabaseIsANoOpAndReturnsFalse() async throws {
        let db = try AppDatabase.inMemory()
        try await seedEvent(db, batch: nil, subtype: "headache")   // real event
        try insertRelationship(db, status: .active)                // real active edge
        let before = try relationshipCount(db)

        let didClean = try await db.purgeSyntheticData(scope: .all)

        #expect(didClean == false)
        #expect(try relationshipCount(db) == before)               // NOT wiped — the P0 guard
        #expect(try await eventCount(db) == 1)
    }

    @Test func purgeWithSyntheticRowsRemovesThemAndNonDismissedRelationships() async throws {
        let db = try AppDatabase.inMemory()
        try await seedEvent(db, batch: nil, subtype: "realHeadache")
        try await seedEvent(db, batch: DemoBatch.weather, subtype: "demoMigraine")
        try await seedObject(db, batch: DemoBatch.weather, name: "DemoFood")
        try await seedObject(db, batch: nil, name: "RealFood")
        try insertRelationship(db, status: .active)
        try insertRelationship(db, status: .userDismissed)

        let didClean = try await db.purgeSyntheticData(scope: .all)

        #expect(didClean == true)
        #expect(try await eventCount(db) == 1)                     // only the real event remains
        #expect(try objectCount(db) == 1)                          // only RealFood remains
        #expect(try relationshipCount(db) == 1)                    // dismissed preserved, active wiped
        try await db.dbWriter.read { database in
            let status = try String.fetchOne(database, sql: "SELECT status FROM relationships LIMIT 1")
            #expect(status == "userDismissed")
        }
    }

    @Test func purgeGuardFiresOnObjectOnlyOrphan() async throws {
        let db = try AppDatabase.inMemory()
        try await seedObject(db, batch: DemoBatch.mood, name: "OrphanObject")   // objects only
        #expect(try await db.purgeSyntheticData(scope: .all) == true)
        #expect(try objectCount(db) == 0)
    }

    @Test func purgeGuardFiresOnEventOnlyOrphan() async throws {
        let db = try AppDatabase.inMemory()
        try await seedEvent(db, batch: DemoBatch.mood, subtype: "orphanEvent")  // events only
        #expect(try await db.purgeSyntheticData(scope: .all) == true)
        #expect(try await eventCount(db) == 0)
    }

    @Test func batchScopedPurgeLeavesOtherBatchesAndRealRows() async throws {
        let db = try AppDatabase.inMemory()
        try await seedEvent(db, batch: nil, subtype: "real")
        try await seedEvent(db, batch: DemoBatch.mood, subtype: "moodEvent")
        try await seedEvent(db, batch: DemoBatch.weather, subtype: "weatherEvent")
        // Spec T3: prove the OBJECTS half too — mood objects go, weather + real stay.
        try await seedObject(db, batch: nil, name: "RealFood")
        try await seedObject(db, batch: DemoBatch.mood, name: "MoodFood")
        try await seedObject(db, batch: DemoBatch.weather, name: "WeatherFood")

        let didClean = try await db.purgeSyntheticData(scope: .batch(DemoBatch.mood))

        #expect(didClean == true)
        let events = try await GRDBEventStore(database: db)
            .events(in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        #expect(Set(events.map { $0.subtype }) == ["real", "weatherEvent"])
        let objects = try await GRDBObjectStore(database: db).objects(kind: .food, includeArchived: true)
        #expect(Set(objects.map { $0.name }) == ["RealFood", "WeatherFood"])   // MoodFood gone only
    }

    @Test func reloadModeWipesRelationshipsEvenWhenItsBatchIsAbsent() async throws {
        let db = try AppDatabase.inMemory()
        try insertRelationship(db, status: .active)
        try insertRelationship(db, status: .userDismissed)
        // No rows of batch "weather" exist yet — reload must still wipe non-dismissed edges.
        try await db.resetForSeedReload(batch: DemoBatch.weather)
        #expect(try relationshipCount(db) == 1)                    // active wiped, dismissed kept
    }

    @Test func reloadModeDeletesOnlyItsOwnBatchRows() async throws {
        let db = try AppDatabase.inMemory()
        try await seedEvent(db, batch: DemoBatch.mood, subtype: "moodEvent")
        try await seedEvent(db, batch: DemoBatch.weather, subtype: "weatherEvent")
        try await db.resetForSeedReload(batch: DemoBatch.weather)
        let events = try await GRDBEventStore(database: db)
            .events(in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        #expect(events.map { $0.subtype } == ["moodEvent"])        // weather batch gone, mood kept
    }

    @Test func hasSyntheticDataReflectsPresence() async throws {
        let db = try AppDatabase.inMemory()
        #expect(try await db.hasSyntheticData() == false)
        try await seedEvent(db, batch: DemoBatch.weather, subtype: "x")
        #expect(try await db.hasSyntheticData() == true)
    }

    @Test func syncPurgeNoOpOnCleanDatabaseLeavesRelationshipsIntact() throws {
        let db = try AppDatabase.inMemory()
        // No synthetic rows → sync purge is a no-op returning false, relationships intact.
        try insertRelationship(db, status: .active)
        #expect(try db.purgeSyntheticDataSync(scope: .all) == false)
        #expect(try relationshipCount(db) == 1)
    }

    @Test func syncPurgeRemovesSyntheticRowsAndReturnsTrue() async throws {
        let db = try AppDatabase.inMemory()
        // This is the Release-bootstrap path: a container that DID hold demo data.
        try await seedEvent(db, batch: DemoBatch.weather, subtype: "demo")
        try await seedObject(db, batch: DemoBatch.weather, name: "DemoFood")
        try insertRelationship(db, status: .active)

        #expect(try db.purgeSyntheticDataSync(scope: .all) == true)
        #expect(try await eventCount(db) == 0)
        #expect(try objectCount(db) == 0)
        #expect(try relationshipCount(db) == 0)     // non-dismissed edge wiped for rebuild
    }
}
