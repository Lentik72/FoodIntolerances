import Foundation

/// Why a daily-statistics re-ingest refused to report success.
enum DailyStatRepairError: LocalizedError {
    /// The HealthKit identifiers whose re-ingest threw. The rest were still
    /// re-ingested — this only says the pass was incomplete.
    case typesFailed([String])

    var errorDescription: String? {
        switch self {
        case .typesFailed(let identifiers):
            return "Daily-statistics re-ingest failed for: \(identifiers.joined(separator: ", "))"
        }
    }
}

/// One-shot, versioned repair of daily-statistics rows written by the
/// pre-fix trailing-window recompute (see `HealthKitIngestor.dailyStatRange`).
/// Runs once per install after the shell mounts, silently; bumping
/// `currentVersion` schedules another pass on every install.
enum DailyStatRepair {
    static let versionKey = "hg.hk.dailyStatRepairVersion"
    static let currentVersion = 1

    /// Pure gate: due only when a backfill has completed on this install
    /// (there is nothing to repair before one) and the stored version is
    /// behind `currentVersion`.
    static func isDue(storedVersion: Int, backfillCompleted: Bool) -> Bool {
        backfillCompleted && storedVersion < currentVersion
    }

    /// Runs `reingest` if due, then stamps `currentVersion` — ONLY on
    /// success. A throw is logged and leaves the version unset so the
    /// next launch retries. `reingest` is injected so the contract is
    /// testable without HealthKit.
    static func runIfDue(defaults: UserDefaults = .standard,
                         reingest: () async throws -> Void) async {
        guard isDue(storedVersion: defaults.integer(forKey: versionKey),
                    backfillCompleted: defaults.bool(forKey: HealthKitIngestor.backfillCompletedKey))
        else { return }
        do {
            try await reingest()
            defaults.set(currentVersion, forKey: versionKey)
        } catch {
            // Fail-open and silent: nothing user-facing moved, and the
            // unstamped version is itself the retry.
            Logger.error(error, message: "Daily-statistics repair failed; retrying next launch",
                         category: .data)
        }
    }
}
