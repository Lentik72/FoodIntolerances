import Foundation
import SwiftData

/// The core AI brain that generates personalized responses based on user's history
class PersonalAIAssistant {

    // MARK: - Dependencies

    private let memoryService = UserMemoryService()
    private let foodSafetyService = FoodSafetyService()
    private let healthService = HealthMonitoringService()
    private let cloudAI = CloudAIService.shared

    // MARK: - Adaptive Context Windows

    /// Get the appropriate lookback window (in hours) for a symptom category
    private func contextWindowHours(for symptom: String) -> Int {
        let symptomLower = symptom.lowercased()

        // GI symptoms: faster onset (6-24 hours)
        if symptomLower.contains("bloating") ||
           symptomLower.contains("nausea") ||
           symptomLower.contains("stomach") ||
           symptomLower.contains("diarrhea") ||
           symptomLower.contains("constipation") ||
           symptomLower.contains("ibs") ||
           symptomLower.contains("reflux") ||
           symptomLower.contains("digestive") {
            return 24
        }

        // Headaches/Migraines: moderate onset (12-48 hours)
        if symptomLower.contains("headache") ||
           symptomLower.contains("migraine") {
            return 48
        }

        // Skin reactions: slower onset (24-72 hours)
        if symptomLower.contains("rash") ||
           symptomLower.contains("hives") ||
           symptomLower.contains("eczema") ||
           symptomLower.contains("acne") ||
           symptomLower.contains("skin") {
            return 72
        }

        // Joint/muscle pain: moderate to slow (24-48 hours)
        if symptomLower.contains("joint") ||
           symptomLower.contains("muscle") ||
           symptomLower.contains("pain") ||
           symptomLower.contains("arthritis") {
            return 48
        }

        // Fatigue/Energy: can be cumulative (24-48 hours)
        if symptomLower.contains("fatigue") ||
           symptomLower.contains("tired") ||
           symptomLower.contains("energy") {
            return 48
        }

        // Mental symptoms: variable (12-36 hours)
        if symptomLower.contains("anxiety") ||
           symptomLower.contains("brain fog") ||
           symptomLower.contains("mood") ||
           symptomLower.contains("depression") {
            return 36
        }

        // Default: 24 hours
        return 24
    }

    /// Get the maximum context window across multiple symptoms
    private func maxContextWindow(for symptoms: [String]) -> Int {
        symptoms.map { contextWindowHours(for: $0) }.max() ?? 24
    }

    // MARK: - Main Response Generation

    /// Generate a personalized AI response for a logged symptom/entry
    func generateResponse(
        for log: LogEntry,
        memories: [AIMemory],
        userAllergies: [UserAllergy],
        recentLogs: [LogEntry],
        profile: UserProfile?,
        screenings: [HealthScreeningSchedule],
        environmentalPressure: String? = nil
    ) -> AIResponse {
        var response = AIResponse()

        // Get user's AI suggestion level preferences
        let suggestionLevel = profile?.aiSuggestionLevelEnum ?? .standard
        let confidenceThreshold = suggestionLevel.confidenceThreshold
        let minOccurrences = suggestionLevel.minimumOccurrences

        // 1. Check environmental factors
        let environmentalObservations = checkEnvironmentalFactors(
            log: log,
            memories: memories,
            currentPressure: environmentalPressure
        )
        // Filter by confidence threshold
        response.observations.append(contentsOf: environmentalObservations.filter {
            confidenceValue(for: $0.confidence) >= confidenceThreshold
        })

        // 2. Find what worked before for these symptoms
        let suggestions = findWhatWorked(
            for: log.symptoms,
            memories: memories
        )
        response.suggestions.append(contentsOf: suggestions)

        // 3. Check for known triggers
        let triggerObservations = checkForTriggers(
            log: log,
            memories: memories,
            recentLogs: recentLogs
        )
        // Filter by confidence threshold
        response.observations.append(contentsOf: triggerObservations.filter {
            confidenceValue(for: $0.confidence) >= confidenceThreshold
        })

        // 4. Check food safety if food was logged (always show - safety critical)
        if let foodItem = log.foodDrinkItem, !foodItem.isEmpty {
            let foodWarnings = checkFoodSafety(
                food: foodItem,
                userAllergies: userAllergies,
                memories: memories
            )
            response.warnings.append(contentsOf: foodWarnings)
        }

        // 5. Generate relevant questions (limited by suggestion level)
        let questions = generateQuestions(
            for: log,
            memories: memories,
            profile: profile
        )
        response.questions.append(contentsOf: Array(questions.prefix(suggestionLevel.maxQuestions)))

        // 6. Check for clinical escalation (always show - health critical)
        let escalationWarnings = checkClinicalEscalation(
            log: log,
            recentLogs: recentLogs
        )
        response.warnings.append(contentsOf: escalationWarnings)

        // 7. Check overdue screenings (opportunistic reminder)
        if suggestionLevel != .minimal {
            let screeningReminders = checkScreeningReminders(
                screenings: screenings,
                symptoms: log.symptoms
            )
            response.observations.append(contentsOf: screeningReminders)
        }

        // 8. Add pattern observations
        let patternObservations = findPatterns(
            for: log,
            memories: memories
        )
        // Filter by confidence threshold
        response.observations.append(contentsOf: patternObservations.filter {
            confidenceValue(for: $0.confidence) >= confidenceThreshold
        })

        // 9. Check if we should show "needs more data" message
        if suggestionLevel.showNeedsMoreData {
            response.needsMoreData = checkNeedsMoreData(
                for: log,
                memories: memories,
                currentResponse: response,
                minimumOccurrences: minOccurrences
            )
        }

        return response
    }

