import SwiftUI

struct FirstRunConnectView: View {
    let onSkip: () -> Void
    let onConnected: () -> Void

    @EnvironmentObject private var ingestor: HealthKitIngestor
    @EnvironmentObject private var importStatus: HealthImportStatusStore
    @State private var authorizationFailed = false
    @State private var isRequesting = false

    /// Test seam ONLY. `nil` in production (every call site passes two
    /// closures), so the real path always builds the workflow over the
    /// root-injected environment objects below — never a second
    /// HealthImportStatusStore. Tests inject a factory over recording doubles
    /// to pin the view's result mapping, which no workflow-level test can see.
    private let workflowOverride: (@MainActor () -> ConnectWorkflow)?

    init(onSkip: @escaping () -> Void,
         onConnected: @escaping () -> Void,
         workflowOverride: (@MainActor () -> ConnectWorkflow)? = nil) {
        self.onSkip = onSkip
        self.onConnected = onConnected
        self.workflowOverride = workflowOverride
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

            if authorizationFailed {
                Text("Couldn't reach Apple Health. You can try again, or continue and connect later.")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
            }
            Spacer()
            Button(authorizationFailed ? "Retry" : "Connect Apple Health") { connectTapped() }
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isRequesting)
            Button("Not now") {
                workflow.skip()   // pinned side-effect-free — see ConnectWorkflowTests
                onSkip()
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
    }

    /// The transition logic lives in ConnectWorkflow, NOT here, so its call
    /// ORDER is pinned by recording-double tests (the `.interrupted`-clobber
    /// defect is invisible to any final-state assertion). Built per call from
    /// the root-injected environment objects — never a second
    /// HealthImportStatusStore instance, which would leave Backfill observing
    /// a store nothing writes to.
    private var workflow: ConnectWorkflow {
        workflowOverride?() ?? ConnectWorkflow(authorizer: ingestor, importStatus: importStatus)
    }

    /// `isRequesting` is guarded and set HERE, synchronously in the button
    /// action, not inside the dispatched Task — otherwise two fast taps can
    /// enqueue two connect() calls before `.disabled(isRequesting)` applies.
    private func connectTapped() {
        guard !isRequesting else { return }
        isRequesting = true
        Task { await connect() }
    }

    private func connect() async {
        defer { isRequesting = false }
        switch await workflow.connect() {
        case .advanceToBackfill:
            authorizationFailed = false
            onConnected()
        case .stayOnConnect:
            authorizationFailed = true
        }
    }
}
