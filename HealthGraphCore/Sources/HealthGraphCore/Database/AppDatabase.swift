import Foundation
import GRDB

/// Owns the GRDB database and its schema migrations.
/// Schema changes happen ONLY here, in numbered migrations.
public struct AppDatabase: Sendable {
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
        // Migrations are append-only and immutable from Phase 1C on: the graph is the
        // source of truth, so a shipped migration body must never change (GRDB does not
        // checksum bodies). New schema = a new numbered migration. Editing v1..vN in place
        // would silently drift schemas on existing installs. `eraseDatabaseOnSchemaChange`
        // was removed here; the DEBUG-only `eraseAllRows()` remains for the debug Reset button.

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

        migrator.registerMigration("v2") { db in
            try db.alter(table: "health_events") { t in
                // Cross-source ingest dedup (spec §5.5). NULL = exempt (manual
                // and legacy events don't participate in import dedup).
                t.add(column: "dedupKey", .text)
            }
            // Partial unique index: SQLite treats NULLs as distinct anyway,
            // but the WHERE clause keeps the index small.
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_events_dedupKey
                ON health_events(dedupKey) WHERE dedupKey IS NOT NULL
                """)
            // Serves the ingest pipeline's duration-overlap query
            // (category + subtype + time range) at 100k+ events (spec §17).
            try db.create(index: "idx_events_category_subtype_timestamp",
                          on: "health_events",
                          columns: ["category", "subtype", "timestamp"])
        }

        migrator.registerMigration("v3") { db in
            // External-content FTS5 index over subtype + category.
            // Scope is deliberately narrow in 1B; capture (1C) extends it to
            // user-typed text. unicode61 default tokenizer; camelCase subtypes
            // index as single tokens ("asleepCore" -> asleepcore) — prefix
            // queries still reach them ("asleep*").
            try db.execute(sql: """
                CREATE VIRTUAL TABLE health_events_fts USING fts5(
                    subtype, category,
                    content='health_events',
                    content_rowid='rowid'
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_events_fts_ai AFTER INSERT ON health_events BEGIN
                    INSERT INTO health_events_fts(rowid, subtype, category)
                    VALUES (new.rowid, new.subtype, new.category);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_events_fts_ad AFTER DELETE ON health_events BEGIN
                    INSERT INTO health_events_fts(health_events_fts, rowid, subtype, category)
                    VALUES ('delete', old.rowid, old.subtype, old.category);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_events_fts_au AFTER UPDATE ON health_events BEGIN
                    INSERT INTO health_events_fts(health_events_fts, rowid, subtype, category)
                    VALUES ('delete', old.rowid, old.subtype, old.category);
                    INSERT INTO health_events_fts(rowid, subtype, category)
                    VALUES (new.rowid, new.subtype, new.category);
                END
                """)
            // Backfill rows that predate the index.
            try db.execute(sql: """
                INSERT INTO health_events_fts(rowid, subtype, category)
                SELECT rowid, subtype, category FROM health_events
                """)
        }

        migrator.registerMigration("v4") { db in
            // External-content FTS over object names, so "search your history" finds
            // events by their linked substance/food name, not only the typed subtype.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE health_objects_fts USING fts5(
                    name, content='health_objects', content_rowid='rowid')
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_objects_fts_ai AFTER INSERT ON health_objects BEGIN
                    INSERT INTO health_objects_fts(rowid, name) VALUES (new.rowid, new.name);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_objects_fts_ad AFTER DELETE ON health_objects BEGIN
                    INSERT INTO health_objects_fts(health_objects_fts, rowid, name)
                    VALUES ('delete', old.rowid, old.name);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_objects_fts_au AFTER UPDATE ON health_objects BEGIN
                    INSERT INTO health_objects_fts(health_objects_fts, rowid, name)
                    VALUES ('delete', old.rowid, old.name);
                    INSERT INTO health_objects_fts(rowid, name) VALUES (new.rowid, new.name);
                END
                """)
            try db.execute(sql: """
                INSERT INTO health_objects_fts(rowid, name)
                SELECT rowid, name FROM health_objects
                """)
        }