    // MARK: - Needs More Data Check

    /// Check if we should show a "needs more data" message
    private func checkNeedsMoreData(
        for log: LogEntry,
        memories: [AIMemory],
        currentResponse: AIResponse,
        minimumOccurrences: Int
    ) -> NeedsMoreDataMessage? {
        // If we have meaningful content, don't show needs more data
        if !currentResponse.observations.isEmpty || !currentResponse.suggestions.isEmpty {
            return nil
        }

        // Check how much data we have for these symptoms
        for symptom in log.symptoms {
            let symptomMemories = memories.filter {
                $0.symptom?.lowercased() == symptom.lowercased() &&
                $0.isActive &&
                !$0.isStale
            }

            let totalOccurrences = symptomMemories.reduce(0) { $0 + $1.occurrenceCount }

            // If we have very little data for this symptom
            if totalOccurrences < minimumOccurrences {
                return .forSymptom(symptom, occurrences: totalOccurrences, minimumNeeded: minimumOccurrences)
            }
        }

        // If we have data but all observations were filtered out due to low confidence
        let allMemoriesLowConfidence = memories.filter {
            log.symptoms.contains($0.symptom ?? "") && $0.isActive
        }.allSatisfy { $0.decayedConfidence < 0.5 }

        if allMemoriesLowConfidence && !memories.isEmpty {
            return .generalLowConfidence()
        }

        return nil
    }

    /// Convert confidence level to numeric value for threshold comparison
    private func confidenceValue(for level: ConfidenceLevel) -> Double {
        switch level {
        case .high: return 0.8
        case .medium: return 0.5
        case .low: return 0.3
        }
    }

    // MARK: - Environmental Factors

    private func checkEnvironmentalFactors(
        log: LogEntry,
        memories: [AIMemory],
        currentPressure: String?
    ) -> [AIObservation] {
        var observations: [AIObservation] = []

        // Check atmospheric pressure
        let pressure = currentPressure ?? log.atmosphericPressure
        if !pressure.isEmpty && pressure != "Normal" {
            // Find memories linking this pressure to symptoms
            let pressureMemories = memories.filter {
                $0.memoryTypeEnum == .pattern &&
                $0.relatedEnvironmentalFactor?.contains(pressure) == true &&
                log.symptoms.contains($0.symptom ?? "")
            }

            if let memory = pressureMemories.first {
                observations.append(AIObservation(
                    text: "Atmospheric pressure is \(pressure.lowercased()) today - this has triggered your \(memory.symptom ?? "symptoms") \(memory.occurrenceCount) times before.",
                    confidence: memory.confidenceLevel,
                    relatedMemory: memory,
                    icon: "cloud.sun"
                ))
            } else if pressure == "Low" || pressure == "Falling" {
                observations.append(AIObservation(
                    text: "Atmospheric pressure is \(pressure.lowercased()) today, which can trigger headaches and fatigue in some people.",
                    confidence: .low,
                    icon: "cloud.sun"
                ))
            }
        }

        // Check moon phase patterns
        if !log.moonPhase.isEmpty {
            let moonMemories = memories.filter {
                $0.memoryTypeEnum == .pattern &&
                $0.relatedEnvironmentalFactor?.contains(log.moonPhase) == true &&
                log.symptoms.contains($0.symptom ?? "")
            }

            if let memory = moonMemories.first, memory.confidence >= 0.5 {
                observations.append(AIObservation(
                    text: "It's a \(log.moonPhase) - you've noticed \(memory.symptom ?? "symptoms") during this phase \(memory.occurrenceCount) times.",
                    confidence: memory.confidenceLevel,
                    relatedMemory: memory,
                    icon: "moon.fill"
                ))
            }
        }

        // Check season patterns
        if !log.season.isEmpty {
            let seasonMemories = memories.filter {
                $0.memoryTypeEnum == .pattern &&
                $0.relatedEnvironmentalFactor?.contains(log.season) == true &&
                log.symptoms.contains($0.symptom ?? "")
            }

            if let memory = seasonMemories.first, memory.confidence >= 0.6 {
                observations.append(AIObservation(
                    text: "Your \(memory.symptom ?? "symptoms") tend to be more common in \(log.season).",
                    confidence: memory.confidenceLevel,
                    relatedMemory: memory,
                    icon: "leaf.fill"
                ))
            }
        }

        return observations
    }

