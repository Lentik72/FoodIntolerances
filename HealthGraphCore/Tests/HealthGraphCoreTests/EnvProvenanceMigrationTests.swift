import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

/// Upgrade migration (v6): stamp temporal provenance into every existing
/// environment row's metadata AND rewrite its dedupKey to the provenance-scoped
/// format, so re-emitted events dedup against — and never resurrect — them.
struct EnvProvenanceMigrationTests {
    // A non-UTC zone catches a Calendar.current-instead-of-row-timezone bug.
    static let tz = "America/Los_Angeles"
    // A fixed instant; integer seconds so DB round-trip is loss-free.
    static let ts = Date(timeIntervalSince1970: 1_750_075_200)

    static func dayStart(_ instant: Date = ts, zone: String = tz) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal.startOfDay(for: instant)
    }

    /// Legacy pre-provenance daily key (what the old factory persisted).
    static func legacyKey(_ subtype: String) -> String {
        "environment|\(subtype)|day|\(DedupKey.minute(dayStart()))"
    }

    /// A DatabaseQueue migrated to v5 only (pre-provenance), ready to seed
    /// legacy rows before v6 runs.
    private func queueAtV5() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v5")
        return queue
    }

    private func seedLegacy(_ queue: DatabaseQueue, subtype: String,
                            metadata: [String: String]? = nil,
                            deletedAt: Date? = nil) throws {
        let event = HealthEvent(
            timestamp: Self.ts, timezoneID: Self.tz,
            category: .environment, subtype: subtype,
            source: .weatherAPI,
            metadata: metadata.flatMap { try? JSONEncoder().encode($0) },
            dedupKey: Self.legacyKey(subtype),
            deletedAt: deletedAt)
        try queue.write { db in try event.insert(db) }
    }

    // MARK: - Classification + key PARITY

    @Test func migrationStampsConservativeProvenanceAndKeyMatchesFactoryFormat() throws {
        let queue = try queueAtV5()
        // Conservative legacy classification by subtype.
        let expected: [String: TemporalProvenance] = [
            "temperature": .forecast,
            "humidity": .forecast,
            "pressure": .currentSnapshot,
            "pressureDrop": .currentSnapshot,
            "moonPhase": .observedCompletedDay,
            "season": .observedCompletedDay,
            "mercuryRetrograde": .observedCompletedDay,
            "airQuality": .forecast,   // legacy AQI is forecast-derived → NEVER observed
        ]
        try seedLegacy(queue, subtype: "temperature", metadata: ["low": "12.0"])
        try seedLegacy(queue, subtype: "humidity")
        try seedLegacy(queue, subtype: "pressure")
        try seedLegacy(queue, subtype: "pressureDrop")
        try seedLegacy(queue, subtype: "moonPhase", metadata: ["phase": "Full Moon"])
        try seedLegacy(queue, subtype: "season", metadata: ["season": "Summer"])
        try seedLegacy(queue, subtype: "mercuryRetrograde")
        try seedLegacy(queue, subtype: "airQuality")
        // Unknown subtype: left unclassified, key untouched.
        try seedLegacy(queue, subtype: "pollen")

        _ = try AppDatabase(queue) // applies v6

        let rows = try queue.read { db in try HealthEvent.fetchAll(db) }
        let bySubtype = Dictionary(uniqueKeysWithValues: rows.map { ($0.subtype ?? "", $0) })

        for (subtype, provenance) in expected {
            let row = try #require(bySubtype[subtype], "missing \(subtype)")
            #expect(row.temporalProvenance == provenance, "provenance mismatch for \(subtype)")
            // PARITY: migrated key EXACTLY equals today's factory key builder.
            let factoryKey = DedupKey.daily(.environment, subtype,
                                            dayStart: Self.dayStart(), provenance: provenance)
            #expect(row.dedupKey == factoryKey, "key parity failed for \(subtype)")
        }

        // AQI specifically must NOT be mineable (fail-closed gate keys on observed).
        #expect(bySubtype["airQuality"]?.temporalProvenance != .observedCompletedDay)

        // Existing metadata keys survive alongside the added provenance.
        let temp = try #require(bySubtype["temperature"])
        let tempMeta = try JSONDecoder().decode([String: String].self, from: temp.metadata ?? Data())
        #expect(tempMeta["low"] == "12.0")
        #expect(tempMeta["provenance"] == "forecast")

        // Unknown subtype: nil provenance, legacy key preserved verbatim.
        let pollen = try #require(bySubtype["pollen"])
        #expect(pollen.temporalProvenance == nil)
        #expect(pollen.dedupKey == Self.legacyKey("pollen"))
    }

    // MARK: - Tombstone (never resurrect) — NON-AQI subtype whose legacy and
    // new-emission provenance MATCH, so the migrated tombstone key equals the
    // new emission's key and blocks resurrection.

    @Test func migratedTombstoneBlocksResurrectionAndPreservesDeletedAt() async throws {
        let queue = try queueAtV5()
        // A soft-deleted legacy moonPhase (observedCompletedDay both sides).
        try seedLegacy(queue, subtype: "moonPhase",
                       metadata: ["phase": "Full Moon"], deletedAt: Date())

        let appDB = try AppDatabase(queue) // applies v6

        let newKey = DedupKey.daily(.environment, "moonPhase",
                                    dayStart: Self.dayStart(), provenance: .observedCompletedDay)

        // Migration rewrote the tombstone to the new key AND kept it deleted.
        try await queue.read { db in
            let row = try #require(try HealthEvent
                .filter(Column("dedupKey") == newKey).fetchOne(db))
            #expect(row.deletedAt != nil, "migration must preserve deletedAt")
        }

        // Re-emit the equivalent NEW-format event.
        let reading = EnvironmentalReading(
            date: Self.ts, pressureHPa: nil, previousPressureHPa: nil,
            moonPhaseName: "Full Moon",
            isMercuryRetrograde: false, timezoneID: Self.tz)
        let newEvents = EnvironmentalEventFactory.events(for: reading)
        #expect(newEvents.first { $0.subtype == "moonPhase" }?.dedupKey == newKey) // keys align

        let summary = try await IngestPipeline(database: appDB).ingest(newEvents)
        #expect(summary.inserted == 0)
        #expect(summary.skipped >= 1)

        // The user's delete is NOT resurrected: ZERO visible rows for that key.
        let visible = try await appDB.dbWriter.read { db in
            try HealthEvent
                .filter(Column("dedupKey") == newKey)
                .filter(Column("deletedAt") == nil)
                .fetchCount(db)
        }
        #expect(visible == 0)
    }
}
