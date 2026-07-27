import Foundation

/// Requests HealthKit read authorization. Production is `HealthKitIngestor`,
/// which silently RETURNS (no throw) when health data is unavailable, and
/// Apple reports denied reads as "not determined" — so a successful return
/// does not imply access was granted. Denied reads are NOT an error path;
/// only a genuine throw is.
@MainActor
protocol HealthAuthorizationRequesting: AnyObject {
    func requestAuthorization() async throws
}

/// The slice of import status Connect may read and mutate. Production is the
/// ROOT-INJECTED `HealthImportStatusStore` — never a second instance, which
/// would leave the Backfill screen observing a store nothing writes to.
@MainActor
protocol ImportStatusTransitioning: AnyObject {
    var currentOutcome: HealthImportOutcome { get }
    func beginAttempt()
    func failAttempt()
}

extension HealthKitIngestor: HealthAuthorizationRequesting {}

extension HealthImportStatusStore: ImportStatusTransitioning {
    var currentOutcome: HealthImportOutcome { current.outcome }
}

/// Connect's transitions, extracted from the view so their ORDER is testable
/// with recording doubles. A pure decision function cannot pin ordering, and
/// ordering is the defect that already occurred here: `beginAttempt()` called
/// before the status inspection overwrites a persisted `.interrupted` — the
/// final state is `.inProgress` either way, so only the call sequence
/// discriminates — making Backfill's recovery branch dead code on every
/// onboarding path and silently restarting a killed multi-minute import.
@MainActor
struct ConnectWorkflow {
    enum ConnectResult: Equatable {
        case advanceToBackfill
        case stayOnConnect
    }

    private let authorizer: any HealthAuthorizationRequesting
    private let importStatus: any ImportStatusTransitioning

    init(authorizer: any HealthAuthorizationRequesting,
         importStatus: any ImportStatusTransitioning) {
        self.authorizer = authorizer
        self.importStatus = importStatus
    }

    /// "Not now". Deliberately side-effect-free — no authorization request, no
    /// status read, no write — and routed through the workflow anyway so the
    /// tests pin that emptiness. `startedVersion` is NOT written here either:
    /// FirstRunFlowView marks the flow started at entry, so every branch
    /// (including this one) is covered.
    func skip() {}

    /// One connect attempt. The status is inspected BEFORE any mutation:
    /// a persisted `.interrupted` must survive this call in every branch so
    /// the Backfill screen (which reads it AFTER this runs) can offer recovery
    /// instead of silently restarting the import. Authorization still runs on
    /// the interrupted path — the user reaches Backfill's resume without
    /// HealthKit access otherwise.
    func connect() async -> ConnectResult {
        let resumingInterrupted = importStatus.currentOutcome == .interrupted
        if !resumingInterrupted { importStatus.beginAttempt() }
        do {
            try await authorizer.requestAuthorization()
            return .advanceToBackfill
        } catch {
            // Stay on Connect. Denied READS are not an error — Apple reports
            // them as "not determined" — so only a genuine throw lands here.
            // On the interrupted path failAttempt() is skipped too: it would
            // clobber `.interrupted` → `.attemptFailed`, and failAttempt
            // without a preceding beginAttempt is always a defect.
            if !resumingInterrupted { importStatus.failAttempt() }
            return .stayOnConnect
        }
    }
}
