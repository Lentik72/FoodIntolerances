import SwiftUI
import SwiftData

struct AddTrackedItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var type: TrackedItemType = .food
    @State private var brand: String = ""
    @State private var startDate: Date = Date()
    @State private var notes: String = ""
    @State private var isActive: Bool = true

    enum AddItemAlert: Identifiable {
        case confirmation
        case validationError
        case saveError(String)

        var id: String {
            switch self {
            case .confirmation:
                return "AddItemAlert_confirmation"
            case .validationError:
                return "AddItemAlert_validationError"
            case .saveError(let message):
                return "AddItemAlert_saveError_" + message
            }
        }
    }

    @State private var activeAlert: AddItemAlert?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Item Details")) {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(TrackedItemType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    TextField("Brand (optional)", text: $brand)
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Toggle("Is Active", isOn: $isActive)
                }

                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
            }
            .navigationTitle("Add Tracked Item")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save") {
                    saveItem()
                }
            )
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .confirmation:
                    return Alert(
                        title: Text("Success"),
                        message: Text("Tracked item added successfully."),
                        dismissButton: .default(Text("OK")) {
                            dismiss()
                        }
                    )
                case .validationError:
                    return Alert(
                        title: Text("Validation Error"),
                        message: Text("Please enter a valid name."),
                        dismissButton: .default(Text("OK"))
                    )
                case .saveError(let message):
                    return Alert(
                        title: Text("Save Error"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }

    private func saveItem() {
        Logger.debug("saveItem() called", category: .data)

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            Logger.debug("Validation failed: Name is empty", category: .data)
            activeAlert = .validationError
            return
        }

        let newItem = TrackedItem(
            name: trimmedName,
            type: type,
            brand: brand.isEmpty ? nil : brand,
            startDate: startDate,
            notes: notes,
            isActive: isActive
        )

        modelContext.insert(newItem)
        Logger.debug("Inserted new TrackedItem: \(newItem)", category: .data)

        do {
            try modelContext.save()
            Logger.info("modelContext.save() succeeded", category: .data)
            activeAlert = .confirmation
        } catch {
            Logger.error(error, message: "modelContext.save() failed", category: .data)
            activeAlert = .saveError("Failed to save the tracked item. Please try again.")
        }
    }
}

// MARK: - Preview
struct AddTrackedItemView_Previews: PreviewProvider {
    static var previews: some View {
        AddTrackedItemView()
            .modelContainer(for: [TrackedItem.self], inMemory: true)
    }
}
