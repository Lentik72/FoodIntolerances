import Foundation
import HealthGraphCore

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var feed = InsightsFeedModel(sections: [])
    @Published var pendingUndo: PendingUndo?
    @Published private(set) var demoDataLoaded = false
    struct PendingUndo: Equatable { let id: UUID; let priorStatus: RelStatus }

    private let database: AppDatabase
    private let now: () -> Date
    private let relStore: GRDBRelationshipStore
    private let objectStore: GRDBObjectStore
    private let engine: EvidenceEngine
    private let config = InsightsConfig.default
    private let hasSyntheticDataCheck: @Sendable () async throws -> Bool

    init(database: AppDatabase = HealthGraphProvider.shared, now: @escaping () -> Date = { Date() },
         hasSyntheticData: (@Sendable () async throws -> Bool)? = nil) {
        self.database = database; self.now = now
        self.relStore = GRDBRelationshipStore(database: database)
        self.objectStore = GRDBObjectStore(database: database)
        self.engine = EvidenceEngine(database: database)
        self.hasSyntheticDataCheck = hasSyntheticData ?? { try await database.hasSyntheticData() }
    }

    func load() async {
        // Set the demo flag first (fail closed) so an early return below still leaves
        // the banner and dismissal gate in a safe state.
        let demo = await demoDataPresentFailingClosed()
        if demo { pendingUndo = nil }        // a queued undo would target a rebuilt id
        demoDataLoaded = demo
        guard let rels = try? await relStore.all() else { feed = InsightsFeedModel(sections: []); return }
        var resolved: [ResolvedRelationship] = []
        for r in rels {
            let (label, category) = await exposure(for: r)
            var recent: [Bool] = []
            if r.status == .active, let ev = try? await engine.evidence(for: r, asOf: now()) {
                recent = ev.exposures.suffix(config.recentDotCount).map(\.outcomeFollowed)   // last-N chronological
            }
            resolved.append(ResolvedRelationship(relationship: r, exposureLabel: label,
                                                 outcomeLabel: InsightPhrasing.outcomeLabel(for: r),
                                                 exposureCategory: category, recentOutcomes: recent))
        }
        feed = InsightsFeed.build(resolved, now: now())
    }

    func dismiss(_ card: InsightCardModel) async {
        // Demo present OR unverifiable: dismissal is blocked (a dismissed demo edge could
        // later suppress a genuine edge sharing its edgeKey). Re-checked here, not only in
        // the UI, to close the stale-card race; fails closed on a query error.
        if await demoDataPresentFailingClosed() { return }
        guard var r = try? await relStore.relationship(id: card.id) else { return }
        // Only active/no-effect edges are dismissable (mirrors InsightsFeed.build's section
        // split) — belt-and-suspenders against re-suppressing an already-archived edge
        // (e.g. .decayed → .userDismissed would permanently hide a signal that could
        // otherwise re-activate on a future recompute). The hidden Dismiss button on
        // archive cards is the primary fix; this guard is defense in depth.
        guard r.status == .active || r.status == .confirmedNoEffect else { return }
        pendingUndo = PendingUndo(id: r.id, priorStatus: r.status)   // capture for undo
        r.status = .userDismissed
        try? await relStore.save(r)
        await load()
    }

    func undoDismiss() async {
        if await demoDataPresentFailingClosed() { pendingUndo = nil; return }
        guard let undo = pendingUndo, var r = try? await relStore.relationship(id: undo.id) else { return }
        r.status = undo.priorStatus
        try? await relStore.save(r)
        pendingUndo = nil
        await load()
    }

    /// Fails CLOSED: any error verifying demo presence is treated as "present", so
    /// the banner never hides and dismissal never unlocks while the database state
    /// cannot be confirmed.
    private func demoDataPresentFailingClosed() async -> Bool {
        do { return try await hasSyntheticDataCheck() }
        catch { return true }
    }

    /// Resolve the exposure's display label + a representative category for its icon.
    private func exposure(for r: Relationship) async -> (String, EventCategory) {
        if let oid = r.fromObjectID, let obj = try? await objectStore.object(id: oid) {
            let category = EventCategory(rawValue: r.fromCategory ?? "") ?? .food
            return (obj.name.capitalized, category)
        }
        if let fc = r.fromCategory, let derived = InsightPhrasing.derivedExposureLabel(fromCategory: fc) {
            let category: EventCategory = fc.hasPrefix("cyclePhase") ? .cycle
                : fc == "shortSleep" ? .sleep : fc == "highStress" ? .stress
                : fc == "pressureDrop" || fc == "fullMoon" || fc == "mercuryRetrograde"
                    || fc == "hotDay" || fc == "coldDay" || fc == "humidDay" || fc == "swingDay"
                    || fc == "poorAirDay" ? .environment : .note
            return (derived, category)
        }
        return (r.fromCategory ?? "Something", .note)
    }
}
