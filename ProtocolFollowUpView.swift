import SwiftUI
import SwiftData

struct ProtocolFollowUpView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    let logEntry: LogEntry
    
    @State private var effectiveness: Int = 3
    @State private var notes: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Protocol Effectiveness")) {
                    Picker("Rate effectiveness", selection: $effectiveness) {
                        ForEach(1...5, id: \.self) { rating in
                            Text("\(rating)").tag(rating)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
                
                Button("Save Feedback") {
                    saveProtocolFeedback()
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Protocol Follow-up")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveProtocolFeedback() {
        logEntry.protocolEffectiveness = effectiveness
        logEntry.protocolNotes = notes
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving protocol feedback: \(error)")
        }
    }
}
