import SwiftUI
import SwiftData

struct ProtocolRecommendationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: LogItemViewModel
    
    // Optional parameters for when called from LogSymptomView
    var selectedSymptoms: Set<String>? = nil
    var onSkip: (() -> Void)? = nil
    var onSelectProtocol: ((TherapyProtocol) -> Void)? = nil
    
    // State for internal use
    @State private var activeSymptom: String = ""
    @State private var selectedCategory: String = "All"
    @State private var filteredProtocols: [TherapyProtocol] = []
    
    @Query private var logs: [LogEntry]
    @Query(sort: [SortDescriptor(\TherapyProtocol.dateAdded, order: .reverse)])
    private var protocols: [TherapyProtocol]
    
    /// Available categories for filtering (dynamic based on existing protocols)
    private var categories: [String] {
        let allCategories = protocols.map { $0.category }
        return ["All"] + Array(Set(allCategories)).sorted()
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Search & Filter UI
                // Only show if not called with specific symptoms
                if selectedSymptoms == nil {
                    HStack {
                        TextField("Search by symptom...", text: $activeSymptom)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                            .onChange(of: activeSymptom) { oldValue, newValue in
                                filterProtocols()
                            }
                        
                        Menu {
                            ForEach(categories, id: \.self) { category in
                                Button(action: { selectedCategory = category; filterProtocols() }) {
                                    Text(category)
                                }
                            }
                        } label: {
                            Label("Filter", systemImage: "line.horizontal.3.decrease.circle")
                        }
                        .padding(.trailing)
                    }
                    .padding(.top)
                } else {
                    Text("Recommended Protocols for Your Symptoms")
                        .font(.headline)
                        .padding()
                }
                
                // Recommended Protocols List
                List {
                    if filteredProtocols.isEmpty {
                        Text("No matching protocols found.")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        ForEach(filteredProtocols) { proto in
                            if onSelectProtocol != nil {
                                NavigationLink(destination: ProtocolDetailAndConfirmView(
                                    protocol: proto,
                                    symptoms: Array(selectedSymptoms ?? [activeSymptom].filter { !$0.isEmpty }.toSet()),
                                    onSelectProtocol: onSelectProtocol!
                                )) {
                                    protocolRow(for: proto)
                                }
                            } else {
                                NavigationLink(destination: ProtocolDetailView(therapyProtocol: proto)) {
                                    protocolRow(for: proto)
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                
                // Skip button if called from LogSymptomView
                if let onSkip = onSkip {
                    Button(action: {
                        onSkip()
                        dismiss()
                    }) {
                        Text("Continue Without Protocol")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                    }
                    .padding()
                }
            }
            .navigationTitle("Protocol Recommendations")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        activeSymptom = ""
                        selectedCategory = "All"
                        filterProtocols()
                    }
                }
                
                if onSkip != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Skip") {
                            onSkip?()
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                initializeWithSelectedSymptoms()
                filterProtocols()
            }
        }
    }
    
    private func initializeWithSelectedSymptoms() {
        // If we have selected symptoms from outside, use them for filtering
        if let symptoms = selectedSymptoms, !symptoms.isEmpty {
            activeSymptom = symptoms.joined(separator: ", ")
        }
    }
    
    /// Filters protocols based on symptoms & category
    private func filterProtocols() {
        // Use selected symptoms if provided, otherwise use activeSymptom
        let symptomsList: [String] = selectedSymptoms?.map { $0 } ??
                                    activeSymptom.split(separator: ",")
                                              .map { $0.trimmingCharacters(in: .whitespaces) }
                                              .filter { !$0.isEmpty }
        
        if symptomsList.isEmpty && selectedCategory == "All" {
            // No specific filtering, show all protocols
            filteredProtocols = protocols
            return
        }
        
        if !symptomsList.isEmpty {
            // Use smart recommender for complex recommendations
            let recommender = SmartProtocolRecommender()
            Task {
                let recommendations = recommender.recommendProtocols(
                    for: symptomsList,
                    logs: logs,
                    using: modelContext
                )
                
                // Filter by category if needed
                if selectedCategory != "All" {
                    filteredProtocols = recommendations.filter {
                        $0.category == selectedCategory
                    }
                } else {
                    filteredProtocols = recommendations
                }
            }
        } else {
            // Only category filter
            filteredProtocols = protocols.filter {
                selectedCategory == "All" || $0.category == selectedCategory
            }
        }
    }
    
    /// View for protocol row
    private func protocolRow(for proto: TherapyProtocol) -> some View {
        HStack {
            Image(systemName: "heart.text.square.fill")
                .foregroundColor(.green)
            VStack(alignment: .leading) {
                Text(proto.title)
                    .font(.headline)
                Text(proto.category)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let matchedSymptoms = matchedSymptoms(for: proto) {
                    Text("Matched: \(matchedSymptoms)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    /// Returns the matched symptoms for a protocol
    private func matchedSymptoms(for protocolItem: TherapyProtocol) -> String? {
        // Get symptoms to match against (from selected symptoms or active search)
        let symptomsToMatch: [String] = selectedSymptoms?.map { $0.lowercased() } ??
                                       activeSymptom.lowercased()
                                                  .split(separator: ",")
                                                  .map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Safely handle optional symptoms
        let protoSymptoms = protocolItem.symptoms ?? []
        let matches = protoSymptoms.filter { protoSymptom in
            symptomsToMatch.contains { symptomToMatch in
                protoSymptom.lowercased().contains(symptomToMatch)
            }
        }
        
        return matches.isEmpty ? nil : matches.joined(separator: ", ")
    }
}

// Helper extension to convert array to set
extension Array where Element: Hashable {
    func toSet() -> Set<Element> {
        return Set(self)
    }
}

// Keep the ProtocolDetailAndConfirmView as it was in ProtocolRecommendationView.swift
struct ProtocolDetailAndConfirmView: View {
    let `protocol`: TherapyProtocol
    let symptoms: [String]
    let onSelectProtocol: (TherapyProtocol) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section("Protocol Details") {
                Text(`protocol`.title)
                    .font(.headline)
                Text(`protocol`.category)
                    .foregroundColor(.secondary)
                Text(`protocol`.instructions)
                    .font(.subheadline)
            }
            
            Section("Treatment Plan") {
                Text("Frequency: \(`protocol`.frequency)")
                Text("Duration: \(`protocol`.duration)")
                if let reminderTime = `protocol`.reminderTime {
                    Text("Reminder: \(reminderTime.formatted(date: .omitted, time: .shortened))")
                }
            }
            
            Section("Targeted Symptoms") {
                ForEach((`protocol`.symptoms ?? []), id: \.self) { symptom in
                    HStack {
                        Text(symptom)
                        if symptoms.contains(where: { $0.lowercased() == symptom.lowercased() }) {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            
            Button(action: {
                onSelectProtocol(`protocol`)
                dismiss()
            }) {
                Text("Use This Protocol")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Protocol Details")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
