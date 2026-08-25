import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

struct ExperimentStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func experiment(status: ExperimentStatus = .running,
                            shape: ExperimentShape = .repeated) -> Experiment {
        Experiment(interventionObjectID: UUID(), outcomeSubtype: "migraine", shape: shape,
                   startedAt: t0, intendedEndAt: t0.addingTimeInterval(21 * 86_400),
                   status: status, createdAt: t0)
    }

    @Test func roundTripsThroughTheDatabase() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBExperimentStore(database: db)
        let e = experiment()
        try await store.save(e)
        let back = try await store.experiment(id: e.id)
        #expect(back == e)
    }

    @Test func filtersByStatus() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBExperimentStore(database: db)
        try await store.save(experiment(status: .running))
        try await store.save(experiment(status: .completed))
        try await store.save(experiment(status: .abandoned))
        #expect(try await store.experiments(status: .running).count == 1)
        #expect(try await store.all().count == 3)
    }

    @Test func theShapeIsStoredNotInferred() async throws {
        // The whole antibiotic case rests on this column: a course and a repeated
        // intake can look identical in the events, so the declaration must survive
        // the round trip rather than being re-derived later.
        let db = try AppDatabase.inMemory()
        let store = GRDBExperimentStore(database: db)
        let course = experiment(shape: .course)
        try await store.save(course)
        #expect(try await store.experiment(id: course.id)?.shape == .course)
    }

    @Test func experimentsCoexistWithExistingEventData() async throws {
        // Experiments table can be created alongside existing event data in a
        // single migrator run, and both tables remain accessible and intact.
        let db = try AppDatabase.inMemory()
        try await GRDBEventStore(database: db).save([
            HealthEvent(timestamp: t0, category: .symptom, subtype: "migraine",
                        value: 5, unit: "severity", source: .manual)
        ])
        let store = GRDBExperimentStore(database: db)
        try await store.save(experiment())
        #expect(try await store.all().count == 1)
        #expect(try await GRDBEventStore(database: db).count() == 1)   // existing data intact
    }

    // MARK: - True upgrade path (v7 -> v8)

    /// Every other test above uses `AppDatabase.inMemory()`, which runs v1...v8
    /// in a single shot on a brand-new database — that can never exercise the
    /// v8 migration BODY running against data that is already sitting in an
    /// at-rest v7 database, which is what every real installed app does on
    /// upgrade. Precedent: EnvProvenanceMigrationTests migrates to "v5", seeds
    /// legacy rows, then applies the rest. This is that same shape for v8, the
    /// only migration this feature ships, and the only defect class here that
    /// can damage a real user's existing data.
    @Test func migratingFromV7PreservesExistingDataAndBringsUpTheExperimentsTable() async throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v7")

        // Seed data into the pre-v8 database, via the plain GRDB record API
        // (not a store, which requires an already-fully-migrated AppDatabase) —
        // exactly as EnvProvenanceMigrationTests seeds legacy rows before
        // applying the migration under test.
        // createdAt is pinned to `t0` (an integer number of seconds), not
        // `Date()`: GRDB's date round trip loses sub-second precision, so a
        // wall-clock `Date()` default would make the post-fetch equality check
        // below fail on precision alone, unrelated to what this test verifies.
        let object = HealthObject(kind: .supplement, name: "Magnesium", createdAt: t0)
        let event = HealthEvent(timestamp: t0, category: .supplement, subtype: "Magnesium",
                                objectID: object.id, value: 200, unit: "mg", source: .manual,
                                createdAt: t0)
        try await queue.write { db in
            try object.insert(db)
            try event.insert(db)
        }

        let appDB = try AppDatabase(queue)   // applies v8 on top of the seeded v7 database

        // Pre-existing rows survived the upgrade untouched.
        let objectsAfter = try await queue.read { db in try HealthObject.fetchAll(db) }
        let eventsAfter = try await queue.read { db in try HealthEvent.fetchAll(db) }
        #expect(objectsAfter == [object])
        #expect(eventsAfter == [event])

        // The experiments table introduced by v8 actually works on a database
        // that upgraded to it, not only one created fresh at v8.
        let store = GRDBExperimentStore(database: appDB)
        let e = experiment()
        try await store.save(e)
        #expect(try await store.experiment(id: e.id) == e)
    }
}
