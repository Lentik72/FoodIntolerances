import SwiftUI

/// Thin Button-to-model wiring over ConnectViewState: each button calls
/// exactly one model method and the body renders published state. Every
/// decision — the result → callback mapping, the synchronous double-tap
/// guard, the side-effect-free skip route — lives in ConnectViewState, where
/// ConnectViewStateTests pins it directly.
struct FirstRunConnectView: View {
    @StateObject private var state: ConnectViewState

    /// Both collaborators are passed down by FirstRunFlowView from the
    /// root-injected environment objects — never constructed here. In
    /// particular the importStatus is the SAME HealthImportStatusStore
    /// instance the Backfill screen observes; a second instance would leave
    /// it observing a store nothing writes to.
    init(ingestor: HealthKitIngestor,
         importStatus: HealthImportStatusStore,
         onSkip: @escaping () -> Void,
         onConnected: @escaping () -> Void) {
        _state = StateObject(wrappedValue: ConnectViewState(
            authorizer: ingestor,
            importStatus: importStatus,
            onSkip: onSkip,
            onConnected: onConnected))
    }

    private let imported = ["sleep", "workouts", "heart rate", "HRV", "cycle", "weight"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bring in the history you already have.")
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(imported, id: \.self) { item in
                    Text("· \(item)")
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.inkSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hgCard()

            if state.authorizationFailed {
                Text("Couldn't reach Apple Health. You can try again, or continue and connect later.")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
            }
            Spacer()
            Button(state.authorizationFailed ? "Retry" : "Connect Apple Health") { state.connectTapped() }
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(state.isRequesting)
            Button("Not now") { state.skipTapped() }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
    }
}
