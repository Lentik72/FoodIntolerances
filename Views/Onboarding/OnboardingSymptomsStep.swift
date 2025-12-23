import SwiftUI

/// Step 4: Current symptoms being tracked
struct OnboardingSymptomsStep: View {
    @Binding var selectedSymptoms: Set<String>

    var onNext: () -> Void
    var onBack: () -> Void

    @State private var customSymptom: String = ""
    @State private var showAddCustom: Bool = false

    let commonSymptoms: [(category: String, symptoms: [String])] = [
        ("Head & Mind", ["Headaches/Migraines", "Brain Fog", "Dizziness", "Anxiety", "Depression"]),
        ("Energy & Sleep", ["Fatigue", "Insomnia", "Poor Sleep Quality", "Low Energy"]),
        ("Digestive", ["Bloating", "Stomach Pain", "Nausea", "Acid Reflux", "IBS Symptoms"]),
        ("Pain", ["Joint Pain", "Muscle Pain", "Back Pain", "Chronic Pain"]),
        ("Skin", ["Rashes", "Acne", "Eczema", "Hives"]),
        ("Other", ["Allergic Reactions", "Sinus Issues", "Heart Palpitations"])
    ]

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

                // Add custom
                if showAddCustom {
                    HStack {
                        TextField("Enter symptom", text: $customSymptom)
                            .textFieldStyle(.roundedBorder)

                        Button(action: {
                            if !customSymptom.isEmpty {
                                selectedSymptoms.insert(customSymptom)
                                customSymptom = ""
                                showAddCustom = false
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Button(action: { showAddCustom = true }) {
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.blue)
                            Text("Add other symptom")
                                .foregroundColor(.blue)
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    }
                    .padding(.horizontal)
                }

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
