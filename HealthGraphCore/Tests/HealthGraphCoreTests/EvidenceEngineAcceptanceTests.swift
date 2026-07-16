import Testing
import Foundation
@testable import HealthGraphCore

struct EvidenceEngineAcceptanceTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    func fullConfig() -> SyntheticConfig {
        var cfg = SyntheticConfig(
            startDate: now.addingTimeInterval(-400 * 86_400), days: 400, seed: 42,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food,
                                      outcomeSubtype: "bloating", lagHours: 8, lagJitterHours: 3,
                                      followProbability: 0.7, exposureProbabilityPerDay: 0.5)],
            outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 1...3)
        cfg.derivedScenarios = DerivedScenarios(
            shortSleepFatigue: true, pressureHeadache: true, stressSymptom: true,
            lutealSymptom: true, protectiveSupplement: true, confounderPair: true,
            nullEffectSupplement: true)
        return cfg
    }

    func minedDB() async throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try await SyntheticDataGenerator.generate(config: fullConfig()).insert(into: db)
        _ = try await EvidenceEngine(database: db).recompute(asOf: now)
        return db
    }

    @Test func recallAllPlantedPatterns() async throws {
        let rels = try await GRDBRelationshipStore(database: minedDB()).relationships(status: .active)
        let outcomes = Set(rels.map { $0.toSubtype ?? "" })
        #expect(outcomes.contains("bloating"))   // object trigger
        #expect(outcomes.contains("fatigue"))    // short-sleep
        #expect(outcomes.contains("headache"))   // pressure-drop
        #expect(outcomes.contains("tension"))    // stress
        #expect(outcomes.contains("cramps"))     // luteal
        #expect(rels.contains { $0.type == .improves })  // protective supplement (magnesium→migraine)
        // ~correct lag (spec §8 #1): dairy→bloating was planted at 8h ± 3h jitter.
        if let bloating = rels.first(where: { $0.toSubtype == "bloating" }) {
            #expect((bloating.lagHours ?? 0) >= 4 && (bloating.lagHours ?? 0) <= 16)
        }
    }

    @Test func precisionIsHonestForAnAssociationEngine() async throws {
        let db = try await minedDB()
        let objects = GRDBObjectStore(database: db)
        let active = try await GRDBRelationshipStore(database: db).relationships(status: .active)
        func pairKey(_ r: Relationship) async throws -> String {
            var exposure = r.fromCategory ?? "?"                       // derived edges carry the kind here
            if let oid = r.fromObjectID, let o = try await objects.object(id: oid) { exposure = o.name }
            return "\(exposure)|\(r.toSubtype ?? "?")"
        }
        var activePairs: Set<String> = []
        for r in active { activePairs.insert(try await pairKey(r)) }

        let planted: Set<String> = [
            "dairy|bloating", "shortSleep|fatigue", "pressureDrop|headache",
            "highStress|tension", "cyclePhase.luteal|cramps", "magnesium|migraine",
            "espresso|jitters", "croissant|jitters",
        ]
        // 1. Full recall: every planted pair is active.
        #expect(planted.isSubset(of: activePairs), "missing planted: \(planted.subtracting(activePairs))")
        // 2. Honest bounds: nothing exceeds the observational ceiling.
        #expect(active.allSatisfy { $0.confidence <= 0.75 + 1e-9 })
        // 3. Bounded precision: active ⊆ planted ∪ {real cycle correlation} ∪ (≤1 residual chance
        //    association). Perfect precision is impossible on observational data — chicken→cramps is
        //    statistically indistinguishable from a weak real signal (stability-gate design §4).
        let allowed = planted.union(["cyclePhase.menstrual|cramps"])   // genuine cycle correlation
        let residual = activePairs.subtracting(allowed)
        #expect(residual.count <= 1, "unexpected active associations beyond the documented residual: \(residual)")
    }

    @Test func illnessRecordedAsConfounderForOverlappingExposure() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let gluten = try await GRDBObjectStore(database: db).findOrCreate(name: "gluten", kind: .food, metadata: nil)
        var events: [HealthEvent] = []
        let base = now.addingTimeInterval(-40 * 86_400)
        for d in 0..<20 {
            let day = base.addingTimeInterval(Double(d) * 86_400)
            events.append(HealthEvent(timestamp: day.addingTimeInterval(9 * 3600), timezoneID: "UTC",
                                      category: .food, subtype: "gluten", objectID: gluten.id, source: .manual))
            events.append(HealthEvent(timestamp: day.addingTimeInterval(15 * 3600), timezoneID: "UTC",
                                      category: .symptom, subtype: "nausea", value: 5, source: .manual))
            if d < 18 {  // illness on 18/20 = 90% of gluten days ( > 60% )
                events.append(HealthEvent(timestamp: day.addingTimeInterval(8 * 3600), timezoneID: "UTC",
                                          category: .illness, subtype: "cold", source: .manual))
            }
        }
        try await store.save(events)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)
        let edge = try await GRDBRelationshipStore(database: db).all().first { $0.toSubtype == "nausea" }
        #expect(edge != nil)
        let ev = try await engine.evidence(for: edge!, asOf: now)
        #expect(!ev.confounders.isEmpty)   // illness shadows gluten
    }

    @Test func confounderIsRecordedForInseparablePair() async throws {
        let db = try await minedDB()
        let espresso = try await GRDBObjectStore(database: db)
            .findOrCreate(name: "espresso", kind: .food, metadata: nil)   // returns the existing object
        let edges = try await GRDBRelationshipStore(database: db).relationships(fromObjectID: espresso.id)
        guard let edge = edges.first(where: { $0.toSubtype == "jitters" }) else {
            Issue.record("expected an espresso→jitters edge"); return
        }
        let ev = try await EvidenceEngine(database: db).evidence(for: edge, asOf: now)
        #expect(!ev.confounders.isEmpty)   // croissant always co-occurs → shadows espresso
    }

    @Test func confirmedNoEffectForNullSupplement() async throws {
        let rels = try await GRDBRelationshipStore(database: minedDB()).all()
        #expect(rels.contains { $0.status == .confirmedNoEffect })
    }

    @Test func observationalCeilingNeverExceeded() async throws {
        let rels = try await GRDBRelationshipStore(database: minedDB()).all()
        #expect(rels.allSatisfy { $0.confidence <= 0.75 + 1e-9 })
    }

    @Test func deterministicAcrossRuns() async throws {
        // The engine is deterministic, but the harness mints object UUIDs from the
        // system CSPRNG (not the seed), so raw edgeKeys (which embed obj:UUID) differ
        // across two independent DBs. Compare STRUCTURAL identity instead: the same
        // seeded data must yield the same set of (fromCategory, toSubtype, type, status)
        // edges. (Intra-DB idempotence is covered by Task 13's recomputeIsIdempotent.)
        func signatures() async throws -> Set<String> {
            let db = try AppDatabase.inMemory()
            try await SyntheticDataGenerator.generate(config: fullConfig()).insert(into: db)
            _ = try await EvidenceEngine(database: db).recompute(asOf: now)
            let all = try await GRDBRelationshipStore(database: db).all()
            return Set(all.map {
                "\($0.fromCategory ?? "")|\($0.toSubtype ?? "")|\($0.type.rawValue)|\($0.status.rawValue)"
            })
        }
        let a = try await signatures(); let b = try await signatures()
        #expect(a == b)
        #expect(!a.isEmpty)
    }
}
