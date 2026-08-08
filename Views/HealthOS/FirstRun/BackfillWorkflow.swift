import Foundation
import HealthGraphCore

/// The backfill side of `HealthKitIngestor`. `lastBackfillFailures` is a
/// SNAPSHOT-ONLY value: the ingestor clears it at the start of every run and
/// populates it as the run proceeds, so it is correct only at the instant
/// `backfill()` returns. Anything read later may belong to a different run.
@MainActor
protocol HealthBackfillRunning: AnyObject {
    var lastBackfillFailures: [String] { get }
    func backfill(years: Int) async throws -> IngestSummary
    /// Anchored live ingestion, resuming exactly where the backfill stopped.
    func startObserving()
}

/// The slice of import status the backfill run writes. Extends the Connect
/// slice with the two terminal writes. Production is the ROOT-INJECTED
/// `HealthImportStatusStore` — never a second instance, which would leave this
/// screen observing a store nothing writes to.
@MainActor
protocol ImportStatusRecording: ImportStatusTransitioning {
    func finish(summary: IngestSummary, failures: [String])
    func recordCategories(_ count: Int)
}

/// Reads back what actually landed in the graph, scoped to HealthKit. Returns
/// nil when the READ ITSELF failed, which is not the same as an empty import:
/// recording zero categories on a failed read would overwrite the count a
/// successful import just established.
@MainActor
protocol ImportedSummaryReading {
    func healthKitSummaries() async -> [ImportedCategorySummary]?
}

extension HealthKitIngestor: HealthBackfillRunning {}

extension HealthImportStatusStore: ImportStatusRecording {}

struct HealthKitImportedSummaryReader: ImportedSummaryReading {
    /// Explicitly nonisolated: conforming to a @MainActor protocol would
    /// otherwise isolate the implicit init, and default arguments are evaluated
    /// outside the callee's isolation.
    nonisolated init() {}

    func healthKitSummaries() async -> [ImportedCategorySummary]? {
        let store = GRDBEventStore(database: HealthGraphProvider.shared)
        return try? await store.importedSummary(source: .healthKit)
    }
}

/// One backfill run's transitions, extracted from the view so their ORDER is
/// testable with recording doubles.
///
/// The ordering that matters here is the failures snapshot. `backfill()` only
/// throws when authorization throws; every per-type failure is swallowed into
/// `lastBackfillFailures`, which the next run clears. Read it late — after
/// `startObserving()`, or after awaiting the summary read — and a partial
/// import can be committed as a clean one, which is the difference between
/// "your history was imported, but some data couldn't be read" and a silent
/// claim of completeness. The final status is identical either way, so only
/// the recorded position of the read discriminates.
@MainActor
struct BackfillWorkflow {
    enum RunResult: Equatable {
        case imported([ImportedCategorySummary])
        case failed
    }

    private let ingestor: any HealthBackfillRunning
    private let importStatus: any ImportStatusRecording
    private let summaryReader: any ImportedSummaryReading

    init(ingestor: any HealthBackfillRunning,
         importStatus: any ImportStatusRecording,
         summaryReader: any ImportedSummaryReading) {
        self.ingestor = ingestor
        self.importStatus = importStatus
        self.summaryReader = summaryReader
    }

    /// Whether this screen is a RECOVERY screen rather than a fresh import.
    /// A pure read: the caller renders and waits for the user, so nothing may
    /// be mutated here. Connect deliberately preserves `.interrupted` through
    /// authorization so this read can find it.
    var resumesInterruptedImport: Bool {
        importStatus.currentOutcome == .interrupted
    }

    /// One backfill run — including a resumed one. `beginAttempt()` is
    /// unconditional here, unlike Connect: this IS the start of a real import,
    /// so `.inProgress` must be persisted before HealthKit is touched or a
    /// second kill is undetectable.
    func run() async -> RunResult {
        importStatus.beginAttempt()
        do {
            let summary = try await ingestor.backfill(years: 1)
            // SNAPSHOT, before anything else and before the next await: this is
            // the only instant the value belongs to the run that just finished.
            let failures = ingestor.lastBackfillFailures
            importStatus.finish(summary: summary, failures: failures)
            // Only after the run is committed — live observation resumes from
            // the anchors the backfill left behind.
            ingestor.startObserving()
            let summaries = await summaryReader.healthKitSummaries()
            if let summaries { importStatus.recordCategories(summaries.count) }
            return .imported(summaries ?? [])
        } catch {
            // Reached only when authorization throws; per-type failures are in
            // the snapshot above, not here.
            importStatus.failAttempt()
            return .failed
        }
    }
}
