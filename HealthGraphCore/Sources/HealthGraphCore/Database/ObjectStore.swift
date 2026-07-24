import Foundation
import GRDB

public protocol ObjectStore {
    func findOrCreate(name: String, kind: ObjectKind, metadata: Data?,
                      syntheticBatch: String?) async throws -> HealthObject
    func object(id: UUID) async throws -> HealthObject?
    func objects(kind: ObjectKind?, includeArchived: Bool) async throws -> [HealthObject]
    func setArchived(id: UUID, _ archived: Bool) async throws
    func count() async throws -> Int
}

public struct GRDBObjectStore: ObjectStore {
    let dbWriter: any DatabaseWriter

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    public func findOrCreate(name: String, kind: ObjectKind, metadata: Data?,
                             syntheticBatch: String? = nil) async throws -> HealthObject {
        // Same derivation the init uses (both via DemoBatch/NameNormalizer), so the
        // lookup key and the stored row's normalizedName cannot diverge.
        let normalized = syntheticBatch
            .map { DemoBatch.normalizedName(name, batch: $0) }
            ?? NameNormalizer.normalize(name)
        return try await dbWriter.write { db in
            if let existing = try HealthObject
                .filter(Column("normalizedName") == normalized)
                .filter(Column("kind") == kind.rawValue)
                .filter(Column("syntheticBatch") == syntheticBatch)   // real→IS NULL, demo→= batch
                .fetchOne(db) {
                return existing
            }
            let object = HealthObject(kind: kind, name: name, metadata: metadata,
                                      syntheticBatch: syntheticBatch)   // normalizedName derived by init
            try object.insert(db)
            return object
        }
    }

    public func object(id: UUID) async throws -> HealthObject? {
        try await dbWriter.read { db in
            try HealthObject.fetchOne(db, key: id)
        }
    }

    public func objects(kind: ObjectKind?, includeArchived: Bool) async throws -> [HealthObject] {
        try await dbWriter.read { db in
            var request = HealthObject.order(Column("name"))
            if let kind {
                request = request.filter(Column("kind") == kind.rawValue)
            }
            if !includeArchived {
                request = request.filter(Column("isArchived") == false)
            }
            return try request.fetchAll(db)
        }
    }

    public func setArchived(id: UUID, _ archived: Bool) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "UPDATE health_objects SET isArchived = ? WHERE id = ?",
                arguments: [archived, id]
            )
        }
    }

    public func count() async throws -> Int {
        try await dbWriter.read { db in try HealthObject.fetchCount(db) }
    }
}
