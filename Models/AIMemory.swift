import Foundation
import SwiftData

/// Stores AI's learned knowledge about what works/doesn't work for this user
@Model
class AIMemory: Identifiable {
    // MARK: - Identity
    @Attribute(.unique) var id: UUID = UUID()

    // MARK: - Memory Classification
    @Attribute var memoryType: String  // MemoryType raw value

    // MARK: - Context
    @Attribute var symptom: String?         // Related symptom (e.g., "Headache")
    @Attribute var trigger: String?          // Food, supplement, event, or condition
    @Attribute var resolution: String?       // What helped resolve the symptom
    @Attribute var resolutionTime: String?   // "within 2 hours", "next day", etc.

    // MARK: - Tracking
    @Attribute var occurrenceCount: Int = 1       // How many times this pattern observed
    @Attribute var successCount: Int = 0          // Times it helped (for remedies)
    @Attribute var failureCount: Int = 0          // Times it didn't help
    @Attribute var lastOccurrence: Date = Date()

    // MARK: - Specific Dates (for detailed memory mode)
    @Attribute var specificDatesData: Data = Data()
    var specificDates: [Date] {
        get {
            guard !specificDatesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([Date].self, from: specificDatesData)) ?? []
        }
        set {
            specificDatesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Confidence
    @Attribute var confidence: Double = 0.5      // 0-1 based on occurrences and consistency
    @Attribute var userConfirmed: Bool = false   // User said "yes this is accurate"
    @Attribute var userDenied: Bool = false      // User said "no this is wrong"

    // MARK: - Additional Context
    @Attribute var notes: String?
    @Attribute var relatedEnvironmentalFactor: String?  // "low pressure", "high humidity"
    @Attribute var relatedTimeOfDay: String?            // "morning", "evening"
    @Attribute var correlationStrength: Double?         // Calculated correlation percentage

    // MARK: - Status
    @Attribute var isActive: Bool = true
    @Attribute var createdDate: Date = Date()
    @Attribute var lastUpdated: Date = Date()

    // MARK: - Initializer
    init(
        memoryType: MemoryType,
        symptom: String? = nil,
        trigger: String? = nil,
        resolution: String? = nil,
        resolutionTime: String? = nil,
        occurrenceCount: Int = 1,
        confidence: Double = 0.5,
        notes: String? = nil
    ) {
        self.memoryType = memoryType.rawValue
        self.symptom = symptom
        self.trigger = trigger
        self.resolution = resolution
        self.resolutionTime = resolutionTime
        self.occurrenceCount = occurrenceCount
        self.confidence = confidence
        self.notes = notes
    }

    // MARK: - Computed Properties
    var memoryTypeEnum: MemoryType {
        MemoryType(rawValue: memoryType) ?? .pattern
    }

    var confidenceLevel: ConfidenceLevel {
        ConfidenceLevel.from(confidence: confidence, occurrences: occurrenceCount)
    }

    var effectivenessScore: Double {
        guard successCount + failureCount > 0 else { return 0.5 }
        return Double(successCount) / Double(successCount + failureCount)
    }

    var effectivenessPercentage: Int {
        Int(effectivenessScore * 100)
    }

    /// Time-decayed confidence that weighs recent data more heavily
    var decayedConfidence: Double {
        let daysSinceLastOccurrence = Calendar.current.dateComponents(
            [.day],
            from: lastOccurrence,
            to: Date()
        ).day ?? 0

        // Apply decay: confidence drops by ~10% per month of inactivity
        // After 6 months, decay is ~50%; after 12 months, ~75%
        let decayFactor = exp(-Double(daysSinceLastOccurrence) / 180.0)
        return confidence * decayFactor
    }

    /// Decayed confidence level considering time since last occurrence
    var decayedConfidenceLevel: ConfidenceLevel {
        ConfidenceLevel.from(confidence: decayedConfidence, occurrences: recentOccurrenceCount)
    }

    /// Count of occurrences in the last 90 days (more relevant than total)
    var recentOccurrenceCount: Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let recentDates = specificDates.filter { $0 >= cutoffDate }
        return max(recentDates.count, min(occurrenceCount, 3)) // At least show 3 if we have them
    }

    /// Whether this memory is stale and should be deprioritized
    var isStale: Bool {
        let daysSinceLastOccurrence = Calendar.current.dateComponents(
            [.day],
            from: lastOccurrence,
            to: Date()
        ).day ?? 0
        return daysSinceLastOccurrence > 180 // Stale after 6 months
    }

