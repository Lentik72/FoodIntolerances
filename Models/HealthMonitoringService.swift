import Foundation
import SwiftData

/// Service for managing health screenings, test results, and clinical escalations
class HealthMonitoringService {

    // MARK: - Screening Management

    /// Set up recommended screenings for a user based on their profile
    func setupRecommendedScreenings(
        for profile: UserProfile,
        context: ModelContext
    ) -> [HealthScreeningSchedule] {
        let age = profile.age
        let gender = profile.gender
        let conditions = profile.healthConditions

        // Get recommended screenings
        let recommended = DefaultHealthScreenings.getRecommendedScreenings(
            age: age,
            gender: gender,
            conditions: conditions
        )

        // Check for existing screenings to avoid duplicates
        let existingDescriptor = FetchDescriptor<HealthScreeningSchedule>()
        let existing = (try? context.fetch(existingDescriptor)) ?? []
        let existingNames = Set(existing.map { $0.screeningName })

        // Insert new screenings
        var newScreenings: [HealthScreeningSchedule] = []
        for screening in recommended {
            if !existingNames.contains(screening.screeningName) {
                screening.calculateNextDueDate()
                context.insert(screening)
                newScreenings.append(screening)
            }
        }

        Logger.info("Set up \(newScreenings.count) new health screenings", category: .data)
        return newScreenings
    }

    /// Get upcoming and overdue screenings
    func getUpcomingScreenings(from screenings: [HealthScreeningSchedule]) -> [HealthScreeningSchedule] {
        return screenings
            .filter { $0.isEnabled }
            .filter { $0.isOverdue || $0.isUpcoming }
            .sorted { s1, s2 in
                // Overdue first, then by due date
                if s1.isOverdue && !s2.isOverdue { return true }
                if !s1.isOverdue && s2.isOverdue { return false }
                guard let d1 = s1.nextDueDate, let d2 = s2.nextDueDate else { return false }
                return d1 < d2
            }
    }

    /// Get overdue screenings
    func getOverdueScreenings(from screenings: [HealthScreeningSchedule]) -> [HealthScreeningSchedule] {
        return screenings.filter { $0.isEnabled && $0.isOverdue }
    }

    /// Mark a screening as completed
    func completeScreening(
        _ screening: HealthScreeningSchedule,
        date: Date = Date(),
        context: ModelContext
    ) {
        screening.markCompleted(date: date)

        do {
            try context.save()
            Logger.info("Marked screening '\(screening.screeningName)' as completed", category: .data)
        } catch {
            Logger.error(error, message: "Failed to save screening completion", category: .data)
        }
    }

    // MARK: - Test Result Analysis

    /// Analyze test results and return any concerns
    func analyzeTestResults(_ results: [HealthTestResult]) -> [HealthConcern] {
        var concerns: [HealthConcern] = []

        for result in results {
            switch result.statusEnum {
            case .high, .low:
                concerns.append(HealthConcern(
                    title: "\(result.testName) is \(result.statusEnum.rawValue.lowercased())",
                    description: "Your result of \(result.formattedValue) is outside the normal range (\(result.normalRangeText ?? "N/A")).",
                    severity: .moderate,
                    testResult: result,
                    recommendation: "Discuss this result with your healthcare provider."
                ))

            case .critical:
                concerns.append(HealthConcern(
                    title: "\(result.testName) requires attention",
                    description: "Your result of \(result.formattedValue) is significantly outside normal range.",
                    severity: .high,
                    testResult: result,
                    recommendation: "Contact your healthcare provider soon."
                ))

            case .borderlineHigh, .borderlineLow:
                concerns.append(HealthConcern(
                    title: "\(result.testName) is borderline",
                    description: "Your result is near the edge of the normal range.",
                    severity: .low,
                    testResult: result,
                    recommendation: "Monitor this value and consider lifestyle adjustments."
                ))

            case .normal:
                break
            }
        }

        // Check for test result trends
        let resultsByName = Dictionary(grouping: results, by: { $0.testName })
        for (testName, testResults) in resultsByName where testResults.count >= 2 {
            let sorted = testResults.sorted { $0.testDate < $1.testDate }
            if let trend = detectTrend(in: sorted) {
                concerns.append(HealthConcern(
                    title: "\(testName) is trending \(trend.direction)",
                    description: "Your \(testName) results show a \(trend.direction) trend over time.",
                    severity: trend.severity,
                    testResult: sorted.last,
                    recommendation: trend.recommendation
                ))
            }
        }

        return concerns.sorted { $0.severity.rawValue > $1.severity.rawValue }
    }