    // MARK: - What Worked

    private func findWhatWorked(for symptoms: [String], memories: [AIMemory]) -> [AISuggestion] {
        var suggestions: [AISuggestion] = []

        for symptom in symptoms {
            // Get what worked for this symptom
            let whatWorked = memoryService.getWhatWorked(for: symptom, from: memories)

            for memory in whatWorked.prefix(2) {
                guard let resolution = memory.resolution else { continue }

                let timeText = memory.resolutionTime ?? "usually"
                let effectivenessText = memory.effectivenessPercentage > 0 ?
                    " (\(memory.effectivenessPercentage)% effective for you)" : ""

                suggestions.append(AISuggestion(
                    text: "Last time you had \(symptom.lowercased()), \(resolution) helped \(timeText).\(effectivenessText)",
                    effectiveness: memory.effectivenessPercentage > 0 ? memory.effectivenessPercentage : nil,
                    lastHelped: memory.lastOccurrence,
                    icon: "checkmark.circle.fill"
                ))
            }
        }

        return suggestions
    }

    // MARK: - Trigger Detection

    private func checkForTriggers(
        log: LogEntry,
        memories: [AIMemory],
        recentLogs: [LogEntry]
    ) -> [AIObservation] {
        var observations: [AIObservation] = []

        // Check if logged food is a known trigger
        if let food = log.foodDrinkItem, !food.isEmpty {
            for symptom in log.symptoms {
                let triggerMemories = memories.filter {
                    $0.memoryTypeEnum == .trigger &&
                    $0.trigger?.lowercased() == food.lowercased() &&
                    $0.symptom == symptom &&
                    $0.confidence >= 0.4
                }

                if let memory = triggerMemories.first {
                    let confidenceText = memory.confidenceLevel == .high ? "often" :
                                        (memory.confidenceLevel == .medium ? "sometimes" : "may")
                    observations.append(AIObservation(
                        text: "\(food.capitalized) \(confidenceText) triggers \(symptom.lowercased()) for you (seen \(memory.occurrenceCount) times).",
                        confidence: memory.confidenceLevel,
                        relatedMemory: memory,
                        icon: "exclamationmark.triangle"
                    ))
                }
            }
        }

        // Check recent food logs for potential triggers using adaptive context windows
        let contextWindow = maxContextWindow(for: log.symptoms)
        let recentFoodLogs = recentLogs.filter {
            $0.foodDrinkItem != nil &&
            !$0.foodDrinkItem!.isEmpty &&
            $0.date < log.date &&
            Calendar.current.dateComponents([.hour], from: $0.date, to: log.date).hour ?? (contextWindow + 1) <= contextWindow
        }

        for foodLog in recentFoodLogs.prefix(3) {
            guard let food = foodLog.foodDrinkItem else { continue }

            for symptom in log.symptoms {
                // Use symptom-specific context window for more precise detection
                let symptomWindow = contextWindowHours(for: symptom)
                let hoursAgo = Calendar.current.dateComponents([.hour], from: foodLog.date, to: log.date).hour ?? 0

                guard hoursAgo <= symptomWindow else { continue }

                let triggerMemories = memories.filter {
                    $0.memoryTypeEnum == .trigger &&
                    $0.trigger?.lowercased() == food.lowercased() &&
                    $0.symptom == symptom &&
                    $0.decayedConfidence >= 0.4 && // Use decayed confidence
                    !$0.isStale // Skip stale memories
                }

                if let memory = triggerMemories.first {
                    observations.append(AIObservation(
                        text: "You had \(food) \(hoursAgo) hours ago - this is a known trigger for your \(symptom.lowercased()).",
                        confidence: memory.decayedConfidenceLevel,
                        relatedMemory: memory,
                        icon: "fork.knife"
                    ))
                }
            }
        }

        return observations
    }

