import SwiftUI
import SwiftData

struct ProtocolItemEditor: View {
    @Binding var input: TherapyProtocolItemInput
    var cabinetItems: [CabinetItem]  // Passed from EditProtocolSheet

    @State private var useCabinet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Item Name", text: $input.itemName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Dosage/Quantity", text: $input.dosageOrQuantity)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Usage Notes", text: $input.usageNotes)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Toggle("Pick from Cabinet?", isOn: $useCabinet)

            if useCabinet && !cabinetItems.isEmpty {
                Picker("Select Cabinet Item", selection: $input.selectedCabinetItem) {
                    Text("None").tag(CabinetItem?.none)
                    ForEach(cabinetItems) { item in
                        Text(item.name).tag(CabinetItem?.some(item))
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
