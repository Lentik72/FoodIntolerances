import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct EvidenceBatchReportTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    /// Seeds a dairy→bloating signal plus an unrelated coffee exposure, so at
    /// least one edge activates and the confounder pool is non-trivial.
    func seed(into db: AppDatabase) async throws {
        let objects = GRDBObjectStore(database: db)
        let dairy = try await objects.findOrCreate(name: "dairy", kind: .food, metadata: nil)
        let coffee = try await objects.findOrCreate(name: "coffee", kind: .food, metadata: nil)
        var events: [HealthEvent] = []
        for d in 0..<30 {
            let day = now.addingTimeInterval(Double(-d) * 86_400)
            events.append(HealthEvent(timestamp: day, timezoneID: "UTC", category: .food,
                                      subtype: "dairy", objectID: dairy.id,
                                      source: .manual, createdAt: day))
            events.append(HealthEvent(timestamp: day.addingTimeInterval(1800), timezoneID: "UTC",
                                      category: .food, subtype: "coffee", objectID: coffee.id,
                                      source: .manual, createdAt: day))
            if d % 4 != 0 {
                events.append(HealthEvent(timestamp: day.addingTimeInterval(21_600), timezoneID: "UTC",
                                          category: .symptom, subtype: "bloating", value: 5,
                                          source: .manual, createdAt: day))
            }
        }
        try await GRDBEventStore(database: db).save(events)
    }

    @Test func batchMatchesPerRelationshipEvidenceExactly() async throws {
        let db = try AppDatabase.inMemory()
        try await seed(into: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)

        let rels = try await GRDBRelationshipStore(database: db).all()
        #expect(!rels.isEmpty)   // non-vacuous: the loop below must actually run

        let batch = try await engine.evidenceReports(for: rels, asOf: now)
        #expect(batch.count == rels.count)   // every relationship gets an entry

        for r in rels {
            let single = try await engine.evidence(for: r, asOf: now)
            let fromBatch = batch[r.id]
            #expect(fromBatch == single)     // byte-for-byte parity, incl. confounders + pair order
        }
    }

    @Test func unparseableRelationshipYieldsAnEmptyEntryNotAMissingKey() async throws {
        let db = try AppDatabase.inMemory()
        try await seed(into: db)
        let engine = EvidenceEngine(database: db)
        let bogus = Relationship(type: .possibleTrigger, firstSeen: now, lastSeen: now,
                                 lastRecomputed: now, edgeKey: "not-a-valid-edge-key")

        let batch = try await engine.evidenceReports(for: [bogus], asOf: now)
        let entry = batch[bogus.id]
        #expect(entry != nil)                // fail-soft: present, not dropped
        #expect(entry?.exposures.isEmpty == true)
        #expect(entry?.followCount == 0)
        #expect(entry?.relationshipID == bogus.id)
    }

    @Test func decayedRelationshipsAreReportedToo() async throws {
        let db = try AppDatabase.inMemory()
        try await seed(into: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)

        let store = GRDBRelationshipStore(database: db)
        var rels = try await store.all()
        #expect(!rels.isEmpty)
        rels[0].status = .decayed
        try await store.save(rels[0])

        let batch = try await engine.evidenceReports(for: rels, asOf: now)
        #expect(batch[rels[0].id] != nil)    // status is never consulted
    }

    @Test func illnessSentinelPrintsAsIllnessNotAUUID() {
        #expect(EvidenceEngine.illnessConfounderKey.diagnosticLabel == "illness")
        #expect(ExposureKey.derived(.highStress).diagnosticLabel == "derived:highStress")
        #expect(ExposureKey.derived(.cyclePhase(.luteal)).diagnosticLabel == "derived:cyclePhase.luteal")
    }

    @Test func everyOtherKeyLabelsExactlyAsItsEdgeToken() {
        // Pins the delegation. If the label ever forks from EdgeIdentity, the
        // dump's confounder column stops matching its own edgeKey column.
        let keys: [ExposureKey] = [
            .derived(.shortSleep), .derived(.pressureDrop), .derived(.fullMoon),
            .derived(.mercuryRetrograde), .derived(.hotDay), .derived(.coldDay),
            .derived(.humidDay), .derived(.swingDay), .derived(.poorAirDay),
            .derived(.cyclePhase(.menstrual)), .object(UUID(), .food),
        ]
        for key in keys {
            #expect(key.diagnosticLabel == EdgeIdentity.fromToken(key))
        }
    }

    @Test func anEdgeIsNeverItsOwnConfounder() async throws {
        // Pins the per-target `others` filter. Dropping it makes every edge
        // overlap itself at 1.0 and take the maximum confidence penalty.
        let db = try AppDatabase.inMemory()
        try await seed(into: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)
        let rels = try await GRDBRelationshipStore(database: db).all()
        #expect(!rels.isEmpty)
        let batch = try await engine.evidenceReports(for: rels, asOf: now)
        for r in rels {
            guard let (expKey, _) = EdgeIdentity.parse(r) else { continue }
            #expect(batch[r.id]?.confounders.contains(expKey) == false)
        }
    }
}
