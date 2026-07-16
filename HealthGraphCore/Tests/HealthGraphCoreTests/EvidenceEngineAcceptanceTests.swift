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

    @Test func precisionRejectsNoise() async throws {
        let rels = try await GRDBRelationshipStore(database: minedDB()).relationships(status: .active)
        // Noise foods (rice/chicken/…) are logged daily but drive nothing, so no
        // active edge should point at an outcome we never planted.
        let planted: Set<String> = ["bloating", "fatigue", "headache", "tension", "cramps", "jitters", "migraine"]
        #expect(rels.allSatisfy { planted.contains($0.toSubtype ?? "") })
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
