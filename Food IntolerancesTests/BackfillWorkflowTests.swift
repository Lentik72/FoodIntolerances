import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

/// Pins the ORDER of the backfill run's collaborator calls, not just its
/// final state — the same discipline ConnectWorkflowTests applies to Connect.
///
/// The defect this guards against is the snapshot hazard called out in the
/// plan: `lastBackfillFailures` is reset at the START of every run and
/// `progress` is nil'd in a `defer`, so both are only correct at the instant
/// `backfill()` returns. A workflow that reads failures later — after
/// `startObserving()`, or after awaiting the summary read — can observe a
/// DIFFERENT value than the run produced, and reports a partial import as a
/// clean one. No final-state assertion catches that; only the recorded
/// position of the read does.
///
/// All doubles append to ONE shared recorder so cross-collaborator ordering is
/// a single list.
@MainActor
@Suite struct BackfillWorkflowTests {

    enum Call: Equatable {
        case readOutcome
        case beginAttempt
        case failAttempt
        case backfill
        case readFailures
        case finish(events: Int, failures: [String])
        case startObserving
        case readSummaries
        case recordCategories(Int)
    }

    final class Recorder {
        var calls: [Call] = []
    }

    /// Reproduces the two production behaviors that make the snapshot
    /// load-bearing: failures are cleared when a run starts, and populated only
    /// as the run returns. The GETTER is recorded, which is what lets these
    /// tests assert *when* the workflow read it.
    final class RecordingIngestor: HealthBackfillRunning {
        struct AuthorizationError: Error {}
        let recorder: Recorder
        var shouldThrow = false
        /// What this run leaves in `lastBackfillFailures` when it returns.
        var failuresAtReturn: [String] = []
        var summary = IngestSummary(inserted: 1200)
        private var storedFailures: [String] = []

        init(recorder: Recorder) { self.recorder = recorder }

        var lastBackfillFailures: [String] {
            recorder.calls.append(.readFailures)
            return storedFailures
        }

        func backfill(years: Int) async throws -> IngestSummary {
            recorder.calls.append(.backfill)
            storedFailures = []                       // reset at run start, as production does
            if shouldThrow { throw AuthorizationError() }
            storedFailures = failuresAtReturn
            return summary
        }

        func startObserving() { recorder.calls.append(.startObserving) }
    }

    final class RecordingImportStatus: ImportStatusRecording {
        let recorder: Recorder
        var outcome: HealthImportOutcome
        init(recorder: Recorder, outcome: HealthImportOutcome = .notStarted) {
            self.recorder = recorder
            self.outcome = outcome
        }
        var currentOutcome: HealthImportOutcome {
            recorder.calls.append(.readOutcome)
            return outcome
        }
        func beginAttempt() { recorder.calls.append(.beginAttempt); outcome = .inProgress }
        func failAttempt() { recorder.calls.append(.failAttempt); outcome = .attemptFailed }
        func finish(summary: IngestSummary, failures: [String]) {
            recorder.calls.append(.finish(events: summary.inserted + summary.updated,
                                          failures: failures))
        }
        func recordCategories(_ count: Int) { recorder.calls.append(.recordCategories(count)) }
    }

    final class StubSummaryReader: ImportedSummaryReading {
        let recorder: Recorder
        /// nil models a database read that FAILED — distinct from an empty
        /// import, which is a legitimate zero.
        var result: [ImportedCategorySummary]?
        init(recorder: Recorder, result: [ImportedCategorySummary]? = StubSummaryReader.twoCategories) {
            self.recorder = recorder
            self.result = result
        }
        func healthKitSummaries() async -> [ImportedCategorySummary]? {
            recorder.calls.append(.readSummaries)
            return result
        }
        static let twoCategories = [
            ImportedCategorySummary(category: "sleep", count: 400,
                                    earliest: Date(timeIntervalSince1970: 1_700_000_000)),
            ImportedCategorySummary(category: "heartRate", count: 800,
                                    earliest: Date(timeIntervalSince1970: 1_720_000_000))]
    }

    private func harness(outcome: HealthImportOutcome = .notStarted,
                         throwing: Bool = false,
                         failures: [String] = [],
                         summaries: [ImportedCategorySummary]? = StubSummaryReader.twoCategories)
    -> (BackfillWorkflow, Recorder, RecordingImportStatus) {
        let recorder = Recorder()
        let ingestor = RecordingIngestor(recorder: recorder)
        ingestor.shouldThrow = throwing
        ingestor.failuresAtReturn = failures
        let status = RecordingImportStatus(recorder: recorder, outcome: outcome)
        let reader = StubSummaryReader(recorder: recorder, result: summaries)
        return (BackfillWorkflow(ingestor: ingestor, importStatus: status, summaryReader: reader),
                recorder, status)
    }

    // MARK: - The snapshot, and the full success ordering

