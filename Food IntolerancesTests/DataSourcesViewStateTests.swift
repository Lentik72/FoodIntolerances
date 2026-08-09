import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

/// Pins the Data Sources screen's two lifecycle obligations, neither of which
/// is visible in a screenshot:
///
/// 1. A later import must call `startObserving()`. The root `.task` already ran
///    this session and will not retry, so a user who skipped onboarding and
///    imports from here gets NO live ingestion for the rest of the session
///    unless that call happens. The ordering itself lives in BackfillWorkflow
///    (pinned by BackfillWorkflowTests); these tests prove this screen routes
///    through that workflow rather than reimplementing it.
/// 2. The export-file import must release the screen-wake hold and clear its
///    progress on EVERY path, including a throw — otherwise a failed parse
///    leaves the device awake with a spinner that never resolves.
@MainActor
@Suite struct DataSourcesViewStateTests {

    enum Call: Equatable {
        case beginAttempt
        case failAttempt
        case backfill
        case readFailures
        case finish
        case startObserving
        case readSummaries
        case recordCategories(Int)
        case holdScreenWake
        case releaseScreenWake
        case importExportFile
    }

    final class Recorder {
        var calls: [Call] = []
        var backfills: Int { calls.filter { $0 == .backfill }.count }
        var holds: Int { calls.filter { $0 == .holdScreenWake }.count }
        var releases: Int { calls.filter { $0 == .releaseScreenWake }.count }
    }

    final class RecordingIngestor: HealthBackfillRunning {
        struct AuthorizationError: Error {}
        let recorder: Recorder
        var shouldThrow = false
        private var storedFailures: [String] = []
        init(recorder: Recorder) { self.recorder = recorder }
        var lastBackfillFailures: [String] {
            recorder.calls.append(.readFailures)
            return storedFailures
        }
        func backfill(years: Int) async throws -> IngestSummary {
            recorder.calls.append(.backfill)
            storedFailures = []
            if shouldThrow { throw AuthorizationError() }
            return IngestSummary(inserted: 1200)
        }
        func startObserving() { recorder.calls.append(.startObserving) }
    }

    final class RecordingImportStatus: ImportStatusRecording {
        let recorder: Recorder
        var outcome: HealthImportOutcome = .notStarted
        init(recorder: Recorder) { self.recorder = recorder }
        var currentOutcome: HealthImportOutcome { outcome }
        func beginAttempt() { recorder.calls.append(.beginAttempt); outcome = .inProgress }
        func failAttempt() { recorder.calls.append(.failAttempt); outcome = .attemptFailed }
        func finish(summary: IngestSummary, failures: [String]) { recorder.calls.append(.finish) }
        func recordCategories(_ count: Int) { recorder.calls.append(.recordCategories(count)) }
    }

    final class StubSummaryReader: ImportedSummaryReading {
        let recorder: Recorder
        init(recorder: Recorder) { self.recorder = recorder }
        func healthKitSummaries() async -> [ImportedCategorySummary]? {
            recorder.calls.append(.readSummaries)
            return Self.twoCategories
        }
        static let twoCategories = [
            ImportedCategorySummary(category: "sleep", count: 400,
                                    earliest: Date(timeIntervalSince1970: 1_700_000_000)),
            ImportedCategorySummary(category: "heartRate", count: 800,
                                    earliest: Date(timeIntervalSince1970: 1_720_000_000))]
    }

    final class RecordingScreenWake: ScreenWakeHolding {
        let recorder: Recorder
        init(recorder: Recorder) { self.recorder = recorder }
        func hold() { recorder.calls.append(.holdScreenWake) }
        func release() { recorder.calls.append(.releaseScreenWake) }
    }

