import Foundation
import HealthGraphCore

/// Pure copy + formatting for the import surfaces, so the state machine's
/// wording is unit-testable without rendering a view.
enum DataSourcesPresentation {
    /// Vocabulary deliberately avoids Connected/Denied: Apple reports denied
    /// READS as "not determined", so the app cannot know and must not claim.
    static func statusLabel(for status: HealthImportStatus) -> String {
        switch status.outcome {
        case .notStarted:          return "Not imported"
        case .inProgress:          return "Importing…"
        case .interrupted:         return "Import interrupted"
        case .attemptFailed:       return "Import attempted"
        case .completedNoData:     return "Imported — nothing came through"
        case .completed:           return "Last imported"
        case .completedWithIssues: return "Imported with issues"
        }
    }

    static func backfillMessage(for status: HealthImportStatus) -> String {
        switch status.outcome {
        case .interrupted:
            return "The previous import was interrupted."
        case .attemptFailed:
            return "Apple Health couldn't be reached."
        case .completedNoData:
            return "Nothing came through yet."
        case .completedWithIssues:
            return status.eventsImported > 0
                ? "Your history was imported, but some data couldn't be read."
                : "Apple Health couldn't be fully imported."
        case .completed:
            return "You're not starting from zero."
        case .notStarted, .inProgress:
            return "Importing your history…"
        }
    }

    /// Whether the surface should offer to run the import again. A clean import
    /// must NOT — re-running costs minutes and there is nothing to fix, so a
    /// permanent Retry beside it just invites waste.
    static func offersRetry(for status: HealthImportStatus) -> Bool {
        switch status.outcome {
        case .interrupted, .attemptFailed, .completedNoData, .completedWithIssues:
            return true
        case .notStarted, .inProgress, .completed:
            return false
        }
    }

    /// User-facing copy for a failed export-file import. Deliberately not
    /// `String(describing: error)`: that puts type names and error domains on
    /// screen, which tells the user nothing and reads as a crash. The raw error
    /// goes to the log instead.
    static func importErrorMessage(for error: Error) -> String {
        switch error {
        case ExportImportError.noPermission:
            return "No permission to read the selected file."
        default:
            return "That export couldn't be read. Try exporting again from Apple Health."
        }
    }

    /// Derived from the HealthKit-scoped summary, never from the requested
    /// one-year window: export.zip reaches further back, a partial grant less.
    /// The earliest date is the whole point of Task 7 computing `earliest` —
    /// "back to March 2025" is what makes the number feel like the user's own
    /// history rather than a counter.
    static func summaryLine(from summaries: [ImportedCategorySummary]) -> String? {
        guard !summaries.isEmpty else { return nil }
        let total = summaries.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        let categories = summaries.count
        var line = "\(total.formatted()) events across \(categories) categor\(categories == 1 ? "y" : "ies")"
        if let earliest = summaries.map(\.earliest).min() {
            line += ", back to \(earliest.formatted(.dateTime.month(.wide).year()))"
        }
        return line
    }
}