    /// Whether this memory has enough recent data to be reliable
    var hasRecentData: Bool {
        let daysSinceLastOccurrence = Calendar.current.dateComponents(
            [.day],
            from: lastOccurrence,
            to: Date()
        ).day ?? 0
        return daysSinceLastOccurrence <= 90
    }

    // MARK: - Methods

    /// Record that this memory was observed again
    func recordOccurrence(date: Date = Date()) {
        occurrenceCount += 1
        lastOccurrence = date
        lastUpdated = Date()

        // Add to specific dates if in detailed mode
        var dates = specificDates
        dates.append(date)
        // Keep only last 20 dates to avoid data bloat
        if dates.count > 20 {
            dates = Array(dates.suffix(20))
        }
        specificDates = dates

        updateConfidence()
    }

    /// Record that the remedy/suggestion helped
    func recordSuccess() {
        successCount += 1
        lastUpdated = Date()
        updateConfidence()
    }

    /// Record that the remedy/suggestion didn't help
    func recordFailure() {
        failureCount += 1
        lastUpdated = Date()
        updateConfidence()
    }

    /// User confirmed this memory is accurate
    func confirmByUser() {
        userConfirmed = true
        userDenied = false
        confidence = min(1.0, confidence + 0.1)
        lastUpdated = Date()
    }

    /// User denied this memory is accurate
    func denyByUser() {
        userDenied = true
        userConfirmed = false
        confidence = max(0.0, confidence - 0.2)
        lastUpdated = Date()
    }

    /// Recalculate confidence based on occurrences and feedback
    private func updateConfidence() {
        var newConfidence: Double = 0.3  // Base confidence

        // Occurrences boost confidence
        if occurrenceCount >= 10 { newConfidence += 0.3 }
        else if occurrenceCount >= 5 { newConfidence += 0.2 }
        else if occurrenceCount >= 3 { newConfidence += 0.1 }

        // Effectiveness for remedies
        if memoryTypeEnum == .whatWorked || memoryTypeEnum == .whatDidntWork {
            let effectiveness = effectivenessScore
            if effectiveness >= 0.7 { newConfidence += 0.3 }
            else if effectiveness >= 0.5 { newConfidence += 0.15 }
        }

        // User feedback adjustments
        if userConfirmed { newConfidence += 0.1 }
        if userDenied { newConfidence -= 0.2 }

        confidence = min(1.0, max(0.0, newConfidence))
    }
}

// MARK: - Supporting Enums

enum MemoryType: String, Codable, CaseIterable {
    case whatWorked = "What Worked"       // "Magnesium helped headache"
    case whatDidntWork = "What Didn't Work" // "Ibuprofen didn't help"
    case trigger = "Trigger"               // "Dairy causes bloating"
    case pattern = "Pattern"               // "Headaches on low pressure days"
    case correlation = "Correlation"       // "Sleep < 6hrs -> fatigue"
    case preference = "Preference"         // "User prefers natural remedies"

    var icon: String {
        switch self {
        case .whatWorked: return "checkmark.circle.fill"
        case .whatDidntWork: return "xmark.circle.fill"
        case .trigger: return "exclamationmark.triangle.fill"
        case .pattern: return "waveform.path.ecg"
        case .correlation: return "arrow.triangle.branch"
        case .preference: return "heart.fill"
        }
    }

    var description: String {
        switch self {
        case .whatWorked: return "Remedies and treatments that helped"
        case .whatDidntWork: return "Things that didn't help"
        case .trigger: return "Foods, events, or conditions that cause symptoms"
        case .pattern: return "Recurring patterns observed over time"
        case .correlation: return "Relationships between factors and symptoms"
        case .preference: return "User preferences and settings"
        }
    }
}

enum ConfidenceLevel: String, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var icon: String {
        switch self {
        case .high: return "circle.fill"      // Green
        case .medium: return "circle.fill"    // Yellow
        case .low: return "circle.fill"       // Red
        }
    }

    var colorName: String {
        switch self {
        case .high: return "green"
        case .medium: return "yellow"
        case .low: return "red"
        }
    }

    var description: String {
        switch self {
        case .high: return "Observed many times with consistent results"
        case .medium: return "Observed several times, pattern emerging"
        case .low: return "Limited observations, needs more data"
        }
    }

    static func from(confidence: Double, occurrences: Int) -> ConfidenceLevel {
        if occurrences >= 10 && confidence >= 0.7 { return .high }
        if occurrences >= 5 && confidence >= 0.5 { return .medium }
        return .low
    }
}