    // MARK: - Food Safety

    private func checkFoodSafety(
        food: String,
        userAllergies: [UserAllergy],
        memories: [AIMemory]
    ) -> [AIWarning] {
        var warnings: [AIWarning] = []

        let learnedTriggers = memoryService.getAllTriggers(from: memories)
        let result = foodSafetyService.checkFood(food, userAllergies: userAllergies, learnedTriggers: learnedTriggers)

        switch result.status {
        case .avoid:
            warnings.append(AIWarning(
                text: result.explanation,
                severity: .alert,
                actionRequired: true
            ))
        case .caution:
            warnings.append(AIWarning(
                text: result.explanation,
                severity: .caution,
                actionRequired: false
            ))
        case .safe:
            break
        }

        return warnings
    }

    // MARK: - Questions

    private func generateQuestions(
        for log: LogEntry,
        memories: [AIMemory],
        profile: UserProfile?
    ) -> [AIQuestion] {
        var questions: [AIQuestion] = []

        // Ask about sleep if sleep correlation exists
        let sleepCorrelated = memories.contains {
            $0.memoryTypeEnum == .correlation &&
            $0.trigger?.lowercased().contains("sleep") == true &&
            log.symptoms.contains($0.symptom ?? "")
        }

        if sleepCorrelated || log.symptoms.contains(where: { $0.lowercased().contains("fatigue") || $0.lowercased().contains("headache") }) {
            questions.append(AIQuestion(
                text: "How was your sleep last night?",
                options: ["Less than 6 hrs", "6-7 hrs", "7-8 hrs", "8+ hrs"],
                context: "Sleep often correlates with these symptoms",
                relatedTo: "sleep"
            ))
        }

        // Ask about stress if mental symptoms
        if log.category.lowercased().contains("mental") ||
           log.symptoms.contains(where: { $0.lowercased().contains("anxiety") || $0.lowercased().contains("stress") }) {
            questions.append(AIQuestion(
                text: "How's your stress level today?",
                options: ["Low", "Moderate", "High", "Very High"],
                context: nil,
                relatedTo: "stress"
            ))
        }

        // Ask about hydration for certain symptoms
        if log.symptoms.contains(where: { $0.lowercased().contains("headache") || $0.lowercased().contains("fatigue") }) {
            questions.append(AIQuestion(
                text: "Have you had enough water today?",
                options: ["Yes, plenty", "Some", "Not much", "Barely any"],
                context: "Dehydration can cause headaches and fatigue",
                relatedTo: "hydration"
            ))
        }

        // Ask about supplements if they have them tracked
        let supplementMemories = memories.filter {
            $0.memoryTypeEnum == .whatWorked &&
            log.symptoms.contains($0.symptom ?? "")
        }

        if let supp = supplementMemories.first, let resolution = supp.resolution {
            questions.append(AIQuestion(
                text: "Did you take your \(resolution) today?",
                options: ["Yes", "No", "Not yet"],
                context: "It usually helps with your \(supp.symptom ?? "symptoms")",
                relatedTo: "supplement"
            ))
        }

        return Array(questions.prefix(3)) // Limit to 3 questions
    }

    // MARK: - Clinical Escalation

    private func checkClinicalEscalation(
        log: LogEntry,
        recentLogs: [LogEntry]
    ) -> [AIWarning] {
        var warnings: [AIWarning] = []

        // Include current log in analysis
        let allLogs = [log] + recentLogs

        let escalations = healthService.checkClinicalEscalations(
            logs: allLogs,
            rules: ClinicalEscalationRule.defaultRules
        )

        for escalation in escalations.prefix(2) {
            let severity: AIWarning.WarningSeverity
            switch escalation.urgency {
            case .urgent: severity = .alert
            case .important: severity = .caution
            default: severity = .info
            }

            warnings.append(AIWarning(
                text: escalation.message,
                severity: severity,
                actionRequired: escalation.urgency == .urgent || escalation.urgency == .important
            ))
        }

        return warnings
    }

    // MARK: - Screening Reminders

