import SwiftUI
import SwiftData

struct EditTrackedItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Bindable var trackedItem: TrackedItem
    
    enum EditItemAlert: Identifiable {
        case confirmation
        case validationError
        case saveError(String)

        var id: String {
            switch self {
            case .confirmation:
                return "EditItemAlert_confirmation"
            case .validationError:
                return "EditItemAlert_validationError"
            case .saveError(let message):
                return "EditItemAlert_saveError_" + message
            }
        }
    }

    @State private var activeAlert: EditItemAlert?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Item Details")) {
                    TextField("Name", text: $trackedItem.name)

                    Picker("Type", selection: $trackedItem.type) {
                        ForEach(TrackedItemType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    TextField("Brand (optional)", text: brandBinding)
                    
                    DatePicker("Start Date", selection: $trackedItem.startDate, displayedComponents: .date)
                    Toggle("Is Active", isOn: $trackedItem.isActive)
                }

                Section(header: Text("Notes")) {
                    TextEditor(text: $trackedItem.notes)
                        .frame(height: 100)
                }
            }
            .navigationTitle("Edit Tracked Item")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                },
                trailing: Button("Save Changes") {
                    saveChanges()
                }
            )
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .confirmation:
                    return Alert(
                        title: Text("Success"),
                        message: Text("Tracked item updated successfully."),
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

    private var brandBinding: Binding<String> {
        Binding<String>(
            get: { trackedItem.brand ?? "" },
            set: { newValue in
                trackedItem.brand = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private func saveChanges() {
        print("saveChanges() called")

        let trimmedName = trackedItem.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            print("Validation failed: Name is empty")
            activeAlert = .validationError
            return
        }

        do {
            try modelContext.save()
            print("modelContext.save() succeeded in EditTrackedItemView")
            activeAlert = .confirmation
        } catch {
            print("modelContext.save() failed with error: \(error)")
            activeAlert = .saveError("Failed to save changes. Please try again.")
        }
    }
}

// MARK: - Preview
struct EditTrackedItemView_Previews: PreviewProvider {
    static var previews: some View {
        let sample = TrackedItem(name: "Sample", type: .food)
        EditTrackedItemView(trackedItem: sample)
            .modelContainer(for: [TrackedItem.self], inMemory: true)
    }
}
