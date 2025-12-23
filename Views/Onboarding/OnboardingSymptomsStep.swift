import SwiftUI

/// Step 4: Current symptoms being tracked
struct OnboardingSymptomsStep: View {
    @Binding var selectedSymptoms: Set<String>

    var onNext: () -> Void
    var onBack: () -> Void

    @State private var customSymptom: String = ""
    @State private var showAddCustomSheet: Bool = false

    let commonSymptoms: [(category: String, symptoms: [String])] = [
        ("Head & Mind", ["Headaches/Migraines", "Brain Fog", "Dizziness", "Anxiety", "Depression"]),
        ("Energy & Sleep", ["Fatigue", "Insomnia", "Poor Sleep Quality", "Low Energy"]),
        ("Digestive", ["Bloating", "Stomach Pain", "Nausea", "Acid Reflux", "IBS Symptoms"]),
        ("Pain", ["Joint Pain", "Muscle Pain", "Back Pain", "Chronic Pain"]),
        ("Skin", ["Rashes", "Acne", "Eczema", "Hives"]),
        ("Other", ["Allergic Reactions", "Sinus Issues", "Heart Palpitations"])
    ]

    private var allCommonSymptomNames: Set<String> {
        Set(commonSymptoms.flatMap { $0.symptoms })
    }

    private var customAddedSymptoms: [String] {
        selectedSymptoms.filter { !allCommonSymptomNames.contains($0) }.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 40))
                        .foregroundColor(.purple)

                    Text("Ongoing Symptoms")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Any symptoms you're currently tracking? I'll help monitor patterns and find what helps.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)

                // Symptom categories
                VStack(spacing: 16) {
                    ForEach(commonSymptoms, id: \.category) { category in
                        SymptomCategorySection(
                            category: category.category,
                            symptoms: category.symptoms,
                            selectedSymptoms: $selectedSymptoms
                        )
                    }
                }
                .padding(.horizontal)

                // None option
                Button(action: {
                    selectedSymptoms.removeAll()
                }) {
                    HStack {
                        Image(systemName: selectedSymptoms.isEmpty ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedSymptoms.isEmpty ? .blue : .gray.opacity(0.5))
                        Text("None currently")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedSymptoms.isEmpty ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    )
                }
                .padding(.horizontal)

                // Custom added symptoms
                if !customAddedSymptoms.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        FlowLayout(spacing: 8) {
                            ForEach(customAddedSymptoms, id: \.self) { symptom in
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                    Text(symptom)
                                        .font(.subheadline)
                                    Button(action: {
                                        selectedSymptoms.remove(symptom)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.purple.opacity(0.2))
                                )
                                .foregroundColor(.purple)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Add custom button
                Button(action: { showAddCustomSheet = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.purple)
                        Text("Add Other Symptom")
                            .foregroundColor(.purple)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.purple.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
                .padding(.horizontal)

                // Selected count
                if !selectedSymptoms.isEmpty {
                    Text("\(selectedSymptoms.count) symptom\(selectedSymptoms.count == 1 ? "" : "s") selected")
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
            CustomSymptomSheet(
                symptomName: $customSymptom,
                onAdd: {
                    let trimmed = customSymptom.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        selectedSymptoms.insert(trimmed)
                        customSymptom = ""
                        showAddCustomSheet = false
                    }
                },
                onCancel: {
                    customSymptom = ""
                    showAddCustomSheet = false
                }
            )
            .presentationDetents([.height(250)])
        }
    }
}

// MARK: - Custom Symptom Sheet

struct CustomSymptomSheet: View {
    @Binding var symptomName: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Symptom Name"), footer: Text("Enter a symptom you want to track that's not listed above.")) {
                    TextField("e.g., Tinnitus, Vertigo, Tremors", text: $symptomName)
                        .autocapitalization(.words)
                }
            }
            .navigationTitle("Add Symptom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd()
                    }
                    .disabled(symptomName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct SymptomCategorySection: View {
    let category: String
    let symptoms: [String]
    @Binding var selectedSymptoms: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(symptoms, id: \.self) { symptom in
                    SymptomChip(
                        symptom: symptom,
                        isSelected: selectedSymptoms.contains(symptom)
                    ) {
                        if selectedSymptoms.contains(symptom) {
                            selectedSymptoms.remove(symptom)
                        } else {
                            selectedSymptoms.insert(symptom)
                        }
                    }
                }
            }
        }
    }
}

struct SymptomChip: View {
    let symptom: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                }
                Text(symptom)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.purple.opacity(0.2) : Color.gray.opacity(0.15))
            )
            .foregroundColor(isSelected ? .purple : .primary)
        }
    }
}

#Preview {
    OnboardingSymptomsStep(
        selectedSymptoms: .constant(["Headaches/Migraines", "Fatigue"]),
        onNext: {},
        onBack: {}
    )
}
