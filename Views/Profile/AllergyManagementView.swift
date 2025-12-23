import SwiftUI
import SwiftData

/// View for managing allergies and sensitivities
struct AllergyManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserAllergy.name) private var allergies: [UserAllergy]

    @State private var showAddAllergy = false

    var body: some View {
        List {
            if allergies.isEmpty {
                ContentUnavailableView(
                    "No Allergies Added",
                    systemImage: "allergens",
                    description: Text("Add your allergies and sensitivities to get food safety warnings")
                )
            } else {
                // Group by type
                ForEach(groupedAllergies.keys.sorted(), id: \.self) { type in
                    Section(type) {
                        ForEach(groupedAllergies[type] ?? []) { allergy in
                            NavigationLink(destination: AllergyDetailView(allergy: allergy)) {
                                AllergyRow(allergy: allergy)
                            }
                        }
                        .onDelete { indexSet in
                            deleteAllergies(at: indexSet, in: type)
                        }
                    }
                }
            }
        }
        .navigationTitle("Allergies")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddAllergy = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddAllergy) {
            AddAllergyView()
        }
    }

    private var groupedAllergies: [String: [UserAllergy]] {
        Dictionary(grouping: allergies) { $0.allergyType }
    }

    private func deleteAllergies(at offsets: IndexSet, in type: String) {
        guard let allergiesInType = groupedAllergies[type] else { return }
        for index in offsets {
            modelContext.delete(allergiesInType[index])
        }
    }
}

// MARK: - Allergy Row

struct AllergyRow: View {
    let allergy: UserAllergy

    var body: some View {
        HStack(spacing: 12) {
            // Severity indicator
            Circle()
                .fill(severityColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(allergy.name)
                    .font(.headline)

                HStack(spacing: 4) {
                    Text(allergy.severityEnum.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !allergy.crossReactiveItems.isEmpty {
                        Text("• \(allergy.crossReactiveItems.count) cross-reactive")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: allergy.allergyTypeEnum.icon)
                .foregroundColor(.secondary)
        }
    }

    private var severityColor: Color {
        switch allergy.severityEnum {
        case .mild: return .green
        case .moderate: return .yellow
        case .severe: return .red
        }
    }
}

// MARK: - Allergy Detail View

struct AllergyDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let allergy: UserAllergy

    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            // Basic Info
            Section("Information") {
                LabeledContent("Type", value: allergy.allergyTypeEnum.rawValue)
                LabeledContent("Severity", value: allergy.severityEnum.rawValue)

                if let dateDiscovered = allergy.dateDiscovered {
                    LabeledContent("Discovered", value: dateDiscovered, format: .dateTime.year().month())
                }

                LabeledContent("Added", value: allergy.dateAdded, format: .dateTime.year().month().day())
            }

            // Reactions
            if !allergy.knownReactions.isEmpty {
                Section("Known Reactions") {
                    ForEach(allergy.knownReactions, id: \.self) { reaction in
                        Label(reaction, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                }
            }

            // Cross-reactive items
            if !allergy.crossReactiveItems.isEmpty {
                Section {
                    ForEach(allergy.crossReactiveItems, id: \.self) { item in
                        Text(item)
                    }
                } header: {
                    Text("Cross-Reactive Foods")
                } footer: {
                    Text("These foods may cause similar reactions due to related proteins")
                }
            }

            // Helpful medications
            if !allergy.helpfulMedications.isEmpty {
                Section("Helpful Medications") {
                    ForEach(allergy.helpfulMedications, id: \.self) { med in
                        Label(med, systemImage: "pills")
                    }
                }
            }

            // Notes
            if let notes = allergy.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            // Delete
            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Allergy", systemImage: "trash")
                }
            }
        }
        .navigationTitle(allergy.name)
        .confirmationDialog(
            "Delete Allergy",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(allergy)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this allergy? You won't receive warnings about this allergen.")
        }
    }
}

// MARK: - Add Allergy View