        migrator.registerMigration("v5") { db in
            // Phase 2A edge identity. `edgeKey` is the engine-computed, deterministic
            // identity of an exposure→outcome edge (the schema deliberately left edge
            // identity to the engine, v1 comment). A composite unique index can't work
            // here — SQLite treats NULLs as distinct and every derived edge has a NULL
            // fromObjectID — so a single non-null edgeKey carries uniqueness.
            try db.alter(table: "relationships") { t in
                t.add(column: "edgeKey", .text)
                t.add(column: "toSubtype", .text)
            }
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_rel_edgeKey
                ON relationships(edgeKey) WHERE edgeKey IS NOT NULL
                """)
        }

        migrator.registerMigration("v6") { db in
            // Environmental-ingestion correctness: stamp a temporal provenance into
            // every existing environment row's metadata AND rewrite its dedupKey to
            // the provenance-scoped format, so a re-emitted event dedups against —
            // and (for soft-deleted rows) never resurrects — its legacy counterpart.
            //
            // Rewrite EVERY category='environment' row INCLUDING soft-deleted ones
            // (do NOT filter deletedAt): IngestPipeline blocks resurrection by exact
            // dedupKey match against soft-deleted rows, so a tombstone left on its
            // legacy key would not match the new provenance-scoped emission and the
            // user's delete would resurrect. `deletedAt` is preserved (untouched).
            //
            // FROZEN BODY: uses raw SQL + Row (not the HealthEvent record — a future
            // column would crash a record-based migration on fresh install) and an
            // inlined key builder (not DedupKey.daily — a future key-format change
            // must not retroactively alter what v6 emits). The parity test pins this
            // format to today's factory; any future change gets its OWN migration.
            func v6EnvironmentKey(subtype: String?, provenance: String, dayStart: Date) -> String {
                "environment|\(subtype ?? "")|\(provenance)|day|\(Int(dayStart.timeIntervalSince1970 / 60))"
            }
            // Conservative legacy classification. Weather (temperature/humidity) is
            // forecast-derived; pressure is a current snapshot; date-facts are
            // observed. Legacy airQuality → forecast (NEVER observed): it must not be
            // mined by the fail-closed gate. Unknown subtypes stay unclassified.
            func v6Provenance(_ subtype: String?) -> String? {
                switch subtype {
                case "temperature", "humidity": return "forecast"
                case "pressure", "pressureDrop": return "currentSnapshot"
                case "moonPhase", "season", "mercuryRetrograde": return "observedCompletedDay"
                case "airQuality": return "forecast"
                default: return nil
                }
            }
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, subtype, timestamp, timezoneID, metadata
                FROM health_events WHERE category = 'environment'
                """)
            for row in rows {
                let subtype = row["subtype"] as String?
                guard let provenance = v6Provenance(subtype) else { continue }
                guard let timestamp = row["timestamp"] as Date? else { continue }
                let tzID = row["timezoneID"] as String? ?? "UTC"
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: tzID) ?? .current
                let dayStart = cal.startOfDay(for: timestamp)
                var meta: [String: String] = [:]
                if let data = row["metadata"] as Data?,
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                    meta = decoded
                }
                meta["provenance"] = provenance
                let metaData = try? JSONEncoder().encode(meta)
                let newKey = v6EnvironmentKey(subtype: subtype, provenance: provenance, dayStart: dayStart)
                let id = row["id"] as DatabaseValue
                try db.execute(
                    sql: "UPDATE health_events SET metadata = ?, dedupKey = ? WHERE id = ?",
                    arguments: [metaData, newKey, id])
            }
        }

        return migrator
    }
}

#if DEBUG
extension AppDatabase {
    /// Dev/debug tooling: hard-deletes every row in every table. The single
    /// sanctioned exception to the soft-delete rule — exists so the app's
    /// DEBUG screens never need to import GRDB directly. #if DEBUG-gated so
    /// it does not exist in Release builds of the package at all; the store
    /// itself is durable in Release (no dev-time DB wipe on schema change).
    public func eraseAllRows() async throws {
        try await dbWriter.write { db in
            try HealthEvent.deleteAll(db)
            try Relationship.deleteAll(db)
            try HealthObject.deleteAll(db)
        }
    }
}
#endif
