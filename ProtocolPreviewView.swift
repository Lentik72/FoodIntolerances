import SwiftUI
import SwiftData

struct ProtocolPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let extraction: ProtocolExtraction
    @State private var title: String
    @State private var category: String
    @State private var instructions: String
    @State private var frequency: String = "Daily"
    @State private var timeOfDay: String = "Morning"
    @State private var duration: String
    @State private var symptoms: [String]
    @State private var notes: String
    @State private var isWishlist: Bool = false
    @State private var reviewStage: ReviewStage = .basic
    @State private var verificationChecked: Bool = false
    
    // Add missing variables for validation
    @State private var showValidationError = false
    @State private var validationError: String?
    
    // Track which verification steps have been completed
    @State private var titleVerified = false
    @State private var instructionsVerified = false
    @State private var scheduleVerified = false
    
    enum ReviewStage {
        case basic, schedule, verification, final
    }
    
    init(extraction: ProtocolExtraction, onSave: @escaping (TherapyProtocol) -> Void) {
        self.extraction = extraction
        
        // Initialize state with extracted info
        _title = State(initialValue: extraction.title)
        _instructions = State(initialValue: extraction.instructions)
        _category = State(initialValue: extraction.category)
        _duration = State(initialValue: extraction.duration.isEmpty ? "As needed" : extraction.duration)
        _symptoms = State(initialValue: extraction.symptoms)
        _notes = State(initialValue: "Source: \(extraction.sourceURL)")
        
        // Extract frequency from dosage if possible
        if extraction.dosage.lowercased().contains("daily") {
            _frequency = State(initialValue: "Daily")
        } else if extraction.dosage.lowercased().contains("weekly") {
            _frequency = State(initialValue: "Weekly")
        } else if extraction.dosage.lowercased().contains("as needed") {
            _frequency = State(initialValue: "As Needed")
        }
        
        // Extract time of day if possible
        if extraction.dosage.lowercased().contains("morning") {
            _timeOfDay = State(initialValue: "Morning")
        } else if extraction.dosage.lowercased().contains("evening") {
            _timeOfDay = State(initialValue: "Evening")
        } else if extraction.dosage.lowercased().contains("night") {
            _timeOfDay = State(initialValue: "Night")
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            ProgressIndicator(stage: reviewStage)
                .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Content based on current stage
                    Group {
                        switch reviewStage {
                        case .basic:
                            basicInfoView
                        case .schedule:
                            scheduleView
                        case .verification:
                            verificationView
                        case .final:
                            finalReviewView
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(15)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            
            // Navigation buttons
            HStack {
                if reviewStage != .basic {
                    Button("Back") {
                        withAnimation {
                            moveBackward()
                        }
                    }
                    .padding()
                    .frame(minWidth: 100)
                }
                
                Spacer()
                
                Button(reviewStage == .final ? "Save Protocol" : "Continue") {
                    withAnimation {
                        if reviewStage == .final {
                            saveProtocol()
                        } else {
                            moveForward()
                        }
                    }
                }
                .padding()
                .frame(minWidth: 140)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(reviewStage == .verification && !verificationChecked)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle("Protocol Review")
        .navigationBarItems(trailing: Button("Cancel") {
            dismiss()
        })
        .alert(isPresented: $showValidationError) {
            Alert(
                title: Text("Validation Error"),
                message: Text(validationError ?? "Please fix the errors before saving"),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // Basic information view
    var basicInfoView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Basic Information")
                .font(.headline)
                .padding(.bottom, 5)
            
            TextField("Protocol Title", text: $title)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.bottom, 5)
            
            Picker("Category", selection: $category) {
                ForEach(ProtocolCategory.defaultCategories, id: \.name) { category in
                    Text(category.name).tag(category.name)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding(.bottom, 10)
            
            Text("Instructions")
                .font(.subheadline)
                .bold()
            
            TextEditor(text: $instructions)
                .frame(minHeight: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
                .padding(.bottom, 10)
            
            Text("Targeted Symptoms")
                .font(.subheadline)
                .bold()
            
            // Editable symptom tags
            FlowLayout(spacing: 8) {
                ForEach(symptoms, id: \.self) { symptom in
                    Button(action: {
                        if let index = symptoms.firstIndex(of: symptom) {
                            symptoms.remove(at: index)
                        }
                    }) {
                        HStack {
                            Text(symptom)
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                }
                
                Button(action: {
                    let alert = UIAlertController(title: "Add Symptom", message: nil, preferredStyle: .alert)
                    alert.addTextField { field in
                        field.placeholder = "Symptom name"
                    }
                    
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                    alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
                        if let field = alert.textFields?.first,
                           let text = field.text,
                           !text.isEmpty,
                           !symptoms.contains(text) {
                            symptoms.append(text)
                        }
                    })
                    
                    // Present the alert
                    UIApplication
                        .shared
                        .windows
                        .first?
                        .rootViewController?
                        .present(alert, animated: true)
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Symptom")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                }
            }
            .padding(.bottom, 10)
            
            Toggle("Add to Wishlist", isOn: $isWishlist)
        }
    }
    
    // Schedule view
    var scheduleView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Treatment Schedule")
                .font(.headline)
                .padding(.bottom, 5)
            
            Picker("Frequency", selection: $frequency) {
                Text("Daily").tag("Daily")
                Text("Multiple Times Daily").tag("Multiple Times Daily")
                Text("Every Other Day").tag("Every Other Day")
                Text("Weekly").tag("Weekly")
                Text("As Needed").tag("As Needed")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.bottom, 10)
            
            Picker("Time of Day", selection: $timeOfDay) {
                Text("Morning").tag("Morning")
                Text("Afternoon").tag("Afternoon")
                Text("Evening").tag("Evening")
                Text("Bedtime").tag("Bedtime")
                Text("Multiple Times").tag("Multiple Times")
                Text("With Meals").tag("With Meals")
                Text("As Needed").tag("As Needed")
            }
            .pickerStyle(MenuPickerStyle())
            .padding(.bottom, 10)
            
            Text("Duration")
                .font(.subheadline)
                .bold()
            
            TextField("Duration (e.g., 2 weeks)", text: $duration)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.bottom, 10)
            
            Text("Notes")
                .font(.subheadline)
                .bold()
            
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
                .padding(.bottom, 5)
            
            Text("Source: \(extraction.sourceURL)")
                .font(.caption)
                .foregroundColor(.blue)
        }
    }
    
    // Verification view
    var verificationView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Safety Verification")
                .font(.headline)
                .padding(.bottom, 5)
            
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Important Health Information")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.orange)
                    
                    Text("This protocol was obtained from the web and has not been medically verified. Before proceeding, please verify that:")
                        .font(.callout)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        verificationItem(
                            text: "I've reviewed the instructions for safety",
                            isChecked: $titleVerified
                        )
                        
                        verificationItem(
                            text: "I will consult a healthcare professional before use",
                            isChecked: $instructionsVerified
                        )
                        
                        verificationItem(
                            text: "I understand this is for informational purposes only",
                            isChecked: $scheduleVerified
                        )
                    }
                    .padding(.vertical, 5)
                    
                    Toggle("I confirm all of the above", isOn: $verificationChecked)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .padding(.top, 5)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    // Final review view
    var finalReviewView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Final Review")
                .font(.headline)
                .padding(.bottom, 5)
            
            Group {
                reviewRow(label: "Title", value: title)
                reviewRow(label: "Category", value: category)
                reviewRow(label: "Instructions", value: instructions)
                reviewRow(label: "Frequency", value: frequency)
                reviewRow(label: "Time of Day", value: timeOfDay)
                reviewRow(label: "Duration", value: duration)
                reviewRow(label: "Symptoms", value: symptoms.joined(separator: ", "))
                
                if isWishlist {
                    reviewRow(label: "Added to", value: "Wishlist")
                }
                
                reviewRow(label: "Source", value: extraction.sourceURL)
            }
            
            Text("This protocol will be saved to your protocols with an 'Unverified' tag. You can edit it at any time.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 5)
        }
    }
    
    // Helper views
    func verificationItem(text: String, isChecked: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: isChecked.wrappedValue ? "checkmark.square.fill" : "square")
                .foregroundColor(isChecked.wrappedValue ? .green : .gray)
                .onTapGesture {
                    isChecked.wrappedValue.toggle()
                }
            
            Text(text)
                .font(.subheadline)
        }
    }
    
    func reviewRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.body)
                .padding(.leading, 5)
        }
        .padding(.vertical, 2)
    }
    
    // Navigation functions
    func moveForward() {
        switch reviewStage {
        case .basic:
            reviewStage = .schedule
        case .schedule:
            reviewStage = .verification
        case .verification:
            reviewStage = .final
        case .final:
            // We save the protocol in the button action
            break
        }
    }
    
    func moveBackward() {
        switch reviewStage {
        case .basic:
            // Already at first stage
            break
        case .schedule:
            reviewStage = .basic
        case .verification:
            reviewStage = .schedule
        case .final:
            reviewStage = .verification
        }
    }
    
    // Add validation function
    private func validateProtocol() -> Bool {
        // Title validation
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationError = "Protocol title cannot be empty"
            showValidationError = true
            return false
        }
        
        // Instructions validation
        if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationError = "Instructions cannot be empty"
            showValidationError = true
            return false
        }
        
        // Duration validation - ensure it has some value
        if duration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            duration = "As needed"
        }
        
        // Symptoms validation - ensure there's at least one
        if symptoms.isEmpty {
            validationError = "Please add at least one targeted symptom"
            showValidationError = true
            return false
        }
        
        return true
    }
    
    // Save the protocol
    func saveProtocol() {
        // Validate before saving
        if !validateProtocol() {
            return
        }
        
        // Create therapy protocol from state
        let newProtocol = TherapyProtocol(
            title: title,
            category: category,
            instructions: instructions,
            frequency: frequency,
            timeOfDay: timeOfDay,
            duration: duration,
            symptoms: symptoms,
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()), // Default to 2 weeks
            notes: notes + "\n\nDISCLAIMER: This protocol was imported from the web and has not been medically verified.",
            isWishlist: isWishlist,
            isActive: false,
            dateAdded: Date(),
            tags: ["Web Source - Unverified", "Requires Review"]
        )
        
        // Insert into database
        modelContext.insert(newProtocol)
        try? modelContext.save()
        
        // Dismiss the sheet
        dismiss()
    }
}