    @Test func aSuccessfulRunSnapshotsFailuresAtTheMomentBackfillReturns() async {
        let (workflow, recorder, _) = harness(failures: ["HKQuantityTypeIdentifierHeartRate: no"])
        let result = await workflow.run()

        // The exact sequence. `.readFailures` sits immediately after `.backfill`
        // and BEFORE `.finish` — moved after `.startObserving` or after the
        // summary read, this assertion fails, which is the whole point.
        #expect(recorder.calls == [
            .beginAttempt,
            .backfill,
            .readFailures,
            .finish(events: 1200, failures: ["HKQuantityTypeIdentifierHeartRate: no"]),
            .startObserving,
            .readSummaries,
            .recordCategories(2),
        ])
        #expect(result == .imported(StubSummaryReader.twoCategories))
    }

    @Test func liveObservationStartsOnlyAfterTheImportedHistoryIsRecorded() async {
        // startObserving() picks up where backfill's anchors stopped, so it must
        // run after finish() has committed the run — and it must run at all, or
        // the app imports history once and then never sees another sample.
        let (workflow, recorder, _) = harness()
        _ = await workflow.run()
        let finishIndex = recorder.calls.firstIndex { if case .finish = $0 { return true }; return false }
        let observeIndex = recorder.calls.firstIndex(of: .startObserving)
        #expect(finishIndex != nil)
        #expect(observeIndex != nil)
        #expect((finishIndex ?? 0) < (observeIndex ?? 0))
    }

    // MARK: - The failure path

    @Test func aThrownBackfillFailsTheAttemptAndNeverFinishesOrObserves() async {
        let (workflow, recorder, status) = harness(throwing: true)
        let result = await workflow.run()

        #expect(result == .failed)
        // Exact: a throw must not finish the import, must not start live
        // observation, and must not blank the recorded category count.
        #expect(recorder.calls == [.beginAttempt, .backfill, .failAttempt])
        #expect(status.outcome == .attemptFailed)
    }

    // MARK: - Partial imports reach the real store as .completedWithIssues

    @Test func perTypeFailuresLandInTheRealStoreAsCompletedWithIssues() async {
        // The recording double proves the failures were PASSED; this proves the
        // production store turns them into the outcome the copy branches read.
        // A run where some types failed must never present as a clean import.
        let defaults = UserDefaults(suiteName: "backfill-workflow-\(UUID().uuidString)")!
        let store = HealthImportStatusStore(defaults: defaults)
        let recorder = Recorder()
        let ingestor = RecordingIngestor(recorder: recorder)
        ingestor.failuresAtReturn = ["HKQuantityTypeIdentifierHeartRate: The operation couldn't be completed."]
        let workflow = BackfillWorkflow(ingestor: ingestor, importStatus: store,
                                        summaryReader: StubSummaryReader(recorder: recorder))
        _ = await workflow.run()

        #expect(store.current.outcome == .completedWithIssues)
        #expect(store.current.eventsImported == 1200)
        #expect(store.current.categoriesImported == 2)
        // Identifier only — the store strips the message after the colon, and
        // no sample payload ever reaches persisted status.
        #expect(store.current.failureIdentifiers == ["HKQuantityTypeIdentifierHeartRate"])
    }

    // MARK: - A failed summary read is not a zero

    @Test func aFailedSummaryReadLeavesTheRecordedCategoryCountAlone() async {
        // A database read that throws is NOT "0 categories". Recording zero
        // would overwrite the count a successful import just established, so
        // the Data Sources screen would read "1,200 events across 0 categories".
        let (workflow, recorder, _) = harness(summaries: nil)
        let result = await workflow.run()

        #expect(result == .imported([]))
        #expect(!recorder.calls.contains { if case .recordCategories = $0 { return true }; return false })
        // Everything before the read still happened — the import itself is fine.
        #expect(recorder.calls.contains(.startObserving))
    }

    // MARK: - Recovery entry: reading status must not mutate it

    @Test func askingWhetherAnImportWasInterruptedOnlyReadsTheStatus() async {
        let (workflow, recorder, status) = harness(outcome: .interrupted)
        #expect(workflow.resumesInterruptedImport == true)
        // Exact-empty except the read: inspecting the recovery state must not
        // begin, fail, or finish anything — the screen renders before the user
        // has chosen to resume.
        #expect(recorder.calls == [.readOutcome])
        #expect(status.outcome == .interrupted)
    }

    @Test func resumingAnInterruptedImportStillBeginsAnAttempt() async {
        // Unlike Connect — which deliberately leaves `.interrupted` intact so
        // this screen can offer recovery — an actual run here IS a new attempt,
        // so it must persist `.inProgress` before touching HealthKit. Skipping
        // beginAttempt on this path leaves a killed resume undetectable: the
        // status would still read `.interrupted` from the run before it.
        let (workflow, recorder, _) = harness(outcome: .interrupted)
        _ = await workflow.run()
        #expect(recorder.calls.first == .beginAttempt)
        #expect(recorder.calls.contains(.backfill))
    }
}
