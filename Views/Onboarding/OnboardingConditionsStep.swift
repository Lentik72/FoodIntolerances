import SwiftUI

/// Step 2: Health conditions
struct OnboardingConditionsStep: View {
    @Binding var selectedConditions: Set<String>

    var onNext: () -> Void
    var onBack: () -> Void

    @State private var customCondition: String = ""
    @State private var showAddCustomSheet: Bool = false

    let commonConditions = CommonHealthCondition.all

    // Custom conditions that user added (not in the common list)
    private var customAddedConditions: [String] {
        selectedConditions.filter { !commonConditions.contains($0) }.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)

                    Text("Health Conditions")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Do you have any ongoing health conditions? This helps me provide relevant screening reminders.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)

                // Conditions list
                VStack(spacing: 8) {
                    ForEach(commonConditions, id: \.self) { condition in
                        ConditionToggleRow(
                            condition: condition,
                            isSelected: selectedConditions.contains(condition)
                        ) {
                            if selectedConditions.contains(condition) {
                                selectedConditions.remove(condition)
                            } else {
                                selectedConditions.insert(condition)
                            }
                        }
                    }

                    // None option
                    Button(action: {
                        selectedConditions.removeAll()
                    }) {
                        HStack {
                            Image(systemName: selectedConditions.isEmpty ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedConditions.isEmpty ? .blue : .gray.opacity(0.5))
                            Text("None of these")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedConditions.isEmpty ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                        )
                    }

                    // Custom added conditions
                    ForEach(customAddedConditions, id: \.self) { condition in
                        HStack {
                            Image(systemName: selectedConditions.contains(condition) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(.blue)
                            Text(condition)
                                .foregroundColor(.primary)
                            Spacer()
                            Button(action: {
                                selectedConditions.remove(condition)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }

                    // Add custom button
                    Button(action: { showAddCustomSheet = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Add Other Condition")
                                .foregroundColor(.blue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    }
                }
                .padding(.horizontal)

                // Selected count
                if !selectedConditions.isEmpty {
                    Text("\(selectedConditions.count) condition\(selectedConditions.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 40)

                // Navigation buttons
                HStack(spacing: 12) {
                    Button(action: onBack) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }

                    Button(action: onNext) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showAddCustomSheet) {
            CustomConditionSheet(
                conditionName: $customCondition,
                onAdd: {
                    let trimmed = customCondition.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        selectedConditions.insert(trimmed)
                        customCondition = ""
                        showAddCustomSheet = false
                    }
                },
                onCancel: {
                    customCondition = ""
                    showAddCustomSheet = false
                }
            )
            .presentationDetents([.height(250)])
        }
    }
}

// MARK: - Custom Condition Sheet

struct CustomConditionSheet: View {
    @Binding var conditionName: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Condition Name"), footer: Text("Enter a health condition not listed above.")) {
                    TextField("e.g., Fibromyalgia, PCOS, Lupus", text: $conditionName)
                        .autocapitalization(.words)
                }
            }
            .navigationTitle("Add Condition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd()
                    }
                    .disabled(conditionName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct ConditionToggleRow: View {
    let condition: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                Text(condition)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            )
        }
    }
}

#Preview {
    OnboardingConditionsStep(
        selectedConditions: .constant(["Diabetes"]),
        onNext: {},
        onBack: {}
    )
}
