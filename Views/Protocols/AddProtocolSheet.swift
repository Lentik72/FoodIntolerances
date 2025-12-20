import SwiftUI
import SwiftData

struct AddProtocolSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    // Protocol Fields
    @State private var protocolName: String = ""
    @State private var category: String = "Unassigned"
    @State private var customCategory: String = ""
    @State private var instructions: String = ""
    @State private var isWishlist: Bool = false
    @State private var isActive: Bool = true
    @State private var startDate: Date = Date()
    @State private var endDate: Date? = nil

    // Frequency & Reminder Settings
    @State private var frequency: String = "Daily"
    @State private var reminderTimes: [Date] = [Date()]
    @State private var duration: Int = 7
    @State private var enableReminder: Bool = false

    // Symptoms & Tags
    @State private var symptomsString: String = ""
    @State private var tagsString: String = ""
    @State private var notes: String = ""

    // Protocol Items
    @Query private var allCabinetItems: [CabinetItem]
    @State private var selectedCabinetItems: Set<CabinetItem> = []

    @State private var predefinedCategories = ["Digestive Health", "Mental Wellness", "Physical Therapy", "Sleep Improvement", "Unassigned"]
    @State private var protocolItems: [TherapyProtocolItemInput] = []

    var body: some View {
        NavigationView {
            Form {
                // 📌 GENERAL INFORMATION
                Section(header: Text("Protocol Info").font(.headline)) {
                    TextField("Protocol Name", text: $protocolName)

                    Picker("Category", selection: $category) {
                        ForEach(predefinedCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                        Text("Custom...").tag("Custom")
                    }
                    .onChange(of: category) { oldValue, newValue in
                        if newValue == "Custom" {
                            customCategory = ""
                        }
                    }

                    if category == "Custom" {
                        TextField("Enter Custom Category", text: $customCategory)
                            .onChange(of: customCategory) { oldValue, newValue in
                                if !newValue.isEmpty {
                                    category = newValue
                                }
                            }
                    }

                    Toggle("Active Protocol", isOn: $isActive)
                }

                // 🕰️ INSTRUCTIONS & TIMING
                Section(header: Text("Instructions & Timing").font(.headline)) {
                    TextField("Instructions", text: $instructions)

                    Picker("Frequency", selection: $frequency) {
                        Text("Daily").tag("Daily")
                        Text("Multiple Times a Day").tag("Multiple")
                        Text("Every Other Day").tag("Every Other Day")
                        Text("Weekly").tag("Weekly")
                        Text("Monthly").tag("Monthly")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)

                    Stepper("Duration: \(duration) days", value: $duration, in: 1...365)
                        .onChange(of: duration) { oldValue, newValue in
                            endDate = Calendar.current.date(byAdding: .day, value: duration, to: startDate)
                        }

                    if let endDate = endDate {
                        Text("End Date: \(endDate.formatted(date: .long, time: .omitted))")
                            .foregroundColor(.secondary)
                    }

                    Toggle("Enable Reminder", isOn: $enableReminder)

                    if enableReminder {
                        if frequency == "Multiple" {
                            ForEach(0..<reminderTimes.count, id: \.self) { index in
                                DatePicker("Reminder \(index + 1)", selection: $reminderTimes[index], displayedComponents: .hourAndMinute)
                            }
                            Button("Add Reminder Time") {
                                reminderTimes.append(Date())
                            }
                        } else {
                            DatePicker("Reminder Time", selection: $reminderTimes[0], displayedComponents: .hourAndMinute)
                        }
                    }
                }

                // 📝 SYMPTOMS & NOTES
                Section(header: Text("Symptoms & Notes").font(.headline)) {
                    TextField("Symptoms (comma-separated)", text: $symptomsString)
                    TextField("Tags (comma-separated)", text: $tagsString)
                    Toggle("Wishlist?", isOn: $isWishlist)
                    TextField("Notes", text: $notes)
                }

                // 📋 PROTOCOL ITEMS (Now allows multiple selections)
                Section(header: Text("Protocol Items").font(.headline)) {
                    ForEach(allCabinetItems) { item in
                        MultipleSelectionRow(item: item, isSelected: selectedCabinetItems.contains(item)) {
                            if selectedCabinetItems.contains(item) {
                                selectedCabinetItems.remove(item)
                            } else {
                                selectedCabinetItems.insert(item)
                            }
                        }
                    }
                }

                Button("Add Protocol") {
                    addProtocol()
                }
                .disabled(protocolName.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
            }
            .navigationTitle("New Protocol")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }

    // MARK: - Helper Methods
    private func addProtocol() {
        let newProtocol = TherapyProtocol(
            title: protocolName,
            category: category.isEmpty ? "Unassigned" : category,
            instructions: instructions,
            frequency: frequency,
            timeOfDay: enableReminder ? reminderTimes.first?.formatted(date: .omitted, time: .shortened) ?? "" : "",
            duration: "\(duration) days",
            symptoms: symptomsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            startDate: startDate,
            endDate: endDate,
            notes: notes.isEmpty ? nil : notes,
            isWishlist: isWishlist,
            isActive: isActive,
            dateAdded: Date(),
            tags: tagsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            enableReminder: enableReminder,
            reminderTime: enableReminder ? reminderTimes.first : nil
        )

        for cabinetItem in selectedCabinetItems {
            let newItem = TherapyProtocolItem(
                itemName: cabinetItem.name,
                parentProtocol: newProtocol,
                dosageOrQuantity: cabinetItem.quantity ?? "",
                usageNotes: cabinetItem.notes ?? "",
                cabinetItem: cabinetItem
            )
            newProtocol.items.append(newItem)
            modelContext.insert(newItem)
        }

        modelContext.insert(newProtocol)
        do {
            try modelContext.save()
            isPresented = false
        } catch {
            print("❌ Error saving new protocol: \(error)")
        }
    }
}

// Helper for multi-selection
struct MultipleSelectionRow: View {
    var item: CabinetItem
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(item.name)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}
