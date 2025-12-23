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

    // MARK: - Optional Health Details (not required, used for screening context only)
    /// Height in centimeters (internally stored as metric, displayed based on preference)
    @Attribute var heightCm: Double?
    /// Weight in kilograms (internally stored as metric, displayed based on preference)
    @Attribute var weightKg: Double?
    /// When height/weight were last updated
    @Attribute var bodyMeasurementsUpdated: Date?
    /// User preference for units: "imperial" or "metric"
    @Attribute var unitPreference: String = "imperial"

    /// Height displayed in user's preferred format
    var heightDisplayString: String? {
        guard let cm = heightCm else { return nil }
        if unitPreference == "imperial" {
            let totalInches = cm / 2.54
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            return "\(feet)'\(inches)\""
        } else {
            return "\(Int(cm)) cm"
        }
    }

    /// Weight displayed in user's preferred format
    var weightDisplayString: String? {
        guard let kg = weightKg else { return nil }
        if unitPreference == "imperial" {
            let lbs = kg * 2.20462
            return "\(Int(lbs)) lbs"
        } else {
            return "\(Int(kg)) kg"
        }
    }

    /// Clear body measurements (for privacy)
    func clearBodyMeasurements() {
        heightCm = nil
        weightKg = nil
        bodyMeasurementsUpdated = nil
        lastUpdated = Date()
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

    // MARK: - Notification Privacy
    /// When ON, notifications show generic text instead of health details (for lock screen privacy)
    @Attribute var hideSensitiveNotificationContent: Bool = true

    // MARK: - AI Suggestion Level
    @Attribute var aiSuggestionLevel: String = "standard"  // "minimal", "standard", "proactive"

    var aiSuggestionLevelEnum: AISuggestionLevel {
        AISuggestionLevel(rawValue: aiSuggestionLevel) ?? .standard
    }

    // MARK: - AI Memory Control
    @Attribute var allowMemoryLearning: Bool = true  // When OFF, AI responds but doesn't update memories
    @Attribute var lastMemoryResetDate: Date?        // Track when memories were last reset
    @Attribute var learningPausedDate: Date?         // Track when learning was paused

    /// Pause AI learning temporarily (AI still responds, just doesn't learn new patterns)
    func pauseLearning() {
        allowMemoryLearning = false
        learningPausedDate = Date()
        lastUpdated = Date()
    }

    /// Resume AI learning
    func resumeLearning() {
        allowMemoryLearning = true
        learningPausedDate = nil
        lastUpdated = Date()
    }

    /// Days since learning was paused (nil if learning is active)
    var daysSinceLearningPaused: Int? {
        guard !allowMemoryLearning, let pausedDate = learningPausedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: pausedDate, to: Date()).day
    }

    /// Returns a hint message if learning has been paused for a while
    var learningResumeHint: LearningResumeHint? {
        guard let daysPaused = daysSinceLearningPaused else { return nil }

        if daysPaused >= 14 {
            return LearningResumeHint(
                message: "AI learning has been paused for \(daysPaused) days. Resume to improve personalization.",
                severity: .important
            )
        } else if daysPaused >= 7 {
            return LearningResumeHint(
                message: "AI learning is paused. Resume when ready to continue improving insights.",
                severity: .gentle
            )
        }

        return nil
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

    /// Status indicator text for display in UI headers
    var statusIndicator: String {
        switch self {
        case .minimal: return "AI Mode: Minimal"
        case .standard: return "AI Mode: Standard"
        case .proactive: return "AI Mode: Proactive"
        }
    }

    /// Short status for compact display
    var shortStatus: String {
        switch self {
        case .minimal: return "Observations Only"
        case .standard: return "Balanced"
        case .proactive: return "Active"
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

// MARK: - Learning Resume Hint

/// Hint shown when AI learning has been paused for a while
struct LearningResumeHint {
    let message: String
    let severity: Severity

    enum Severity {
        case gentle     // 7+ days paused
        case important  // 14+ days paused

        var icon: String {
            switch self {
            case .gentle: return "info.circle"
            case .important: return "exclamationmark.circle"
            }
        }

        var colorName: String {
            switch self {
            case .gentle: return "blue"
            case .important: return "orange"
            }
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