    final class StubExportImporter: ExportFileImporting {
        let recorder: Recorder
        var errorToThrow: Error?
        /// Progress values the parse reports before finishing (or throwing).
        var progressUpdates: [Int] = []
        /// A callback captured so a test can fire it LATE — after the run ended.
        private(set) var lastProgress: (@Sendable (Int) -> Void)?
        init(recorder: Recorder) { self.recorder = recorder }
        func importExport(at url: URL, progress: @escaping @Sendable (Int) -> Void) async throws {
            recorder.calls.append(.importExportFile)
            lastProgress = progress
            for value in progressUpdates { progress(value) }
            if let errorToThrow { throw errorToThrow }
        }
    }

    private func harness(throwingBackfill: Bool = false)
    -> (state: DataSourcesViewState, recorder: Recorder,
        ingestor: RecordingIngestor, exporter: StubExportImporter) {
        let recorder = Recorder()
        let ingestor = RecordingIngestor(recorder: recorder)
        ingestor.shouldThrow = throwingBackfill
        let exporter = StubExportImporter(recorder: recorder)
        let state = DataSourcesViewState(
            ingestor: ingestor,
            importStatus: RecordingImportStatus(recorder: recorder),
            summaryReader: StubSummaryReader(recorder: recorder),
            exportImporter: exporter,
            screenWake: RecordingScreenWake(recorder: recorder))
        return (state, recorder, ingestor, exporter)
    }

    private func settle() async {
        for _ in 0..<25 { await Task.yield() }
    }

    private func pickedFile() -> Result<[URL], Error> {
        .success([URL(fileURLWithPath: "/tmp/export.zip")])
    }

    // MARK: - HealthKit import