struct AddAllergyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var allergyType: AllergyType = .trueAllergy
    @State private var severity: AllergySeverity = .moderate
    @State private var knownReactions: [String] = []
    @State private var crossReactiveItems: [String] = []
    @State private var helpfulMedications: [String] = []
    @State private var notes: String = ""
    @State private var diagnosedByDoctor: Bool = false
    @State private var dateDiscovered: Date = Date()
    @State private var hasDiscoveryDate: Bool = false

    @State private var showCommonAllergies = true
    @State private var newReaction: String = ""
    @State private var newCrossReactive: String = ""
    @State private var newMedication: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // Quick add from common allergies
                if showCommonAllergies {
                    Section {
                        Text("Select from common allergies or add custom below")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CommonAllergy.all.prefix(8), id: \.name) { common in
                                    Button(action: {
                                        selectCommonAllergy(common)
                                    }) {
                                        Text(common.name)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        }
                    }
                }

                // Basic Info
                Section("Allergy Information") {
                    TextField("Allergy Name", text: $name)

                    Picker("Type", selection: $allergyType) {
                        ForEach(AllergyType.allCases, id: \.rawValue) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    Picker("Severity", selection: $severity) {
                        ForEach(AllergySeverity.allCases, id: \.rawValue) { sev in
                            HStack {
                                Circle()
                                    .fill(severityColor(sev))
                                    .frame(width: 8, height: 8)
                                Text(sev.rawValue)
                            }
                            .tag(sev)
                        }
                    }

                    Toggle("Diagnosed by Doctor", isOn: $diagnosedByDoctor)

                    Toggle("I know when I discovered it", isOn: $hasDiscoveryDate)
                    if hasDiscoveryDate {
                        DatePicker("Discovered", selection: $dateDiscovered, displayedComponents: .date)
                    }
                }

                // Known Reactions
                Section {
                    ForEach(knownReactions, id: \.self) { reaction in
                        Text(reaction)
                    }
                    .onDelete { indexSet in
                        knownReactions.remove(atOffsets: indexSet)
                    }

                    HStack {
                        TextField("Add reaction", text: $newReaction)
                        Button(action: {
                            if !newReaction.isEmpty {
                                knownReactions.append(newReaction)
                                newReaction = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newReaction.isEmpty)
                    }
                } header: {
                    Text("Known Reactions")
                } footer: {
                    Text("e.g., Hives, Swelling, Difficulty breathing")
                }

                // Cross-reactive items
                Section {
                    ForEach(crossReactiveItems, id: \.self) { item in
                        Text(item)
                    }
                    .onDelete { indexSet in
                        crossReactiveItems.remove(atOffsets: indexSet)
                    }

                    HStack {
                        TextField("Add food", text: $newCrossReactive)
                        Button(action: {
                            if !newCrossReactive.isEmpty {
                                crossReactiveItems.append(newCrossReactive)
                                newCrossReactive = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newCrossReactive.isEmpty)
                    }
                } header: {
                    Text("Cross-Reactive Foods")
                } footer: {
                    Text("Foods that may cause similar reactions")
                }

                // Helpful medications
                Section {
                    ForEach(helpfulMedications, id: \.self) { med in
                        Text(med)
                    }
                    .onDelete { indexSet in
                        helpfulMedications.remove(atOffsets: indexSet)
                    }

                    HStack {
                        TextField("Add medication", text: $newMedication)
                        Button(action: {
                            if !newMedication.isEmpty {
                                helpfulMedications.append(newMedication)
                                newMedication = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newMedication.isEmpty)
                    }
                } header: {
                    Text("Helpful Medications")
                } footer: {
                    Text("e.g., Benadryl, EpiPen")
                }

                // Notes
                Section("Additional Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .navigationTitle("Add Allergy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAllergy()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func selectCommonAllergy(_ common: CommonAllergy) {
        name = common.name
        allergyType = common.type
        knownReactions = common.commonReactions
        crossReactiveItems = common.crossReactiveItems
        showCommonAllergies = false
    }

    private func severityColor(_ severity: AllergySeverity) -> Color {
        switch severity {
        case .mild: return .green
        case .moderate: return .yellow
        case .severe: return .red
        }
    }

    private func saveAllergy() {
        let allergy = UserAllergy(
            name: name,
            allergyType: allergyType,
            severity: severity,
            dateDiscovered: hasDiscoveryDate ? dateDiscovered : nil,
            knownReactions: knownReactions,
            crossReactiveItems: crossReactiveItems,
            helpfulMedications: helpfulMedications,
            notes: notes.isEmpty ? nil : notes,
            diagnosedByDoctor: diagnosedByDoctor
        )

        modelContext.insert(allergy)

        do {
            try modelContext.save()
            Logger.info("Allergy '\(name)' saved successfully", category: .data)
            dismiss()
        } catch {
            Logger.error(error, message: "Failed to save allergy", category: .data)
        }
    }
}

#Preview("Allergy Management") {
    NavigationStack {
        AllergyManagementView()
    }
    .modelContainer(for: [UserAllergy.self], inMemory: true)
}

#Preview("Add Allergy") {
    AddAllergyView()
        .modelContainer(for: [UserAllergy.self], inMemory: true)
}
