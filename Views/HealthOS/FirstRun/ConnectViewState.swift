import Foundation

/// FirstRunConnectView's screen state: the published flags the body renders,
/// the mapping from ConnectWorkflow's result to the flow callbacks, and the
/// double-tap guard. Extracted from the view so all three are pinned by
/// direct, deterministic unit tests (ConnectViewStateTests) — no mounted
/// host, no accessibility tree. The view is thin wiring: each button calls
/// exactly one method here.
///
/// Transition ORDER (inspect-before-beginAttempt, the interrupted-resume
/// branches) stays in ConnectWorkflow, pinned by ConnectWorkflowTests — this
/// model never reads or writes import status itself.
@MainActor
final class ConnectViewState: ObservableObject {
    @Published private(set) var authorizationFailed = false
    @Published private(set) var isRequesting = false

    private let workflow: ConnectWorkflow
    private let onSkip: () -> Void
    private let onConnected: () -> Void

    /// The in-flight connect attempt. Read-only outside; tests await it so
    /// assertions run deterministically after completion instead of spinning
    /// a run loop. Production code never reads it.
    private(set) var connectTask: Task<Void, Never>?

    /// Default wiring: builds ConnectWorkflow over whatever is injected — in
    /// production the root HealthKitIngestor and the ROOT-INJECTED
    /// HealthImportStatusStore, both passed down by FirstRunFlowView. Never
    /// constructs a store: a second instance would leave the Backfill screen
    /// observing a store nothing writes to. Tests inject recording doubles at
    /// this same boundary (HealthKitIngestor is final and is never faked).
    init(authorizer: any HealthAuthorizationRequesting,
         importStatus: any ImportStatusTransitioning,
         onSkip: @escaping () -> Void,
         onConnected: @escaping () -> Void) {
        self.workflow = ConnectWorkflow(authorizer: authorizer, importStatus: importStatus)
        self.onSkip = onSkip
        self.onConnected = onConnected
    }

    /// The guard runs SYNCHRONOUSLY in the button action, before any
    /// dispatch: two taps can land in the same main-actor turn, before a
    /// re-render applies `.disabled(isRequesting)`, and a flag set inside the
    /// Task is too late — both taps would already have enqueued a connect.
    func connectTapped() {
        guard !isRequesting else { return }
        isRequesting = true
        connectTask = Task { await connect() }
    }

    /// "Not now". Routed through the workflow's deliberately side-effect-free
    /// skip() — no authorization request, no status read or write, pinned
    /// empty by ConnectWorkflowTests — then hands the flow on.
    func skipTapped() {
        workflow.skip()
        onSkip()
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