    @Test func importingRoutesThroughTheBackfillWorkflowAndStartsLiveObservation() async {
        let h = harness()
        h.state.importTapped()
        #expect(h.state.isImporting == true)      // synchronous, disables the button this turn
        await h.state.importTask?.value

        #expect(h.recorder.calls == [
            .beginAttempt, .backfill, .readFailures, .finish,
            .startObserving, .readSummaries, .recordCategories(2),
        ])
        #expect(h.state.isImporting == false)
        #expect(h.state.summaries == StubSummaryReader.twoCategories)
    }

    @Test func twoImmediateImportTapsImportOnce() async {
        let h = harness()
        h.state.importTapped()
        h.state.importTapped()
        await h.state.importTask?.value
        await settle()
        #expect(h.recorder.backfills == 1)
    }

    @Test func aFailedImportNeverStartsObservationAndLeavesTheButtonUsable() async {
        let h = harness(throwingBackfill: true)
        h.state.importTapped()
        await h.state.importTask?.value
        #expect(h.recorder.calls == [.beginAttempt, .backfill, .failAttempt])
        #expect(h.state.isImporting == false)
    }

    // MARK: - export.zip import

    @Test func anExportImportHoldsTheScreenAwakeAndReleasesItOnSuccess() async {
        let h = harness()
        h.exporter.progressUpdates = [500, 1000]
        h.state.exportFilePicked(pickedFile())
        #expect(h.state.exportProgress == 0)      // synchronous: the card appears this turn
        await h.state.exportTask?.value
        await settle()

        #expect(h.recorder.holds == 1)
        #expect(h.recorder.releases == 1)
        #expect(h.state.exportProgress == nil)    // spinner cleared
        #expect(h.state.errorMessage == nil)
        #expect(h.state.summaries == StubSummaryReader.twoCategories)   // refreshed after parse
    }

    @Test func aThrownParseStillReleasesTheScreenAndClearsProgress() async {
        // The plan's mutant: skipping the release on the throw path leaves the
        // device awake indefinitely with a progress card that never resolves.
        struct ParseFailure: Error {}
        let h = harness()
        h.exporter.errorToThrow = ParseFailure()
        h.state.exportFilePicked(pickedFile())
        await h.state.exportTask?.value
        await settle()

        #expect(h.recorder.releases == 1)
        #expect(h.state.exportProgress == nil)
        #expect(h.state.errorMessage != nil)
    }

    @Test func aPermissionFailureExplainsItselfWithoutDumpingTheRawError() async {
        let h = harness()
        h.exporter.errorToThrow = ExportImportError.noPermission
        h.state.exportFilePicked(pickedFile())
        await h.state.exportTask?.value
        #expect(h.state.errorMessage == "No permission to read the selected file.")
    }

    @Test func anUnknownFailureGetsAHumanSentenceNotADebugDump() async {
        struct WeirdFailure: Error {}
        let h = harness()
        h.exporter.errorToThrow = WeirdFailure()
        h.state.exportFilePicked(pickedFile())
        await h.state.exportTask?.value
        let message = h.state.errorMessage ?? ""
        #expect(!message.contains("WeirdFailure"))       // no type names in the UI
        #expect(!message.contains("Error Domain"))
        #expect(message.hasSuffix("."))                  // a sentence
    }

    @Test func aLateProgressCallbackDoesNotResurrectTheSpinner() async {
        // The parser reports progress from a detached parse, so a batch callback
        // can land after the run already finished. Applied blindly it re-sets
        // exportProgress with nothing left to clear it — a card stuck at
        // "1,000 records read" forever.
        let h = harness()
        h.state.exportFilePicked(pickedFile())
        await h.state.exportTask?.value
        await settle()
        #expect(h.state.exportProgress == nil)

        h.exporter.lastProgress?(999)
        await settle()
        #expect(h.state.exportProgress == nil)
    }

    @Test func anExportImportCannotStartWhileAHealthKitImportIsRunning() async {
        let h = harness()
        h.state.importTapped()
        h.state.exportFilePicked(pickedFile())     // same turn, before any re-render
        await h.state.importTask?.value
        await settle()
        #expect(h.recorder.holds == 0)
        #expect(!h.recorder.calls.contains(.importExportFile))
    }

    // MARK: - Entry

    @Test func appearingLoadsWhatIsAlreadyImported() async {
        let h = harness()
        h.state.appeared()
        await h.state.summaryTask?.value
        #expect(h.state.summaries == StubSummaryReader.twoCategories)
    }

    // MARK: - DEBUG resets

    @Test func resettingFirstRunSetsForceShowSoTheFlowActuallyReappears() {
        // Without forceShow the reset silently does nothing: reconciliation
        // re-marks a populated graph complete on the very next launch, and the
        // developer concludes the flow is broken rather than un-reset.
        let defaults = UserDefaults(suiteName: "data-sources-reset-\(UUID().uuidString)")!
        defaults.set(3, forKey: FirstRunKeys.startedVersion)
        defaults.set(3, forKey: FirstRunKeys.completedVersion)
        defaults.set(["headache"], forKey: FirstRunKeys.symptomSeeds)

        DataSourcesViewState.resetFirstRun(defaults: defaults)

        #expect(defaults.object(forKey: FirstRunKeys.startedVersion) == nil)
        #expect(defaults.object(forKey: FirstRunKeys.completedVersion) == nil)
        #expect(defaults.object(forKey: FirstRunKeys.symptomSeeds) == nil)
        #expect(defaults.bool(forKey: FirstRunKeys.forceShow) == true)
    }

    @Test func resettingTheBackfillTouchesOnlyTheBackfillFlag() {
        // Deliberately NOT folded into resetFirstRun: clearing this invites a
        // year-long re-backfill, so it stays a separate, labelled action.
        let defaults = UserDefaults(suiteName: "data-sources-reset-\(UUID().uuidString)")!
        defaults.set(true, forKey: HealthKitIngestor.backfillCompletedKey)
        defaults.set(3, forKey: FirstRunKeys.completedVersion)

        DataSourcesViewState.resetBackfill(defaults: defaults)

        #expect(defaults.object(forKey: HealthKitIngestor.backfillCompletedKey) == nil)
        #expect(defaults.integer(forKey: FirstRunKeys.completedVersion) == 3)
    }
}
