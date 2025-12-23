import SwiftUI

/// Step 5: Medications and supplements
struct OnboardingMedicationsStep: View {
    @Binding var medications: [String]
    @Binding var supplements: Set<String>

    var onNext: () -> Void
    var onBack: () -> Void

    @State private var newMedication: String = ""
    @State private var showAddMedicationSheet: Bool = false
    @State private var newSupplement: String = ""
    @State private var showAddSupplementSheet: Bool = false

    let commonSupplements = [
        "Vitamin D",
        "Vitamin B12",
        "Vitamin C",
        "Magnesium",
        "Omega-3 / Fish Oil",
        "Probiotics",
        "Iron",
        "Zinc",
        "Calcium",
        "Multivitamin",
        "Melatonin",
        "Turmeric/Curcumin",
        "Vitamin B Complex",
        "CoQ10",
        "Collagen"
    ]

    private var customSupplements: [String] {
        supplements.filter { !commonSupplements.contains($0) }.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)

                    Text("Medications & Supplements")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("What do you currently take? I'll help track if you've taken them and correlate with how you feel.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)

                // Medications section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "cross.case.fill")
                            .foregroundColor(.red)
                        Text("Medications")
                            .font(.headline)
                    }

                    if medications.isEmpty {
                        Text("No medications added")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(medications, id: \.self) { med in
                                HStack {
                                    Text(med)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Button(action: {
                                        medications.removeAll { $0 == med }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                    }

                    // Add medication button
                    Button(action: { showAddMedicationSheet = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.red)
                            Text("Add Medication")
                                .foregroundColor(.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    }
                }
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Supplements section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "leaf.fill")
                            .foregroundColor(.green)
                        Text("Supplements")
                            .font(.headline)
                    }

                    FlowLayout(spacing: 8) {
                        ForEach(commonSupplements, id: \.self) { supplement in
                            SupplementChip(
                                supplement: supplement,
                                isSelected: supplements.contains(supplement)
                            ) {
                                if supplements.contains(supplement) {
                                    supplements.remove(supplement)
                                } else {
                                    supplements.insert(supplement)
                                }
                            }
                        }
                    }

                    // Custom supplements
                    if !customSupplements.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(customSupplements, id: \.self) { supplement in
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                    Text(supplement)
                                        .font(.subheadline)
                                    Button(action: {
                                        supplements.remove(supplement)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.3))
                                )
                                .foregroundColor(.green)
                            }
                        }
                    }

                    // Add custom supplement button
                    Button(action: { showAddSupplementSheet = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Add Other Supplement")
                                .foregroundColor(.green)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.green.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    }
                }
                .padding(.horizontal)

                // None option
                Button(action: {
                    medications.removeAll()
                    supplements.removeAll()
                }) {
                    HStack {
                        Image(systemName: (medications.isEmpty && supplements.isEmpty) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor((medications.isEmpty && supplements.isEmpty) ? .blue : .gray.opacity(0.5))
                        Text("None")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill((medications.isEmpty && supplements.isEmpty) ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    )
                }
                .padding(.horizontal)

                // Summary
                if !medications.isEmpty || !supplements.isEmpty {
                    let total = medications.count + supplements.count
                    Text("\(total) item\(total == 1 ? "" : "s") selected")
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
        .sheet(isPresented: $showAddMedicationSheet) {
            CustomMedicationSheet(
                medicationName: $newMedication,
                onAdd: {
                    let trimmed = newMedication.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && !medications.contains(trimmed) {
                        medications.append(trimmed)
                        newMedication = ""
                        showAddMedicationSheet = false
                    }
                },
                onCancel: {
                    newMedication = ""
                    showAddMedicationSheet = false
                }
            )
            .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showAddSupplementSheet) {
            CustomSupplementSheet(
                supplementName: $newSupplement,
                onAdd: {
                    let trimmed = newSupplement.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        supplements.insert(trimmed)
                        newSupplement = ""
                        showAddSupplementSheet = false
                    }
                },
                onCancel: {
                    newSupplement = ""
                    showAddSupplementSheet = false
                }
            )
            .presentationDetents([.height(250)])
        }
    }
}

// MARK: - Custom Medication Sheet

struct CustomMedicationSheet: View {
    @Binding var medicationName: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Medication Name"), footer: Text("Enter the name of any prescription or over-the-counter medication you take regularly.")) {
                    TextField("e.g., Metformin, Lisinopril, Advil", text: $medicationName)
                        .autocapitalization(.words)
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd()
                    }
                    .disabled(medicationName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Custom Supplement Sheet

struct CustomSupplementSheet: View {
    @Binding var supplementName: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Supplement Name"), footer: Text("Enter any supplement not listed in the common options above.")) {
                    TextField("e.g., Ashwagandha, Biotin, NAC", text: $supplementName)
                        .autocapitalization(.words)
                }
            }
            .navigationTitle("Add Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd()
                    }
                    .disabled(supplementName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct SupplementChip: View {
    let supplement: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                }
                Text(supplement)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.green.opacity(0.2) : Color.gray.opacity(0.15))
            )
            .foregroundColor(isSelected ? .green : .primary)
        }
    }
}

#Preview {
    OnboardingMedicationsStep(
        medications: .constant(["Metformin"]),
        supplements: .constant(["Vitamin D", "Magnesium"]),
        onNext: {},
        onBack: {}
    )
}
