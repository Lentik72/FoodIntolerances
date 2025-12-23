import Foundation
import SwiftData

/// Service for building and managing AI memories from user's log history
class UserMemoryService {

    // MARK: - Configuration

    /// Minimum occurrences needed to create a memory
    static let minimumOccurrences = 2

    /// Time window for correlating food with symptoms (hours)
    static let correlationWindowHours = 24

    /// Maximum memories to keep per type
    static let maxMemoriesPerType = 50

    // MARK: - Memory Building

    /// Analyze all logs and build initial memories
    /// Call this during onboarding or when user requests re-analysis
    func buildInitialMemories(
        from logs: [LogEntry],
        treatments: [TrackedItem],
        context: ModelContext,
        memoryLevel: AIMemoryLevel = .patterns
    ) -> [AIMemory] {
        var memories: [AIMemory] = []

        // 1. Find food/drink triggers
        let triggerMemories = buildTriggerMemories(from: logs, memoryLevel: memoryLevel)
        memories.append(contentsOf: triggerMemories)

        // 2. Find what worked (treatments, protocols)
        let effectivenessMemories = buildEffectivenessMemories(from: logs, treatments: treatments, memoryLevel: memoryLevel)
        memories.append(contentsOf: effectivenessMemories)

        // 3. Find environmental patterns
        let environmentalMemories = buildEnvironmentalMemories(from: logs, memoryLevel: memoryLevel)
        memories.append(contentsOf: environmentalMemories)

        // 4. Find time-of-day patterns
        let timePatternMemories = buildTimePatternMemories(from: logs, memoryLevel: memoryLevel)
        memories.append(contentsOf: timePatternMemories)

        // Save all memories
        for memory in memories {
            context.insert(memory)
        }

        Logger.info("Built \(memories.count) initial memories from \(logs.count) logs", category: .data)

        return memories
    }

    // MARK: - Trigger Detection

    /// Find correlations between foods and symptoms
    private func buildTriggerMemories(from logs: [LogEntry], memoryLevel: AIMemoryLevel) -> [AIMemory] {
        var triggerCounts: [String: [String: Int]] = [:] // [food: [symptom: count]]
        var triggerDates: [String: [String: [Date]]] = [:] // [food: [symptom: [dates]]]

        // Sort logs by date
        let sortedLogs = logs.sorted { $0.date < $1.date }

        for log in sortedLogs {
            guard !log.symptoms.isEmpty else { continue }

            // Find food logs within the correlation window before this symptom
            let symptomDate = log.date
            let windowStart = Calendar.current.date(byAdding: .hour, value: -Self.correlationWindowHours, to: symptomDate) ?? symptomDate

            // Look for food items in logs within the window
            let foodLogs = sortedLogs.filter { foodLog in
                foodLog.date >= windowStart &&
                foodLog.date <= symptomDate &&
                foodLog.foodDrinkItem != nil &&
                !foodLog.foodDrinkItem!.isEmpty
            }

            // Also check if this log itself has a food trigger
            if let foodItem = log.foodDrinkItem, !foodItem.isEmpty {
                for symptom in log.symptoms {
                    let foodKey = foodItem.lowercased()
                    if triggerCounts[foodKey] == nil {
                        triggerCounts[foodKey] = [:]
                        triggerDates[foodKey] = [:]
                    }
                    triggerCounts[foodKey]![symptom, default: 0] += 1
                    if triggerDates[foodKey]![symptom] == nil {
                        triggerDates[foodKey]![symptom] = []
                    }
                    triggerDates[foodKey]![symptom]!.append(log.date)
                }
            }

            // Check food logs in the window
            for foodLog in foodLogs {
                guard let foodItem = foodLog.foodDrinkItem, !foodItem.isEmpty else { continue }
                let foodKey = foodItem.lowercased()

                for symptom in log.symptoms {
                    if triggerCounts[foodKey] == nil {
                        triggerCounts[foodKey] = [:]
                        triggerDates[foodKey] = [:]
                    }
                    triggerCounts[foodKey]![symptom, default: 0] += 1
                    if triggerDates[foodKey]![symptom] == nil {
                        triggerDates[foodKey]![symptom] = []
                    }
                    triggerDates[foodKey]![symptom]!.append(log.date)
                }
            }
        }

        // Build memories from significant triggers
        var memories: [AIMemory] = []

        for (food, symptomCounts) in triggerCounts {
            for (symptom, count) in symptomCounts {
                guard count >= Self.minimumOccurrences else { continue }

                let memory = AIMemory(
                    memoryType: .trigger,
                    symptom: symptom,
                    trigger: food,
                    occurrenceCount: count,
                    confidence: calculateConfidence(occurrences: count)
                )

                // Add specific dates if detailed memory level
                if memoryLevel == .detailed, let dates = triggerDates[food]?[symptom] {
                    memory.specificDates = Array(dates.suffix(20))
                }

                if let lastDate = triggerDates[food]?[symptom]?.last {
                    memory.lastOccurrence = lastDate
                }

                memories.append(memory)
            }
        }

        return memories
    }

