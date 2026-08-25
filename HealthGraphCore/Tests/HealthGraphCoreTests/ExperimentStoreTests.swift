import Testing
import Foundation
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

    @Test func migrationAddsTheTableToAnExistingDatabase() async throws {
        // v8 must apply to a database created before it existed, not only to a
        // fresh one — a migration that only works on new installs is not one.
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
}
