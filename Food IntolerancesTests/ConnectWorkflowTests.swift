import Foundation
import Testing
@testable import Food_Intolerances

/// Pins the ORDER of Connect's collaborator calls, not just final state.
///
/// Why sequence, not outcome: the defect this guards against — beginAttempt()
/// called before the status is inspected — leaves the same final state
/// (.inProgress) as the correct order on the success path. Only the recorded
/// call sequence discriminates. beginAttempt() overwrites a persisted
/// .interrupted unconditionally, so the wrong order makes the Backfill
/// screen's recovery branch dead code on every onboarding path and silently
/// restarts a multi-minute import.
///
/// Both doubles append to ONE shared recorder so cross-collaborator ordering
/// (status read vs beginAttempt vs requestAuthorization) is a single list.
@MainActor
@Suite struct ConnectWorkflowTests {

    enum Call: Equatable {
        case readOutcome
        case beginAttempt
        case failAttempt
        case requestAuthorization
    }

    final class Recorder {
        var calls: [Call] = []
    }

    final class RecordingAuthorizer: HealthAuthorizationRequesting {
        struct AuthorizationError: Error {}
        let recorder: Recorder
        var shouldThrow = false
        init(recorder: Recorder) { self.recorder = recorder }
        func requestAuthorization() async throws {
            recorder.calls.append(.requestAuthorization)
            if shouldThrow { throw AuthorizationError() }
        }
    }

    final class RecordingImportStatus: ImportStatusTransitioning {
        let recorder: Recorder
        var outcome: HealthImportOutcome
        init(recorder: Recorder, outcome: HealthImportOutcome = .notStarted) {
            self.recorder = recorder
            self.outcome = outcome
        }
        /// The READ itself is recorded — that is what lets these tests assert
        /// "inspected before beginAttempt" instead of only observing writes.
        var currentOutcome: HealthImportOutcome {
            recorder.calls.append(.readOutcome)
            return outcome
        }
        func beginAttempt() { recorder.calls.append(.beginAttempt); outcome = .inProgress }
        func failAttempt() { recorder.calls.append(.failAttempt); outcome = .attemptFailed }
    }

    private func harness(outcome: HealthImportOutcome = .notStarted, throwing: Bool = false)
    -> (ConnectWorkflow, Recorder, RecordingImportStatus) {
        let recorder = Recorder()
        let authorizer = RecordingAuthorizer(recorder: recorder)
        authorizer.shouldThrow = throwing
        let status = RecordingImportStatus(recorder: recorder, outcome: outcome)
        return (ConnectWorkflow(authorizer: authorizer, importStatus: status), recorder, status)
    }

    // MARK: - Path 1: skip ("Not now")

    @Test func skipNeverRequestsAuthorizationAndLeavesImportStatusUntouched() {
        let (workflow, recorder, status) = harness()
        workflow.skip()
        // Exact-empty, not "no beginAttempt": ANY collaborator call on the
        // skip path is a defect — skip must not even read the status.
        #expect(recorder.calls == [])
        #expect(status.outcome == .notStarted)
    }

    // MARK: - Path 2: authorization success

    @Test func successInspectsStatusBeforeBeginAttemptThenAuthorizesOnceAndAdvances() async {
        let (workflow, recorder, _) = harness()
        let result = await workflow.connect()
        // Exact sequence: one read FIRST (a read after beginAttempt sees the
        // .inProgress beginAttempt just wrote, never a persisted .interrupted),
        // beginAttempt exactly once, requestAuthorization exactly once, and
        // nothing else — no failAttempt, no second read, no second request.
        #expect(recorder.calls == [.readOutcome, .beginAttempt, .requestAuthorization])
        #expect(result == .advanceToBackfill)
    }

    @Test func successLeavesTheAttemptInProgressForBackfillToFinish() async {
        // finish()/failure recording belongs to the Backfill step; Connect's
        // success hand-off is an OPEN attempt.
        let (workflow, _, status) = harness()
        _ = await workflow.connect()
        #expect(status.outcome == .inProgress)
    }

