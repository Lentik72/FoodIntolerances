import Testing
import Foundation
@testable import HealthGraphCore

struct EvidenceEngineTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    // A dataset where "dairy" reliably precedes "bloating".
    func seedDairyBloating(into db: AppDatabase) async throws {
        let store = GRDBEventStore(database: db)
        let objects = GRDBObjectStore(database: db)
        let dairy = try await objects.findOrCreate(name: "dairy", kind: .food, metadata: nil)
        var events: [HealthEvent] = []
        let base = now.addingTimeInterval(-60 * 86_400)   // 60 days of history
        for d in 0..<30 {
            let exp = base.addingTimeInterval(Double(d) * 2 * 86_400 + 9 * 3600)  // every 2 days, 09:00
            events.append(HealthEvent(timestamp: exp, timezoneID: "UTC", category: .food,
                                      subtype: "dairy", objectID: dairy.id, source: .manual))
            events.append(HealthEvent(timestamp: exp.addingTimeInterval(6 * 3600), timezoneID: "UTC",
                                      category: .symptom, subtype: "bloating", value: 6, source: .manual))
        }
        try await store.save(events)
    }

    @Test func minesDairyBloatingAsActiveTrigger() async throws {
        let db = try AppDatabase.inMemory()
        try await seedDairyBloating(into: db)
        let report = try await EvidenceEngine(database: db).recompute(asOf: now)
        #expect(report.pairsEvaluated >= 1)
        let rels = try await GRDBRelationshipStore(database: db).relationships(status: .active)
        #expect(rels.contains { $0.toSubtype == "bloating" && $0.type == .possibleTrigger })
    }

    @Test func recomputeIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        try await seedDairyBloating(into: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)
        let first = try await GRDBRelationshipStore(database: db).all()
        _ = try await engine.recompute(asOf: now)
        let second = try await GRDBRelationshipStore(database: db).all()
        #expect(first.count == second.count)                       // no duplicates
        #expect(Set(first.compactMap(\.edgeKey)) == Set(second.compactMap(\.edgeKey)))
    }

    @Test func userDismissedSurvivesRecompute() async throws {
        let db = try AppDatabase.inMemory()
        try await seedDairyBloating(into: db)
        let store = GRDBRelationshipStore(database: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)
        var rel = try await store.all().first { $0.toSubtype == "bloating" }!
        rel.status = .userDismissed
        try await store.save(rel)
        _ = try await engine.recompute(asOf: now)
        let after = try await store.relationship(id: rel.id)
        #expect(after?.status == .userDismissed)
    }

    @Test func disappearedEdgeDecaysOnRecompute() async throws {
        let db = try AppDatabase.inMemory()
        try await seedDairyBloating(into: db)
        let events = GRDBEventStore(database: db)
        let rels = GRDBRelationshipStore(database: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)
        #expect(try await rels.relationships(status: .active).contains { $0.toSubtype == "bloating" })
        // Remove every dairy exposure; the edge can no longer be produced → decayed.
        let all = try await events.events(in: DateInterval(start: .distantPast, end: .distantFuture),
                                          category: .food)
        for e in all where e.subtype == "dairy" { try await events.softDelete(id: e.id) }
        _ = try await engine.recompute(asOf: now)
        let bloating = try await rels.all().first { $0.toSubtype == "bloating" }
        #expect(bloating?.status == .decayed)
    }

    @Test func staleEvidenceDecaysViaStaleness() async throws {
        // §8 test #5: an edge that IS still produced but whose evidence is all old
        // → staleness pushes confidence below the decay threshold. Distinct from the
        // reconcile path above (where the edge is no longer produced at all).
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let dairy = try await GRDBObjectStore(database: db).findOrCreate(name: "dairy", kind: .food, metadata: nil)
        var events: [HealthEvent] = []
        let base = now.addingTimeInterval(-200 * 86_400)   // all evidence ~6 months old
        for d in 0..<10 {                                  // few exposures + old → low confidence
            let exp = base.addingTimeInterval(Double(d) * 2 * 86_400 + 9 * 3600)
            events.append(HealthEvent(timestamp: exp, timezoneID: "UTC", category: .food,
                                      subtype: "dairy", objectID: dairy.id, source: .manual))
            events.append(HealthEvent(timestamp: exp.addingTimeInterval(6 * 3600), timezoneID: "UTC",
                                      category: .symptom, subtype: "bloating", value: 6, source: .manual))
        }
        try await store.save(events)
        _ = try await EvidenceEngine(database: db).recompute(asOf: now)
        let bloating = try await GRDBRelationshipStore(database: db).all().first { $0.toSubtype == "bloating" }
        #expect(bloating?.status == .decayed)
    }
}
