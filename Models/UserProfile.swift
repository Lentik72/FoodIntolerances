import Foundation
import SwiftData

/// User's personal profile for AI personalization
@Model
class UserProfile: Identifiable {
    // MARK: - Identity
    @Attribute(.unique) var id: UUID = UUID()

    // MARK: - Basic Information
    @Attribute var age: Int?
    @Attribute var gender: String?  // "Male", "Female", "Other", "Prefer not to say"
    @Attribute var dateOfBirth: Date?

    // MARK: - Health Conditions (stored as JSON)
    @Attribute var healthConditionsData: Data = Data()
    var healthConditions: [String] {
        get {
            guard !healthConditionsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: healthConditionsData)) ?? []
        }
        set {
            healthConditionsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Lifestyle
    @Attribute var activityLevel: String?  // "Sedentary", "Light", "Moderate", "Active", "Very Active"
    @Attribute var dietType: String?  // "Omnivore", "Vegetarian", "Vegan", "Pescatarian", "Other"
    @Attribute var smokingStatus: String?  // "Never", "Former", "Current"
    @Attribute var alcoholConsumption: String?  // "None", "Occasional", "Moderate", "Frequent"

    // MARK: - Sleep
    @Attribute var targetSleepHours: Double = 8.0
    @Attribute var typicalBedtime: Date?
    @Attribute var typicalWakeTime: Date?

    // MARK: - AI Memory Preferences
    @Attribute var memoryLevel: String = "patterns"  // "detailed", "patterns", "minimal"
    @Attribute var memoryPreferencesData: Data = Data()  // Per-topic memory settings
    var memoryPreferences: [String: String] {
        get {
            guard !memoryPreferencesData.isEmpty else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: memoryPreferencesData)) ?? [:]
        }
        set {
            memoryPreferencesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Onboarding Status
    @Attribute var hasCompletedOnboarding: Bool = false
    @Attribute var onboardingCompletedDate: Date?
    @Attribute var onboardingStepsCompleted: Int = 0  // Track progress (0-7)

    // MARK: - Preferences
    @Attribute var enableProactiveNotifications: Bool = true
    @Attribute var enableHealthScreeningReminders: Bool = true
    @Attribute var enableSupplementReminders: Bool = true
    @Attribute var enableWeatherAlerts: Bool = true

    // MARK: - AI Suggestion Level
    @Attribute var aiSuggestionLevel: String = "standard"  // "minimal", "standard", "proactive"

    var aiSuggestionLevelEnum: AISuggestionLevel {
        AISuggestionLevel(rawValue: aiSuggestionLevel) ?? .standard
    }

    // MARK: - Cloud AI (Optional)
    @Attribute var useCloudAI: Bool = false

    // MARK: - Timestamps
    @Attribute var createdDate: Date = Date()
    @Attribute var lastUpdated: Date = Date()

    // MARK: - Initializer
    init(
        age: Int? = nil,
        gender: String? = nil,
        dateOfBirth: Date? = nil,
        healthConditions: [String] = [],
        activityLevel: String? = nil,
        dietType: String? = nil,
        targetSleepHours: Double = 8.0,
        memoryLevel: String = "patterns"
    ) {
        self.age = age
        self.gender = gender
        self.dateOfBirth = dateOfBirth
        self.healthConditions = healthConditions
        self.activityLevel = activityLevel
        self.dietType = dietType
        self.targetSleepHours = targetSleepHours
        self.memoryLevel = memoryLevel
    }
}

// MARK: - Supporting Enums

enum AIMemoryLevel: String, Codable, CaseIterable {
    case detailed = "detailed"    // "Pizza caused migraine on Dec 15th"
    case patterns = "patterns"    // "Pizza often causes migraines for you"
    case minimal = "minimal"      // "Some foods trigger migraines"

    var displayName: String {
        switch self {
        case .detailed: return "Detailed"
        case .patterns: return "Patterns Only"
        case .minimal: return "Minimal"
        }
    }

    var description: String {
        switch self {
        case .detailed: return "Remember specific dates and events"
        case .patterns: return "Remember patterns and frequencies"
        case .minimal: return "Keep it general, no specifics"
        }
    }

    var example: String {
        switch self {
        case .detailed: return "Your migraine on Dec 15th after pizza"
        case .patterns: return "Pizza often causes migraines for you"
        case .minimal: return "Some foods may trigger migraines"
        }
    }
}

enum Gender: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"
    case other = "Other"
    case preferNotToSay = "Prefer not to say"
}

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary = "Sedentary"
    case light = "Light"
    case moderate = "Moderate"
    case active = "Active"
    case veryActive = "Very Active"
}

enum DietType: String, Codable, CaseIterable {
    case omnivore = "Omnivore"
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case pescatarian = "Pescatarian"
    case keto = "Keto"
    case paleo = "Paleo"
    case other = "Other"
}

/// Controls how proactive the AI is with suggestions
enum AISuggestionLevel: String, Codable, CaseIterable, Identifiable {
    case minimal = "minimal"       // Only show high-confidence insights
    case standard = "standard"     // Show balanced suggestions
    case proactive = "proactive"   // Show more predictions and suggestions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .proactive: return "Proactive"
        }
    }

    var description: String {
        switch self {
        case .minimal:
            return "Only high-confidence insights, fewer questions"
        case .standard:
            return "Balanced suggestions and observations"
        case .proactive:
            return "More predictions, reminders, and check-ins"
        }
    }

    var icon: String {
        switch self {
        case .minimal: return "minus.circle"
        case .standard: return "circle.circle"
        case .proactive: return "plus.circle"
        }
    }

    /// Minimum confidence threshold for showing observations
    var confidenceThreshold: Double {
        switch self {
        case .minimal: return 0.7    // Only high confidence
        case .standard: return 0.5   // Medium and high
        case .proactive: return 0.3  // Show more, including low confidence
        }
    }

    /// Minimum occurrences before showing a pattern
    var minimumOccurrences: Int {
        switch self {
        case .minimal: return 5
        case .standard: return 3
        case .proactive: return 2
        }
    }

    /// Maximum number of questions to ask
    var maxQuestions: Int {
        switch self {
        case .minimal: return 1
        case .standard: return 2
        case .proactive: return 3
        }
    }

    /// Whether to show "needs more data" messages
    var showNeedsMoreData: Bool {
        switch self {
        case .minimal: return false
        case .standard: return true
        case .proactive: return true
        }
    }
}

// MARK: - Common Health Conditions
struct CommonHealthCondition {
    static let all: [String] = [
        "Diabetes",
        "High Blood Pressure",
        "Heart Disease",
        "Thyroid Issues",
        "Asthma",
        "COPD",
        "Autoimmune Condition",
        "Arthritis",
        "Anxiety",
        "Depression",
        "GERD/Acid Reflux",
        "IBS",
        "Migraines",
        "Fibromyalgia",
        "Chronic Fatigue",
        "Sleep Apnea"
    ]
}
