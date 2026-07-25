import Foundation
import GRDB

/// Which synthetic rows a maintenance operation targets.
public enum SyntheticScope: Sendable {
    case all                 // syntheticBatch IS NOT NULL
    case batch(String)       // syntheticBatch = ?
}

public extension AppDatabase {

    /// PURGE MODE (clear button, Release purge). Existence-guarded across BOTH
    /// tables: if no row matches the scope in `health_events` OR `health_objects`,
    /// nothing is touched and `false` is returned. This guard is load-bearing —
    /// without it every ordinary (no-demo) launch would wipe real relationships.
    /// When rows match, in one transaction: wipe non-dismissed relationships,
    /// delete matching events, delete matching objects. Returns whether it acted.
    @discardableResult
    func purgeSyntheticData(scope: SyntheticScope) async throws -> Bool {
        try await dbWriter.write { db in try Self.purge(db, scope: scope) }
    }

    /// Synchronous variant for bootstrap (the Release purge runs before the
    /// database handle is exposed, where no `await` is available).
    @discardableResult
    func purgeSyntheticDataSync(scope: SyntheticScope) throws -> Bool {
        try dbWriter.write { db in try Self.purge(db, scope: scope) }
    }

    /// RELOAD MODE (seed buttons). Unconditionally wipes non-dismissed
    /// relationships (the incoming dataset shifts every baseline) and deletes
    /// only this batch's existing rows. No guard, no return — the caller always
    /// inserts a fresh dataset and recomputes afterward.
    func resetForSeedReload(batch: String) async throws {
        try await dbWriter.write { db in
            try Self.wipeNonDismissedRelationships(db)
            try Self.deleteSyntheticRows(db, scope: .batch(batch))
        }
    }

    /// True if any synthetic row exists (drives the banner and the dismissal gate).
    func hasSyntheticData() async throws -> Bool {
        try await dbWriter.read { db in try Self.syntheticRowsExist(db, scope: .all) }
    }

    // MARK: - Shared internals

    private static func purge(_ db: Database, scope: SyntheticScope) throws -> Bool {
        guard try syntheticRowsExist(db, scope: scope) else { return false }
        try wipeNonDismissedRelationships(db)
        try deleteSyntheticRows(db, scope: scope)
        return true
    }

    /// The scope's WHERE clause and its bound argument (if any).
    private static func clause(_ scope: SyntheticScope) -> (sql: String, args: StatementArguments) {
        switch scope {
        case .all:            return ("syntheticBatch IS NOT NULL", [])
        case .batch(let b):   return ("syntheticBatch = ?", [b])
        }
    }

    /// Existence guard across BOTH tables (an interrupted seed can leave an
    /// object-only or event-only orphan; a one-table check would skip the purge).
    private static func syntheticRowsExist(_ db: Database, scope: SyntheticScope) throws -> Bool {
        let (where_, args) = clause(scope)
        let inEvents = try Bool.fetchOne(db,
            sql: "SELECT EXISTS(SELECT 1 FROM health_events WHERE \(where_))", arguments: args) ?? false
        if inEvents { return true }
        return try Bool.fetchOne(db,
            sql: "SELECT EXISTS(SELECT 1 FROM health_objects WHERE \(where_))", arguments: args) ?? false
    }

    private static func wipeNonDismissedRelationships(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM relationships WHERE status <> ?",
                       arguments: [RelStatus.userDismissed.rawValue])
    }

    /// Events before objects: the `objectID` FK is `.setNull`, so deleting demo
    /// events first prevents any real event that referenced a demo object from
    /// being stranded with a nulled link mid-transaction.
    private static func deleteSyntheticRows(_ db: Database, scope: SyntheticScope) throws {
        let (where_, args) = clause(scope)
        try db.execute(sql: "DELETE FROM health_events WHERE \(where_)", arguments: args)
        try db.execute(sql: "DELETE FROM health_objects WHERE \(where_)", arguments: args)
    }
}
