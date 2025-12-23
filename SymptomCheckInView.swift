import SwiftUI
import SwiftData

struct SymptomCheckInView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let symptom: OngoingSymptom
    
    @State private var severity: Int = 3
    @State private var protocolUsed: String = ""
    @State private var protocolEffectiveness: Int?
    @State private var protocolNotes: String = ""
    @State private var notes: String = ""
    @State private var date: Date = Date()
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                // Date Section
                Section(header: Text("Check-in Time")) {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                
                // Severity Section
                Section(header: Text("Symptom Severity")) {
                    Picker("Severity Level", selection: $severity) {
                        ForEach(1...5, id: \.self) { level in
                            Text("\(level) - \(severityDescription(level))")
                                .tag(level)
                        }
                    }
                }
                
                // Protocol Follow-up Section
                Section(header: Text("Protocol")) {
                    TextField("Protocol Used", text: $protocolUsed)
                    
                    Picker("Protocol Effectiveness", selection: $protocolEffectiveness) {
                        Text("Select Rating").tag(Optional<Int>.none)
                        ForEach(1...5, id: \.self) { rating in
                            Text("\(rating)").tag(Optional<Int>.some(rating))
                        }
                    }
                    
                    TextField("Protocol Notes", text: $protocolNotes)
                }
                
                // Notes Section
                Section(header: Text("Additional Notes")) {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
                
                // Save Button Section
                Section {
                    Button(action: saveCheckIn) {
                        Text("Save Check-in")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
            }
            .navigationTitle("\(symptom.name) Check-in")
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
    
    private func severityDescription(_ level: Int) -> String {
        switch level {
        case 1: return "Mild"
        case 2: return "Light"
        case 3: return "Moderate"
        case 4: return "Severe"
        case 5: return "Extreme"
        default: return ""
        }
    }
    
    private func saveCheckIn() {
        let checkIn = SymptomCheckIn(
            parentSymptomID: symptom.id,
            date: date,
            severity: severity,
            protocolUsed: protocolUsed,
            notes: notes
        )
        
        // Set optional properties if they have values
        if let effectiveness = protocolEffectiveness {
            checkIn.protocolEffectiveness = effectiveness
        }
        
        if !protocolNotes.isEmpty {
            checkIn.protocolNotes = protocolNotes
        }
        
        modelContext.insert(checkIn)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = "Could not save your check-in. Please try again."
            showSaveError = true
            Logger.error(error, message: "Failed to save check-in", category: .data)
        }
    }
}

struct SymptomCheckInView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleSymptom = OngoingSymptom(name: "Headache")
        SymptomCheckInView(symptom: sampleSymptom)
            .modelContainer(for: [OngoingSymptom.self, SymptomCheckIn.self], inMemory: true)
    }
}