// MARK: - AI Response Models (for display)

/// Represents an AI-generated response after user logs something
struct AIResponse {
    var observations: [AIObservation] = []
    var questions: [AIQuestion] = []
    var suggestions: [AISuggestion] = []
    var warnings: [AIWarning] = []
    var needsMoreData: NeedsMoreDataMessage?  // Shown when AI doesn't have enough info
    var timestamp: Date = Date()

    var hasContent: Bool {
        !observations.isEmpty || !questions.isEmpty || !suggestions.isEmpty || !warnings.isEmpty || needsMoreData != nil
    }

    var hasOnlyNeedsMoreData: Bool {
        observations.isEmpty && questions.isEmpty && suggestions.isEmpty && warnings.isEmpty && needsMoreData != nil
    }
}

/// Message shown when AI doesn't have enough data to provide insights
struct NeedsMoreDataMessage {
    let text: String
    let dataNeeded: [String]     // What data would help
    let currentProgress: String? // e.g., "2 of 5 logs needed"

    static let defaultMessage = NeedsMoreDataMessage(
        text: "I'm still learning your patterns. Keep logging and I'll start spotting trends soon!",
        dataNeeded: ["More symptom logs", "Food/trigger tracking", "Time to observe patterns"],
        currentProgress: nil
    )

    static func forSymptom(_ symptom: String, occurrences: Int, minimumNeeded: Int) -> NeedsMoreDataMessage {
        NeedsMoreDataMessage(
            text: "I don't have enough data about your \(symptom.lowercased()) yet to identify patterns. I'll keep tracking as you log.",
            dataNeeded: ["More \(symptom.lowercased()) logs", "Potential trigger info", "What helped or didn't"],
            currentProgress: occurrences > 0 ? "\(occurrences) of ~\(minimumNeeded) logs for reliable patterns" : nil
        )
    }

    static func generalLowConfidence() -> NeedsMoreDataMessage {
        NeedsMoreDataMessage(
            text: "I have some early observations, but need more data to be confident. I'll keep learning as you log more.",
            dataNeeded: ["Continue logging symptoms", "Note what you eat and do", "Track what helps"],
            currentProgress: nil
        )
    }
}

struct AIObservation {
    let text: String
    let confidence: ConfidenceLevel
    let relatedMemory: AIMemory?
    let icon: String

    init(text: String, confidence: ConfidenceLevel = .medium, relatedMemory: AIMemory? = nil, icon: String = "lightbulb.fill") {
        self.text = text
        self.confidence = confidence
        self.relatedMemory = relatedMemory
        self.icon = icon
    }
}

struct AIQuestion {
    let text: String
    let options: [String]
    let context: String?
    let relatedTo: String?  // What this question relates to (symptom, trigger, etc.)

    init(text: String, options: [String] = ["Yes", "No"], context: String? = nil, relatedTo: String? = nil) {
        self.text = text
        self.options = options
        self.context = context
        self.relatedTo = relatedTo
    }
}

struct AISuggestion {
    let text: String
    let effectiveness: Int?  // Percentage if known
    let lastHelped: Date?
    let icon: String

    init(text: String, effectiveness: Int? = nil, lastHelped: Date? = nil, icon: String = "star.fill") {
        self.text = text
        self.effectiveness = effectiveness
        self.lastHelped = lastHelped
        self.icon = icon
    }
}

struct AIWarning {
    let text: String
    let severity: WarningSeverity
    let actionRequired: Bool

    enum WarningSeverity: String {
        case info = "Info"
        case caution = "Caution"
        case alert = "Alert"

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .caution: return "exclamationmark.circle.fill"
            case .alert: return "exclamationmark.triangle.fill"
            }
        }

        var colorName: String {
            switch self {
            case .info: return "blue"
            case .caution: return "yellow"
            case .alert: return "red"
            }
        }
    }
}

// MARK: - User Feedback

enum UserFeedback: String, CaseIterable {
    case helped = "Helped"
    case didntHelp = "Didn't Help"
    case notSureYet = "Not Sure Yet"

    var icon: String {
        switch self {
        case .helped: return "hand.thumbsup.fill"
        case .didntHelp: return "hand.thumbsdown.fill"
        case .notSureYet: return "questionmark.circle.fill"
        }
    }
}
