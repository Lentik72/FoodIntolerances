//
//  AddProtocolItemSheet.swift
//  Food IntolerancesI am choosing options
//
//  Created by Leo on 2/1/25.
//

import SwiftUI
import SwiftData

struct AddProtocolItemSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var therapyProtocol: TherapyProtocol

    @State private var itemName: String = ""
    @State private var quantity: String = ""
    @State private var usageNotes: String = ""

    @Query private var allCabinetItems: [CabinetItem]
    @State private var selectedCabinet: CabinetItem? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Info") {
                    TextField("Name", text: $itemName)
                    TextField("Dosage or Quantity", text: $quantity)
                    TextField("Usage Notes", text: $usageNotes)
                }
                if !allCabinetItems.isEmpty {
                    Section("Pick from Cabinet") {
                        Picker("Cabinet Item", selection: $selectedCabinet) {
                            Text("None").tag(CabinetItem?.none)
                            ForEach(allCabinetItems) { c in
                                Text(c.name).tag(CabinetItem?.some(c))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addProtocolItem()
                    }
                }
            }
        }
    }

    private func addProtocolItem() {
        guard !itemName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let newItem = TherapyProtocolItem(
            itemName: itemName,
            parentProtocol: therapyProtocol,
            dosageOrQuantity: quantity,
            usageNotes: usageNotes,
            cabinetItem: selectedCabinet
        )
        // Append the new item explicitly to the parent protocol's items array
        therapyProtocol.items.append(newItem)
        modelContext.insert(newItem)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving ProtocolItem: \(error)")
        }
    }
}

struct AddProtocolItemSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddProtocolItemSheet(therapyProtocol: TherapyProtocol(
            title: "Sample Protocol",
            category: "Medication",
            instructions: "Take as directed",
            frequency: "Twice a day",
            timeOfDay: "Morning and Evening",
            duration: "1 week",
            symptoms: ["Headache"],
            startDate: Date(),
            endDate: nil,
            notes: nil,
            isWishlist: false,
            dateAdded: Date(),
            tags: ["Pain"]
        ))
        .modelContainer(for: [CabinetItem.self, TherapyProtocol.self, TherapyProtocolItem.self], inMemory: true)
    }
}
