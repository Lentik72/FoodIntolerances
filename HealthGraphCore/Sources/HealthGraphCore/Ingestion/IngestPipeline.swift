import Foundation
import GRDB

/// Outcome counters for one ingest call.
public struct IngestSummary: Equatable, Sendable {
    public var inserted: Int
    public var updated: Int
    public var skipped: Int
    public var replaced: Int

    public init(inserted: Int = 0, updated: Int = 0, skipped: Int = 0, replaced: Int = 0) {
        self.inserted = inserted
        self.updated = updated
        self.skipped = skipped
        self.replaced = replaced
    }

    public static func + (l: IngestSummary, r: IngestSummary) -> IngestSummary {
        IngestSummary(inserted: l.inserted + r.inserted, updated: l.updated + r.updated,
                      skipped: l.skipped + r.skipped, replaced: l.replaced + r.replaced)
    }
}

/// Spec §5.5 source priority: live HealthKit > export file > everything else.
public enum SourcePriority {
    public static func rank(_ source: EventSource) -> Int {
        switch source {
        case .healthKit: return 3
        case .healthExportFile: return 2
        default: return 1
        }
    }
}

/// Idempotent, source-priority-aware event ingestion (spec §5.5).
/// See the dedup policy comment on `process` for the exact rules.
public struct IngestPipeline: Sendable {
    public static let batchSize = 500
    let dbWriter: any DatabaseWriter

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    /// Async entry point: batches of `batchSize`, one transaction each.
    public func ingest(_ events: [HealthEvent]) async throws -> IngestSummary {
        var total = IngestSummary()
        var index = 0
        while index < events.count {
            let batch = Array(events[index ..< min(index + Self.batchSize, events.count)])
            total = total + (try await dbWriter.write { db in
                try Self.process(batch, db: db)
            })
            index += Self.batchSize
        }
        return total
    }

    /// Synchronous core — runs inside one GRDB transaction. Exposed so the
    /// export parser's (synchronous) streaming loop can flush batches without
    /// hopping executors.
    ///
    /// Policy, in order:
    /// 1. `dedupKey == nil` → insert (manual/legacy events don't dedup).
    /// 2. Exact dedupKey match (soft-deleted rows included — the unique index
    ///    spans them): deleted → skip (user deletes are never resurrected);
    ///    incoming rank lower → skip; else update in place, keeping the
    ///    existing row's `id` and `createdAt`.
    /// 3. Duration events (endTimestamp != nil) with no exact match: overlap
    ///    against live duration events of the same category+subtype. Any
    ///    overlap with rank ≥ incoming → skip; otherwise soft-delete the
    ///    lower-rank overlaps and insert (`replaced`).
    /// 4. A dedupKey repeated within the call → later occurrence skipped.
    public static func process(_ events: [HealthEvent], db: Database) throws -> IngestSummary {
        var summary = IngestSummary()
        var seenKeys = Set<String>()

        let keys = events.compactMap(\.dedupKey)
        let existingRows = keys.isEmpty ? [] : try HealthEvent
            .filter(keys.contains(Column("dedupKey")))
            .fetchAll(db) // deliberately includes soft-deleted rows
        var existingByKey = Dictionary(existingRows.map { ($0.dedupKey!, $0) },
                                       uniquingKeysWith: { a, _ in a })

        for var event in events {
            guard let key = event.dedupKey else {
                try event.insert(db)
                summary.inserted += 1
                continue
            }
            guard seenKeys.insert(key).inserted else {
                summary.skipped += 1
                continue
            }
            if let existing = existingByKey[key] {
                if existing.deletedAt != nil {
                    summary.skipped += 1
                    continue
                }
                if SourcePriority.rank(event.source) < SourcePriority.rank(existing.source) {
                    summary.skipped += 1
                    continue
                }
                event.id = existing.id
                event.createdAt = existing.createdAt
                try event.save(db)
                existingByKey[key] = event
                summary.updated += 1
                continue
            }
            if let end = event.endTimestamp {
                let overlapping = try HealthEvent
                    .filter(Column("deletedAt") == nil)
                    .filter(Column("category") == event.category.rawValue)
                    .filter(Column("subtype") == event.subtype)
                    .filter(Column("endTimestamp") != nil)
                    .filter(Column("timestamp") < end)
                    .filter(Column("endTimestamp") > event.timestamp)
                    .fetchAll(db)
                let rank = SourcePriority.rank(event.source)
                let maxExistingRank = overlapping.map { SourcePriority.rank($0.source) }.max()
                if let maxExistingRank, maxExistingRank > rank {
                    summary.skipped += 1
                    continue
                }
                if let maxExistingRank, maxExistingRank == rank {
                    // Two equal-rank sources (e.g. Watch + iPhone via live
                    // HealthKit) recorded overlapping-but-different segments:
                    // drop the incoming one only if it adds no coverage;
                    // otherwise keep both — coverage is never truncated.
                    let peers = overlapping.filter { SourcePriority.rank($0.source) == rank }
                    if Self.isInterval(from: event.timestamp, to: end, coveredBy: peers) {
                        summary.skipped += 1
                    } else {
                        try event.insert(db)
                        summary.inserted += 1
                    }
                    continue
                }
                if overlapping.isEmpty {
                    try event.insert(db)
                    summary.inserted += 1
                } else {
                    for old in overlapping {
                        try db.execute(
                            sql: "UPDATE health_events SET deletedAt = ? WHERE id = ?",
                            arguments: [Date(), old.id])
                    }
                    try event.insert(db)
                    summary.replaced += 1
                }
                continue
            }
            try event.insert(db)
            summary.inserted += 1
        }
        return summary
    }

    /// True when [start, end] is fully covered by the union of the given
    /// events' intervals.
    static func isInterval(from start: Date, to end: Date,
                           coveredBy events: [HealthEvent]) -> Bool {
        let intervals = events
            .compactMap { e -> (Date, Date)? in
                guard let eEnd = e.endTimestamp else { return nil }
                return (e.timestamp, eEnd)
            }
            .sorted { $0.0 < $1.0 }
        var cursor = start
        for (s, e) in intervals {
            if s > cursor { return false }
            if e > cursor { cursor = e }
            if cursor >= end { return true }
        }
        return cursor >= end
    }
}
