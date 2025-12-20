import SwiftUI
import SwiftData

struct DebugTrackedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trackedItems: [TrackedItem]

    var body: some View {
        List {
            ForEach(trackedItems) { item in
                VStack(alignment: .leading) {
                    Text(item.name)
                        .font(.headline)
                    Text("Type: \(item.type.rawValue)")
                        .font(.subheadline)
                    if let brand = item.brand {
                        Text("Brand: \(brand)")
                            .font(.caption)
                    }
                    Text("Start Date: \(item.startDate, formatter: dateFormatter)")
                        .font(.caption2)
                    Text("Notes: \(item.notes)")
                        .font(.caption2)
                    Text("Active: \(item.isActive ? "Yes" : "No")")
                        .font(.caption2)
                }
                .padding(.vertical, 5)
            }
        }
        .navigationTitle("Debug Tracked Items")
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
}

// MARK: - Preview
struct DebugTrackedItemsView_Previews: PreviewProvider {
    static var previews: some View {
        DebugTrackedItemsView()
            .modelContainer(for: [TrackedItem.self], inMemory: true)
    }
}
