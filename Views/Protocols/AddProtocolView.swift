import SwiftUI
import SwiftData

struct AddProtocolView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var protocolName: String = ""
    @State private var category: String = ""
    @State private var instructions: String = ""
    @State private var frequency: String = ""
    @State private var timeOfDay: String = ""
    @State private var duration: String = ""
    @State private var symptoms: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date?
    @State private var isWishlist: Bool = false
    @State private var tagsString: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Protocol Details")) {
                    TextField("Name", text: $protocolName)
                    TextField("Category", text: $category)
                    TextField("Instructions", text: $instructions)
                    TextField("Frequency", text: $frequency)
                    TextField("Time of Day", text: $timeOfDay)
                    TextField("Duration", text: $duration)
                    TextField("Symptoms (comma-separated)", text: $symptoms)
                    TextField("Tags (comma-separated)", text: $tagsString)
                    Toggle("Wishlist?", isOn: $isWishlist)
                    DatePicker("Start Date", selection: $startDate)
                    DatePicker("End Date", selection: Binding($endDate, replacingNilWith: Date()))
                }

                Button("Save Protocol") {
                    saveProtocol()
                }
                .disabled(protocolName.isEmpty)
            }
            .navigationTitle("Add Protocol")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveProtocol() {
        let newProtocol = TherapyProtocol(
            title: protocolName,
            category: category,
            instructions: instructions,
            frequency: frequency,
            timeOfDay: timeOfDay,
            duration: duration,
            symptoms: symptoms.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            startDate: startDate,
            endDate: endDate,
            notes: nil,
            isWishlist: isWishlist,
            dateAdded: Date(),  // ✅ Moved `dateAdded` before `tags`
            tags: tagsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        )

        modelContext.insert(newProtocol)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            Logger.error(error, message: "Error saving new protocol", category: .data)
        }
    }
}
