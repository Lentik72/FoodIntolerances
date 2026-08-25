import Testing
import Foundation
@testable import HealthGraphCore

/// End-to-end over the real engine: seed → recompute → inspect relationships.
/// This is the check the device gate was meant to be, made deterministic and
/// permanent — a real graph is outcome-empty and mines nothing, so the on-device
/// version of this assertion passes for the wrong reason.
struct StressDemoAcceptanceTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func minedDB() async throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        let events = StressDemoSeed.events(endingAt: now, timeZone: TimeZone(identifier: "UTC")!)
        try await GRDBEventStore(database: db).save(events)
        _ = try await EvidenceEngine(database: db).recompute(asOf: now)
        return db
    }

    @Test func highStressToHeadacheIsMinedAndActive() async throws {
        let active = try await GRDBRelationshipStore(database: minedDB()).relationships(status: .active)
        let pairs = active.compactMap(EdgeIdentity.parse)
        #expect(pairs.contains { $0.exposure == .derived(.highStress)
                                 && $0.outcome == .symptom(StressDemoSeed.outcomeSubtype) })
    }

    @Test func theSelfPairIsNeverMinedInAnyStatus() async throws {
        // The tautology has PERFECT co-occurrence available to it — same event on
        // both sides — so it is the edge most likely to clear every gate if
        // ExposureDerivation were broken. Checked across all statuses, not just
        // active, because a demoted tautology is still a mined tautology.
        let all = try await GRDBRelationshipStore(database: minedDB()).all()
        let pairs = all.compactMap(EdgeIdentity.parse)
        #expect(!pairs.contains { $0.exposure == .derived(.highStress)
                                  && $0.outcome == .symptom(HighStressExposureSource.symptomSubtype) })
        #expect(!pairs.isEmpty)   // non-vacuous: something WAS mined
    }
}
