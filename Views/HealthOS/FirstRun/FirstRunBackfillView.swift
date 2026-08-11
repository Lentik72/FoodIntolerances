import SwiftUI
import HealthGraphCore

/// Thin wiring over BackfillViewState: appearance and each button call exactly
/// one model method, and the body renders published state. Every decision —
/// the entry policy (auto-run vs. offer recovery), the synchronous
/// double-invocation guard, what survives a failed retry — lives in
/// BackfillViewState, where BackfillViewStateTests pins it directly. The run's
/// ordering lives one level further down in BackfillWorkflow.
struct FirstRunBackfillView: View {
    let onContinue: () -> Void

    @StateObject private var state: BackfillViewState
    /// Observed for the live progress bar only — display-only plumbing state
    /// with no decision attached, so it is read straight from the ingestor
    /// rather than mirrored into the model.
    @ObservedObject private var ingestor: HealthKitIngestor
    /// The headline copy is a pure function of persisted status, so the screen
    /// re-renders as the run transitions it.
    @ObservedObject private var importStatus: HealthImportStatusStore

    /// Both collaborators are passed down by FirstRunFlowView from the
    /// root-injected environment objects — never constructed here. In
    /// particular the importStatus is the SAME HealthImportStatusStore instance
    /// Connect writes through; a second instance would never show the
    /// `.interrupted` that makes this a recovery screen.
    init(ingestor: HealthKitIngestor,
         importStatus: HealthImportStatusStore,
         onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        _ingestor = ObservedObject(wrappedValue: ingestor)
        _importStatus = ObservedObject(wrappedValue: importStatus)
        _state = StateObject(wrappedValue: BackfillViewState(ingestor: ingestor,
                                                             importStatus: importStatus))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(DataSourcesPresentation.backfillMessage(for: importStatus.current))
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)

            // The card floats between the headline and the actions rather than
            // clinging under the headline: once the import finishes this screen
            // is two short lines, and a single top-aligned card left most of the
            // display empty.
            Spacer()

            if state.isRunning, let progress = ingestor.progress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(progress.completedSteps),
                                 total: Double(max(progress.totalSteps, 1)))
                        .tint(HealthTheme.accent)
                    Text("\(progress.eventsIngested.formatted()) events so far")
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.inkSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hgCard()
            } else if let line = DataSourcesPresentation.summaryLine(from: state.summaries) {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hgCard()
            }

            Spacer()
            // Offered only when there is something to retry. A clean import
            // under a Retry button invites redoing a multi-minute job for
            // nothing; the recovery and partial-failure states genuinely need it.
            if state.hasRun && !state.isRunning,
               DataSourcesPresentation.offersRetry(for: importStatus.current) {
                Button("Retry") { state.retryTapped() }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(state.isRunning)
        }
        .padding(.horizontal, 16)
        // Synchronous entry: the model owns the Task it starts, so this needs
        // no cancellation semantics of its own.
        .onAppear { state.appeared() }
    }
}