    // MARK: - Treatment Effectiveness

    /// Find what treatments/supplements worked
    private func buildEffectivenessMemories(
        from logs: [LogEntry],
        treatments: [TrackedItem],
        memoryLevel: AIMemoryLevel
    ) -> [AIMemory] {
        var treatmentResults: [String: [String: (successes: Int, failures: Int, dates: [Date])]] = [:]
        // [treatment: [symptom: (successes, failures, dates)]]

        for log in logs {
            guard !log.symptoms.isEmpty else { continue }

            // Check treatments used in this log
            for treatment in log.treatments {
                let treatmentKey = treatment.name.lowercased()

                for symptom in log.symptoms {
                    if treatmentResults[treatmentKey] == nil {
                        treatmentResults[treatmentKey] = [:]
                    }
                    if treatmentResults[treatmentKey]![symptom] == nil {
                        treatmentResults[treatmentKey]![symptom] = (successes: 0, failures: 0, dates: [])
                    }

                    // Check effectiveness (1-10 scale, > 5 is success)
                    if let effectiveness = treatment.effectiveness {
                        if effectiveness > 5 {
                            treatmentResults[treatmentKey]![symptom]!.successes += 1
                        } else {
                            treatmentResults[treatmentKey]![symptom]!.failures += 1
                        }
                    }
                    treatmentResults[treatmentKey]![symptom]!.dates.append(log.date)
                }
            }

            // Also check protocol effectiveness
            if let protocolEffectiveness = log.protocolEffectiveness {
                let protocolKey = "protocol_\(log.protocolID?.uuidString.prefix(8) ?? "unknown")"

                for symptom in log.symptoms {
                    if treatmentResults[protocolKey] == nil {
                        treatmentResults[protocolKey] = [:]
                    }
                    if treatmentResults[protocolKey]![symptom] == nil {
                        treatmentResults[protocolKey]![symptom] = (successes: 0, failures: 0, dates: [])
                    }

                    if protocolEffectiveness > 5 {
                        treatmentResults[protocolKey]![symptom]!.successes += 1
                    } else {
                        treatmentResults[protocolKey]![symptom]!.failures += 1
                    }
                    treatmentResults[protocolKey]![symptom]!.dates.append(log.date)
                }
            }
        }

        // Build memories
        var memories: [AIMemory] = []

        for (treatment, symptomResults) in treatmentResults {
            for (symptom, results) in symptomResults {
                let totalOccurrences = results.successes + results.failures
                guard totalOccurrences >= Self.minimumOccurrences else { continue }

                let memoryType: MemoryType = results.successes > results.failures ? .whatWorked : .whatDidntWork

                let memory = AIMemory(
                    memoryType: memoryType,
                    symptom: symptom,
                    resolution: treatment,
                    occurrenceCount: totalOccurrences,
                    confidence: calculateConfidence(occurrences: totalOccurrences)
                )

                memory.successCount = results.successes
                memory.failureCount = results.failures

                if memoryLevel == .detailed {
                    memory.specificDates = Array(results.dates.suffix(20))
                }

                if let lastDate = results.dates.last {
                    memory.lastOccurrence = lastDate
                }

                memories.append(memory)
            }
        }

        return memories
    }

