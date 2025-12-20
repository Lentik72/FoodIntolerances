import SwiftUI
import SwiftData
import Charts

struct SymptomTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    let symptom: String
    
    @Query private var logs: [LogEntry]
    
    var symptomLogs: [LogEntry] {
        logs.filter { $0.symptoms.contains(symptom) }
            .sorted { $0.date > $1.date }
    }
    
    private func groupTreatments(logs: [LogEntry]) -> [(name: String, averageImprovement: Double, averageEffectiveness: Double)] {
        // Group logs by used protocol or food/drink item
        let groupedLogs = Dictionary(grouping: logs) { log -> String in
            if let protocolID = log.usedProtocolID {
                return "Protocol \(protocolID.uuidString)"
            }
            return log.foodDrinkItem ?? "Unknown Item"
        }
        
        // Calculate treatments with improvement and effectiveness
        let treatments = groupedLogs.compactMap { (name, groupLogs) -> (name: String, averageImprovement: Double, averageEffectiveness: Double)? in
            // Filter valid logs
            let validLogs = groupLogs.filter { $0.severity > 0 }
            guard !validLogs.isEmpty else { return nil }
            
            // Calculate improvement (5 - severity)
            let averageImprovement = validLogs.reduce(0.0) {
                $0 + Double(5 - $1.severity)
            } / Double(validLogs.count)
            
            // Calculate effectiveness (use protocol effectiveness if available)
            let protocolEffectiveness = validLogs.compactMap { $0.protocolEffectiveness }
            let averageEffectiveness = protocolEffectiveness.isEmpty
                ? averageImprovement
                : Double(protocolEffectiveness.reduce(0, +)) / Double(protocolEffectiveness.count)
            
            return (
                name: name,
                averageImprovement: averageImprovement,
                averageEffectiveness: averageEffectiveness
            )
        }
        
        return treatments.sorted { $0.averageImprovement > $1.averageImprovement }
    }

   
    var body: some View {
        List {
            // Severity Over Time Chart
            Section(header: Text("Severity Timeline")) {
                Chart {
                    ForEach(symptomLogs) { log in
                        LineMark(
                            x: .value("Date", log.date),
                            y: .value("Severity", log.severity)
                        )
                    }
                }
                .frame(height: 200)
            }
            
            // Environmental Correlations
            Section(header: Text("Environmental Patterns")) {
                VStack(alignment: .leading) {
                    Text("Most common during:")
                        .font(.headline)
                    
                    // Moon Phase Analysis
                    let moonPhaseStats = analyzeMoonPhases(logs: symptomLogs)
                    Text("Moon Phase: \(moonPhaseStats.mostCommon)")
                    
                    // Atmospheric Pressure Analysis
                    let pressureStats = analyzePressure(logs: symptomLogs)
                    Text("Pressure: \(pressureStats.mostCommon)")
                }
            }
            
            // Treatment Effectiveness
            Section(header: Text("Treatment Effectiveness")) {
                ForEach(groupTreatments(logs: symptomLogs), id: \.name) { treatment in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(treatment.name)
                                .font(.headline)
                            Text("Average improvement: \(treatment.averageImprovement, specifier: "%.1f") points")
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        // Star rating
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: 
                                  star <= Int(treatment.averageEffectiveness) 
                                  ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            
            // Resolution Analysis
            Section(header: Text("Resolution Analysis")) {
                if let mostEffective = findMostEffectiveTreatment(logs: symptomLogs) {
                    VStack(alignment: .leading) {
                        Text("Most Effective Treatment:")
                            .font(.headline)
                        Text(mostEffective.description)
                        Text("Average Resolution Time: \(mostEffective.averageResolutionDays) days")
                    }
                }
            }
        }
        .navigationTitle("Tracking: \(symptom)")
    }
}
