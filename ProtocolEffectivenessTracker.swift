// Create a new file: ProtocolEffectivenessTracker.swift
import SwiftUI
import SwiftData

struct ProtocolEffectivenessTracker: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var protocols: [TherapyProtocol]
    @Query private var logs: [LogEntry]
    
    var body: some View {
        List {
            ForEach(protocols.filter { $0.isActive }) { proto in
                VStack(alignment: .leading) {
                    Text(proto.title)
                        .font(.headline)
                    
                    if let targetSymptoms = proto.symptoms, !targetSymptoms.isEmpty {
                        Text("Targeting: \(targetSymptoms.joined(separator: ", "))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Calculate effectiveness
                    let effectiveness = calculateEffectiveness(for: proto)
                    
                    HStack {
                        Text("Effectiveness")
                        Spacer()
                        ForEach(1...5, id: \.self) { rating in
                            Image(systemName: rating <= effectiveness ? "star.fill" : "star")
                                .foregroundColor(rating <= effectiveness ? .yellow : .gray)
                        }
                    }
                    
                    if proto.startDate != Date(timeIntervalSince1970: 0) {  // Example default date
                        Text("Started: \(proto.startDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Protocol Effectiveness")
    }
    
    private func calculateEffectiveness(for proto: TherapyProtocol) -> Int {
        guard let symptoms = proto.symptoms, !symptoms.isEmpty else { return 0 }
              
        // Get all logs after the protocol started
        let relevantLogs = logs.filter { log in
            log.date >= proto.startDate && !Set(log.symptoms).isDisjoint(with: Set(symptoms))
        }
        
        // If no relevant logs, return 0
        if relevantLogs.isEmpty {
            return 0
        }
        
        // Group logs by week
        let calendar = Calendar.current
        var logsByWeek: [Date: [LogEntry]] = [:]
        
        for log in relevantLogs {
            let weekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: log.date)
            guard let weekDate = calendar.date(from: weekStart) else { continue }
            logsByWeek[weekDate, default: []].append(log)
        }
        
        // Calculate average severity by week
        var weeklyAverageSeverity: [Date: Double] = [:]
        for (week, logs) in logsByWeek {
            let totalSeverity = logs.reduce(0) { $0 + $1.severity }
            weeklyAverageSeverity[week] = Double(totalSeverity) / Double(logs.count)
        }
        
        // Calculate improvement
        let weeks = weeklyAverageSeverity.keys.sorted()
        guard weeks.count >= 2 else { return 3 } // Default to medium if not enough data
        
        let firstWeekSeverity = weeklyAverageSeverity[weeks.first!] ?? 5.0
        let lastWeekSeverity = weeklyAverageSeverity[weeks.last!] ?? 5.0
        
        let improvement = firstWeekSeverity - lastWeekSeverity
        
        // Convert to 1-5 scale
        if improvement <= -1 { return 1 } // Getting worse
        if improvement < 0 { return 2 } // Slightly worse
        if improvement < 1 { return 3 } // No significant change
        if improvement < 2 { return 4 } // Improvement
        return 5 // Significant improvement
    }
}
