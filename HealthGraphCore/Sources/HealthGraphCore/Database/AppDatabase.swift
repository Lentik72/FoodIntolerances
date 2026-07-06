import Foundation
import GRDB

/// Owns the GRDB database and its schema migrations.
/// Schema changes happen ONLY here, in numbered migrations.
public struct AppDatabase {
    public let dbWriter: any DatabaseWriter

    public init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.migrator.migrate(dbWriter)
    }

    /// Opens (creating if needed) a database file, creating parent directories.
    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let dbQueue = try DatabaseQueue(path: url.path)
        return try AppDatabase(dbQueue)
    }

    /// In-memory database for tests, previews, and the synthetic harness.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // GRDB does not checksum migration bodies: without this flag, editing
        // migration v1 during development leaves SILENT schema drift on
        // existing databases — worse than erasure. This is safe only while
        // the graph is fully reconstructible (legacy SwiftData store intact,
        // synthetic data reloadable). REMOVE this flag before Phase 1 live
        // capture ships, when the graph becomes the source of truth.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "health_objects") { t in
                t.primaryKey("id", .blob)
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("normalizedName", .text).notNull()
                t.column("metadata", .blob)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                // DB-level dedup guarantee; the implicit index also serves
                // normalized-name lookups.
                t.uniqueKey(["normalizedName", "kind"])
            }

            try db.create(table: "health_events") { t in
                t.primaryKey("id", .blob)
                t.column("timestamp", .datetime).notNull()
                t.column("timezoneID", .text).notNull()
                t.column("endTimestamp", .datetime)
                t.column("category", .text).notNull()
                t.column("subtype", .text)
                t.column("objectID", .blob)
                    .references("health_objects", onDelete: .setNull)
                t.column("value", .double)
                t.column("unit", .text)
                t.column("source", .text).notNull()
                t.column("confidence", .double).notNull().defaults(to: 1.0)
                t.column("metadata", .blob)
                t.column("attachmentPath", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(index: "idx_events_category_timestamp",
                          on: "health_events", columns: ["category", "timestamp"])
            try db.create(index: "idx_events_object_timestamp",
                          on: "health_events", columns: ["objectID", "timestamp"])

            try db.create(table: "relationships") { t in
                t.primaryKey("id", .blob)
                t.column("fromObjectID", .blob)
                    .references("health_objects", onDelete: .cascade)
                t.column("fromCategory", .text)
                t.column("toObjectID", .blob)
                    .references("health_objects", onDelete: .cascade)
                t.column("toCategory", .text)
                t.column("type", .text).notNull()
                t.column("evidenceCount", .integer).notNull().defaults(to: 0)
                t.column("contradictionCount", .integer).notNull().defaults(to: 0)
                t.column("confidence", .double).notNull().defaults(to: 0)
                t.column("strength", .double)
                t.column("lagHours", .double)
                t.column("firstSeen", .datetime).notNull()
                t.column("lastSeen", .datetime).notNull()
                t.column("lastRecomputed", .datetime).notNull()
                t.column("status", .text).notNull()
                t.column("aiExplanation", .text)
                // An edge must have at least one endpoint on each side.
                // (Semantic edge identity/uniqueness is defined by the Phase 2
                // engine — deliberately not constrained here.)
                t.check(sql: "fromObjectID IS NOT NULL OR fromCategory IS NOT NULL")
                t.check(sql: "toObjectID IS NOT NULL OR toCategory IS NOT NULL")
            }
            try db.create(index: "idx_rel_from", on: "relationships", columns: ["fromObjectID"])
            try db.create(index: "idx_rel_to", on: "relationships", columns: ["toObjectID"])
            try db.create(index: "idx_rel_status", on: "relationships", columns: ["status"])
        }

        return migrator
    }
}

#if DEBUG
extension AppDatabase {
    /// Dev/debug tooling: hard-deletes every row in every table. The single
    /// sanctioned exception to the soft-delete rule — exists so the app's
    /// DEBUG screens never need to import GRDB directly. #if DEBUG-gated
    /// (same pattern as eraseDatabaseOnSchemaChange above) so it does not
    /// exist in Release builds of the package at all.
    public func eraseAllRows() async throws {
        try await dbWriter.write { db in
            try HealthEvent.deleteAll(db)
            try Relationship.deleteAll(db)
            try HealthObject.deleteAll(db)
        }
    }
}
#endif
