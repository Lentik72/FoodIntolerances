import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

/// Pins the screen-side seam directly on BackfillViewState — the entry policy
/// (auto-run vs. offer recovery), the published flags the body renders, and
/// the synchronous double-invocation guard on both entry points.
///
/// The guard matters more here than on Connect: this screen starts a
/// multi-minute HealthKit read by itself, on appearance, with no tap at all.
/// `.task`/`.onAppear` can fire more than once for the same screen, and Retry
/// sits right next to a run in flight — either one landing twice means two
/// concurrent backfills over the same anchors.
///
/// Run ORDER (beginAttempt, the failures snapshot, startObserving after
/// finish) stays in BackfillWorkflow, pinned by BackfillWorkflowTests; this
/// model never reads or writes import status itself.
@MainActor
@Suite struct BackfillViewStateTests {

    enum Call: Equatable {
        case readOutcome
        case beginAttempt
        case failAttempt
        case backfill
        case readFailures
        case finish
        case startObserving
        case readSummaries
        case recordCategories(Int)
    }

    final class Recorder {
        var calls: [Call] = []
        var backfills: Int { calls.filter { $0 == .backfill }.count }
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

    private func harness(outcome: HealthImportOutcome = .notStarted, throwing: Bool = false)
    -> (state: BackfillViewState, recorder: Recorder, ingestor: RecordingIngestor) {
        let recorder = Recorder()
        let ingestor = RecordingIngestor(recorder: recorder)
        ingestor.shouldThrow = throwing
        let state = BackfillViewState(
            ingestor: ingestor,
            importStatus: RecordingImportStatus(recorder: recorder, outcome: outcome),
            summaryReader: StubSummaryReader(recorder: recorder))
        return (state, recorder, ingestor)
    }

    /// Gives any main-actor work a BROKEN guard might have enqueued the chance
    /// to run before counting: each yield reschedules this test behind every
    /// job already on the main actor, so 25 of them drain a wrongly enqueued
    /// second backfill. Correct code has nothing left to run, so the pass stays
    /// fast and the test stays deterministic.
    private func settle() async {
        for _ in 0..<25 { await Task.yield() }
    }

    // MARK: - Entry: the screen starts the import itself

    @Test func appearingStartsTheImportAndPublishesTheSummary() async {
        let h = harness()
        h.state.appeared()
        // Synchronously true, before the run has had a chance to start: this is
        // what disables Continue in the same turn the screen appears.
        #expect(h.state.isRunning == true)

        await h.state.backfillTask?.value
        #expect(h.recorder.backfills == 1)
        #expect(h.state.isRunning == false)
        #expect(h.state.hasRun == true)
        #expect(h.state.summaries == StubSummaryReader.twoCategories)
    }

    @Test func twoImmediateAppearancesRunTheImportExactlyOnce() async {
        let h = harness()
        // Both in the SAME main-actor turn — no await between them, so nothing
        // dispatched has run yet. Only a guard that runs synchronously inside
        // appeared() separates one backfill from two; a flag set inside the
        // dispatched Task is too late, and two concurrent backfills would walk
        // the same HealthKit anchors at once.
        h.state.appeared()
        h.state.appeared()
        await h.state.backfillTask?.value
        await settle()
        #expect(h.recorder.backfills == 1)
    }

    @Test func appearingAgainAfterAFinishedRunDoesNotReimport() async {
        // `.onAppear` fires again when the screen is returned to. A guard on
        // `isRunning` alone lets the second appearance restart a multi-minute
        // import that already completed.
        let h = harness()
        h.state.appeared()
        await h.state.backfillTask?.value
        h.state.appeared()
        await h.state.backfillTask?.value
        await settle()
        #expect(h.recorder.backfills == 1)
    }

    // MARK: - Recovery: an interrupted import waits for the user

    @Test func anInterruptedImportOffersRecoveryInsteadOfSilentlyRestarting() async {
        let h = harness(outcome: .interrupted)
        h.state.appeared()
        await h.state.backfillTask?.value
        await settle()

        // Exact-empty except the read: the whole point of Connect preserving
        // `.interrupted` is that this screen finds it and STOPS. Auto-running
        // here restarts a killed multi-minute import with no way to decline.
        #expect(h.recorder.calls == [.readOutcome])
        #expect(h.state.isRunning == false)
        // Still "has run" so the body offers Retry rather than a bare Continue
        // over copy that says the previous import was interrupted.
        #expect(h.state.hasRun == true)
    }

    @Test func retryAfterAnInterruptedImportRunsTheImport() async {
        let h = harness(outcome: .interrupted)
        h.state.appeared()
        await h.state.backfillTask?.value
        h.state.retryTapped()
        await h.state.backfillTask?.value

        #expect(h.recorder.backfills == 1)
        #expect(h.recorder.calls.contains(.beginAttempt))
        #expect(h.state.summaries == StubSummaryReader.twoCategories)
    }

    // MARK: - Retry

    @Test func twoImmediateRetriesRunTheImportExactlyOnce() async {
        let h = harness(outcome: .interrupted)
        h.state.appeared()
        h.state.retryTapped()
        h.state.retryTapped()
        await h.state.backfillTask?.value
        await settle()
        #expect(h.recorder.backfills == 1)
    }

    @Test func aFailedRetryKeepsTheSummaryFromTheLastGoodImport() async {
        // A retry that can't reach Apple Health does not delete the history
        // already imported, so blanking the summary line would misreport it.
        // The failure is communicated by the outcome copy, not by erasure.
        let h = harness()
        h.state.appeared()
        await h.state.backfillTask?.value
        #expect(h.state.summaries.count == 2)

        h.ingestor.shouldThrow = true
        h.state.retryTapped()
        await h.state.backfillTask?.value
        #expect(h.recorder.calls.contains(.failAttempt))
        #expect(h.state.summaries == StubSummaryReader.twoCategories)
        #expect(h.state.isRunning == false)   // Retry stays tappable
    }
}
