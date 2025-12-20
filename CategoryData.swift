import Foundation

// MARK: - Enumerations

/// Enumeration for different types of new items that can be added
enum NewItemType: String, CaseIterable, Identifiable {
    case category = "Category"
    case symptom = "Symptom"
    var id: String { rawValue }
}

/// Alert types for user feedback
enum AlertType {
    case error
    case success
    case avoidSuggestion
}

/// Enumeration for different cause types
enum CauseType: String, CaseIterable, Identifiable {
    case mental = "Mental"
    case environmental = "Environmental"
    case physical = "Physical"
    case foodAndDrink = "Food/Drink"
    case unknown = "Unknown"
    var id: String { rawValue }
}

/// Enumeration for the logging steps
enum LogStep: Int, CaseIterable, Identifiable {
    case symptomSelection
    case causeIdentification
    case severityRating
    case affectedAreas
    case dateNotes
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .symptomSelection: return "Select Symptoms"
        case .causeIdentification: return "Identify Cause"
        case .severityRating: return "Rate Severity"
        case .affectedAreas: return "Affected Areas"
        case .dateNotes: return "Date & Notes"
        case .review: return "Review & Save"
        }
    }
}

// LogCategory is defined in LogCategory.swift

// MARK: - Category Data

/// Static category data for cause types
struct CategoryLists {
    /// Categories under Mental cause type
    static let mental: [String] = [
        "Stress",
        "Anxiety",
        "Depression",
        "Burnout",
        "Trauma",
        "Overthinking",
        "Mood Swings",
        "Emotional Exhaustion"
    ]

    /// Categories under Environmental cause type
    static let environmental: [String] = [
        "Weather Changes",
        "Allergens",
        "Air Quality",
        "Temperature",
        "Humidity",
        "Noise Pollution",
        "Lighting",
        "Seasonal Changes"
    ]

    /// Categories under Physical cause type
    static let physical: [String] = [
        "Exercise",
        "Fatigue",
        "Injury",
        "Posture",
        "Sleep Disruption",
        "Overexertion",
        "Muscle Strain",
        "Dehydration"
    ]

    /// Categories under Food & Drink cause type
    static let foodAndDrink: [String] = [
        "Meal",
        "Snack",
        "Drink",
        "Alcohol",
        "Caffeine",
        "Processed Foods",
        "Dairy",
        "Gluten",
        "Sugar",
        "Spicy Foods"
    ]

    /// Categories under Unknown cause type
    static let unknown: [String] = [
        "Unexplained",
        "Random",
        "No Clear Cause",
        "Other"
    ]

    /// Default custom categories
    static let defaultCustomCategories: [String] = [
        "Beverages",
        "Meats",
        "Nuts & Seeds",
        "Vegetables",
        "Supplements",
        "Other"
    ]

    /// Symptom triggers
    static let symptomTriggers: [String] = [
        "Diet Change",
        "Weather Change",
        "Medication",
        "Alcohol",
        "Caffeine",
        "Hormonal Changes",
        "Travel",
        "Work Pressure",
        "Social Interaction"
    ]

    /// Returns categories for a given cause type
    static func categories(for causeType: CauseType) -> [String] {
        switch causeType {
        case .mental:
            return mental
        case .environmental:
            return environmental
        case .physical:
            return physical
        case .foodAndDrink:
            return foodAndDrink
        case .unknown:
            return unknown
        }
    }
}
