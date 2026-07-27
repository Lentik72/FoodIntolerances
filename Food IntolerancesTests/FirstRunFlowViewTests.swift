import Foundation
import SwiftUI
import Testing
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

    @Test func aResumedFlowWithATerminalNonCompletedOutcomeAlsoStartsAtThePromise() {
        // .completedWithIssues is terminal: the import ran and finished. Only
        // .interrupted and .inProgress belong on the recovery screen — the gate
        // is a whitelist, not "anything but .completed".
        #expect(initialStep(entry: .resume, importOutcome: .completedWithIssues) == .promise)
    }
}
