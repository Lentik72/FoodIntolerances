import SwiftUI
import SwiftData

struct ProtocolRowView: View {
    @Environment(\.modelContext) private var modelContext
    var therapyProtocol: TherapyProtocol
    
    @State private var showDetails = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(therapyProtocol.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(therapyProtocol.status)
                    .font(.subheadline)
                    .foregroundColor(therapyProtocol.status == "Active" ? .green : .gray)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                Button(action: toggleProtocolStatus) {
                    Image(systemName: therapyProtocol.status == "Active" ? "pause.circle.fill" : "play.circle.fill")
                        .foregroundColor(therapyProtocol.status == "Active" ? .yellow : .green)
                }
                .accessibilityLabel(therapyProtocol.status == "Active" ? "Deactivate Protocol" : "Activate Protocol")
                
                Button(action: { showDetails = true }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("View Protocol Details")
            }
        }
        .padding(.vertical, 5)
        .sheet(isPresented: $showDetails) {
            ProtocolDetailView(therapyProtocol: therapyProtocol)
        }
    }

    private func toggleProtocolStatus() {
        therapyProtocol.status = (therapyProtocol.status == "Active") ? "Inactive" : "Active"
        do {
            try modelContext.save()
        } catch {
            print("Error saving protocol status: \(error)")
        }
    }
}

struct ProtocolRowView_Previews: PreviewProvider {
    static var previews: some View {
        ProtocolRowView(therapyProtocol: TherapyProtocol(
            title: "Example Protocol",
            category: "Medication",
            instructions: "Take 1 pill daily",
            frequency: "Daily",
            timeOfDay: "Morning",
            duration: "30 days",
            symptoms: ["Headache"],
            startDate: Date(),
            endDate: nil,
            notes: "Sample notes",
            isWishlist: false,
            dateAdded: Date(),
            tags: ["Pain", "Relief"]
        ))
        .modelContainer(for: [TherapyProtocol.self], inMemory: true)
    }
}
