import Foundation
import HealthGraphCore

/// FirstRunBackfillView's screen state: the published flags the body renders,
/// the entry policy (auto-run vs. offer recovery), and the double-invocation
/// guard. Extracted from the view so all three are pinned by direct,
/// deterministic unit tests (BackfillViewStateTests) — no mounted host.
/// The view is thin wiring: appearance and each button call exactly one
/// method here.
///
/// Run ORDER (beginAttempt, the failures snapshot, startObserving after
/// finish) stays in BackfillWorkflow, pinned by BackfillWorkflowTests — this
/// model never reads or writes import status itself.
///
/// Deliberately NOT owned here: the live progress bar. `ingestor.progress` is
/// display-only plumbing state with no decision attached to it, and mirroring
/// it would mean a Combine subscription that can itself break. The view
/// observes the ingestor directly for that one value and gates it on this
/// model's `isRunning`.
@MainActor
final class BackfillViewState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var summaries: [ImportedCategorySummary] = []
    /// True once this screen has either run an import or decided not to. Drives
    /// the Retry affordance, so a recovery screen offers it before any run.
    @Published private(set) var hasRun = false

    private let workflow: BackfillWorkflow

    /// The in-flight backfill. Read-only outside; tests await it so assertions
    /// run deterministically after completion instead of spinning a run loop.
    /// Production code never reads it.
    private(set) var backfillTask: Task<Void, Never>?

    /// Default wiring: builds BackfillWorkflow over whatever is injected — in
    /// production the root HealthKitIngestor and the ROOT-INJECTED
    /// HealthImportStatusStore, both passed down by FirstRunFlowView. Never
    /// constructs a store: a second instance would be written by Connect and
    /// read here, so the recovery branch would never see `.interrupted`.
    init(ingestor: any HealthBackfillRunning,
         importStatus: any ImportStatusRecording,
         summaryReader: any ImportedSummaryReading = HealthKitImportedSummaryReader()) {
        self.workflow = BackfillWorkflow(ingestor: ingestor,
                                         importStatus: importStatus,
                                         summaryReader: summaryReader)
    }

    /// Screen entry. Starts the import by itself — no tap — so the guard has to
    /// hold against an appearance callback that fires more than once for the
    /// same screen, and against returning to a screen whose import finished.
    func appeared() {
        guard !hasRun, !isRunning else { return }
        // An interrupted import becomes a RECOVERY screen: the user chooses
        // Retry rather than having a killed multi-minute job silently restart.
        if workflow.resumesInterruptedImport {
            hasRun = true
            return
        }
        beginRun()
    }

    func retryTapped() {
        guard !isRunning else { return }
        beginRun()
    }

    /// The guard above runs SYNCHRONOUSLY in the caller, before any dispatch:
    /// two appearances or two taps can land in the same main-actor turn, before
    /// a re-render applies `.disabled(isRunning)`, and a flag set inside the
    /// Task is too late — both would already have enqueued a backfill over the
    /// same HealthKit anchors.
    private func beginRun() {
        isRunning = true
        hasRun = true
        backfillTask = Task { await run() }
    }

    private func run() async {
        defer { isRunning = false }
        // A failed run leaves the last good summary standing: the events it
        // describes are still in the graph, and the failure is communicated by
        // the outcome copy above it rather than by erasing the line.
        if case .imported(let imported) = await workflow.run() {
            summaries = imported
        }
    }
}
