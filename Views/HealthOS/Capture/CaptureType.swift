import SwiftUI
import HealthGraphCore

enum CaptureType: String, CaseIterable, Identifiable {
    case symptom, meal, dose, note, mood
    var id: String { rawValue }
    var label: String {
        switch self { case .symptom: "Symptom"; case .meal: "Meal"; case .dose: "Dose"; case .note: "Note"; case .mood: "Mood" }
    }
    var icon: String {
        switch self {
        case .symptom: "exclamationmark.circle"
        case .meal: "fork.knife"
        case .dose: "pills.fill"
        case .note: "note.text"
        case .mood: "face.smiling"
        }
    }
}