    // MARK: - Environmental Patterns

    /// Find correlations between environmental factors and symptoms
    private func buildEnvironmentalMemories(from logs: [LogEntry], memoryLevel: AIMemoryLevel) -> [AIMemory] {
        var pressurePatterns: [String: [String: Int]] = [:] // [pressure: [symptom: count]]
        var moonPatterns: [String: [String: Int]] = [:] // [moonPhase: [symptom: count]]
        var seasonPatterns: [String: [String: Int]] = [:] // [season: [symptom: count]]
        var patternDates: [String: [Date]] = [:] // [patternKey: [dates]]

        for log in logs {
            guard !log.symptoms.isEmpty else { continue }

            for symptom in log.symptoms {
                // Atmospheric pressure patterns
                let pressure = log.atmosphericPressure
                if !pressure.isEmpty && pressure != "Normal" {
                    pressurePatterns[pressure, default: [:]][symptom, default: 0] += 1
                    let key = "pressure_\(pressure)_\(symptom)"
                    if patternDates[key] == nil { patternDates[key] = [] }
                    patternDates[key]!.append(log.date)
                }

                // Moon phase patterns
                let moon = log.moonPhase
                if !moon.isEmpty {
                    moonPatterns[moon, default: [:]][symptom, default: 0] += 1
                    let key = "moon_\(moon)_\(symptom)"
                    if patternDates[key] == nil { patternDates[key] = [] }
                    patternDates[key]!.append(log.date)
                }

                // Season patterns
                let season = log.season
                if !season.isEmpty {
                    seasonPatterns[season, default: [:]][symptom, default: 0] += 1
                    let key = "season_\(season)_\(symptom)"
                    if patternDates[key] == nil { patternDates[key] = [] }
                    patternDates[key]!.append(log.date)
                }
            }
        }

        var memories: [AIMemory] = []

        // Build pressure memories
        for (pressure, symptomCounts) in pressurePatterns {
            for (symptom, count) in symptomCounts where count >= Self.minimumOccurrences {
                let memory = AIMemory(
                    memoryType: .pattern,
                    symptom: symptom,
                    occurrenceCount: count,
                    confidence: calculateConfidence(occurrences: count),
                    notes: "\(symptom) often occurs during \(pressure) pressure"
                )
                memory.relatedEnvironmentalFactor = pressure

                let key = "pressure_\(pressure)_\(symptom)"
                if memoryLevel == .detailed, let dates = patternDates[key] {
                    memory.specificDates = Array(dates.suffix(20))
                }

                memories.append(memory)
            }
        }

        // Build moon phase memories
        for (moon, symptomCounts) in moonPatterns {
            for (symptom, count) in symptomCounts where count >= Self.minimumOccurrences + 1 {
                let memory = AIMemory(
                    memoryType: .pattern,
                    symptom: symptom,
                    occurrenceCount: count,
                    confidence: calculateConfidence(occurrences: count) * 0.8, // Slightly lower confidence for moon patterns
                    notes: "\(symptom) observed during \(moon)"
                )
                memory.relatedEnvironmentalFactor = "Moon: \(moon)"

                let key = "moon_\(moon)_\(symptom)"
                if memoryLevel == .detailed, let dates = patternDates[key] {
                    memory.specificDates = Array(dates.suffix(20))
                }

                memories.append(memory)
            }
        }

        // Build season memories
        for (season, symptomCounts) in seasonPatterns {
            for (symptom, count) in symptomCounts where count >= Self.minimumOccurrences + 2 {
                let memory = AIMemory(
                    memoryType: .pattern,
                    symptom: symptom,
                    occurrenceCount: count,
                    confidence: calculateConfidence(occurrences: count),
                    notes: "\(symptom) more common in \(season)"
                )
                memory.relatedEnvironmentalFactor = "Season: \(season)"

                let key = "season_\(season)_\(symptom)"
                if memoryLevel == .detailed, let dates = patternDates[key] {
                    memory.specificDates = Array(dates.suffix(20))
                }

                memories.append(memory)
            }
        }

        return memories
    }

