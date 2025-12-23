import SwiftUI
import SwiftData

struct AddAvoidedItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var itemName: String = ""
    @State private var itemType: AvoidedItemType = .food
    @State private var reason: String = ""
    @State private var showAlert: Bool = false
    @State private var isRecommended: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Item Details")) {
                    TextField("Item Name", text: $itemName)
                        .autocapitalization(.words)

                    Picker("Item Type", selection: $itemType) {
                        ForEach(AvoidedItemType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    TextField("Reason (optional)", text: $reason)
                        .autocapitalization(.sentences)
                    
                    Toggle("Add as Recommendation", isOn: $isRecommended)
                        .help("When enabled, this item will be added to the 'Recommended to Avoid' section")
                }
                Button("Add to Avoid List") {
                    addItem()
                }
                .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Add Avoid Item")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text("Item name cannot be empty."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func addItem() {
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showAlert = true
            return
        }
        
        let newItem = AvoidedItem(
            name: trimmed,
            type: itemType,
            reason: reason.isEmpty ? nil : reason,
            isRecommended: isRecommended 
        )
        
        modelContext.insert(newItem)
        do {
            try modelContext.save()
            Logger.info("Successfully saved new AvoidedItem: \(newItem.name)", category: .data)
            dismiss()
        } catch {
            Logger.error(error, message: "Error saving avoid item", category: .data)
        }
    }
}
