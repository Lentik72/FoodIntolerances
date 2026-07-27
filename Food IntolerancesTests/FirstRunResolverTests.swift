import Foundation
import Testing
@testable import Food_Intolerances

@Suite struct FirstRunResolverTests {
    private func defaults(started: Int = 0, completed: Int = 0, forceShow: Bool = false) -> UserDefaults {
        let suite = UserDefaults(suiteName: "firstrun-test-\(UUID().uuidString)")!
        suite.set(started, forKey: FirstRunKeys.startedVersion)
        suite.set(completed, forKey: FirstRunKeys.completedVersion)
        suite.set(forceShow, forKey: FirstRunKeys.forceShow)
        return suite
    }

    @Test func completedAtOrAboveCurrentGoesToShell() {
        let r = FirstRunResolver.resolve(defaults: defaults(completed: 2), currentVersion: 2,
                                         anyEventExists: { false }, backfillAttempted: false)
        #expect(r == .shell)
    }

    @Test func interruptedCurrentVersionResumesTheFlow() {
        // started == current, completed < current: the app died mid-flow.
        let r = FirstRunResolver.resolve(defaults: defaults(started: 1, completed: 0), currentVersion: 1,
                                         anyEventExists: { true }, backfillAttempted: true)
        #expect(r == .flow(.resume))
    }

    @Test func upgradeFromAnOlderCompletedVersionRunsTheFlow() {
        // A Boolean resolver (completedVersion > 0 -> shell) passes every other
        // case and fails exactly this one.
        let r = FirstRunResolver.resolve(defaults: defaults(completed: 1), currentVersion: 2,
                                         anyEventExists: { true }, backfillAttempted: true)
        #expect(r == .flow(.upgrade(from: 1)))
    }

    @Test func interruptedUpgradeAlsoRunsTheFlow() {
        // completed 1, started 2, current 2 — the other case a Boolean resolver misses.
        let r = FirstRunResolver.resolve(defaults: defaults(started: 2, completed: 1), currentVersion: 2,
                                         anyEventExists: { true }, backfillAttempted: true)
        #expect(r == .flow(.resume))
    }

    @Test func bothZeroWithAPopulatedGraphReconcilesToShell() {
        let r = FirstRunResolver.resolve(defaults: defaults(), currentVersion: 1,
                                         anyEventExists: { true }, backfillAttempted: false)
        #expect(r == .reconcileThenShell)
    }

    @Test func bothZeroWithABackfillFlagReconcilesEvenOnAnEmptyGraph() {
        let r = FirstRunResolver.resolve(defaults: defaults(), currentVersion: 1,
                                         anyEventExists: { false }, backfillAttempted: true)
        #expect(r == .reconcileThenShell)
    }

    @Test func bothZeroAndTrulyEmptyRunsTheFreshFlow() {
        let r = FirstRunResolver.resolve(defaults: defaults(), currentVersion: 1,
                                         anyEventExists: { false }, backfillAttempted: false)
        #expect(r == .flow(.fresh))
    }

    @Test func reconciliationNeverConsultsTheGraphOnceOnboardingHasStarted() {
        // The self-skipping defect: onboarding's OWN writes satisfied the
        // predicate that decides whether onboarding is needed.
        var graphConsulted = false
        let r = FirstRunResolver.resolve(defaults: defaults(started: 1, completed: 0), currentVersion: 1,
                                         anyEventExists: { graphConsulted = true; return true },
                                         backfillAttempted: true)
        #expect(r == .flow(.resume))
        #expect(graphConsulted == false)
    }

    @Test func aStaleStartedVersionNeverReconciles() {
        // THE test this suite exists for. Every other fixture with started > 0
        // has started == currentVersion, so it returns at row 2 before row 4 is
        // ever reached — meaning the `started == 0` guard on the reconciliation
        // row is otherwise never exercised, and DELETING IT PASSES ALL OF THEM.
        // That guard is the whole mechanism preventing the self-skipping bug:
        // an interrupted older-version flow, plus the events onboarding itself
        // inserted, would satisfy the reconciliation predicate and mark
        // onboarding permanently complete.
        //
        // Also kills a second mutant: `started == currentVersion` -> `started > 0`
        // in row 2, which would misroute this to .resume.
        //
        // Expected entry is .fresh, deliberately: this user began v1 and never
        // finished anything, so there is no partial state worth resuming.
        let r = FirstRunResolver.resolve(defaults: defaults(started: 1, completed: 0), currentVersion: 2,
                                         anyEventExists: { true }, backfillAttempted: true)
        #expect(r == .flow(.fresh))
    }

    @Test func forceShowBypassesReconciliation() {
        let r = FirstRunResolver.resolve(defaults: defaults(forceShow: true), currentVersion: 1,
                                         anyEventExists: { true }, backfillAttempted: true)
        #expect(r == .flow(.fresh))
    }

    @Test func aCompletedInstallGoesToShellEvenWithAStartedMarkerStillSet() {
        // Row 1 / row 2 precedence. No other fixture has BOTH markers at
        // currentVersion, so swapping the shell and resume rows survived —
        // and that swap re-onboards every user whose completion write raced a
        // crash into leaving startedVersion behind. Completion must win.
        let r = FirstRunResolver.resolve(defaults: defaults(started: 1, completed: 1), currentVersion: 1,
                                         anyEventExists: { false }, backfillAttempted: false)
        #expect(r == .shell)
    }

    @Test func forceShowBypassesEvenACompletedInstall() {
        // The existing forceShow fixture has completed: 0 — the one state
        // where the bypass isn't needed to reach the flow — so moving the
        // DEBUG block below the shell row survived. The whole point of the
        // debug switch is re-showing onboarding on an install that already
        // completed it; pin the bypass ABOVE the shell row.
        let r = FirstRunResolver.resolve(defaults: defaults(completed: 1, forceShow: true), currentVersion: 1,
                                         anyEventExists: { false }, backfillAttempted: false)
        #expect(r == .flow(.fresh))
    }
}