    // MARK: - Time Patterns

    /// Find time-of-day patterns
    private func buildTimePatternMemories(from logs: [LogEntry], memoryLevel: AIMemoryLevel) -> [AIMemory] {
        var timePatterns: [String: [String: Int]] = [:] // [timeOfDay: [symptom: count]]
        var patternDates: [String: [Date]] = [:] // [patternKey: [dates]]

        for log in logs {
            guard !log.symptoms.isEmpty else { continue }

            let hour = Calendar.current.component(.hour, from: log.date)
            let timeOfDay: String
            switch hour {
            case 5..<12: timeOfDay = "Morning"
            case 12..<17: timeOfDay = "Afternoon"
            case 17..<21: timeOfDay = "Evening"
            default: timeOfDay = "Night"
            }

            for symptom in log.symptoms {
                timePatterns[timeOfDay, default: [:]][symptom, default: 0] += 1
                let key = "time_\(timeOfDay)_\(symptom)"
                if patternDates[key] == nil { patternDates[key] = [] }
                patternDates[key]!.append(log.date)
            }
        }

        var memories: [AIMemory] = []

        for (timeOfDay, symptomCounts) in timePatterns {
            for (symptom, count) in symptomCounts where count >= Self.minimumOccurrences + 1 {
                let memory = AIMemory(
                    memoryType: .pattern,
                    symptom: symptom,
                    occurrenceCount: count,
                    confidence: calculateConfidence(occurrences: count),
                    notes: "\(symptom) often occurs in the \(timeOfDay.lowercased())"
                )
                memory.relatedTimeOfDay = timeOfDay

                let key = "time_\(timeOfDay)_\(symptom)"
                if memoryLevel == .detailed, let dates = patternDates[key] {
                    memory.specificDates = Array(dates.suffix(20))
                }

                memories.append(memory)
            }
        }

        return memories
    }

    // MARK: - Incremental Updates

    /// Update memories with a new log entry
    func updateMemories(
        with newLog: LogEntry,
        existingMemories: [AIMemory],
        recentLogs: [LogEntry],
        context: ModelContext,
        memoryLevel: AIMemoryLevel = .patterns
    ) {
        // Check for trigger updates
        if let foodItem = newLog.foodDrinkItem, !foodItem.isEmpty {
            for symptom in newLog.symptoms {
                updateOrCreateTriggerMemory(
                    food: foodItem,
                    symptom: symptom,
                    date: newLog.date,
                    existingMemories: existingMemories,
                    context: context,
                    memoryLevel: memoryLevel
                )
            }
        }

        // Check for treatment effectiveness updates
        for treatment in newLog.treatments {
            for symptom in newLog.symptoms {
                updateOrCreateEffectivenessMemory(
                    treatment: treatment.name,
                    symptom: symptom,
                    effectiveness: treatment.effectiveness,
                    date: newLog.date,
                    existingMemories: existingMemories,
                    context: context,
                    memoryLevel: memoryLevel
                )
            }
        }

        // Check for environmental pattern updates
        if !newLog.atmosphericPressure.isEmpty && newLog.atmosphericPressure != "Normal" {
            for symptom in newLog.symptoms {
                updateOrCreatePatternMemory(
                    factor: newLog.atmosphericPressure,
                    factorType: "pressure",
                    symptom: symptom,
                    date: newLog.date,
                    existingMemories: existingMemories,
                    context: context,
                    memoryLevel: memoryLevel
                )
            }
        }

        Logger.debug("Updated memories with new log entry", category: .data)
    }

