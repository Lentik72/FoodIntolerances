import SwiftUI
import SwiftData

struct ProtocolTagsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var protocols: [TherapyProtocol]
    
    var allTags: [String] {
        var tags = Set<String>()
        for proto in protocols {
            if let protocolTags = proto.tags {
                tags.formUnion(protocolTags)
            }
        }
        return Array(tags).sorted()
    }
    
    @State private var selectedTags: Set<String> = []
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Browse by Tag")
                .font(.title)
                .padding()
            
            // Tags flow layout
            FlowLayout(spacing: 8) {
                ForEach(allTags, id: \.self) { tag in
                    Button(action: {
                        toggleTag(tag)
                    }) {
                        Text(tag)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedTags.contains(tag) ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(selectedTags.contains(tag) ? .white : .primary)
                            .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal)
            
            // Filtered protocols
            if !selectedTags.isEmpty {
                List {
                    ForEach(filteredProtocols) { proto in
                        NavigationLink(destination: ProtocolDetailView(therapyProtocol: proto)) {
                            VStack(alignment: .leading) {
                                Text(proto.title)
                                    .font(.headline)
                                
                                Text(proto.category)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                if let tags = proto.tags, !tags.isEmpty {
                                    HStack {
                                        ForEach(tags.prefix(3), id: \.self) { tag in
                                            Text(tag)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(8)
                                        }
                                        
                                        if (tags.count > 3) {
                                            Text("+\(tags.count - 3) more")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Select tags to filter protocols")
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Spacer()
        }
    }
    
    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
    
    private var filteredProtocols: [TherapyProtocol] {
        guard !selectedTags.isEmpty else { return [] }
        
        return protocols.filter { proto in
            guard let tags = proto.tags else { return false }
            return !selectedTags.isDisjoint(with: Set(tags))
        }
    }
}
