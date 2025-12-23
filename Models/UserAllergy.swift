import Foundation
import SwiftData

/// Stores user's allergies, intolerances, and food sensitivities
@Model
class UserAllergy: Identifiable {
    // MARK: - Identity
    @Attribute(.unique) var id: UUID = UUID()

    // MARK: - Basic Information
    @Attribute var name: String  // "Shellfish", "Dairy", "Birch Pollen"
    @Attribute var allergyType: String  // AllergyType raw value
    @Attribute var severity: String  // AllergySeverity raw value

    // MARK: - Dates
    @Attribute var dateAdded: Date = Date()
    @Attribute var dateDiscovered: Date?  // When user first noticed the allergy

    // MARK: - Reactions (stored as JSON)
    @Attribute var knownReactionsData: Data = Data()
    var knownReactions: [String] {
        get {
            guard !knownReactionsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: knownReactionsData)) ?? []
        }
        set {
            knownReactionsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Cross-Reactive Items (stored as JSON)
    @Attribute var crossReactiveItemsData: Data = Data()
    var crossReactiveItems: [String] {
        get {
            guard !crossReactiveItemsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: crossReactiveItemsData)) ?? []
        }
        set {
            crossReactiveItemsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Helpful Medications (stored as JSON)
    @Attribute var helpfulMedicationsData: Data = Data()
    var helpfulMedications: [String] {
        get {
            guard !helpfulMedicationsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: helpfulMedicationsData)) ?? []
        }
        set {
            helpfulMedicationsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Additional Information
    @Attribute var notes: String?
    @Attribute var diagnosedByDoctor: Bool = false
    @Attribute var isActive: Bool = true  // User can "deactivate" allergies they've outgrown

    // MARK: - Initializer
    init(
        name: String,
        allergyType: AllergyType = .trueAllergy,
        severity: AllergySeverity = .moderate,
        dateDiscovered: Date? = nil,
        knownReactions: [String] = [],
        crossReactiveItems: [String] = [],
        helpfulMedications: [String] = [],
        notes: String? = nil,
        diagnosedByDoctor: Bool = false
    ) {
        self.name = name
        self.allergyType = allergyType.rawValue
        self.severity = severity.rawValue
        self.dateDiscovered = dateDiscovered
        self.knownReactions = knownReactions
        self.crossReactiveItems = crossReactiveItems
        self.helpfulMedications = helpfulMedications
        self.notes = notes
        self.diagnosedByDoctor = diagnosedByDoctor
    }

    // MARK: - Computed Properties
    var allergyTypeEnum: AllergyType {
        AllergyType(rawValue: allergyType) ?? .trueAllergy
    }

    var severityEnum: AllergySeverity {
        AllergySeverity(rawValue: severity) ?? .moderate
    }

    var severityColor: String {
        severityEnum.colorName
    }

    var severityIcon: String {
        severityEnum.icon
    }
}

// MARK: - Supporting Enums

enum AllergyType: String, Codable, CaseIterable {
    case trueAllergy = "True Allergy"        // IgE-mediated (e.g., peanuts, shellfish)
    case intolerance = "Intolerance"         // Non-immune (e.g., lactose intolerance)
    case sensitivity = "Sensitivity"          // Non-specific (e.g., caffeine sensitivity)
    case crossReactive = "Cross-Reactive"     // Oral allergy syndrome (e.g., birch -> apples)

    var description: String {
        switch self {
        case .trueAllergy:
            return "Immune system reaction (IgE-mediated)"
        case .intolerance:
            return "Digestive system cannot process properly"
        case .sensitivity:
            return "Non-specific reaction to substance"
        case .crossReactive:
            return "Reaction due to similar proteins (e.g., pollen allergies)"
        }
    }

    var icon: String {
        switch self {
        case .trueAllergy: return "exclamationmark.shield.fill"
        case .intolerance: return "stomach"
        case .sensitivity: return "waveform.path.ecg"
        case .crossReactive: return "arrow.triangle.branch"
        }
    }
}

enum AllergySeverity: String, Codable, CaseIterable {
    case mild = "Mild"           // Minor discomfort, no medical intervention needed
    case moderate = "Moderate"   // Noticeable symptoms, OTC meds help
    case severe = "Severe"       // Anaphylaxis risk, requires immediate attention

    var description: String {
        switch self {
        case .mild:
            return "Minor discomfort, usually resolves on its own"
        case .moderate:
            return "Noticeable symptoms, may need over-the-counter medication"
        case .severe:
            return "Serious reaction possible, may require emergency treatment"
        }
    }

    var colorName: String {
        switch self {
        case .mild: return "green"
        case .moderate: return "yellow"
        case .severe: return "red"
        }
    }

