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
    /// Injectable for the same reason `hasSyntheticDataCheck` is: it lets a test
    /// assert this is called ONCE per render rather than once per card. Defaults
    /// to the real engine, so every production call site is unaffected.
    private let evidenceReportsProvider: @Sendable ([Relationship], Date) async throws -> [UUID: RelationshipEvidence]

    init(database: AppDatabase = HealthGraphProvider.shared, now: @escaping () -> Date = { Date() },
         hasSyntheticData: (@Sendable () async throws -> Bool)? = nil,
         evidenceReports: (@Sendable ([Relationship], Date) async throws -> [UUID: RelationshipEvidence])? = nil) {
        self.database = database; self.now = now
        self.relStore = GRDBRelationshipStore(database: database)
        self.objectStore = GRDBObjectStore(database: database)
        // Captured as a local, never `self`, so the default closure below does not
        // retain the view model.
        let engine = EvidenceEngine(database: database)
        self.engine = engine
        self.hasSyntheticDataCheck = hasSyntheticData ?? { try await database.hasSyntheticData() }
        self.evidenceReportsProvider = evidenceReports ?? { rels, asOf in
            try await engine.evidenceReports(for: rels, asOf: asOf)
        }
    }

    func load() async {
        // Set the demo flag first (fail closed) so an early return below still leaves
        // the banner and dismissal gate in a safe state.
        let demo = await demoDataPresentFailingClosed()
        if demo { pendingUndo = nil }        // a queued undo would target a rebuilt id
        demoDataLoaded = demo
        guard let rels = try? await relStore.all() else { feed = InsightsFeedModel(sections: []); return }
        // ONE corpus read for every active card. `evidence(for:)` reads the ENTIRE
        // event corpus per call, so the previous per-card loop cost N full reads of
        // the graph — measured at ~7s for 10 cards over 38k events, and growing with
        // both imported history and discovered relationships.
        //
        // `asOf` is taken once, so every card in a render is dated from the same
        // instant rather than drifting across the loop.
        let asOf = now()
        let active = rels.filter { $0.status == .active }
        let reports = (try? await evidenceReportsProvider(active, asOf)) ?? [:]
        var resolved: [ResolvedRelationship] = []
        for r in rels {
            let (label, category) = await exposure(for: r)
            var recent: [Bool] = []
            // Unchanged failure behaviour: the batch path fails soft per edge, so a
            // missing entry yields the same empty dot row a failed per-card call did.
            if r.status == .active, let ev = reports[r.id] {
                recent = ev.exposures.suffix(config.recentDotCount).map(\.outcomeFollowed)   // last-N chronological
            }
            resolved.append(ResolvedRelationship(relationship: r, exposureLabel: label,
                                                 outcomeLabel: InsightPhrasing.outcomeLabel(for: r),
                                                 exposureCategory: category, recentOutcomes: recent))
        }
        feed = InsightsFeed.build(resolved, now: asOf)
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
