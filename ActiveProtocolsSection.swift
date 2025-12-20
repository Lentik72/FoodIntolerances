import SwiftUI

struct ActiveProtocolsSection: View {
    let protocols: [TherapyProtocol]  // Update from ProtocolGroup to TherapyProtocol

    var body: some View {
        VStack(alignment: .leading) {
            Text("Active Protocols")
                .font(.headline)

            if protocols.isEmpty {
                Text("No active protocols.")
                    .foregroundColor(.gray)
            } else {
                ForEach(protocols) { therapyProtocol in
                    HStack {
                        Text(therapyProtocol.title)  // Change groupName to title
                        Spacer()
                        Text(therapyProtocol.isActive ? "Active" : "Inactive")
                            .foregroundColor(therapyProtocol.isActive ? .green : .gray)
                    }
                }
            }
        }
    }
}
