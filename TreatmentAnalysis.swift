import Foundation

struct TreatmentEffectiveness {
    let name: String
    let averageEffectiveness: Double
    let averageImprovement: Double
    let averageResolutionDays: Double
    let description: String
}

// MARK: - Analysis Helper Functions
func findMostEffectiveTreatment(logs: [LogEntry]) -> TreatmentEffectiveness? {
    // Group logs by treatment and analyze effectiveness
    let groupedByTreatment = Dictionary(grouping: logs) { $0.treatments.first?.name ?? "No Treatment" }
    
    return groupedByTreatment.map { treatment, logs in
        let improvement = calculateImprovement(logs: logs)
        let resolutionTime = calculateResolutionTime(logs: logs)
        let effectiveness = calculateEffectiveness(logs: logs)
        
        return TreatmentEffectiveness(
            name: treatment,
            averageEffectiveness: effectiveness,
            averageImprovement: improvement,
            averageResolutionDays: resolutionTime,
            description: generateDescription(
                treatment: treatment,
                improvement: improvement,
                resolutionTime: resolutionTime
            )
        )
    }.max(by: { $0.averageEffectiveness < $1.averageEffectiveness })
}

// Helper functions for calculations
private func calculateImprovement(logs: [LogEntry]) -> Double {
    guard logs.count >= 2 else { return 0 }
    let initialSeverity = logs.last?.severity ?? 0
    let finalSeverity = logs.first?.severity ?? 0
    return Double(initialSeverity - finalSeverity)
}

private func calculateResolutionTime(logs: [LogEntry]) -> Double {
    guard let firstLog = logs.first,
          let lastLog = logs.last else { return 0 }
    
    let duration = lastLog.date.timeIntervalSince(firstLog.date)
    return duration / (24 * 60 * 60) // Convert to days
}

private func calculateEffectiveness(logs: [LogEntry]) -> Double {
    let improvements = logs.compactMap { $0.protocolEffectiveness }
    guard !improvements.isEmpty else { return 0 }
    return Double(improvements.reduce(0, +)) / Double(improvements.count)
}

private func generateDescription(treatment: String, improvement: Double, resolutionTime: Double) -> String {
    if improvement <= 0 {
        return "No significant improvement observed with \(treatment)"
    }
    
    let timeDescription = resolutionTime < 1 ? "less than a day" : 
                         resolutionTime == 1 ? "1 day" :
                         "\(Int(resolutionTime)) days"
    
    return "\(treatment) showed an improvement of \(String(format: "%.1f", improvement)) severity points over \(timeDescription)"
}

// MARK: - Environmental Analysis Functions
func analyzeMoonPhases(logs: [LogEntry]) -> (mostCommon: String, correlation: Double) {
    let phases = logs.map { $0.moonPhase }
    let counts = Dictionary(grouping: phases, by: { $0 }).mapValues { $0.count }
    let mostCommon = counts.max(by: { $0.value < $1.value })?.key ?? "Unknown"
    
    // Calculate correlation between moon phases and severity
    let correlation = calculateCorrelation(elements: phases, severities: logs.map { $0.severity })
    
    return (mostCommon, correlation)
}

func analyzePressure(logs: [LogEntry]) -> (mostCommon: String, correlation: Double) {
    let pressures = logs.map { $0.atmosphericPressure }
    let counts = Dictionary(grouping: pressures, by: { $0 }).mapValues { $0.count }
    let mostCommon = counts.max(by: { $0.value < $1.value })?.key ?? "Unknown"
    
    // Calculate correlation between pressure and severity
    let correlation = calculateCorrelation(elements: pressures, severities: logs.map { $0.severity })
    
    return (mostCommon, correlation)
}

// Update the existing generic correlation function to handle any string inputs
private func calculateCorrelation(elements: [String], severities: [Int]) -> Double {
    // Simplified correlation calculation
    // Returns a value between -1 and 1 indicating correlation strength
    // This is a placeholder - you might want to implement a more sophisticated correlation algorithm
    return 0.0
}
