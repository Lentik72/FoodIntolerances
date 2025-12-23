import SwiftUI
import SwiftData

struct CabinetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\CabinetItem.name, order: .forward)])
    private var cabinetItems: [CabinetItem]

    @State private var showAddSheet = false
    @State private var selectedItemForEditing: CabinetItem?
    @State private var showEditSheet = false
    @State private var showSaveError = false

    var body: some View {
        NavigationStack {
            List(cabinetItems, id: \.id) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                    if let quantity = item.quantity, !quantity.isEmpty {
                        Text("Quantity: \(quantity)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let dosage = item.dosage, !dosage.isEmpty {
                        Text("Dosage: \(dosage)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let ingredients = item.ingredients, !ingredients.isEmpty {
                        Text("Ingredients: \(ingredients)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let notes = item.notes, !notes.isEmpty {
                        Text("Notes: \(notes)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastUsed = item.lastUsed {
                        Text("Last used: \(lastUsed.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let currentStock = item.currentStock {
                        HStack {
                            Text("Stock: \(currentStock)")
                                .font(.caption)
                                .foregroundColor(
                                    item.refillThreshold != nil && currentStock <= (item.refillThreshold ?? 0)
                                    ? .red
                                    : .secondary
                                )
                            
                            if item.refillNotificationEnabled, let threshold = item.refillThreshold, currentStock <= threshold {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    HStack {
                        Button(action: {
                            item.logUsage()
                            _ = SaveHelper.save(context: modelContext, showError: $showSaveError)
                        }) {
                            Label("Log Use", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }

                        if let stock = item.currentStock, stock <= (item.refillThreshold ?? 0) {
                            Button(action: {
                                // Functionality to mark as refilled
                                item.currentStock = Int(item.quantity ?? "0") ?? 10
                                _ = SaveHelper.save(context: modelContext, showError: $showSaveError)
                            }) {
                                Label("Refilled", systemImage: "arrow.clockwise.circle")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                .contextMenu {
                    Button("Edit") {
                        selectedItemForEditing = item
                        showEditSheet = true
                    }
                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Cabinet")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAddSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddCabinetItemSheet(isPresented: $showAddSheet)
            }
            .sheet(item: $selectedItemForEditing) { item in
                EditCabinetItemSheet(item: item) // ✅ Removed isPresented
            }
            .saveErrorAlert(isPresented: $showSaveError)
        }
    }

    private func deleteItem(_ item: CabinetItem) {
        modelContext.delete(item)
        do {
            try modelContext.save()
        } catch {
            Logger.error(error, message: "Error deleting CabinetItem", category: .data)
        }
    }
}

// MARK: - Add Cabinet Item Sheet

struct AddCabinetItemSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var quantity: String = ""
    @State private var dosage: String = ""
    @State private var ingredients: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Cabinet Item Details") {
                    TextField("Name", text: $name)
                    TextField("Quantity", text: $quantity)
                    TextField("Dosage", text: $dosage)
                    TextField("Ingredients", text: $ingredients)
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let newItem = CabinetItem(
                            name: name,
                            quantity: quantity.isEmpty ? nil : quantity, // ✅ Correct Order
                            notes: notes.isEmpty ? nil : notes,
                            dosage: dosage.isEmpty ? nil : dosage,
                            ingredients: ingredients.isEmpty ? nil : ingredients
                        )
                        modelContext.insert(newItem)
                        do {
                            try modelContext.save()
                            isPresented = false
                        } catch {
                            Logger.error(error, message: "Error saving new cabinet item", category: .data)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Edit Cabinet Item Sheet

struct EditCabinetItemSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss // ✅ Dismiss environment
    @State var item: CabinetItem

    var body: some View {
        NavigationStack {
            Form {
                Section("Edit Item") {
                    TextField("Name", text: $item.name)
                    TextField("Quantity", text: Binding($item.quantity, replacingNilWith: ""))
                    TextField("Dosage", text: Binding($item.dosage, replacingNilWith: ""))
                    TextField("Ingredients", text: Binding($item.ingredients, replacingNilWith: ""))
                    TextField("Notes", text: Binding($item.notes, replacingNilWith: ""))
                }
            }
            .navigationTitle("Edit Item")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss() // ✅ Close the sheet immediately on cancel
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
            dismiss() // ✅ Close the sheet immediately after saving
        } catch {
            Logger.error(error, message: "Error saving changes", category: .data)
        }
    }
}

// MARK: - Binding Helper for Optionals
extension Binding where Value == String? {
    init(_ source: Binding<String?>, replacingNilWith defaultValue: String) {
        self.init(
            get: { source.wrappedValue ?? defaultValue },
            set: { newValue in
                if let value = newValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    source.wrappedValue = value
                } else {
                    source.wrappedValue = nil
                }
            }
        )
    }
}
