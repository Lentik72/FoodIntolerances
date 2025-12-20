import SwiftUI

// MARK: - PROTOCOL ITEM CARD (Reusable UI Component)
struct ProtocolItemCard: View {
    let item: TherapyProtocolItem
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.itemName)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }

            if let dose = item.dosageOrQuantity, !dose.isEmpty {
                HStack {
                    Image(systemName: "pills.fill")
                        .foregroundColor(.blue)
                    Text(dose)
                        .foregroundColor(.secondary)
                }
            }

            if let usage = item.usageNotes, !usage.isEmpty {
                HStack {
                    Image(systemName: "note.text")
                        .foregroundColor(.green)
                    Text(usage)
                        .foregroundColor(.secondary)
                }
            }

            if let cabinetItem = item.cabinetItem {
                HStack {
                    Image(systemName: "archivebox.fill")
                        .foregroundColor(.purple)
                    Text("Cabinet: \(cabinetItem.name)")
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
        .onTapGesture {
            onTap()
        }
    }
}