    private func checkScreeningReminders(
        screenings: [HealthScreeningSchedule],
        symptoms: [String]
    ) -> [AIObservation] {
        var observations: [AIObservation] = []

        // Check for overdue screenings that might be relevant
        let overdueScreenings = healthService.getOverdueScreenings(from: screenings)

        // If logging fatigue, mention thyroid/B12 if overdue
        if symptoms.contains(where: { $0.lowercased().contains("fatigue") || $0.lowercased().contains("tired") }) {
            let relevantOverdue = overdueScreenings.filter {
                $0.screeningName.contains("Thyroid") ||
                $0.screeningName.contains("B12") ||
                $0.screeningName.contains("Iron")
            }

            if let screening = relevantOverdue.first {
                observations.append(AIObservation(
                    text: "Your \(screening.screeningName) is overdue. Persistent fatigue can sometimes be related to these levels.",
                    confidence: .low,
                    icon: "testtube.2"
                ))
            }
        }

        // If logging headaches frequently, mention blood pressure
        if symptoms.contains(where: { $0.lowercased().contains("headache") }) {
            let bpOverdue = overdueScreenings.first { $0.screeningName.contains("Blood Pressure") }
            if bpOverdue != nil {
                observations.append(AIObservation(
                    text: "Your blood pressure check is overdue. Regular headaches can sometimes be related to blood pressure.",
                    confidence: .low,
                    icon: "heart.fill"
                ))
            }
        }

        return observations
    }

    // MARK: - Pattern Recognition

    private func findPatterns(for log: LogEntry, memories: [AIMemory]) -> [AIObservation] {
        var observations: [AIObservation] = []

        // Check time of day patterns
        let hour = Calendar.current.component(.hour, from: log.date)
        let timeOfDay: String
        switch hour {
        case 5..<12: timeOfDay = "Morning"
        case 12..<17: timeOfDay = "Afternoon"
        case 17..<21: timeOfDay = "Evening"
        default: timeOfDay = "Night"
        }

        for symptom in log.symptoms {
            let timeMemories = memories.filter {
                $0.memoryTypeEnum == .pattern &&
                $0.relatedTimeOfDay == timeOfDay &&
                $0.symptom == symptom &&
                $0.confidence >= 0.5
            }

            if let memory = timeMemories.first {
                observations.append(AIObservation(
                    text: "Your \(symptom.lowercased()) tends to occur in the \(timeOfDay.lowercased()) (\(memory.occurrenceCount) times).",
                    confidence: memory.confidenceLevel,
                    relatedMemory: memory,
                    icon: "clock.fill"
                ))
            }
        }

        // Check correlation patterns
        let correlations = memories.filter {
            $0.memoryTypeEnum == .correlation &&
            log.symptoms.contains($0.symptom ?? "") &&
            $0.confidence >= 0.5
        }

        for correlation in correlations.prefix(2) {
            if let trigger = correlation.trigger, let symptom = correlation.symptom {
                observations.append(AIObservation(
                    text: "Pattern: \(trigger) often leads to \(symptom.lowercased()) for you.",
                    confidence: correlation.confidenceLevel,
                    relatedMemory: correlation,
                    icon: "arrow.triangle.branch"
                ))
            }
        }

        return observations
    }

    // MARK: - Proactive Check-in

    /// Generate a proactive message based on current conditions
    func generateProactiveMessage(
        currentPressure: String?,
        profile: UserProfile?,
        memories: [AIMemory],
        screenings: [HealthScreeningSchedule]
    ) -> String? {
        var messages: [String] = []

        // Check pressure-sensitive symptoms
        if let pressure = currentPressure, pressure == "Low" || pressure == "Falling" {
            let pressureSensitive = memories.filter {
                $0.memoryTypeEnum == .pattern &&
                $0.relatedEnvironmentalFactor?.contains(pressure) == true &&
                $0.confidence >= 0.6
            }

            if let memory = pressureSensitive.first, let symptom = memory.symptom {
                messages.append("Low pressure today - you might experience \(symptom.lowercased()). Consider taking preventive measures.")
            }
        }

        // Check overdue screenings
        let overdueScreenings = healthService.getOverdueScreenings(from: screenings)
        if let screening = overdueScreenings.first {
            messages.append("Reminder: Your \(screening.screeningName) is overdue.")
        }

        return messages.first
    }

    // MARK: - Summary Generation

    /// Generate a summary of what the AI has learned about the user
    func generateUserSummary(
        memories: [AIMemory],
        profile: UserProfile?
    ) -> String {
        return memoryService.generateMemorySummary(from: memories)
    }

