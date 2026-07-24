import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct InsightsDismissalGateTests {

    /// Insert a relationship with a given status through the PRODUCTION store, so
    /// its `id` (and every column) is encoded exactly as production reads it.
    /// A raw-SQL insert of `id.uuidString` would store TEXT into the BLOB-affinity
    /// `id` column; production `relationship(id:)` binds `UUID` as a 16-byte BLOB
    /// via `fetchOne(db, key:)` and would NOT find that row — making the dismiss
    /// test pass even with a broken gate (dismiss silently no-ops when the lookup
    /// returns nil). Using the store guarantees the encodings match.
    private func makeEdge(_ db: AppDatabase, status: RelStatus) async throws -> UUID {
        // edgeKey MUST be unique per call: there is a partial UNIQUE index
        // `idx_rel_edgeKey ON relationships(edgeKey) WHERE edgeKey IS NOT NULL`
        // (AppDatabase.swift:205), and GRDB `save` INSERTs with the default
        // `.abort` conflict policy. A shared literal key would throw on the second
        // edge (e.g. the two edges in presenceCheckFailsClosedWhenItThrows). Derive
        // it from the row's own UUID so every edge is distinct.
        let id = UUID()
        let rel = Relationship(
            id: id,
            fromCategory: "food", toCategory: "symptom", type: .possibleTrigger,
            confidence: 0.9,
            firstSeen: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0),
            lastRecomputed: Date(timeIntervalSince1970: 0),
            status: status, edgeKey: "k-\(id.uuidString)")
        try await GRDBRelationshipStore(database: db).save(rel)
        return id
    }
    private func status(_ db: AppDatabase, _ id: UUID) async throws -> RelStatus? {
        // Read through the SAME public HealthGraphCore store API production uses
        // (`relationship(id:)`) — so this app-target test needs no direct `import GRDB`,
        // and it exercises the exact blob-keyed lookup path the dismiss gate depends on.
        try await GRDBRelationshipStore(database: db).relationship(id: id)?.status
    }
    private func markDemoLoaded(_ db: AppDatabase) async throws {
        try await GRDBEventStore(database: db).save(
            HealthEvent(timestamp: Date(), category: .symptom, subtype: "x",
                        source: .manual, syntheticBatch: DemoBatch.mood))
    }
    /// A minimal but real card for the given relationship id (public initializer).
    private func card(_ id: UUID) -> InsightCardModel {
        InsightCardModel(id: id, claim: "Coffee → mood", exposureCategory: .food,
                         badge: .moderate, countLine: nil, recentDots: [], subline: nil,
                         isNew: false, kind: .possibleTrigger)
    }

    @Test func dismissIsBlockedWhileDemoDataExists() async throws {
        let db = try AppDatabase.inMemory()
        let id = try await makeEdge(db, status: .active)
        try await markDemoLoaded(db)

        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 0) })
        await vm.dismiss(card(id))

        // A working dismiss would flip active → userDismissed; the gate must prevent it.
        #expect(try await status(db, id) == .active)
    }

    @Test func undoIsBlockedAndPendingUndoClearedWhileDemoDataExists() async throws {
        let db = try AppDatabase.inMemory()
        // Start ALREADY dismissed, with a queued undo whose priorStatus is .active.
        // If the gate fails and undo runs, status flips to "active" — a real
        // discriminator (starting from .active would pass even on a wrong undo).
        let id = try await makeEdge(db, status: .userDismissed)
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 0) })
        vm.pendingUndo = .init(id: id, priorStatus: .active)
        try await markDemoLoaded(db)

        await vm.undoDismiss()

        #expect(vm.pendingUndo == nil)                      // cleared without writing
        #expect(try await status(db, id) == .userDismissed)      // undo did NOT execute
    }

    @Test func demoDataLoadedFlagTracksPresence() async throws {
        let db = try AppDatabase.inMemory()
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 0) })
        await vm.load()
        #expect(vm.demoDataLoaded == false)
        try await GRDBEventStore(database: db).save(
            HealthEvent(timestamp: Date(), category: .symptom, subtype: "x",
                        source: .manual, syntheticBatch: DemoBatch.weather))
        await vm.load()
        #expect(vm.demoDataLoaded == true)
    }

    @Test func loadClearsPendingUndoWhenDemoDataBecomesPresent() async throws {
        // Spec T16: the load()-driven reconciliation (not the undo guard's own clear).
        let db = try AppDatabase.inMemory()
        let id = try await makeEdge(db, status: .userDismissed)
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 0) })
        vm.pendingUndo = .init(id: id, priorStatus: .active)
        try await markDemoLoaded(db)                 // demo data "becomes present"
        await vm.load()
        #expect(vm.pendingUndo == nil)               // cleared by load(), before its early return
    }

    @Test func presenceCheckFailsClosedWhenItThrows() async throws {
        struct Boom: Error {}
        let db = try AppDatabase.inMemory()
        // No demo data actually present, but the checker throws — must fail CLOSED.
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 0) },
                                   hasSyntheticData: { throw Boom() })

        await vm.load()
        #expect(vm.demoDataLoaded == true)                  // unverifiable → treated as present

        // Undo is blocked and pendingUndo cleared, even though the DB has no demo rows.
        let dismissed = try await makeEdge(db, status: .userDismissed)
        vm.pendingUndo = .init(id: dismissed, priorStatus: .active)
        await vm.undoDismiss()
        #expect(vm.pendingUndo == nil)
        #expect(try await status(db, dismissed) == .userDismissed)   // undo did NOT run

        // Dismiss is blocked too.
        let active = try await makeEdge(db, status: .active)
        await vm.dismiss(card(active))
        #expect(try await status(db, active) == .active)             // dismiss did NOT run
    }
}
