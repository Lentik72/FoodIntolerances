import SwiftUI

struct RecentProtocolsSection: View {
    let protocols: [TherapyProtocol]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Protocols")
                .font(.title2)
                .bold()

            if protocols.isEmpty {
                Text("No active protocols available.")
                    .foregroundColor(.gray)
            } else {
                ForEach(protocols) { therapyProtocol in
                    NavigationLink(destination: ProtocolDetailView(therapyProtocol: therapyProtocol)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(therapyProtocol.title)
                                    .font(.headline)
                                Text("Added on \(therapyProtocol.dateAdded.formatted(.dateTime.month().day().year()))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
}