// Progress indicator component
struct ProgressIndicator: View {
    let stage: ProtocolPreviewView.ReviewStage
    
    var body: some View {
        HStack(spacing: 0) {
            progressStep(
                number: 1,
                title: "Basic Info",
                isActive: stage == .basic,
                isCompleted: stage != .basic
            )
            
            progressConnector(isCompleted: stage != .basic)
            
            progressStep(
                number: 2,
                title: "Schedule",
                isActive: stage == .schedule,
                isCompleted: stage == .verification || stage == .final
            )
            
            progressConnector(isCompleted: stage == .verification || stage == .final)
            
            progressStep(
                number: 3,
                title: "Verify",
                isActive: stage == .verification,
                isCompleted: stage == .final
            )
            
            progressConnector(isCompleted: stage == .final)
            
            progressStep(
                number: 4,
                title: "Review",
                isActive: stage == .final,
                isCompleted: false
            )
        }
    }
    
    func progressStep(number: Int, title: String, isActive: Bool, isCompleted: Bool) -> some View {
        VStack {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : (isActive ? Color.blue : Color.gray.opacity(0.3)))
                    .frame(width: 30, height: 30)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .bold))
                } else {
                    Text("\(number)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(isActive ? .blue : .gray)
        }
    }
    
    func progressConnector(isCompleted: Bool) -> some View {
        Rectangle()
            .fill(isCompleted ? Color.green : Color.gray.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }
}