    private func updateOrCreateTriggerMemory(
        food: String,
        symptom: String,
        date: Date,
        existingMemories: [AIMemory],
        context: ModelContext,
        memoryLevel: AIMemoryLevel
    ) {
        let foodKey = food.lowercased()

        // Find existing memory
        if let existing = existingMemories.first(where: {
            $0.memoryTypeEnum == .trigger &&
            $0.trigger?.lowercased() == foodKey &&
            $0.symptom == symptom
        }) {
            existing.recordOccurrence(date: date)
        } else {
            // Create new memory if we've seen this pattern before
            let memory = AIMemory(
                memoryType: .trigger,
                symptom: symptom,
                trigger: food,
                occurrenceCount: 1,
                confidence: 0.3
            )
            if memoryLevel == .detailed {
                memory.specificDates = [date]
            }
            memory.lastOccurrence = date
            context.insert(memory)
        }
    }

    private func updateOrCreateEffectivenessMemory(
        treatment: String,
        symptom: String,
        effectiveness: Int?,
        date: Date,
        existingMemories: [AIMemory],
        context: ModelContext,
        memoryLevel: AIMemoryLevel
    ) {
        let treatmentKey = treatment.lowercased()
        let isEffective = (effectiveness ?? 5) > 5

        // Find existing memory
        if let existing = existingMemories.first(where: {
            ($0.memoryTypeEnum == .whatWorked || $0.memoryTypeEnum == .whatDidntWork) &&
            $0.resolution?.lowercased() == treatmentKey &&
            $0.symptom == symptom
        }) {
            existing.recordOccurrence(date: date)
            if isEffective {
                existing.recordSuccess()
            } else {
                existing.recordFailure()
            }
        } else {
            let memory = AIMemory(
                memoryType: isEffective ? .whatWorked : .whatDidntWork,
                symptom: symptom,
                resolution: treatment,
                occurrenceCount: 1,
                confidence: 0.3
            )
            if isEffective {
                memory.successCount = 1
            } else {
                memory.failureCount = 1
            }
            if memoryLevel == .detailed {
                memory.specificDates = [date]
            }
            memory.lastOccurrence = date
            context.insert(memory)
        }
    }

    private func updateOrCreatePatternMemory(
        factor: String,
        factorType: String,
        symptom: String,
        date: Date,
        existingMemories: [AIMemory],
        context: ModelContext,
        memoryLevel: AIMemoryLevel
    ) {
        // Find existing memory
        if let existing = existingMemories.first(where: {
            $0.memoryTypeEnum == .pattern &&
            $0.relatedEnvironmentalFactor == factor &&
            $0.symptom == symptom
        }) {
            existing.recordOccurrence(date: date)
        } else {
            let memory = AIMemory(
                memoryType: .pattern,
                symptom: symptom,
                occurrenceCount: 1,
                confidence: 0.3,
                notes: "\(symptom) observed during \(factor)"
            )
            memory.relatedEnvironmentalFactor = factor
            if memoryLevel == .detailed {
                memory.specificDates = [date]
            }
            memory.lastOccurrence = date
            context.insert(memory)
        }
    }

    // MARK: - User Feedback

    /// Process user feedback on a memory
    func processFeedback(
        _ feedback: UserFeedback,
        for memory: AIMemory,
        context: ModelContext
    ) {
        switch feedback {
        case .helped:
            memory.confirmByUser()
            if memory.memoryTypeEnum == .whatWorked || memory.memoryTypeEnum == .whatDidntWork {
                memory.recordSuccess()
            }
        case .didntHelp:
            memory.denyByUser()
            if memory.memoryTypeEnum == .whatWorked || memory.memoryTypeEnum == .whatDidntWork {
                memory.recordFailure()
            }
        case .notSureYet:
            // Just record the occurrence without changing confidence much
            break
        }

        memory.lastUpdated = Date()

        Logger.debug("Processed \(feedback.rawValue) feedback for memory: \(memory.id)", category: .data)
    }

    // MARK: - Query Methods

