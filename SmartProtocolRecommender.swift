import Foundation
import SwiftData

class SmartProtocolRecommender {
    @MainActor
    func recommendProtocols(for symptoms: [String], logs: [LogEntry], using context: ModelContext) -> [TherapyProtocol] {
        // Get all available protocols
        let descriptor = FetchDescriptor<TherapyProtocol>()
        guard let allProtocols = try? context.fetch(descriptor) else { return [] }
        
        // Step 1: Find protocols that target these symptoms
        let relevantProtocols = allProtocols.filter { proto in
            guard let protoSymptoms = proto.symptoms, !protoSymptoms.isEmpty else { return false }
            return !Set(protoSymptoms).isDisjoint(with: Set(symptoms))
        }
        
        // Step 2: Calculate effectiveness scores based on previous usage
        var effectivenessScores: [UUID: Double] = [:]
        
        for proto in relevantProtocols {
            // Find logs where this protocol was used
            let previousUsageLogs = logs.filter { log in
                log.protocolID == proto.id || log.usedProtocolID == proto.id
            }
            
            if previousUsageLogs.isEmpty {
                // No previous usage, neutral score
                effectivenessScores[proto.id] = 0.5
                continue
            }
            
            // Calculate average effectiveness from existing ratings
            let ratings = previousUsageLogs.compactMap { $0.protocolEffectiveness }
            if !ratings.isEmpty {
                let averageRating = Double(ratings.reduce(0, +)) / Double(ratings.count) / 5.0
                effectivenessScores[proto.id] = averageRating
                continue
            }
            
            // If no explicit ratings, try to infer from symptom severity changes
            var improvements: [Double] = []
            
            // Group logs by user for more accurate tracking
            let userGroups = Dictionary(grouping: previousUsageLogs) { $0.id }
            
            for (_, userLogs) in userGroups {
                let sortedLogs = userLogs.sorted { $0.date < $1.date }
                if sortedLogs.count >= 2 {
                    let firstSeverity = Double(sortedLogs.first?.severity ?? 5)
                    let lastSeverity = Double(sortedLogs.last?.severity ?? 5)
                    let improvement = (firstSeverity - lastSeverity) / firstSeverity
                    improvements.append(improvement)
                }
            }
            
            if !improvements.isEmpty {
                let averageImprovement = improvements.reduce(0, +) / Double(improvements.count)
                // Convert to a 0-1 scale, where 0.5 is neutral
                effectivenessScores[proto.id] = 0.5 + (averageImprovement / 2.0)
            } else {
                effectivenessScores[proto.id] = 0.5 // Neutral score
            }
        }
        
        // Step 3: Calculate match scores based on symptom overlap
        var matchScores: [UUID: Double] = [:]
        
        for proto in relevantProtocols {
            guard let protoSymptoms = proto.symptoms else { continue }
            
            let matchingSymptoms = Set(protoSymptoms).intersection(Set(symptoms))
            let matchRatio = Double(matchingSymptoms.count) / Double(symptoms.count)
            matchScores[proto.id] = matchRatio
        }
        
        // Step 4: Calculate final scores and sort protocols
        let finalResults = relevantProtocols.map { proto in
            let effectivenessScore = effectivenessScores[proto.id] ?? 0.5
            let matchScore = matchScores[proto.id] ?? 0.0
            
            // Weighted scoring: 60% for symptom match, 40% for effectiveness
            let finalScore = (matchScore * 0.6) + (effectivenessScore * 0.4)
            
            return (protocol: proto, score: finalScore)
        }
        .sorted { $0.score > $1.score }
        .map { $0.protocol }
        
        return finalResults
    }
}
