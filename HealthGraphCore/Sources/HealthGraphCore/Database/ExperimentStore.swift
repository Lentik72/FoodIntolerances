import Foundation
import GRDB

public protocol ExperimentStore {
    func save(_ experiment: Experiment) async throws
    func experiment(id: UUID) async throws -> Experiment?
    func experiments(status: ExperimentStatus) async throws -> [Experiment]
    func all() async throws -> [Experiment]
}

public struct GRDBExperimentStore: ExperimentStore {
    let dbWriter: any DatabaseWriter

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    public func save(_ experiment: Experiment) async throws {
        try await dbWriter.write { db in try experiment.save(db) }
    }

    public func experiment(id: UUID) async throws -> Experiment? {
        try await dbWriter.read { db in try Experiment.fetchOne(db, key: id) }
    }

    public func experiments(status: ExperimentStatus) async throws -> [Experiment] {
        try await dbWriter.read { db in
            try Experiment.filter(Column("status") == status.rawValue)
                .order(Column("startedAt").desc, Column("id").desc).fetchAll(db)
        }
    }

    public func all() async throws -> [Experiment] {
        try await dbWriter.read { db in
            try Experiment.order(Column("startedAt").desc, Column("id").desc).fetchAll(db)
        }
    }
}
