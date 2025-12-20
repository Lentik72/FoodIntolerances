import SwiftUI
import SwiftData

struct ProtocolStatusView: View {
    @Environment(\.modelContext) private var modelContext
    let protocolID: UUID
    
    @Query private var protocols: [TherapyProtocol]
    
    private var associatedProtocol: TherapyProtocol? {
        protocols.first { $0.id == protocolID }
    }
    
    var body: some View {
        if let proto = associatedProtocol {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "pills.circle.fill")
                        .foregroundColor(.blue)
                    Text("Protocol: \(proto.title)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                if proto.isActive {
                    Text("Status: Active")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("Status: Inactive")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                if let effectiveness = proto.protocolEffectiveness {
                    HStack {
                        Text("Effectiveness:")
                            .font(.caption)
                        // Star rating
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= effectiveness ? "star.fill" : "star")
                                    .foregroundColor(.yellow)
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

#Preview {
    ProtocolStatusView(protocolID: UUID())
        .modelContainer(for: [TherapyProtocol.self], inMemory: true)
}
