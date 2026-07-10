import Foundation
import GRDB

/// Keyset cursor for descending timeline pagination. Derive the next cursor
/// from the LAST event of the previous page.
public struct TimelineCursor: Equatable, Sendable {
    public let timestamp: Date
    public let id: UUID
    public init(timestamp: Date, id: UUID) {
        self.timestamp = timestamp
        self.id = id
    }
}

public protocol EventStore {
    func save(_ event: HealthEvent) async throws
    func save(_ events: [HealthEvent]) async throws
    func event(id: UUID) async throws -> HealthEvent?
    func events(in interval: DateInterval, category: EventCategory?) async throws -> [HealthEvent]
    func recentEvents(limit: Int) async throws -> [HealthEvent]
    func softDelete(id: UUID) async throws
    func count() async throws -> Int
    func countsByCategory() async throws -> [String: Int]
    func countsBySource() async throws -> [String: Int]
    /// Newest-first page for the timeline. `cursor == nil` = newest page.
    /// Strictly-older-than-cursor keyset: (timestamp, id) DESC. Excludes soft-deleted.
    func eventsPage(before cursor: TimelineCursor?, limit: Int,
                    categories: Set<EventCategory>?, sources: Set<EventSource>?) async throws -> [HealthEvent]
    /// User-facing undo of a soft delete.
    func restore(id: UUID) async throws
    /// FTS-backed prefix search over subtype + category. Sanitizes input;
    /// empty/symbol-only queries return []. Newest first, soft-deleted excluded.
    func searchEvents(matching query: String, limit: Int) async throws -> [HealthEvent]
}

public struct GRDBEventStore: EventStore {
    let dbWriter: any DatabaseWriter

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    private var notDeleted: SQLExpression { Column("deletedAt") == nil }

    public func save(_ event: HealthEvent) async throws {
        try await save([event])
    }

    public func save(_ events: [HealthEvent]) async throws {
        try await dbWriter.write { db in
            for event in events { try event.save(db) }
        }
    }

    public func event(id: UUID) async throws -> HealthEvent? {
        try await dbWriter.read { [notDeleted] db in
            try HealthEvent.filter(key: id).filter(notDeleted).fetchOne(db)
        }
    }

    public func events(in interval: DateInterval, category: EventCategory?) async throws -> [HealthEvent] {
        try await dbWriter.read { [notDeleted] db in
            var request = HealthEvent
                .filter(notDeleted)
                .filter(Column("timestamp") >= interval.start)
                .filter(Column("timestamp") <= interval.end)
                .order(Column("timestamp"))
            if let category {
                request = request.filter(Column("category") == category.rawValue)
            }
            return try request.fetchAll(db)
        }
    }

    public func recentEvents(limit: Int) async throws -> [HealthEvent] {
        try await dbWriter.read { [notDeleted] db in
            try HealthEvent.filter(notDeleted)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func softDelete(id: UUID) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "UPDATE health_events SET deletedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    public func count() async throws -> Int {
        try await dbWriter.read { [notDeleted] db in
            try HealthEvent.filter(notDeleted).fetchCount(db)
        }
    }

    /// Test/debug helper: physical row count, including soft-deleted.
    public func rawCountIncludingDeleted() async throws -> Int {
        try await dbWriter.read { db in try HealthEvent.fetchCount(db) }
    }

    public func countsByCategory() async throws -> [String: Int] {
        try await groupedCounts(column: "category")
    }

    public func countsBySource() async throws -> [String: Int] {
        try await groupedCounts(column: "source")
    }

    private func groupedCounts(column: String) async throws -> [String: Int] {
        try await dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT \(column) AS k, COUNT(*) AS c FROM health_events
                WHERE deletedAt IS NULL GROUP BY \(column)
                """)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["k"] as String, $0["c"] as Int) })
        }
    }

    public func eventsPage(before cursor: TimelineCursor?, limit: Int,
                           categories: Set<EventCategory>?, sources: Set<EventSource>?) async throws -> [HealthEvent] {
        try await dbWriter.read { db in
            var conditions: [String] = ["deletedAt IS NULL"]
            var arguments: [(any DatabaseValueConvertible)?] = []
            if let cursor {
                conditions.append("(timestamp < ? OR (timestamp = ? AND id < ?))")
                arguments.append(cursor.timestamp)
                arguments.append(cursor.timestamp)
                arguments.append(cursor.id.databaseValue)
            }
            if let categories, !categories.isEmpty {
                let marks = Array(repeating: "?", count: categories.count).joined(separator: ",")
                conditions.append("category IN (\(marks))")
                arguments.append(contentsOf: categories.map(\.rawValue).sorted())
            }
            if let sources, !sources.isEmpty {
                let marks = Array(repeating: "?", count: sources.count).joined(separator: ",")
                conditions.append("source IN (\(marks))")
                arguments.append(contentsOf: sources.map(\.rawValue).sorted())
            }
            let sql = """
                SELECT * FROM health_events
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY timestamp DESC, id DESC
                LIMIT ?
                """
            arguments.append(limit)
            return try HealthEvent.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    public func restore(id: UUID) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "UPDATE health_events SET deletedAt = NULL WHERE id = ?",
                           arguments: [id.databaseValue])
        }
    }

    public func searchEvents(matching query: String, limit: Int) async throws -> [HealthEvent] {
        // Tokenize to alphanumerics; each token becomes a quoted prefix term.
        let tokens = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        let match = tokens.map { "\"\($0)\"*" }.joined(separator: " ")
        return try await dbWriter.read { db in
            try HealthEvent.fetchAll(db, sql: """
                SELECT he.* FROM health_events he
                JOIN health_events_fts f ON f.rowid = he.rowid
                WHERE health_events_fts MATCH ?
                  AND he.deletedAt IS NULL
                ORDER BY he.timestamp DESC
                LIMIT ?
                """, arguments: [match, limit])
        }
    }
}
