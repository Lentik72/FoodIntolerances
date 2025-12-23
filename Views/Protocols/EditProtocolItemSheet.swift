import SwiftUI
import SwiftData

struct EditProtocolItemSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var protocolItem: TherapyProtocolItem
    @Binding var isPresented: Bool
    @Query private var allCabinetItems: [CabinetItem]

    var body: some View {
        Form {
            TextField("Item Name", text: $protocolItem.itemName)
            TextField("Dosage", text: Binding($protocolItem.dosageOrQuantity, replacingNilWith: ""))
            TextField("Usage Notes", text: Binding($protocolItem.usageNotes, replacingNilWith: ""))
            
            Picker("Cabinet Item", selection: Binding(
                get: { protocolItem.cabinetItem },
                set: { newValue in protocolItem.cabinetItem = newValue }
            )) {
                Text("None").tag(CabinetItem?.none) // Keep the "None" option
                ForEach(allCabinetItems) { item in
                    Text(item.name).tag(CabinetItem?.some(item))
                }
            }

            Button("Save") {
                do {
                    try modelContext.save()
                    isPresented = false
                } catch {
                    Logger.error(error, message: "Error saving item", category: .data)
                }
            }
        }
        .navigationTitle("Edit Protocol Item")
    }
}
