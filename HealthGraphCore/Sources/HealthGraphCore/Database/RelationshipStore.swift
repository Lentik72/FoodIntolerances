import Foundation
import GRDB

public protocol RelationshipStore {
    func save(_ relationship: Relationship) async throws
    func relationship(id: UUID) async throws -> Relationship?
    func relationships(status: RelStatus?) async throws -> [Relationship]
    func relationships(fromObjectID: UUID) async throws -> [Relationship]
    func count() async throws -> Int
    func all() async throws -> [Relationship]
    func save(_ relationships: [Relationship]) async throws
}

public struct GRDBRelationshipStore: RelationshipStore {
    let dbWriter: any DatabaseWriter

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    public func save(_ relationship: Relationship) async throws {
        try await dbWriter.write { db in
            try relationship.save(db)
        }
    }

    public func relationship(id: UUID) async throws -> Relationship? {
        try await dbWriter.read { db in
            try Relationship.fetchOne(db, key: id)
        }
    }

    public func relationships(status: RelStatus?) async throws -> [Relationship] {
        try await dbWriter.read { db in
            var request = Relationship.order(Column("confidence").desc)
            if let status {
                request = request.filter(Column("status") == status.rawValue)
            }
            return try request.fetchAll(db)
        }
    }

    public func relationships(fromObjectID: UUID) async throws -> [Relationship] {
        try await dbWriter.read { db in
            try Relationship
                .filter(Column("fromObjectID") == fromObjectID)
                .order(Column("confidence").desc)
                .fetchAll(db)
        }
    }

    public func count() async throws -> Int {
        try await dbWriter.read { db in try Relationship.fetchCount(db) }
    }

    public func all() async throws -> [Relationship] {
        try await dbWriter.read { db in try Relationship.fetchAll(db) }
    }

    public func save(_ relationships: [Relationship]) async throws {
        try await dbWriter.write { db in
            for r in relationships { try r.save(db) }
        }
    }
}
