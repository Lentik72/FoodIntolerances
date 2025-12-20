// Create a new file: SymptomPredictionService.swift
import Foundation
import SwiftData
import CoreML

class SymptomPredictionService {
    @MainActor
    func predictPotentialTriggers(for symptoms: [String], using context: ModelContext) -> [String] {
        // Fetch all logs
        let descriptor = FetchDescriptor<LogEntry>()
        guard let logs = try? context.fetch(descriptor) else { return [] }
        
        // Group logs by symptoms
        let symptomLogs = logs.filter { log in
            !Set(log.symptoms).isDisjoint(with: Set(symptoms))
        }
        
        // Count occurrences of food items with these symptoms
        var foodCounts: [String: Int] = [:]
        for log in symptomLogs {
            if let food = log.foodDrinkItem, !food.isEmpty {
                foodCounts[food, default: 0] += 1
            }
        }
        
        // Return top potential triggers
        return foodCounts.sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }
    
    @MainActor
    func suggestProtocols(for symptoms: [String], using context: ModelContext) -> [TherapyProtocol] {
        let descriptor = FetchDescriptor<TherapyProtocol>()
        guard let protocols = try? context.fetch(descriptor) else { return [] }
        
        // Find protocols that target these symptoms
        return protocols.filter { proto in
            guard let protoSymptoms = proto.symptoms else { return false }
            return !Set(protoSymptoms).isDisjoint(with: Set(symptoms))
        }.sorted { proto1, proto2 in
            // Sort by number of matching symptoms
            let matches1 = Set(proto1.symptoms ?? []).intersection(Set(symptoms)).count
            let matches2 = Set(proto2.symptoms ?? []).intersection(Set(symptoms)).count
            return matches1 > matches2
        }
    }
}
