// Create a new file: GoalTrackingView.swift
import SwiftUI
import SwiftData

struct GoalTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var logs: [LogEntry]
    @Query private var ongoingSymptoms: [OngoingSymptom]
    
    @State private var goalSymptom: String = ""
    @State private var targetSeverity: Int = 1
    @State private var targetDate: Date = Date().addingTimeInterval(60*60*24*30) // 30 days
    
    var symptoms: [String] {
        Array(Set(logs.flatMap { $0.symptoms })).sorted()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Track Your Progress")
                .font(.title2)
                .bold()
            
            // Goal setting section
            VStack(alignment: .leading) {
                Text("Set a Symptom Resolution Goal")
                    .font(.headline)
                
                Picker("Symptom", selection: $goalSymptom) {
                    Text("Select a symptom").tag("")
                    ForEach(symptoms, id: \.self) { symptom in
                        Text(symptom).tag(symptom)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                if !goalSymptom.isEmpty {
                    Text("Target Severity")
                        .font(.subheadline)
                    
                    Picker("Target Severity", selection: $targetSeverity) {
                        Text("1 - Minimal").tag(1)
                        Text("2 - Mild").tag(2)
                        Text("3 - Moderate").tag(3)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    DatePicker("Target Date", selection: $targetDate, displayedComponents: .date)
                    
                    Button("Set Goal") {
                        setSymptomGoal()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(10)
            
            // Progress tracking
            if !ongoingSymptoms.isEmpty {
                Text("Current Progress")
                    .font(.headline)
                    .padding(.top)
                
                ForEach(ongoingSymptoms) { symptom in
                    SymptomProgressCard(symptom: symptom, logs: logs.filter { $0.symptoms.contains(symptom.name) })
                }
            }
        }
        .padding()
    }
    
    private func setSymptomGoal() {
        guard !goalSymptom.isEmpty else { return }
        
        // Check if symptom is already being tracked
        let existing = ongoingSymptoms.first { $0.name == goalSymptom }
        
        if let existing = existing {
            // Update existing goal
            existing.endDate = targetDate
            // We could add target severity as a property to OngoingSymptom
        } else {
            // Create new tracking
            let ongoingSymptom = OngoingSymptom(
                name: goalSymptom,
                startDate: Date(),
                endDate: targetDate,
                isOpen: true,
                notes: "Goal: Reduce to severity \(targetSeverity) by \(targetDate.formatted(date: .abbreviated, time: .omitted))"
            )
            
            modelContext.insert(ongoingSymptom)
        }
        
        do {
            try modelContext.save()
            
            // Reset form
            goalSymptom = ""
            targetSeverity = 1
            targetDate = Date().addingTimeInterval(60*60*24*30)
        } catch {
            print("Error saving symptom goal: \(error)")
        }
    }
}

struct SymptomProgressCard: View {
    let symptom: OngoingSymptom
    let logs: [LogEntry]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(symptom.name)
                .font(.headline)
            
            if let endDate = symptom.endDate {
                Text("Target: \(endDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Calculate progress
            let sortedLogs = logs.sorted { $0.date > $1.date }
            let initialSeverity = sortedLogs.last?.severity ?? 5
            let currentSeverity = sortedLogs.first?.severity ?? initialSeverity
            
            let progress = 1.0 - (Double(currentSeverity) / Double(initialSeverity))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Initial Severity: \(initialSeverity)")
                    Spacer()
                    Text("Current: \(currentSeverity)")
                }
                .font(.caption)
                
                ProgressView(value: progress)
                    .accentColor(progress >= 0.5 ? .green : .orange)
                
                Text("\(Int(progress * 100))% improvement")
                    .font(.caption)
                    .foregroundColor(progress >= 0.5 ? .green : .orange)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(10)
    }
}