    /// Get memories related to a specific symptom
    func getMemories(for symptom: String, from memories: [AIMemory]) -> [AIMemory] {
        return memories.filter { $0.symptom == symptom && $0.isActive }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Get what worked for a symptom
    func getWhatWorked(for symptom: String, from memories: [AIMemory]) -> [AIMemory] {
        return memories.filter {
            $0.memoryTypeEnum == .whatWorked &&
            $0.symptom == symptom &&
            $0.isActive &&
            $0.confidence >= 0.4
        }
        .sorted { $0.effectivenessScore > $1.effectivenessScore }
    }

    /// Get known triggers for a symptom
    func getTriggers(for symptom: String, from memories: [AIMemory]) -> [AIMemory] {
        return memories.filter {
            $0.memoryTypeEnum == .trigger &&
            $0.symptom == symptom &&
            $0.isActive &&
            $0.confidence >= 0.4
        }
        .sorted { $0.confidence > $1.confidence }
    }

    /// Get all triggers (for food checking)
    func getAllTriggers(from memories: [AIMemory]) -> [AIMemory] {
        return memories.filter {
            $0.memoryTypeEnum == .trigger &&
            $0.isActive
        }
    }

    /// Get environmental patterns
    func getEnvironmentalPatterns(from memories: [AIMemory]) -> [AIMemory] {
        return memories.filter {
            $0.memoryTypeEnum == .pattern &&
            $0.relatedEnvironmentalFactor != nil &&
            $0.isActive
        }
        .sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Helpers

    private func calculateConfidence(occurrences: Int) -> Double {
        switch occurrences {
        case 0..<2: return 0.2
        case 2..<5: return 0.4
        case 5..<10: return 0.6
        case 10..<20: return 0.8
        default: return 0.9
        }
    }

    /// Clean up old or low-confidence memories
    func pruneMemories(memories: [AIMemory], context: ModelContext) {
        let cutoffDate = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()

        for memory in memories {
            // Remove very old, unconfirmed, low-confidence memories
            if memory.lastOccurrence < cutoffDate &&
               !memory.userConfirmed &&
               memory.confidence < 0.3 &&
               memory.occurrenceCount < 3 {
                memory.isActive = false
            }
        }
    }
}

// MARK: - Memory Summary Generation

extension UserMemoryService {

    /// Generate a text summary of what the AI has learned
    func generateMemorySummary(from memories: [AIMemory]) -> String {
        let triggers = memories.filter { $0.memoryTypeEnum == .trigger && $0.isActive }
        let whatWorked = memories.filter { $0.memoryTypeEnum == .whatWorked && $0.isActive }
        let patterns = memories.filter { $0.memoryTypeEnum == .pattern && $0.isActive }

        var summary = "Based on your logs, I've learned:\n\n"

        if !triggers.isEmpty {
            summary += "**Triggers:**\n"
            for trigger in triggers.prefix(5) {
                let confidence = trigger.confidenceLevel.rawValue.lowercased()
                summary += "- \(trigger.trigger ?? "Unknown") may trigger \(trigger.symptom ?? "symptoms") (\(confidence) confidence)\n"
            }
            summary += "\n"
        }

        if !whatWorked.isEmpty {
            summary += "**What Helps:**\n"
            for remedy in whatWorked.prefix(5) {
                summary += "- \(remedy.resolution ?? "Unknown") for \(remedy.symptom ?? "symptoms") (\(remedy.effectivenessPercentage)% effective)\n"
            }
            summary += "\n"
        }

        if !patterns.isEmpty {
            summary += "**Patterns:**\n"
            for pattern in patterns.prefix(3) {
                summary += "- \(pattern.notes ?? pattern.symptom ?? "Pattern observed")\n"
            }
        }

        if triggers.isEmpty && whatWorked.isEmpty && patterns.isEmpty {
            summary = "I'm still learning about your patterns. Keep logging your symptoms and what you try, and I'll start noticing correlations!"
        }

        return summary
    }
}
