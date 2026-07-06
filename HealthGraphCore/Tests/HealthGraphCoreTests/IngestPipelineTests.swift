import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

struct IngestPipelineTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    func event(_ category: EventCategory = .vitals, subtype: String = "restingHeartRate",
               offset: TimeInterval = 0, end: TimeInterval? = nil, value: Double = 60,
               source: EventSource = .healthKit, key: String? = "k1") -> HealthEvent {
        HealthEvent(
            timestamp: t0.addingTimeInterval(offset),
            endTimestamp: end.map { t0.addingTimeInterval($0) },
            category: category, subtype: subtype, value: value,
            source: source, createdAt: t0, dedupKey: key
        )
    }

    @Test func insertsFreshEvents() async throws {
        let db = try AppDatabase.inMemory()
        let summary = try await IngestPipeline(database: db)
            .ingest([event(key: "a"), event(offset: 60, key: "b")])
        #expect(summary == IngestSummary(inserted: 2, updated: 0, skipped: 0, replaced: 0))
        #expect(try await GRDBEventStore(database: db).count() == 2)
    }

    @Test func equalRankUpdatesInPlace() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([event(value: 60)])
        let summary = try await pipeline.ingest([event(value: 62)])
        #expect(summary == IngestSummary(inserted: 0, updated: 1, skipped: 0, replaced: 0))
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.count == 1)
        #expect(all.first?.value == 62)
    }

    @Test func lowerRankIsSkipped() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([event(value: 60, source: .healthKit)])
        let summary = try await pipeline.ingest([event(value: 99, source: .healthExportFile)])
        #expect(summary == IngestSummary(inserted: 0, updated: 0, skipped: 1, replaced: 0))
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.first?.value == 60)
        #expect(all.first?.source == .healthKit)
    }

    @Test func higherRankReplacesInPlaceKeepingID() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([event(value: 60, source: .healthExportFile)])
        let originalID = try await GRDBEventStore(database: db).recentEvents(limit: 1).first!.id
        let summary = try await pipeline.ingest([event(value: 61, source: .healthKit)])
        #expect(summary.updated == 1)
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.count == 1)
        #expect(all.first?.id == originalID)
        #expect(all.first?.source == .healthKit)
    }

    @Test func userSoftDeleteIsNeverResurrected() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        let store = GRDBEventStore(database: db)
        _ = try await pipeline.ingest([event()])
        let id = try await store.recentEvents(limit: 1).first!.id
        try await store.softDelete(id: id)
        let summary = try await pipeline.ingest([event(value: 99)])
        #expect(summary == IngestSummary(inserted: 0, updated: 0, skipped: 1, replaced: 0))
        #expect(try await store.count() == 0) // still deleted
    }

    @Test func overlappingDurationSkippedWhenExistingRankHigher() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 0, end: 3600, source: .healthKit, key: "s1")])
        // export-file segment overlapping [0, 3600] with a different key
        let summary = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 600, end: 4200,
                  source: .healthExportFile, key: "s2")])
        #expect(summary == IngestSummary(inserted: 0, updated: 0, skipped: 1, replaced: 0))
        #expect(try await GRDBEventStore(database: db).count() == 1)
    }

    @Test func equalRankFullyCoveredOverlapIsSkipped() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 0, end: 7200, source: .healthKit, key: "s1")])
        // second device's segment lies entirely within existing coverage
        let summary = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 600, end: 3600,
                  source: .healthKit, key: "s2")])
        #expect(summary == IngestSummary(inserted: 0, updated: 0, skipped: 1, replaced: 0))
        #expect(try await GRDBEventStore(database: db).count() == 1)
    }

    @Test func equalRankPartialOverlapKeepsBothSegments() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 0, end: 3600, source: .healthKit, key: "s1")])
        // Watch 00:00–01:00 + iPhone 00:30–02:00: the 01:00–02:00 coverage
        // must not be dropped
        let summary = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 1800, end: 7200,
                  source: .healthKit, key: "s2")])
        #expect(summary == IngestSummary(inserted: 1, updated: 0, skipped: 0, replaced: 0))
        #expect(try await GRDBEventStore(database: db).count() == 2)
    }

    @Test func overlappingDurationReplacedWhenIncomingRankHigher() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 0, end: 3600,
                  source: .healthExportFile, key: "s1")])
        let summary = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 600, end: 4200,
                  source: .healthKit, key: "s2")])
        #expect(summary.replaced == 1)
        let store = GRDBEventStore(database: db)
        #expect(try await store.count() == 1) // old segment soft-deleted, new one live
        #expect(try await store.rawCountIncludingDeleted() == 2)
        #expect(try await store.recentEvents(limit: 1).first?.source == .healthKit)
    }

    @Test func nonOverlappingDurationsCoexist() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 0, end: 3600, source: .healthKit, key: "s1"),
            event(.sleep, subtype: "asleepCore", offset: 7200, end: 10800, source: .healthKit, key: "s2")])
        #expect(try await GRDBEventStore(database: db).count() == 2)
    }

    @Test func duplicateKeyWithinOneBatchIsSkipped() async throws {
        let db = try AppDatabase.inMemory()
        let summary = try await IngestPipeline(database: db)
            .ingest([event(value: 60), event(value: 61)]) // same key "k1"
        #expect(summary == IngestSummary(inserted: 1, updated: 0, skipped: 1, replaced: 0))
    }

    @Test func reingestingSameBatchIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        let batch = [event(key: "a"), event(offset: 60, key: "b"),
                     event(.sleep, subtype: "asleepCore", offset: 0, end: 3600, key: "c")]
        _ = try await pipeline.ingest(batch)
        let second = try await pipeline.ingest(batch)
        #expect(second.inserted == 0)
        #expect(try await GRDBEventStore(database: db).count() == 3)
    }

    @Test func nilKeyEventsAlwaysInsert() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([event(key: nil), event(key: nil)])
        #expect(try await GRDBEventStore(database: db).count() == 2)
    }
}
