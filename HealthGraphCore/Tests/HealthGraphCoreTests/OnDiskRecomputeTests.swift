import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

/// Diagnostic: does `EvidenceEngine.recompute` complete and produce edges when run
/// against a FILE-BACKED `AppDatabase` (the exact `AppDatabase.open(at:)` factory the
/// app uses via `HealthGraphProvider.shared`), as opposed to the `.inMemory()` DB every
/// other test uses? Motivated by an on-device observation: after seeding the 400-day
/// synthetic corpus, the running app never surfaced mined relationships (0 after minutes,
/// for a trivial 7-exposure × 1-outcome candidate set). This isolates whether the engine
/// stalls against an on-disk database, away from the simulator UI.

private struct RecomputeTimedOut: Error, CustomStringConvertible {
    let seconds: Double
    var description: String {
        "recompute did not complete within \(seconds)s — a stall/deadlock against the on-disk database"
    }
}

/// Runs `operation`, failing with `RecomputeTimedOut` if it hasn't finished in `seconds`.
private func withDeadline<T: Sendable>(
    _ seconds: Double, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw RecomputeTimedOut(seconds: seconds)
        }
        guard let first = try await group.next() else { throw RecomputeTimedOut(seconds: seconds) }
        group.cancelAll()
        return first
    }
}

/// The 400-day corpus the debug view's "Load synthetic dataset" button seeds:
/// one planted dairy→bloating trigger plus 1–3 noise foods/day (seed 42, deterministic).
private func debugViewCorpus(end: Date) -> SyntheticConfig {
    SyntheticConfig(
        startDate: end.addingTimeInterval(-400 * 86_400),
        days: 400, seed: 42,
        patterns: [PlantedPattern(
            exposureName: "dairy", exposureCategory: .food,
            outcomeSubtype: "bloating", lagHours: 12, lagJitterHours: 3,
            followProbability: 0.7, exposureProbabilityPerDay: 0.5
        )],
        outcomeBaseRatePerDay: 0.05,
        noiseFoodsPerDay: 1...3
    )
}

@Suite struct OnDiskRecomputeTests {
    private let end = Date(timeIntervalSince1970: 1_752_000_000)

    @Test func recomputeOnDiskCompletesAndProducesEdges() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ondisk-recompute-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("healthgraph.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        let db = try AppDatabase.open(at: url)          // SAME factory as HealthGraphProvider.shared
        try await SyntheticDataGenerator.generate(config: debugViewCorpus(end: end)).insert(into: db)

        let eventCount = try await GRDBEventStore(database: db).count()
        #expect(eventCount > 1000)                       // sanity: corpus seeded

        let report = try await withDeadline(90) {
            try await EvidenceEngine(database: db).recompute(asOf: end)
        }

        let relCount = try await GRDBRelationshipStore(database: db).count()
        let active = try await GRDBRelationshipStore(database: db).relationships(status: .active)
        #expect(report.relationshipsUpserted > 0)
        #expect(relCount > 0)
        #expect(active.contains { $0.toSubtype == "bloating" })   // the planted dairy→bloating edge
    }

    /// Control: identical corpus, in-memory DB. This is the configuration every other
    /// suite uses, so it should pass; if BOTH fail the corpus is the problem, if only
    /// the on-disk test fails the on-disk database is.
    @Test func recomputeInMemoryCompletesAndProducesEdges() async throws {
        let db = try AppDatabase.inMemory()
        try await SyntheticDataGenerator.generate(config: debugViewCorpus(end: end)).insert(into: db)

        let report = try await withDeadline(90) {
            try await EvidenceEngine(database: db).recompute(asOf: end)
        }
        #expect(report.relationshipsUpserted > 0)
    }
}