    @Test func aRetryAfterAFailedAttemptBeginsAFreshAttempt() async {
        // The beginAttempt guard is `== .interrupted`, not "anything but
        // notStarted": a retry after .attemptFailed must open a new attempt,
        // or a kill during ITS backfill would not be detectable as interrupted.
        let (workflow, recorder, _) = harness(outcome: .attemptFailed)
        let result = await workflow.connect()
        #expect(recorder.calls == [.readOutcome, .beginAttempt, .requestAuthorization])
        #expect(result == .advanceToBackfill)
    }

    // MARK: - Path 3: authorization throws

    @Test func aThrowRunsBeginThenFailOnceEachInOrderAndStaysOnConnect() async {
        let (workflow, recorder, status) = harness(throwing: true)
        let result = await workflow.connect()
        // failAttempt AFTER the request that threw, never before, never
        // without a beginAttempt earlier in the same sequence.
        #expect(recorder.calls == [.readOutcome, .beginAttempt, .requestAuthorization, .failAttempt])
        #expect(result == .stayOnConnect)
        #expect(status.outcome == .attemptFailed)
    }

    // MARK: - Path 4: interrupted recovery

    @Test func anInterruptedStatusIsNeverClobberedAndStillReachesBackfill() async {
        let (workflow, recorder, status) = harness(outcome: .interrupted)
        let result = await workflow.connect()
        // The original shipped defect: beginAttempt() before the inspection
        // overwrites the persisted .interrupted, so Backfill's recovery branch
        // never sees it and a killed import silently restarts. beginAttempt
        // must not be called AT ALL here — but authorization still runs, or
        // the user reaches Backfill's resume without HealthKit access.
        #expect(recorder.calls == [.readOutcome, .requestAuthorization])
        #expect(result == .advanceToBackfill)
        #expect(status.outcome == .interrupted)   // survives for Backfill to read
    }

    // MARK: - The real store behind the seam

    @Test func theRealStoreAdapterReportsItsPersistedOutcome() {
        // The workflow only ever sees the store THROUGH `currentOutcome`. A
        // broken adapter (hardcoded, or reading the wrong field) would
        // reintroduce the clobber defect in production while every
        // recording-double test above stays green.
        let d = UserDefaults(suiteName: "connect-workflow-\(UUID().uuidString)")!
        let store = HealthImportStatusStore(defaults: d)
        #expect(store.currentOutcome == .notStarted)
        store.beginAttempt()
        #expect(store.currentOutcome == .inProgress)
        let relaunched = HealthImportStatusStore.makeNormalizedStore(defaults: d)
        #expect(relaunched.currentOutcome == .interrupted)
    }

    @Test func aPersistedInterruptedStatusSurvivesConnectOnDisk() async {
        // End-to-end over the REAL store: an import killed mid-run, the app
        // relaunched, the user taps Connect — the .interrupted must still be
        // on disk afterwards for Backfill's recovery branch AND the next
        // launch's resume routing.
        let d = UserDefaults(suiteName: "connect-workflow-\(UUID().uuidString)")!
        HealthImportStatusStore(defaults: d).beginAttempt()          // killed mid-import
        let relaunched = HealthImportStatusStore.makeNormalizedStore(defaults: d)
        let workflow = ConnectWorkflow(authorizer: RecordingAuthorizer(recorder: Recorder()),
                                       importStatus: relaunched)
        let result = await workflow.connect()
        #expect(result == .advanceToBackfill)
        #expect(relaunched.current.outcome == .interrupted)
        let reloaded = HealthImportStatusStore(defaults: d)
        #expect(reloaded.current.outcome == .interrupted)            // survives on disk
    }

    @Test func anInterruptedStatusAlsoSurvivesAnAuthorizationThrow() async {
        // failAttempt() would clobber .interrupted → .attemptFailed, and a
        // later resume would walk the user past the recovery screen. It is
        // also structurally banned here: failAttempt without a preceding
        // beginAttempt in the same sequence is always a defect.
        let (workflow, recorder, status) = harness(outcome: .interrupted, throwing: true)
        let result = await workflow.connect()
        #expect(recorder.calls == [.readOutcome, .requestAuthorization])
        #expect(result == .stayOnConnect)
        #expect(status.outcome == .interrupted)
    }
}
