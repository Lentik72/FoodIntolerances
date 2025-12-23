import SwiftUI

/// Step 3: Allergies and intolerances
struct OnboardingAllergiesStep: View {
    @Binding var selectedAllergies: [OnboardingAllergy]

    var onNext: () -> Void
    var onBack: () -> Void

    @State private var showSeverityPicker: CommonAllergy?
    @State private var tempSeverity: AllergySeverity = .moderate

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "allergens")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)

                    Text("Allergies & Sensitivities")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Any allergies or food intolerances? I'll warn you before you eat trigger foods.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)

                // Categories
                VStack(spacing: 20) {
                    // Food Allergies Section
                    AllergySection(
                        title: "Food Allergies",
                        icon: "fork.knife",
                        allergies: CommonAllergy.all.filter { $0.type == .trueAllergy },
                        selectedAllergies: $selectedAllergies,
                        onSelectAllergy: { allergy in
                            showSeverityPicker = allergy
                        }
                    )

                    // Intolerances Section
                    AllergySection(
                        title: "Intolerances",
                        icon: "stomach",
                        allergies: CommonAllergy.all.filter { $0.type == .intolerance || $0.type == .sensitivity },
                        selectedAllergies: $selectedAllergies,
                        onSelectAllergy: { allergy in
                            showSeverityPicker = allergy
                        }
                    )

                    // Cross-Reactive Section
                    AllergySection(
                        title: "Pollen/Cross-Reactive",
                        icon: "leaf.fill",
                        allergies: CommonAllergy.all.filter { $0.type == .crossReactive },
                        selectedAllergies: $selectedAllergies,
                        onSelectAllergy: { allergy in
                            showSeverityPicker = allergy
                        }
                    )
                }
                .padding(.horizontal)

                // None option
                Button(action: {
                    selectedAllergies.removeAll()
                }) {
                    HStack {
                        Image(systemName: selectedAllergies.isEmpty ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedAllergies.isEmpty ? .blue : .gray.opacity(0.5))
                        Text("No allergies or sensitivities")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedAllergies.isEmpty ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    )
                }
                .padding(.horizontal)

                // Selected summary
                if !selectedAllergies.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected (\(selectedAllergies.count)):")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        FlowLayout(spacing: 8) {
                            ForEach(selectedAllergies) { allergy in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(severityColor(allergy.severity))
                                        .frame(width: 8, height: 8)
                                    Text(allergy.name)
                                        .font(.caption)
                                    Button(action: {
                                        selectedAllergies.removeAll { $0.id == allergy.id }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)
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
        .sheet(item: $showSeverityPicker) { allergy in
            SeverityPickerSheet(
                allergyName: allergy.name,
                severity: $tempSeverity,
                onConfirm: {
                    addAllergy(allergy, severity: tempSeverity)
                    showSeverityPicker = nil
                    tempSeverity = .moderate
                },
                onCancel: {
                    showSeverityPicker = nil
                    tempSeverity = .moderate
                }
            )
            .presentationDetents([.height(300)])
        }
    }

    private func addAllergy(_ commonAllergy: CommonAllergy, severity: AllergySeverity) {
        let newAllergy = OnboardingAllergy(
            name: commonAllergy.name,
            type: commonAllergy.type,
            severity: severity,
            crossReactiveItems: commonAllergy.crossReactiveItems
        )
        selectedAllergies.append(newAllergy)
    }

    private func severityColor(_ severity: AllergySeverity) -> Color {
        switch severity {
        case .mild: return .green
        case .moderate: return .yellow
        case .severe: return .red
        }
    }
}

// MARK: - Allergy Section

struct AllergySection: View {
    let title: String
    let icon: String
    let allergies: [CommonAllergy]
    @Binding var selectedAllergies: [OnboardingAllergy]
    let onSelectAllergy: (CommonAllergy) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(allergies, id: \.name) { allergy in
                    let isSelected = selectedAllergies.contains { $0.name == allergy.name }

                    Button(action: {
                        if isSelected {
                            selectedAllergies.removeAll { $0.name == allergy.name }
                        } else {
                            onSelectAllergy(allergy)
                        }
                    }) {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                                .font(.caption)
                            Text(allergy.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Severity Picker Sheet

struct SeverityPickerSheet: View {
    let allergyName: String
    @Binding var severity: AllergySeverity
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("How severe is your \(allergyName) reaction?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top)

                VStack(spacing: 12) {
                    ForEach(AllergySeverity.allCases, id: \.rawValue) { level in
                        Button(action: {
                            severity = level
                        }) {
                            HStack {
                                Circle()
                                    .fill(severityColor(level))
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading) {
                                    Text(level.rawValue)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Text(level.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if severity == level {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(severity == level ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                            )
                        }
                    }
                }
                .padding(.horizontal)

                Button(action: onConfirm) {
                    Text("Add Allergy")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func severityColor(_ severity: AllergySeverity) -> Color {
        switch severity {
        case .mild: return .green
        case .moderate: return .yellow
        case .severe: return .red
        }
    }
}

// MARK: - Make CommonAllergy Identifiable for Sheet

extension CommonAllergy: Identifiable {
    var id: String { name }
}

#Preview {
    OnboardingAllergiesStep(
        selectedAllergies: .constant([]),
        onNext: {},
        onBack: {}
    )
}
