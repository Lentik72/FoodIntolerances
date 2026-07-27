import Darwin
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Food_Intolerances

/// Pins the VIEW's result mapping — the seam no workflow-level test can see.
///
/// `ConnectWorkflowTests` exercises `ConnectWorkflow` directly and never goes
/// through the view, so before this suite existed, swapping the two switch
/// cases in `FirstRunConnectView.connect()` (success → stuck on "Couldn't
/// reach Apple Health" forever; genuine throw → silently advance to Backfill
/// with no HealthKit access) passed every package, app, and UI test. Same for
/// dropping `onSkip()` from "Not now" — the button goes inert, uncaught.
///
/// Technique: the same mounted-host pattern as
/// `FirstRunFlowViewTests.mountingTheFlowMarksItStartedBeforeAnyUserAction`,
/// plus button driving through the accessibility tree —
/// `accessibilityActivate()` on the element SwiftUI exposes for each Button.
/// The workflow is substituted via the view's injectable factory, built over
/// the SAME recording doubles `ConnectWorkflowTests` uses, so these tests
/// assert the view's observable outcome (which callback fired, what the
/// screen shows), not workflow internals.
@MainActor
@Suite struct FirstRunConnectViewTests {

    /// SwiftUI's hosting view builds its accessibility tree ONLY when the
    /// process's accessibility bus is active — in a plain unit-test host,
    /// `accessibilityElements` stays empty and no Button is reachable.
    /// `_AXSSetAutomationEnabled` (simulator libAccessibility; the same switch
    /// XCUITest flips, and the one the AccessibilitySnapshot library uses) is
    /// what makes the nodes materialize. Test-target-only; never ships. If the
    /// symbol ever disappears, this is false and every test here fails loudly
    /// at its `#expect(tapped)` — the suite can never silently stop guarding.
    static let accessibilityAutomationEnabled: Bool = {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else { return false }
        unsafeBitCast(symbol, to: (@convention(c) (Int32) -> Void).self)(1)
        return true
    }()

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
        var outcome: HealthImportOutcome = .notStarted
        init(recorder: Recorder) { self.recorder = recorder }
        var currentOutcome: HealthImportOutcome {
            recorder.calls.append(.readOutcome)
            return outcome
        }
        func beginAttempt() { recorder.calls.append(.beginAttempt); outcome = .inProgress }
        func failAttempt() { recorder.calls.append(.failAttempt); outcome = .attemptFailed }
    }

    /// The failure copy the view shows on `.stayOnConnect` — asserted via its
    /// accessibility label, so a mapping mutant that never sets
    /// `authorizationFailed` is visible as "this text never appears".
    static let failureCopy =
        "Couldn't reach Apple Health. You can try again, or continue and connect later."

    /// One mounted FirstRunConnectView over recording doubles, with callback
    /// counters. The window/teardown choreography mirrors
    /// FirstRunFlowViewTests. `@EnvironmentObject`s are deliberately NOT
    /// installed: the injected factory means the view must never read them —
    /// if the production fallback ever runs under test, SwiftUI traps, which
    /// is itself a guard on the seam.
    @MainActor
    final class MountedConnect {
        let recorder = Recorder()
        let authorizer: RecordingAuthorizer
        let status: RecordingImportStatus
        private(set) var factoryInvocations = 0
        private(set) var connectedFires = 0
        private(set) var skipFires = 0
        private let window = UIWindow(frame: UIScreen.main.bounds)

        init(throwing: Bool = false) {
            authorizer = RecordingAuthorizer(recorder: recorder)
            authorizer.shouldThrow = throwing
            status = RecordingImportStatus(recorder: recorder)
            let view = FirstRunConnectView(
                onSkip: { [weak self] in self?.skipFires += 1 },
                onConnected: { [weak self] in self?.connectedFires += 1 },
                workflowOverride: { [weak self] in
                    guard let self else { fatalError("host deallocated mid-test") }
                    factoryInvocations += 1
                    return ConnectWorkflow(authorizer: authorizer, importStatus: status)
                })
            window.rootViewController = UIHostingController(rootView: view)
            window.makeKeyAndVisible()
            window.rootViewController?.view.layoutIfNeeded()
        }

        func tearDown() {
            window.isHidden = true
            window.rootViewController = nil
        }

        /// Breadth-first walk of the mounted hierarchy for the accessibility
        /// element SwiftUI exposes for a Button/Text with this label. Covers
        /// both `subviews` and the two accessibility-container APIs — SwiftUI
        /// hangs its elements off internal hosting views, not UIControls.
        func element(labeled label: String) -> NSObject? {
            guard let root = window.rootViewController?.view else { return nil }
            var visited = Set<ObjectIdentifier>()
            var queue: [NSObject] = [root]
            while !queue.isEmpty {
                let node = queue.removeFirst()
                guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
                if node.accessibilityLabel == label { return node }
                if let children = node.accessibilityElements {
                    queue.append(contentsOf: children.compactMap { $0 as? NSObject })
                }
                let count = node.accessibilityElementCount()
                if count > 0 && count != NSNotFound {
                    for index in 0..<count {
                        if let child = node.accessibilityElement(at: index) as? NSObject {
                            queue.append(child)
                        }
                    }
                }
                if let view = node as? UIView {
                    queue.append(contentsOf: view.subviews)
                }
            }
            return nil
        }

        /// Finds the labeled element (polling — the accessibility tree is
        /// built lazily after layout) and activates it, which performs the
        /// SwiftUI Button's action. Returns false if it never appeared.
        func tap(_ label: String) async -> Bool {
            guard FirstRunConnectViewTests.accessibilityAutomationEnabled else { return false }
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if let target = element(labeled: label) {
                    return target.accessibilityActivate()
                }
                await Task.yield()
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            return false
        }

        /// Spins the main run loop until the condition holds — same
        /// poll-with-deadline shape as the flow-mounting test, so passes are
        /// fast and failures are bounded, not flaky sleeps.
        func spin(until condition: () -> Bool, timeout: TimeInterval = 5) async {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition(), Date() < deadline {
                await Task.yield()
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
    }

    // MARK: - Result mapping: .advanceToBackfill

    @Test func aSuccessfulConnectFiresOnConnectedAndNeverOnSkip() async {
        let host = MountedConnect()
        defer { host.tearDown() }
        let tapped = await host.tap("Connect Apple Health")
        #expect(tapped)
        await host.spin(until: { host.connectedFires == 1 })
        #expect(host.connectedFires == 1)
        #expect(host.skipFires == 0)
        // The view routed through the workflow exactly once, in the pinned
        // collaborator order, and did not enter the failure state.
        #expect(host.recorder.calls == [.readOutcome, .beginAttempt, .requestAuthorization])
        #expect(host.element(labeled: Self.failureCopy) == nil)
    }

    // MARK: - Result mapping: .stayOnConnect

    @Test func aFailedConnectShowsTheFailureStateAndNeverFiresOnConnected() async {
        let host = MountedConnect(throwing: true)
        defer { host.tearDown() }
        let tapped = await host.tap("Connect Apple Health")
        #expect(tapped)
        // Completion is visible as the failure UI: the explanatory copy and
        // the button relabeled "Retry".
        await host.spin(until: { host.element(labeled: "Retry") != nil })
        #expect(host.element(labeled: "Retry") != nil)
        #expect(host.element(labeled: Self.failureCopy) != nil)
        #expect(host.connectedFires == 0)
        #expect(host.skipFires == 0)
        #expect(host.recorder.calls ==
                [.readOutcome, .beginAttempt, .requestAuthorization, .failAttempt])
    }

    // MARK: - "Not now"

    @Test func notNowFiresOnSkipThroughTheSideEffectFreeWorkflowPath() async {
        let host = MountedConnect()
        defer { host.tearDown() }
        let tapped = await host.tap("Not now")
        #expect(tapped)
        await host.spin(until: { host.skipFires == 1 })
        #expect(host.skipFires == 1)
        #expect(host.connectedFires == 0)
        // The button consulted the workflow (factory ran → skip() was reached;
        // skip() itself is deliberately empty, so factory invocation is its
        // only observable trace) and that path touched NO collaborator:
        // no authorization request, no status read, no status write.
        #expect(host.factoryInvocations == 1)
        #expect(host.recorder.calls == [])
    }

    // MARK: - Double-tap race

    @Test func twoImmediateConnectTapsRunTheWorkflowOnlyOnce() async {
        let host = MountedConnect()
        defer { host.tearDown() }
        // Two activations in the SAME main-actor turn — no run-loop spin
        // between them, so no re-render has applied .disabled(isRequesting)
        // yet. Only the synchronous guard in the button action separates one
        // connect() from two.
        let tapped = await host.tap("Connect Apple Health")
        #expect(tapped)
        _ = host.element(labeled: "Connect Apple Health")?.accessibilityActivate()
        await host.spin(until: { host.connectedFires >= 1 })
        // Let any second enqueued Task land before counting.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let authorizationRequests = host.recorder.calls.filter { $0 == .requestAuthorization }
        #expect(authorizationRequests.count == 1)
        #expect(host.connectedFires == 1)
    }
}
