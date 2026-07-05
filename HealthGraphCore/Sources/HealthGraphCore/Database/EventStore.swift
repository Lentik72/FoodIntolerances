import Foundation
import GRDB

public protocol EventStore {
    func save(_ event: HealthEvent) async throws
    func save(_ events: [HealthEvent]) async throws
    func event(id: UUID) async throws -> HealthEvent?
    func events(in interval: DateInterval, category: EventCategory?) async throws -> [HealthEvent]
    func recentEvents(limit: Int) async throws -> [HealthEvent]
    func softDelete(id: UUID) async throws
    func count() async throws -> Int
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
}
