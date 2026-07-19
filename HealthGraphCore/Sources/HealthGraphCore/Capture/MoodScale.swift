import Foundation

/// The single source of truth for the mood scale (1–3). Pure data — labels and
/// values only; the face *drawing* (custom SwiftUI) lives in the app layer.
public enum MoodLevel: Int, CaseIterable, Sendable {
    case rough = 1, okay = 2, good = 3

    public var label: String {
        switch self {
        case .rough: "Rough"
        case .okay:  "Okay"
        case .good:  "Good"
        }
    }

    /// Nearest valid level for any Int — so display/mining never break on an
    /// out-of-range value (an orphaned pre-refinement 4/5 log, or future drift).
    public init(clamping raw: Int) {
        self = raw <= 1 ? .rough : (raw >= 3 ? .good : .okay)
    }
}
