import Foundation

/// The single source of truth for the mood scale (1–5). Every surface reads
/// values/labels/emoji from here.
public enum MoodLevel: Int, CaseIterable, Sendable {
    case awful = 1, low = 2, okay = 3, good = 4, great = 5

    public var label: String {
        switch self {
        case .awful: "Awful"
        case .low:   "Low"
        case .okay:  "Okay"
        case .good:  "Good"
        case .great: "Great"
        }
    }

    public var emoji: String {
        switch self {
        case .awful: "😖"
        case .low:   "🙁"
        case .okay:  "😐"
        case .good:  "🙂"
        case .great: "😄"
        }
    }
}