    // MARK: - Cloud AI Enhancement

    /// Enhance response with natural language from Cloud AI
    func enhanceResponseWithCloudAI(
        for log: LogEntry,
        baseResponse: AIResponse,
        memories: [AIMemory],
        completion: @escaping (String?) -> Void
    ) {
        guard cloudAI.isEnabled else {
            completion(nil)
            return
        }

        // Extract data for the prompt
        let triggers = memories
            .filter { $0.memoryTypeEnum == .trigger && $0.isActive }
            .compactMap { $0.trigger }

        let whatWorked = memories
            .filter { $0.memoryTypeEnum == .whatWorked && $0.isActive }
            .compactMap { memory -> String? in
                guard let resolution = memory.resolution, let symptom = memory.symptom else { return nil }
                return "\(resolution) helped with \(symptom)"
            }

        let patterns = memories
            .filter { ($0.memoryTypeEnum == .pattern || $0.memoryTypeEnum == .correlation) && $0.isActive }
            .compactMap { $0.notes }

        cloudAI.generateHealthInsight(
            symptoms: log.symptoms,
            severity: log.severity,
            triggers: triggers,
            whatWorked: whatWorked,
            recentPatterns: patterns,
            userContext: log.notes
        ) { result in
            switch result {
            case .success(let response):
                completion(response)
            case .failure(let error):
                Logger.warning("Cloud AI enhancement failed: \(error.localizedDescription)", category: .network)
                completion(nil)
            }
        }
    }

    /// Generate a cloud-enhanced weekly summary
    func generateWeeklySummaryWithCloudAI(
        logs: [LogEntry],
        memories: [AIMemory],
        completion: @escaping (String?) -> Void
    ) {
        guard cloudAI.isEnabled else {
            completion(nil)
            return
        }

        // Calculate symptom counts
        let symptomCounts = Dictionary(grouping: logs.flatMap { $0.symptoms }, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }

        // Calculate average severity
        let totalSeverity = logs.reduce(0) { $0 + $1.severity }
        let averageSeverity = logs.isEmpty ? 0.0 : Double(totalSeverity) / Double(logs.count)

        // Get triggers identified
        let triggersIdentified = memories
            .filter { $0.memoryTypeEnum == .trigger && $0.isActive }
            .compactMap { $0.trigger }
            .prefix(5)
            .map { String($0) }

        // Get what was tried
        let improvementsTried = logs
            .compactMap { $0.notes }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0) }

        cloudAI.generateWeeklySummary(
            symptomCounts: symptomCounts,
            averageSeverity: averageSeverity,
            triggersIdentified: Array(triggersIdentified),
            improvementsTried: Array(improvementsTried)
        ) { result in
            switch result {
            case .success(let summary):
                completion(summary)
            case .failure(let error):
                Logger.warning("Cloud AI weekly summary failed: \(error.localizedDescription)", category: .network)
                completion(nil)
            }
        }
    }

    /// Check if cloud AI is available
    var isCloudAIAvailable: Bool {
        cloudAI.isEnabled && cloudAI.hasAPIKey(for: cloudAI.provider)
    }
}

// MARK: - Response Helper Extensions

extension AIResponse {
    /// Get the most important items to display
    var prioritizedContent: (warnings: [AIWarning], observations: [AIObservation], suggestions: [AISuggestion], questions: [AIQuestion]) {
        // Sort warnings by severity
        let sortedWarnings = warnings.sorted { w1, w2 in
            let order: [AIWarning.WarningSeverity] = [.alert, .caution, .info]
            let idx1 = order.firstIndex(of: w1.severity) ?? 3
            let idx2 = order.firstIndex(of: w2.severity) ?? 3
            return idx1 < idx2
        }

        // Sort observations by confidence
        let sortedObservations = observations.sorted { o1, o2 in
            let order: [ConfidenceLevel] = [.high, .medium, .low]
            let idx1 = order.firstIndex(of: o1.confidence) ?? 3
            let idx2 = order.firstIndex(of: o2.confidence) ?? 3
            return idx1 < idx2
        }

        return (
            Array(sortedWarnings.prefix(3)),
            Array(sortedObservations.prefix(4)),
            Array(suggestions.prefix(3)),
            Array(questions.prefix(2))
        )
    }

    /// Check if response has anything meaningful
    var hasImportantContent: Bool {
        !warnings.isEmpty ||
        observations.contains { $0.confidence != .low } ||
        !suggestions.isEmpty
    }
}