    /// Detect trend in sequential test results
    private func detectTrend(in results: [HealthTestResult]) -> (direction: String, severity: ConcernSeverity, recommendation: String)? {
        guard results.count >= 2,
              let firstValue = results.first?.numericValue,
              let lastValue = results.last?.numericValue else {
            return nil
        }

        let percentChange = ((lastValue - firstValue) / firstValue) * 100

        if abs(percentChange) < 5 {
            return nil // No significant trend
        }

        let direction = percentChange > 0 ? "upward" : "downward"
        let severity: ConcernSeverity = abs(percentChange) > 20 ? .moderate : .low
        let recommendation = "Discuss this trend with your healthcare provider at your next visit."

        return (direction, severity, recommendation)
    }

    // MARK: - Clinical Escalation

    /// Check logs for patterns that warrant doctor visit
    func checkClinicalEscalations(
        logs: [LogEntry],
        rules: [ClinicalEscalationRule] = ClinicalEscalationRule.defaultRules
    ) -> [ClinicalEscalation] {
        var escalations: [ClinicalEscalation] = []
        let now = Date()

        for rule in rules {
            // Get logs within the time window
            let windowStart = Calendar.current.date(byAdding: .day, value: -rule.timeWindowDays, to: now) ?? now
            let relevantLogs = logs.filter { log in
                log.date >= windowStart &&
                (rule.symptom == "Any" || log.symptoms.contains { $0.lowercased().contains(rule.symptom.lowercased()) })
            }

            // Check if rule is triggered
            let occurrences = relevantLogs.count
            let maxSeverity = relevantLogs.map { $0.severity }.max() ?? 0
            let daysSpanned = relevantLogs.isEmpty ? 0 :
                Calendar.current.dateComponents([.day], from: relevantLogs.first!.date, to: now).day ?? 0

            if rule.isTriggered(occurrences: occurrences, maxSeverity: maxSeverity, daysSpanned: daysSpanned) {
                escalations.append(ClinicalEscalation(
                    rule: rule,
                    symptom: rule.symptom,
                    occurrences: occurrences,
                    message: rule.message,
                    urgency: rule.urgency
                ))
            }
        }

        return escalations.sorted { $0.urgency.sortOrder < $1.urgency.sortOrder }
    }

    // MARK: - Proactive Recommendations

    /// Get health recommendations based on user profile and data
    func getRecommendations(
        profile: UserProfile,
        testResults: [HealthTestResult],
        screenings: [HealthScreeningSchedule],
        logs: [LogEntry]
    ) -> [HealthRecommendation] {
        var recommendations: [HealthRecommendation] = []

        // Check for missing basic screenings
        let overdueScreenings = getOverdueScreenings(from: screenings)
        for screening in overdueScreenings.prefix(3) {
            recommendations.append(HealthRecommendation(
                title: "Schedule \(screening.screeningName)",
                description: "This screening is overdue by \(abs(screening.daysUntilDue ?? 0)) days.",
                category: .screening,
                priority: .high,
                actionText: "Schedule Now"
            ))
        }

        // Check for old test results that may need retesting
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        let oldResults = testResults.filter { $0.statusEnum != .normal && $0.testDate < sixMonthsAgo }
        for result in oldResults.prefix(2) {
            recommendations.append(HealthRecommendation(
                title: "Retest \(result.testName)",
                description: "Your last result was \(result.statusEnum.rawValue.lowercased()). Consider retesting.",
                category: .testing,
                priority: .medium,
                actionText: "Add Reminder"
            ))
        }

        // Check clinical escalations
        let escalations = checkClinicalEscalations(logs: logs)
        for escalation in escalations.prefix(2) {
            recommendations.append(HealthRecommendation(
                title: "Discuss \(escalation.symptom) with Doctor",
                description: escalation.message,
                category: .doctorVisit,
                priority: escalation.urgency == .urgent ? .high : .medium,
                actionText: "Learn More"
            ))
        }

        // Age-based recommendations
        if let age = profile.age {
            if age >= 40 && !testResults.contains(where: { $0.testName.contains("Cholesterol") }) {
                recommendations.append(HealthRecommendation(
                    title: "Get Cholesterol Checked",
                    description: "At your age, regular cholesterol monitoring is recommended.",
                    category: .testing,
                    priority: .medium,
                    actionText: "Add Test"
                ))
            }

            if age >= 45 && !testResults.contains(where: { $0.testName.contains("Blood Sugar") || $0.testName.contains("HbA1c") }) {
                recommendations.append(HealthRecommendation(
                    title: "Check Blood Sugar",
                    description: "Blood sugar screening is recommended starting at age 45.",
                    category: .testing,
                    priority: .medium,
                    actionText: "Add Test"
                ))
            }
        }

        return recommendations
    }

