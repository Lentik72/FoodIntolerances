import Foundation
import HealthGraphCore
import SwiftUI
import Testing
import UIKit
@testable import Food_Intolerances

@MainActor
@Suite struct FirstRunFlowViewTests {
    /// Reads the initial step off the un-installed view via Mirror — @State
    /// before installation returns its initial value, which is exactly the
    /// routing decision the init makes. Reflection keeps the production
    /// property private, matching the flow shell's spec verbatim.
    private func initialStep(entry: FirstRunEntry, importOutcome: HealthImportOutcome) -> FirstRunFlowView.Step? {
        let view = FirstRunFlowView(entry: entry, importOutcome: importOutcome) { _ in }
        let state = Mirror(reflecting: view).children
            .first { $0.label == "_step" }?.value as? State<FirstRunFlowView.Step>
        return state?.wrappedValue
    }

    @Test func aResumedFlowWithAnInterruptedImportLandsStraightOnBackfill() {
        // The user meets the recovery screen instead of being walked back
        // through Promise and Connect and silently restarting a multi-minute
        // import.
        #expect(initialStep(entry: .resume, importOutcome: .interrupted) == .backfill)
    }

    @Test func aResumedFlowWithAPersistedInProgressAlsoLandsOnBackfill() {
        // .inProgress at flow construction means the process died before launch
        // normalization could run OR the flow was re-entered mid-import — both
        // belong on the recovery screen.
        #expect(initialStep(entry: .resume, importOutcome: .inProgress) == .backfill)
    }

    @Test func aResumedFlowWhoseImportFinishedStartsAtThePromise() {
        // Resume alone is not enough: a user who quit on the seeding screen
        // with a COMPLETED import must not be dropped onto Backfill.
        #expect(initialStep(entry: .resume, importOutcome: .completed) == .promise)
    }

    @Test func aFreshFlowStartsAtThePromiseEvenWithAStaleInterruptedOutcome() {
        // The entry gate matters independently of the outcome: an interrupted
        // status from some earlier install must not skip a brand-new user past
        // the promise and connect screens.
        #expect(initialStep(entry: .fresh, importOutcome: .interrupted) == .promise)
    }

    @Test func aResumedFlowThatNeverStartedAnImportBeginsAtThePromise() {
        // markStarted() fires at flow entry, so quitting ON the promise screen
        // resumes with .notStarted. A blacklist gate (`!= .completed`) drops that
        // user onto Backfill for an import that never ran, past Connect — where
        // HealthKit authorization happens.
        #expect(initialStep(entry: .resume, importOutcome: .notStarted) == .promise)
    }

    @Test func mountingTheFlowMarksItStartedBeforeAnyUserAction() async throws {
        // Pins `.task { firstRunState.markStarted() }` at FLOW ENTRY — the
        // Mirror tests above cannot see it, and no other test mounts the flow.
        // markStarted moved into Connect (or dropped) leaves "Not now" running
        // the rest of the flow with startedVersion still 0, so a kill there
        // plus a populated graph hits the reconciliation row and skips
        // onboarding forever. The .promise step mounts only the promise
        // screen, so a markStarted relocated into Connect fails here.
        let d = UserDefaults(suiteName: "first-run-flow-\(UUID().uuidString)")!
        let db = try AppDatabase.inMemory()
        let state = FirstRunState(defaults: d, store: GRDBEventStore(database: db),
                                  backfillAttempted: false)
        #expect(d.integer(forKey: FirstRunKeys.startedVersion) == 0)   // not at init

        let flow = FirstRunFlowView(entry: .fresh, importOutcome: .notStarted) { _ in }
            .environmentObject(state)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: flow)
        window.makeKeyAndVisible()
        window.rootViewController?.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }

        // `.task` runs asynchronously after appearance — poll with a deadline
        // rather than a fixed sleep so the pass is fast and the fail is bounded.
        let deadline = Date().addingTimeInterval(5)
        while d.integer(forKey: FirstRunKeys.startedVersion) == 0, Date() < deadline {
            await Task.yield()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        #expect(d.integer(forKey: FirstRunKeys.startedVersion) == FirstRunState.currentVersion)
    }

    @Test func aResumedFlowWithATerminalNonCompletedOutcomeAlsoStartsAtThePromise() {
        // .completedWithIssues is terminal: the import ran and finished. Only
        // .interrupted and .inProgress belong on the recovery screen — the gate
        // is a whitelist, not "anything but .completed".
        #expect(initialStep(entry: .resume, importOutcome: .completedWithIssues) == .promise)
    }
}
