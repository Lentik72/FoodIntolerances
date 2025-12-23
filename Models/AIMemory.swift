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

    // MARK: - Schema Version (for future migrations)
    /// Increment when confidence math or memory structure changes
    @Attribute var schemaVersion: Int = 1

    /// Current schema version for new memories
    static let currentSchemaVersion: Int = 1

    // MARK: - Suggestion Cooldown
    @Attribute var lastShownDate: Date?           // When this suggestion was last displayed
    @Attribute var consecutiveIgnores: Int = 0    // Times shown without positive feedback
    @Attribute var cooldownUntil: Date?           // Suppress until this date

    // MARK: - Cooldown Constants
    private static let baseCooldownHours: Int = 24           // 1 day base cooldown
    private static let maxCooldownDays: Int = 14             // Max 2 weeks cooldown
    private static let ignoresBeforeCooldown: Int = 3        // Ignores before cooldown kicks in

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

    // MARK: - Confidence Constants

    /// Minimum confidence floor to prevent oscillation/thrashing
    private static let minimumConfidenceFloor: Double = 0.15

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
        let decayed = confidence * decayFactor

        // Never decay below the floor to prevent thrashing
        return max(decayed, Self.minimumConfidenceFloor)
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

    // MARK: - Cooldown Computed Properties

    /// Whether this suggestion is currently in cooldown (should not be shown)
    var isInCooldown: Bool {
        guard let cooldownEnd = cooldownUntil else { return false }
        return Date() < cooldownEnd
    }

    /// Hours remaining in cooldown (nil if not in cooldown)
    var cooldownHoursRemaining: Int? {
        guard let cooldownEnd = cooldownUntil, isInCooldown else { return nil }
        return Calendar.current.dateComponents([.hour], from: Date(), to: cooldownEnd).hour
    }

    /// Whether this suggestion was shown recently (within 4 hours)
    var wasShownRecently: Bool {
        guard let lastShown = lastShownDate else { return false }
        let hoursSinceShown = Calendar.current.dateComponents([.hour], from: lastShown, to: Date()).hour ?? 0
        return hoursSinceShown < 4
    }

    /// Whether this suggestion should be suppressed (cooldown OR recently shown)
    var shouldSuppressSuggestion: Bool {
        isInCooldown || wasShownRecently
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

    /// Handle user feedback on a suggestion/observation
    func applyFeedback(_ feedback: UserFeedback) {
        lastUpdated = Date()

        switch feedback {
        case .helped:
            recordSuccess()
            userConfirmed = true
            resetCooldown()  // Positive feedback resets cooldown
        case .didntHelp:
            recordFailure()
            recordIgnored()  // Didn't help counts as ignored for cooldown
        case .notSureYet:
            // No action needed
            break
        case .notRelevant:
            // Strongly suppress this memory
            userDenied = true
            confidence = max(0.0, confidence + feedback.confidenceAdjustment)
            recordIgnored()  // Not relevant definitely counts as ignored
            // Mark as suppressed if repeatedly marked not relevant
            if confidence <= 0.2 {
                isActive = false
            }
        }
    }

    // MARK: - Cooldown Management

    /// Record that this suggestion was shown to the user
    func recordShown() {
        lastShownDate = Date()
        lastUpdated = Date()
    }

    /// Record that this suggestion was ignored (no positive feedback)
    func recordIgnored() {
        consecutiveIgnores += 1
        lastUpdated = Date()

        // Apply cooldown if ignored too many times
        if consecutiveIgnores >= Self.ignoresBeforeCooldown {
            applyCooldown()
        }
    }

    /// Apply cooldown period - exponentially increasing based on consecutive ignores
    func applyCooldown() {
        // Exponential backoff: 1 day, 2 days, 4 days, 7 days, 14 days (max)
        let multiplier = min(consecutiveIgnores - Self.ignoresBeforeCooldown + 1, 4)
        let cooldownHours = Self.baseCooldownHours * Int(pow(2.0, Double(multiplier - 1)))
        let maxCooldownHours = Self.maxCooldownDays * 24

        let actualCooldownHours = min(cooldownHours, maxCooldownHours)
        cooldownUntil = Calendar.current.date(byAdding: .hour, value: actualCooldownHours, to: Date())
        lastUpdated = Date()
    }

    /// Reset cooldown when user gives positive feedback
    func resetCooldown() {
        consecutiveIgnores = 0
        cooldownUntil = nil
        lastUpdated = Date()
    }

    /// Clear cooldown manually (for testing or user override)
    func clearCooldown() {
        cooldownUntil = nil
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

    // MARK: - Response Limits
    private static let maxCharacters = 600
    private static let maxObservations = 3
    private static let maxSuggestions = 2
    private static let maxQuestions = 2
    private static let maxWarnings = 2

    var hasContent: Bool {
        !observations.isEmpty || !questions.isEmpty || !suggestions.isEmpty || !warnings.isEmpty || needsMoreData != nil
    }

    var hasOnlyNeedsMoreData: Bool {
        observations.isEmpty && questions.isEmpty && suggestions.isEmpty && warnings.isEmpty && needsMoreData != nil
    }

    /// Total character count of all text content
    var totalCharacterCount: Int {
        let obsChars = observations.reduce(0) { $0 + $1.text.count }
        let sugChars = suggestions.reduce(0) { $0 + $1.text.count }
        let qChars = questions.reduce(0) { $0 + $1.text.count }
        let warnChars = warnings.reduce(0) { $0 + $1.text.count }
        let needsDataChars = needsMoreData?.text.count ?? 0
        return obsChars + sugChars + qChars + warnChars + needsDataChars
    }

    /// Whether response exceeds recommended length
    var isOverLength: Bool {
        totalCharacterCount > Self.maxCharacters
    }

    /// Get a trimmed version of the response that fits within limits
    mutating func trimToFit() {
        // Prioritize: warnings > observations > suggestions > questions
        // Keep most important items, trim excess

        // Limit each category
        if warnings.count > Self.maxWarnings {
            warnings = Array(warnings.prefix(Self.maxWarnings))
        }

        if observations.count > Self.maxObservations {
            // Keep highest confidence observations
            observations = Array(observations
                .sorted { confidenceRank($0.confidence) > confidenceRank($1.confidence) }
                .prefix(Self.maxObservations))
        }

        if suggestions.count > Self.maxSuggestions {
            // Keep highest effectiveness suggestions
            suggestions = Array(suggestions
                .sorted { ($0.effectiveness ?? 0) > ($1.effectiveness ?? 0) }
                .prefix(Self.maxSuggestions))
        }

        if questions.count > Self.maxQuestions {
            questions = Array(questions.prefix(Self.maxQuestions))
        }

        // If still over length, remove low-confidence observations
        if isOverLength && observations.count > 1 {
            observations = observations.filter { $0.confidence != .low }
        }

        // If still over length, remove questions
        if isOverLength && !questions.isEmpty {
            questions = []
        }
    }

    /// Get a pre-trimmed copy of the response
    func trimmed() -> AIResponse {
        var copy = self
        copy.trimToFit()
        return copy
    }

    private func confidenceRank(_ level: ConfidenceLevel) -> Int {
        switch level {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
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

    /// Human-readable evidence summary explaining why this observation was made
    var evidenceSummary: String? {
        guard let memory = relatedMemory else { return nil }

        var parts: [String] = []

        // Occurrence count
        if memory.occurrenceCount > 1 {
            parts.append("\(memory.occurrenceCount) occurrences")
        }

        // Time range
        let daysSinceFirst = Calendar.current.dateComponents(
            [.day],
            from: memory.createdDate,
            to: Date()
        ).day ?? 0

        if daysSinceFirst > 90 {
            let months = daysSinceFirst / 30
            parts.append("over \(months) months")
        } else if daysSinceFirst > 30 {
            parts.append("over \(daysSinceFirst / 7) weeks")
        } else if daysSinceFirst > 7 {
            parts.append("past \(daysSinceFirst) days")
        }

        // Effectiveness if available
        if memory.effectivenessPercentage > 0 && memory.successCount + memory.failureCount >= 3 {
            parts.append("\(memory.effectivenessPercentage)% effective")
        }

        guard !parts.isEmpty else { return nil }
        return "Based on " + parts.joined(separator: ", ")
    }

    /// Short confidence description
    var confidenceDescription: String {
        switch confidence {
        case .high: return "High confidence"
        case .medium: return "Moderate confidence"
        case .low: return "Early observation"
        }
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
    let occurrenceCount: Int?  // How many times this was tried

    init(text: String, effectiveness: Int? = nil, lastHelped: Date? = nil, icon: String = "star.fill", occurrenceCount: Int? = nil) {
        self.text = text
        self.effectiveness = effectiveness
        self.lastHelped = lastHelped
        self.icon = icon
        self.occurrenceCount = occurrenceCount
    }

    /// Human-readable evidence summary for this suggestion
    var evidenceSummary: String? {
        var parts: [String] = []

        if let count = occurrenceCount, count > 1 {
            parts.append("tried \(count) times")
        }

        if let eff = effectiveness, eff > 0 {
            parts.append("\(eff)% success rate")
        }

        if let lastDate = lastHelped {
            let daysAgo = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            if daysAgo == 0 {
                parts.append("helped today")
            } else if daysAgo == 1 {
                parts.append("helped yesterday")
            } else if daysAgo < 7 {
                parts.append("helped \(daysAgo) days ago")
            } else if daysAgo < 30 {
                parts.append("helped \(daysAgo / 7) weeks ago")
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ").capitalized
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
    case notRelevant = "Not Relevant"  // Quickly dismiss irrelevant suggestions

    var icon: String {
        switch self {
        case .helped: return "hand.thumbsup.fill"
        case .didntHelp: return "hand.thumbsdown.fill"
        case .notSureYet: return "questionmark.circle.fill"
        case .notRelevant: return "xmark.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .helped: return "This was helpful"
        case .didntHelp: return "This didn't help"
        case .notSureYet: return "Not sure yet"
        case .notRelevant: return "This doesn't apply to me"
        }
    }

    /// How much to adjust confidence based on feedback
    var confidenceAdjustment: Double {
        switch self {
        case .helped: return 0.1        // Boost confidence
        case .didntHelp: return -0.15   // Reduce confidence
        case .notSureYet: return 0.0    // No change
        case .notRelevant: return -0.25 // Strongly reduce - prevents future resurfacing
        }
    }

    /// Whether this feedback should suppress future suggestions
    var shouldSuppress: Bool {
        self == .notRelevant
    }
}

// MARK: - Memory Health Check

/// Utility for checking and fixing memory system health issues
struct MemoryHealthCheck {

    /// Issues that can be detected in memories
    struct HealthIssue {
        let memoryId: UUID
        let issueType: IssueType
        let description: String
        let autoFixable: Bool

        enum IssueType: String {
            case invalidConfidence = "Invalid Confidence"
            case stuckNeedsMoreData = "Stuck Learning"
            case orphanedMemory = "Orphaned Memory"
            case duplicateMemory = "Duplicate Memory"
            case staleHighConfidence = "Stale High Confidence"
        }
    }

    /// Run health check on all memories
    static func checkHealth(memories: [AIMemory]) -> [HealthIssue] {
        var issues: [HealthIssue] = []

        for memory in memories {
            // Check for NaN or invalid confidence
            if memory.confidence.isNaN || memory.confidence < 0 || memory.confidence > 1 {
                issues.append(HealthIssue(
                    memoryId: memory.id,
                    issueType: .invalidConfidence,
                    description: "Memory has invalid confidence value: \(memory.confidence)",
                    autoFixable: true
                ))
            }

            // Check for stuck "needs more data" (>90 days with low occurrences)
            let daysSinceCreation = Calendar.current.dateComponents(
                [.day],
                from: memory.createdDate,
                to: Date()
            ).day ?? 0

            if daysSinceCreation > 90 && memory.occurrenceCount < 3 && memory.isActive {
                issues.append(HealthIssue(
                    memoryId: memory.id,
                    issueType: .stuckNeedsMoreData,
                    description: "Memory created \(daysSinceCreation) days ago with only \(memory.occurrenceCount) occurrences",
                    autoFixable: true
                ))
            }

            // Check for stale but high confidence (should have decayed)
            if memory.isStale && memory.confidence > 0.8 {
                issues.append(HealthIssue(
                    memoryId: memory.id,
                    issueType: .staleHighConfidence,
                    description: "Memory is stale but still has high confidence (\(Int(memory.confidence * 100))%)",
                    autoFixable: true
                ))
            }
        }

        // Check for duplicates
        let groupedByKey = Dictionary(grouping: memories) { memory in
            "\(memory.memoryType)-\(memory.symptom ?? "")-\(memory.trigger ?? "")-\(memory.resolution ?? "")"
        }

        for (_, group) in groupedByKey where group.count > 1 {
            for duplicate in group.dropFirst() {
                issues.append(HealthIssue(
                    memoryId: duplicate.id,
                    issueType: .duplicateMemory,
                    description: "Duplicate memory found",
                    autoFixable: true
                ))
            }
        }

        return issues
    }

    /// Auto-fix issues that can be fixed
    static func autoFix(memory: AIMemory, issue: HealthIssue) {
        switch issue.issueType {
        case .invalidConfidence:
            // Reset to reasonable default
            memory.confidence = 0.5
            memory.lastUpdated = Date()
            Logger.info("Fixed invalid confidence for memory \(memory.id)", category: .data)

        case .stuckNeedsMoreData:
            // Deactivate stuck memories
            memory.isActive = false
            memory.lastUpdated = Date()
            Logger.info("Deactivated stuck memory \(memory.id)", category: .data)

        case .staleHighConfidence:
            // Force confidence recalculation (decay will apply)
            memory.confidence = memory.decayedConfidence
            memory.lastUpdated = Date()
            Logger.info("Applied decay to stale memory \(memory.id)", category: .data)

        case .duplicateMemory:
            // Deactivate duplicate
            memory.isActive = false
            memory.lastUpdated = Date()
            Logger.info("Deactivated duplicate memory \(memory.id)", category: .data)

        case .orphanedMemory:
            // Can't auto-fix orphaned memories
            break
        }
    }

    /// Run health check and auto-fix issues
    static func runMaintenanceCheck(memories: [AIMemory]) -> Int {
        let issues = checkHealth(memories: memories)
        var fixedCount = 0

        for issue in issues where issue.autoFixable {
            if let memory = memories.first(where: { $0.id == issue.memoryId }) {
                autoFix(memory: memory, issue: issue)
                fixedCount += 1
            }
        }

        if fixedCount > 0 {
            Logger.info("Memory health check: fixed \(fixedCount) issues", category: .data)
        }

        return fixedCount
    }
}

// MARK: - Memory Maintenance Scheduler

/// Manages periodic memory maintenance to keep AI system healthy
class MemoryMaintenanceScheduler {
    static let shared = MemoryMaintenanceScheduler()

    /// Key for storing last maintenance run date
    private let lastRunKey = "aiMemoryLastMaintenanceRun"

    /// Minimum hours between maintenance runs
    private let minimumHoursBetweenRuns: Int = 24

    /// Last time maintenance was run
    var lastMaintenanceDate: Date? {
        get { UserDefaults.standard.object(forKey: lastRunKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastRunKey) }
    }

    /// Whether maintenance should run (hasn't run in last 24 hours)
    var shouldRunMaintenance: Bool {
        guard let lastRun = lastMaintenanceDate else { return true }
        let hoursSinceLastRun = Calendar.current.dateComponents(
            [.hour],
            from: lastRun,
            to: Date()
        ).hour ?? 0
        return hoursSinceLastRun >= minimumHoursBetweenRuns
    }

    /// Run maintenance if needed (call on app foreground)
    /// - Parameter memories: All AI memories from the model context
    /// - Returns: Number of issues fixed, or nil if maintenance was skipped
    @discardableResult
    func runMaintenanceIfNeeded(memories: [AIMemory]) -> Int? {
        guard shouldRunMaintenance else {
            Logger.debug("Skipping AI maintenance - last run was recent", category: .data)
            return nil
        }

        Logger.info("Running AI memory maintenance...", category: .data)

        // Run on background queue to avoid UI jank
        let fixedCount = MemoryHealthCheck.runMaintenanceCheck(memories: memories)

        lastMaintenanceDate = Date()

        if fixedCount > 0 {
            Logger.info("AI maintenance complete: fixed \(fixedCount) issues", category: .data)
        } else {
            Logger.debug("AI maintenance complete: no issues found", category: .data)
        }

        return fixedCount
    }

    /// Force maintenance to run regardless of schedule (for testing/debugging)
    @discardableResult
    func forceRunMaintenance(memories: [AIMemory]) -> Int {
        Logger.info("Force running AI memory maintenance...", category: .data)
        let fixedCount = MemoryHealthCheck.runMaintenanceCheck(memories: memories)
        lastMaintenanceDate = Date()
        return fixedCount
    }

    /// Reset maintenance schedule (for testing)
    func resetSchedule() {
        lastMaintenanceDate = nil
    }
}

// MARK: - AI System Status (Debug/Internal)

/// Provides a quick health summary of the AI system for debugging
struct AISystemStatus {

    enum Status: String {
        case healthy = "Healthy"
        case degraded = "Degraded"
        case needsAttention = "Needs Attention"

        var icon: String {
            switch self {
            case .healthy: return "checkmark.circle.fill"
            case .degraded: return "exclamationmark.circle.fill"
            case .needsAttention: return "exclamationmark.triangle.fill"
            }
        }

        var colorName: String {
            switch self {
            case .healthy: return "green"
            case .degraded: return "yellow"
            case .needsAttention: return "red"
            }
        }
    }

    let status: Status
    let activeMemoryCount: Int
    let totalMemoryCount: Int
    let issueCount: Int
    let oldestMemoryDate: Date?
    let newestMemoryDate: Date?
    let memoriesInCooldown: Int
    let staleMemoryCount: Int
    let schemaVersionIssues: Int

    /// One-line status summary for debug display
    var summary: String {
        if issueCount == 0 {
            return "AI System: \(status.rawValue) • \(activeMemoryCount) active memories • No issues detected"
        } else {
            return "AI System: \(status.rawValue) • \(activeMemoryCount) active memories • \(issueCount) issue\(issueCount == 1 ? "" : "s")"
        }
    }

    /// Detailed status for debug view
    var details: [String] {
        var lines: [String] = []
        lines.append("Status: \(status.rawValue)")
        lines.append("Active memories: \(activeMemoryCount) of \(totalMemoryCount)")

        if memoriesInCooldown > 0 {
            lines.append("In cooldown: \(memoriesInCooldown)")
        }

        if staleMemoryCount > 0 {
            lines.append("Stale: \(staleMemoryCount)")
        }

        if schemaVersionIssues > 0 {
            lines.append("Schema migration needed: \(schemaVersionIssues)")
        }

        if let oldest = oldestMemoryDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            lines.append("Oldest: \(formatter.localizedString(for: oldest, relativeTo: Date()))")
        }

        if issueCount > 0 {
            lines.append("Issues: \(issueCount)")
        }

        return lines
    }

    /// Generate status from memories
    static func generate(from memories: [AIMemory]) -> AISystemStatus {
        let activeMemories = memories.filter { $0.isActive }
        let issues = MemoryHealthCheck.checkHealth(memories: memories)
        let cooldownCount = memories.filter { $0.isInCooldown }.count
        let staleCount = memories.filter { $0.isStale && $0.isActive }.count
        let schemaIssues = memories.filter { $0.schemaVersion != AIMemory.currentSchemaVersion }.count

        let status: Status
        if issues.isEmpty && schemaIssues == 0 {
            status = .healthy
        } else if issues.count <= 3 && schemaIssues == 0 {
            status = .degraded
        } else {
            status = .needsAttention
        }

        return AISystemStatus(
            status: status,
            activeMemoryCount: activeMemories.count,
            totalMemoryCount: memories.count,
            issueCount: issues.count,
            oldestMemoryDate: memories.map { $0.createdDate }.min(),
            newestMemoryDate: memories.map { $0.createdDate }.max(),
            memoriesInCooldown: cooldownCount,
            staleMemoryCount: staleCount,
            schemaVersionIssues: schemaIssues
        )
    }
}