    // MARK: - Summary Generation

    /// Generate a health summary for the user
    func generateHealthSummary(
        testResults: [HealthTestResult],
        screenings: [HealthScreeningSchedule]
    ) -> HealthSummary {
        // Recent test results
        let recentResults = testResults
            .sorted { $0.testDate > $1.testDate }
            .prefix(5)

        let abnormalResults = testResults.filter { $0.statusEnum != .normal }

        // Screening status
        let overdueCount = screenings.filter { $0.isOverdue }.count
        let upcomingCount = screenings.filter { $0.isUpcoming }.count

        // Overall health score (simplified)
        let normalRatio = testResults.isEmpty ? 1.0 :
            Double(testResults.filter { $0.statusEnum == .normal }.count) / Double(testResults.count)
        let screeningRatio = screenings.isEmpty ? 1.0 :
            Double(screenings.filter { !$0.isOverdue }.count) / Double(screenings.count)
        let healthScore = Int((normalRatio * 50 + screeningRatio * 50))

        return HealthSummary(
            healthScore: healthScore,
            recentResults: Array(recentResults),
            abnormalResultsCount: abnormalResults.count,
            overdueScreeningsCount: overdueCount,
            upcomingScreeningsCount: upcomingCount
        )
    }
}

// MARK: - Supporting Types

struct HealthConcern: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let severity: ConcernSeverity
    let testResult: HealthTestResult?
    let recommendation: String
}

enum ConcernSeverity: Int, Comparable {
    case low = 1
    case moderate = 2
    case high = 3

    static func < (lhs: ConcernSeverity, rhs: ConcernSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var colorName: String {
        switch self {
        case .low: return "yellow"
        case .moderate: return "orange"
        case .high: return "red"
        }
    }

    var icon: String {
        switch self {
        case .low: return "exclamationmark.circle"
        case .moderate: return "exclamationmark.triangle"
        case .high: return "exclamationmark.triangle.fill"
        }
    }
}

struct ClinicalEscalation: Identifiable {
    let id = UUID()
    let rule: ClinicalEscalationRule
    let symptom: String
    let occurrences: Int
    let message: String
    let urgency: ClinicalEscalationRule.EscalationUrgency
}

extension ClinicalEscalationRule.EscalationUrgency {
    var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .important: return 1
        case .recommended: return 2
        case .informational: return 3
        }
    }
}

struct HealthRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let category: RecommendationCategory
    let priority: RecommendationPriority
    let actionText: String

    enum RecommendationCategory: String {
        case screening = "Screening"
        case testing = "Testing"
        case doctorVisit = "Doctor Visit"
        case lifestyle = "Lifestyle"
    }

    enum RecommendationPriority: Int {
        case low = 1
        case medium = 2
        case high = 3

        var colorName: String {
            switch self {
            case .low: return "blue"
            case .medium: return "yellow"
            case .high: return "orange"
            }
        }
    }
}

struct HealthSummary {
    let healthScore: Int
    let recentResults: [HealthTestResult]
    let abnormalResultsCount: Int
    let overdueScreeningsCount: Int
    let upcomingScreeningsCount: Int

    var scoreDescription: String {
        switch healthScore {
        case 90...100: return "Excellent"
        case 75..<90: return "Good"
        case 60..<75: return "Fair"
        default: return "Needs Attention"
        }
    }

    var scoreColor: String {
        switch healthScore {
        case 90...100: return "green"
        case 75..<90: return "blue"
        case 60..<75: return "yellow"
        default: return "orange"
        }
    }
}
