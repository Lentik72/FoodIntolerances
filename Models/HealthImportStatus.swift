import Foundation
import HealthGraphCore

/// Full state machine, not three terminal results. `notStarted`/`completed*`
/// alone cannot express an authorization failure, an import that began and was
/// killed, or one attempted but never finished.
enum HealthImportOutcome: String, Codable, Equatable {
    case notStarted
    case inProgress
    case interrupted
    case attemptFailed
    case completedNoData
    case completed
    case completedWithIssues
}

/// Summary fields persist INDEPENDENTLY of `outcome` so an interruption during a
/// re-import doesn't blank what a prior successful import established.
struct HealthImportStatus: Codable, Equatable {
    var outcome: HealthImportOutcome = .notStarted
    var lastAttemptAt: Date?
    var lastCompletedAt: Date?
    var eventsImported: Int = 0
    var categoriesImported: Int = 0
    /// Type identifiers only — never sample payloads.
    var failureIdentifiers: [String] = []
}

@MainActor
final class HealthImportStatusStore: ObservableObject {
    private static let key = "hg.hk.importStatus"
    private let defaults: UserDefaults
    @Published private(set) var current: HealthImportStatus

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(HealthImportStatus.self, from: data) {
            self.current = decoded
        } else {
            self.current = HealthImportStatus()
        }
    }

    /// The production launch path: construct AND normalize, returning the EXACT
    /// instance that was normalized. The pairing is a factory (not two calls at
    /// the app root) because the exact-instance property is invisible to any
    /// disk assertion — normalizing a throwaway store writes the same
    /// .interrupted bytes to UserDefaults while the instance the UI observes
    /// still holds the stale .inProgress it loaded, rendering a spinner that
    /// never resolves.
    static func makeNormalizedStore(defaults: UserDefaults = .standard) -> HealthImportStatusStore {
        let store = HealthImportStatusStore(defaults: defaults)
        store.normalizeAtLaunch()
        return store
    }

    /// Call at launch BEFORE any surface renders. A persisted `inProgress` has
    /// no live task after process death, so rendering it verbatim shows a
    /// spinner that never resolves.
    func normalizeAtLaunch() {
        guard current.outcome == .inProgress else { return }
        var next = current
        next.outcome = .interrupted
        persist(next)
    }

    /// Persisted BEFORE authorization or backfill begins — that is what makes a
    /// kill detectable at all.
    func beginAttempt() {
        var next = current
        next.outcome = .inProgress
        next.lastAttemptAt = Date()
        persist(next)
    }

    func failAttempt() {
        var next = current
        next.outcome = .attemptFailed
        persist(next)
    }

    /// `backfill()` only throws when requestAuthorization throws; every per-type
    /// failure is swallowed into `lastBackfillFailures`. Both signals must be
    /// read, or a run where every type failed reports success.
    func finish(summary: IngestSummary, failures: [String]) {
        var next = current
        // inserted + updated: a repair re-import matches existing dedupKeys and
        // reports `updated`, so an inserted-only count says "0 events" on a run
        // that in fact fixed thousands of rows.
        let imported = summary.inserted + summary.updated
        // ALWAYS write the real count, including zero. Carrying a previous
        // nonzero total forward would let a genuinely empty run be presented as
        // though it imported events — and `backfillMessage` branches on
        // `eventsImported > 0`, so a zero-event run WITH failures would read
        // "your history was imported, but…" instead of "couldn't be fully
        // imported". A killed import keeps its old summary for free, because
        // `finish()` is not called on that path at all.
        next.eventsImported = imported
        next.lastCompletedAt = Date()
        next.failureIdentifiers = failures.map { String($0.prefix(while: { $0 != ":" })) }
        if !failures.isEmpty { next.outcome = .completedWithIssues }
        else if imported == 0 { next.outcome = .completedNoData }
        else { next.outcome = .completed }
        persist(next)
    }

    func recordCategories(_ count: Int) {
        var next = current
        next.categoriesImported = count
        persist(next)
    }

    private func persist(_ status: HealthImportStatus) {
        current = status
        if let data = try? JSONEncoder().encode(status) { defaults.set(data, forKey: Self.key) }
    }
}