    var icon: String {
        switch self {
        case .mild: return "circle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .severe: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Common Allergies
struct CommonAllergy {
    let name: String
    let type: AllergyType
    let commonReactions: [String]
    let crossReactiveItems: [String]

    static let all: [CommonAllergy] = [
        // Food Allergies
        CommonAllergy(
            name: "Shellfish",
            type: .trueAllergy,
            commonReactions: ["Hives", "Swelling", "Difficulty breathing", "Anaphylaxis"],
            crossReactiveItems: ["Shrimp", "Crab", "Lobster", "Crayfish", "Prawns"]
        ),
        CommonAllergy(
            name: "Peanuts",
            type: .trueAllergy,
            commonReactions: ["Hives", "Swelling", "Stomach pain", "Anaphylaxis"],
            crossReactiveItems: ["Tree nuts (sometimes)", "Legumes (sometimes)"]
        ),
        CommonAllergy(
            name: "Tree Nuts",
            type: .trueAllergy,
            commonReactions: ["Hives", "Swelling", "Stomach pain", "Anaphylaxis"],
            crossReactiveItems: ["Almonds", "Cashews", "Walnuts", "Pecans", "Pistachios"]
        ),
        CommonAllergy(
            name: "Eggs",
            type: .trueAllergy,
            commonReactions: ["Skin rash", "Stomach upset", "Respiratory issues"],
            crossReactiveItems: []
        ),
        CommonAllergy(
            name: "Soy",
            type: .trueAllergy,
            commonReactions: ["Hives", "Stomach pain", "Swelling"],
            crossReactiveItems: []
        ),
        CommonAllergy(
            name: "Wheat",
            type: .trueAllergy,
            commonReactions: ["Hives", "Stomach pain", "Anaphylaxis"],
            crossReactiveItems: []
        ),
        CommonAllergy(
            name: "Fish",
            type: .trueAllergy,
            commonReactions: ["Hives", "Swelling", "Difficulty breathing"],
            crossReactiveItems: []
        ),

        // Intolerances
        CommonAllergy(
            name: "Dairy/Lactose",
            type: .intolerance,
            commonReactions: ["Bloating", "Gas", "Diarrhea", "Stomach cramps"],
            crossReactiveItems: ["Milk", "Cheese", "Ice cream", "Yogurt", "Butter"]
        ),
        CommonAllergy(
            name: "Gluten",
            type: .sensitivity,
            commonReactions: ["Bloating", "Fatigue", "Headaches", "Digestive issues"],
            crossReactiveItems: ["Wheat", "Barley", "Rye", "Oats (cross-contaminated)"]
        ),
        CommonAllergy(
            name: "Histamine",
            type: .intolerance,
            commonReactions: ["Headaches", "Flushing", "Hives", "Digestive issues"],
            crossReactiveItems: ["Aged cheese", "Wine", "Fermented foods", "Smoked fish", "Cured meats"]
        ),
        CommonAllergy(
            name: "FODMAP",
            type: .sensitivity,
            commonReactions: ["Bloating", "Gas", "Stomach pain", "Diarrhea"],
            crossReactiveItems: ["Onions", "Garlic", "Apples", "Beans", "Wheat"]
        ),
        CommonAllergy(
            name: "Caffeine",
            type: .sensitivity,
            commonReactions: ["Jitters", "Heart palpitations", "Anxiety", "Insomnia"],
            crossReactiveItems: ["Coffee", "Tea", "Chocolate", "Energy drinks"]
        ),

        // Cross-Reactive (Pollen-related)
        CommonAllergy(
            name: "Birch Pollen",
            type: .crossReactive,
            commonReactions: ["Itchy mouth", "Throat tingling", "Swelling lips"],
            crossReactiveItems: ["Apples", "Carrots", "Celery", "Peaches", "Plums", "Cherries", "Pears", "Almonds", "Hazelnuts"]
        ),
        CommonAllergy(
            name: "Ragweed",
            type: .crossReactive,
            commonReactions: ["Itchy mouth", "Throat tingling"],
            crossReactiveItems: ["Melons", "Bananas", "Zucchini", "Cucumbers", "Sunflower seeds"]
        ),
        CommonAllergy(
            name: "Grass Pollen",
            type: .crossReactive,
            commonReactions: ["Itchy mouth", "Throat tingling"],
            crossReactiveItems: ["Tomatoes", "Oranges", "Melons", "Wheat"]
        ),
        CommonAllergy(
            name: "Latex",
            type: .crossReactive,
            commonReactions: ["Skin rash", "Itching", "Hives"],
            crossReactiveItems: ["Bananas", "Avocados", "Kiwi", "Chestnuts", "Papaya"]
        )
    ]

    static func find(byName name: String) -> CommonAllergy? {
        all.first { $0.name.lowercased() == name.lowercased() }
    }
}

// MARK: - Cross-Reactivity Database
struct CrossReactivityDatabase {
    static let crossReactivities: [String: [String]] = [
        "Birch Pollen": ["apples", "carrots", "celery", "peaches", "plums", "cherries", "pears", "almonds", "hazelnuts", "kiwi"],
        "Ragweed": ["melons", "bananas", "zucchini", "cucumbers", "sunflower seeds", "chamomile"],
        "Grass Pollen": ["tomatoes", "oranges", "melons", "wheat", "peaches"],
        "Latex": ["bananas", "avocados", "kiwi", "chestnuts", "papaya", "passion fruit"],
        "Shellfish": ["shrimp", "crab", "lobster", "crayfish", "prawns", "scallops"],
        "Tree Nuts": ["almonds", "cashews", "walnuts", "pecans", "pistachios", "brazil nuts", "macadamia", "hazelnuts"],
        "Dairy": ["milk", "cheese", "butter", "cream", "yogurt", "ice cream", "whey", "casein"],
        "Gluten": ["wheat", "barley", "rye", "spelt", "kamut", "triticale"],
        "Soy": ["soybeans", "edamame", "tofu", "tempeh", "miso", "soy sauce", "soy milk"]
    ]

    /// Check if a food item is cross-reactive with any of the user's allergies
    static func checkCrossReactivity(food: String, allergies: [String]) -> (isReactive: Bool, sourceAllergy: String?) {
        let normalizedFood = food.lowercased()

        for allergy in allergies {
            if let reactiveItems = crossReactivities[allergy] {
                if reactiveItems.contains(where: { normalizedFood.contains($0) }) {
                    return (true, allergy)
                }
            }
        }

        return (false, nil)
    }
}
