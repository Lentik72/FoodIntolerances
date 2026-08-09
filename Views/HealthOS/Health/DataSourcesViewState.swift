import Foundation
import HealthGraphCore

/// DataSourcesView's screen state: the published flags the body renders, the
/// two synchronous guards, and the export-import orchestration. Extracted from
/// the view so the obligations below are pinned by direct unit tests
/// (DataSourcesViewStateTests) rather than resting on the device gate.
///
/// The HealthKit import deliberately reuses `BackfillWorkflow` — the same one
/// the first-run Backfill screen runs — instead of reimplementing the sequence.
/// That sequence has a live consequence here in particular: the root `.task`
/// already ran this session and will not retry, so a user who skipped
/// onboarding and imports from this screen gets NO live ingestion for the rest
/// of the session unless `startObserving()` is called after the import.
@MainActor
final class DataSourcesViewState: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var summaries: [ImportedCategorySummary] = []
    /// Records read so far by an export-file parse; nil when none is running.
    @Published private(set) var exportProgress: Int?
    @Published private(set) var errorMessage: String?

    private let workflow: BackfillWorkflow
    private let summaryReader: any ImportedSummaryReading
    private let exportImporter: any ExportFileImporting
    private let screenWake: any ScreenWakeHolding

    /// Read-only outside; tests await these so assertions run deterministically
    /// after completion instead of spinning a run loop.
    private(set) var importTask: Task<Void, Never>?
    private(set) var exportTask: Task<Void, Never>?
    private(set) var summaryTask: Task<Void, Never>?

    /// Distinguishes progress callbacks belonging to the CURRENT parse from
    /// stragglers of an earlier one.
    private var exportRun = 0

    init(ingestor: any HealthBackfillRunning,
         importStatus: any ImportStatusRecording,
         summaryReader: any ImportedSummaryReading = HealthKitImportedSummaryReader(),
         exportImporter: any ExportFileImporting = AppleHealthExportFileImporter(),
         screenWake: any ScreenWakeHolding = SystemScreenWake()) {
        self.workflow = BackfillWorkflow(ingestor: ingestor,
                                         importStatus: importStatus,
                                         summaryReader: summaryReader)
        self.summaryReader = summaryReader
        self.exportImporter = exportImporter
        self.screenWake = screenWake
    }

    func appeared() {
        summaryTask = Task { await refreshSummary() }
    }

    /// Both guards run SYNCHRONOUSLY, before any dispatch — two taps can land in
    /// the same main-actor turn, before a re-render applies `.disabled`. The two
    /// imports also exclude each other: they write the same graph rows, and a
    /// concurrent export parse would race the backfill's anchors.
    func importTapped() {
        guard !isImporting, exportProgress == nil else { return }
        isImporting = true
        importTask = Task { await runImport() }
    }

    func exportFilePicked(_ result: Result<[URL], Error>) {
        guard !isImporting, exportProgress == nil else { return }
        exportProgress = 0
        exportRun += 1
        let run = exportRun
        exportTask = Task { await runExportImport(result, run: run) }
    }

    private func runImport() async {
        defer { isImporting = false }
        // Ordering (beginAttempt → backfill → snapshot failures → finish →
        // startObserving → recordCategories) lives in BackfillWorkflow.
        if case .imported(let imported) = await workflow.run() {
            summaries = imported
        }
    }

    private func runExportImport(_ result: Result<[URL], Error>, run: Int) async {
        errorMessage = nil
        screenWake.hold()
        // Both must happen on EVERY path. A parse that throws otherwise leaves
        // the device awake with a progress card nothing will ever clear.
        defer {
            exportProgress = nil
            screenWake.release()
        }
        do {
            guard let picked = try result.get().first else { return }
            try await exportImporter.importExport(at: picked) { [weak self] count in
                Task { @MainActor in self?.applyExportProgress(count, run: run) }
            }
            await refreshSummary()
        } catch {
            Logger.error(error, message: "Apple Health export import failed", category: .data)
            errorMessage = DataSourcesPresentation.importErrorMessage(for: error)
        }
    }

    /// Late callbacks are dropped. The parser reports from a detached parse, so
    /// a batch can land after the run finished; applied blindly it re-sets
    /// `exportProgress` with nothing left to clear it.
    private func applyExportProgress(_ count: Int, run: Int) {
        guard run == exportRun, exportProgress != nil else { return }
        exportProgress = count
    }

    #if DEBUG
    /// `forceShow` is essential, not decoration: without it, reconciliation
    /// re-marks a populated graph complete on the very next launch and the flow
    /// never appears — the reset silently does nothing.
    static func resetFirstRun(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: FirstRunKeys.startedVersion)
        defaults.removeObject(forKey: FirstRunKeys.completedVersion)
        defaults.removeObject(forKey: FirstRunKeys.symptomSeeds)
        defaults.set(true, forKey: FirstRunKeys.forceShow)
    }

    /// Separate and labelled: clearing this invites a year-long re-backfill and
    /// silently disables observers if the flow is then abandoned.
    static func resetBackfill(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: HealthKitIngestor.backfillCompletedKey)
    }
    #endif

    private func refreshSummary() async {
        // nil means the READ failed, which is not an empty import — keep what is
        // already on screen rather than blanking it.
        if let latest = await summaryReader.healthKitSummaries() {
            summaries = latest
        }
    }
}
