import Foundation
import Testing
@testable import Food_Intolerances

/// Pins the screen-side seam directly on ConnectViewState — the mapping from
/// ConnectWorkflow's result to the flow callbacks, the failure flag, the
/// side-effect-free skip route, and the synchronous double-invocation guard.
///
/// Replaces the deleted mounted-host suite (FirstRunConnectViewTests), which
/// drove SwiftUI buttons through a private simulator accessibility switch:
/// the same four discriminating cases, now invoked directly on the model —
/// no host, no accessibility tree, no undocumented symbols. The view is thin
/// Button-to-model wiring (one model method per button), so the model IS the
/// screen's behavior.
///
/// Transition ORDER stays pinned by ConnectWorkflowTests. The exact-sequence
/// assertions here additionally prove the model routed through the REAL
/// workflow it builds over the injected doubles.
@MainActor
@Suite struct ConnectViewStateTests {

    enum Call: Equatable {
        case readOutcome
        case beginAttempt
        case failAttempt
        case requestAuthorization
    }

    final class Recorder {
        var calls: [Call] = []
    }

    final class Counter {
        var value = 0
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
        var outcome: HealthImportOutcome = .notStarted
        init(recorder: Recorder) { self.recorder = recorder }
        var currentOutcome: HealthImportOutcome {
            recorder.calls.append(.readOutcome)
            return outcome
        }
        func beginAttempt() { recorder.calls.append(.beginAttempt); outcome = .inProgress }
        func failAttempt() { recorder.calls.append(.failAttempt); outcome = .attemptFailed }
    }

    /// The model over the SAME recording doubles ConnectWorkflowTests uses,
    /// injected at the workflow boundary (HealthKitIngestor is final and is
    /// never faked). Counters capture callback routing without a host.
    private func harness(throwing: Bool = false)
    -> (state: ConnectViewState, recorder: Recorder, authorizer: RecordingAuthorizer,
        connected: Counter, skipped: Counter) {
        let recorder = Recorder()
        let authorizer = RecordingAuthorizer(recorder: recorder)
        authorizer.shouldThrow = throwing
        let status = RecordingImportStatus(recorder: recorder)
        let connected = Counter()
        let skipped = Counter()
        let state = ConnectViewState(authorizer: authorizer,
                                     importStatus: status,
                                     onSkip: { skipped.value += 1 },
                                     onConnected: { connected.value += 1 })
        return (state, recorder, authorizer, connected, skipped)
    }

    /// Gives any main-actor work a BROKEN guard might have enqueued the
    /// chance to run before counting: each yield reschedules this test behind
    /// every job already on the main actor, so 25 of them drain a wrongly
    /// enqueued second connect. Correct code has nothing left to run, so the
    /// pass stays fast and the test stays deterministic.
    private func settle() async {
        for _ in 0..<25 { await Task.yield() }
    }

    // MARK: - Result mapping: .advanceToBackfill

    @Test func aSuccessfulConnectFiresOnConnectedExactlyOnceWithNoFailureState() async {
        let h = harness()
        h.state.connectTapped()
        await h.state.connectTask?.value
        #expect(h.connected.value == 1)
        #expect(h.skipped.value == 0)
        #expect(h.state.authorizationFailed == false)
        #expect(h.state.isRequesting == false)   // reset for any later attempt
        // Routed through the real workflow exactly once, in the pinned order.
        #expect(h.recorder.calls == [.readOutcome, .beginAttempt, .requestAuthorization])
    }

    // MARK: - Result mapping: .stayOnConnect

    @Test func aFailedConnectExposesTheFailureStateAndNeverFiresOnConnected() async {
        let h = harness(throwing: true)
        h.state.connectTapped()
        await h.state.connectTask?.value
        #expect(h.state.authorizationFailed == true)
        #expect(h.connected.value == 0)
        #expect(h.skipped.value == 0)
        #expect(h.state.isRequesting == false)   // Retry stays tappable
        #expect(h.recorder.calls ==
                [.readOutcome, .beginAttempt, .requestAuthorization, .failAttempt])
    }

    @Test func aSuccessfulRetryClearsTheFailureStateAndFiresOnConnected() async {
        // Not just "success leaves the flag false": a real Retry starts FROM
        // the failure state, so this pins the explicit clear on success —
        // the screen must not stay on "Couldn't reach Apple Health" forever.
        let h = harness(throwing: true)
        h.state.connectTapped()
        await h.state.connectTask?.value
        #expect(h.state.authorizationFailed == true)
        h.authorizer.shouldThrow = false
        h.state.connectTapped()
        await h.state.connectTask?.value
        #expect(h.state.authorizationFailed == false)
        #expect(h.connected.value == 1)
    }

    // MARK: - "Not now"

    @Test func skipFiresOnSkipOnceAndTouchesNoCollaborator() {
        let h = harness()
        h.state.skipTapped()
        #expect(h.skipped.value == 1)
        #expect(h.connected.value == 0)
        // Exact-empty: the skip path must not request authorization, read
        // import status, or write it — ANY recorded call is a defect.
        #expect(h.recorder.calls == [])
        #expect(h.state.isRequesting == false)
    }

    // MARK: - Double-invocation guard

    @Test func twoImmediateConnectsRequestAuthorizationExactlyOnce() async {
        let h = harness()
        // Two calls in the SAME main-actor turn — no await between them, so
        // nothing dispatched has run yet and no re-render has applied
        // .disabled(isRequesting). Only a guard that runs synchronously
        // inside connectTapped() separates one authorization request from
        // two; a flag set inside the dispatched Task is too late.
        h.state.connectTapped()
        h.state.connectTapped()
        await h.state.connectTask?.value
        await settle()
        let authorizationRequests = h.recorder.calls.filter { $0 == .requestAuthorization }
        #expect(authorizationRequests.count == 1)
        #expect(h.connected.value == 1)
        #expect(h.state.isRequesting == false)
    }
}
