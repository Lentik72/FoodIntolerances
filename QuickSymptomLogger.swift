import SwiftUI
import SwiftData

struct QuickSymptomLogger: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var viewModel: LogItemViewModel
    @State private var recentSymptoms: [String] = []
    @State private var selectedSymptom: String?
    @State private var severity: Double = 3
    @State private var showConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Log")
                .font(.headline)
                .padding(.bottom, 5)
            
            if recentSymptoms.isEmpty {
                Text("No recent symptoms to show. Log symptoms to see them here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recentSymptoms, id: \.self) { symptom in
                            QuickSymptomButton(
                                symptom: symptom,
                                isSelected: selectedSymptom == symptom,
                                action: {
                                    selectedSymptom = symptom
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                if selectedSymptom != nil {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Severity")
                                .font(.subheadline)
                            
                            HStack {
                                Text("1")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Slider(value: $severity, in: 1...5, step: 1)
                                    .accentColor(severityColor(severity))
                                
                                Text("5")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                ForEach(1...5, id: \.self) { index in
                                    Circle()
                                        .fill(index <= Int(severity) ? severityColor(Double(index)) : Color.gray.opacity(0.3))
                                        .frame(width: 12, height: 12)
                                }
                                
                                Text(severityDescription(Int(severity)))
                                    .font(.caption)
                                    .foregroundColor(severityColor(severity))
                                    .padding(.leading, 4)
                            }
                        }
                        
                        Button(action: {
                            logSymptom()
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Log \(selectedSymptom ?? "")")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(15)
        .shadow(radius: 3)
        .padding(.horizontal)
        .overlay(
            ZStack {
                if showConfirmation {
                    Color.black.opacity(0.2)
                    
                    VStack {
                        Text("✅ Logged!")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                }
            }
            .opacity(showConfirmation ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: showConfirmation)
        )
        .onAppear {
            loadRecentSymptoms()
        }
    }
    
    private func loadRecentSymptoms() {
        // Get recent symptoms from logs or saved preferences
        // Limit to 5-10 most frequent symptoms
        
        let storedRecentSymptoms = viewModel.getRecentSymptoms()
         
         if !storedRecentSymptoms.isEmpty {
             recentSymptoms = storedRecentSymptoms
             return
         }
        
        do {
            let descriptor = FetchDescriptor<LogEntry>(sortBy: [SortDescriptor(\LogEntry.date, order: .reverse)])
            let allLogs = try modelContext.fetch(descriptor)
            
            // Create frequency map
            var symptomFrequency: [String: Int] = [:]
            for log in allLogs {
                for symptom in log.symptoms {
                    if let count = symptomFrequency[symptom] {
                        symptomFrequency[symptom] = count + 1
                    } else {
                        symptomFrequency[symptom] = 1
                    }
                }
            }
            
            // Sort by frequency and limit to top 10
            let sortedSymptoms = symptomFrequency.sorted { $0.value > $1.value }.prefix(10).map { $0.key }
            recentSymptoms = Array(sortedSymptoms)
        } catch {
            Logger.error(error, message: "Error fetching log entries", category: .data)
        }
    }
    
    private func logSymptom() {
        guard let symptom = selectedSymptom else { return }
        
        // Reset viewModel to ensure clean state
        viewModel.resetForm()
        
        // Set up the log entry with minimum required data
        viewModel.addSymptom(symptom)
        viewModel.severity = severity
        viewModel.date = Date()
        
        // Save the log
        viewModel.saveLog(using: modelContext)
        
        // Show confirmation
        withAnimation {
            showConfirmation = true
        }
        
        // Reset selection
        selectedSymptom = nil
        severity = 3
        
        // Hide confirmation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showConfirmation = false
            }
        }
    }
    
    private func severityColor(_ value: Double) -> Color {
        switch Int(value) {
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
    
    private func severityDescription(_ value: Int) -> String {
        AppConstants.Severity.description(for: value)
    }
}

struct QuickSymptomButton: View {
    let symptom: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(symptom)
                .font(.footnote)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.tertiarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
                .shadow(color: isSelected ? Color.blue.opacity(0.5) : Color.clear, radius: 4)
        }
    }
}
