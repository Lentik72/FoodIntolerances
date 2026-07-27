import SwiftUI
import HealthGraphCore

/// Six-step value-first first run. Screens are added in Tasks 12-15; this file
/// owns only the step machine and the shared state they mutate.
struct FirstRunFlowView: View {
    enum Step: Int, CaseIterable { case promise, connect, backfill, seeding, location, done }

    let entry: FirstRunEntry
    let onComplete: ([String]) -> Void

    @State private var step: Step
    @State private var selectedSeeds: [String] = []

    /// A resumed flow whose import was killed lands straight on Backfill, so
    /// the user meets the recovery screen instead of being walked back through
    /// Promise and Connect and silently restarting a multi-minute import.
    init(entry: FirstRunEntry, importOutcome: HealthImportOutcome, onComplete: @escaping ([String]) -> Void) {
        self.entry = entry
        self.onComplete = onComplete
        let resumesIntoBackfill = entry == .resume
            && (importOutcome == .interrupted || importOutcome == .inProgress)
        _step = State(initialValue: resumesIntoBackfill ? .backfill : .promise)
    }

    @EnvironmentObject private var firstRunState: FirstRunState

    var body: some View {
        ZStack {
            HealthTheme.paper.ignoresSafeArea()
            content
        }
        // Marked at FLOW ENTRY, before any branch. Doing it inside Connect
        // instead would leave "Not now" running the rest of the flow — including
        // the location prompt, a real side effect — with startedVersion still 0,
        // so a kill there plus a populated graph hits the reconciliation row and
        // skips onboarding forever. Same defect class as the original blocker.
        .task { firstRunState.markStarted() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .promise:  FirstRunPromiseView { advance(to: .connect) }
        case .connect:  FirstRunConnectView(onSkip: { advance(to: .seeding) },
                                            onConnected: { advance(to: .backfill) })
        case .backfill: FirstRunBackfillView { advance(to: .seeding) }
        case .seeding:  FirstRunSeedingView(selection: $selectedSeeds) { advance(to: .location) }
        case .location: FirstRunLocationView(seeds: selectedSeeds) { advance(to: .done) }
        case .done:     Color.clear.onAppear { onComplete(selectedSeeds) }
        }
    }

    private func advance(to next: Step) {
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }
}
