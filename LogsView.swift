import SwiftUI
import SwiftData
import Charts

struct SeverityCount: Identifiable {
    let id = UUID()
    let severity: Int
    let count: Int
}


struct LogsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\LogEntry.date, order: .reverse)])
    private var logs: [LogEntry]

    @StateObject private var viewModel = LogsViewModel()
    @State private var showFilters = false
    @State private var sortOption: SortOption = .dateDesc
    @State private var searchText: String = ""
    
    // Edit/Delete states
    @State private var logToDelete: LogEntry? = nil
    @State private var showDeleteAlert = false
    @State private var logToEdit: LogEntry? = nil
    @State private var showEditSheet = false
    @State private var selectedLogForProtocol: LogEntry? = nil
    @State private var showProtocolSheet = false
    @State private var showSaveError = false
    @Query private var avoidedItems: [AvoidedItem]

    enum SortOption: String, CaseIterable, Identifiable {
        case dateDesc = "Date (Newest First)"
        case dateAsc = "Date (Oldest First)"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Search Section
                Section {
                    SearchBar(text: $searchText)
                        .frame(height: 44)
                        .accessibilityLabel("Search Logs")
                        .accessibilityHint("Enter text to search within logs")
                }

                // Filters Section
                CombinedFiltersView(viewModel: viewModel, showFilters: $showFilters)

                // Sort Section
                Section(header: Text("Sort By")) {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                // Statistics Section
                Section(header: Text("Severity Distribution")) {
                    Text("Total logs found: \(filteredAndSortedLogs.count)")
                        .font(.subheadline)
                        .foregroundColor(.blue)

                    severityChartSection
                }

                // Logs List Section
                Section(header: Text("Matching Logs")) {
                    if filteredAndSortedLogs.isEmpty {
                        Text("No logs found with these filters.")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(filteredAndSortedLogs) { log in
                            LogRowView(
                                log: log,
                                fetchProtocol: fetchProtocol,
                                avoidedItems: avoidedItems,
                                onToggleStatus: toggleLogStatus
                            )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    logToEdit = log
                                    showEditSheet = true
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        logToDelete = log
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityLabel("Delete log")
                                    .accessibilityHint("Swipe or double tap to delete this log entry")

                                    Button {
                                        logToEdit = log
                                        showEditSheet = true
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                    .accessibilityLabel("Edit log")
                                    .accessibilityHint("Swipe or double tap to edit this log entry")
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        toggleResolved(log: log)
                                    } label: {
                                        Label(log.isOngoing ?? false ? "Resolve" : "Reopen",
                                              systemImage: log.isOngoing ?? false ? "checkmark.circle" : "arrow.counterclockwise")
                                    }
                                    .tint(log.isOngoing ?? false ? .green : .orange)
                                    .accessibilityLabel(log.isOngoing ?? false ? "Mark as resolved" : "Reopen log")
                                    .accessibilityHint(log.isOngoing ?? false ? "Swipe or double tap to mark this symptom as resolved" : "Swipe or double tap to reopen this log")
                                }
                                .accessibilityHint("Double tap to edit. Swipe left to delete or edit. Swipe right to toggle resolved status.")
                        }
                    }
                }
            }
            .navigationTitle("View Logs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: exportLogs) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export logs")
                    .accessibilityHint("Double tap to export your symptom logs")
                }
            }
            .sheet(item: $selectedLogForProtocol) { log in
                ProtocolRecommendationsView(
                    selectedSymptoms: Set(log.symptoms),
                    onSkip: {
                        selectedLogForProtocol = nil
                    },
                    onSelectProtocol: { selectedProtocol in
                        log.protocolID = selectedProtocol.id
                        try? modelContext.save()
                        selectedLogForProtocol = nil
                    }
                )
            }
            .sheet(item: $logToEdit) { log in
                EditLogSheet(log: log)
            }
            .alert("Delete Log?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let log = logToDelete {
                        modelContext.delete(log)
                        do {
                            try modelContext.save()
                        } catch {
                            showSaveError = true
                            print("Failed to delete log: \(error)")
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this log?")
            }
            .saveErrorAlert(isPresented: $showSaveError)
            .onAppear {
                updateAvailableFilters()
            }
        }
    }

    private var filteredAndSortedLogs: [LogEntry] {
        let filtered = logs.filter { log in
            matchesBasicFilters(log) &&
            matchesEnvironmentalFilters(log) &&
            matchesStatusFilters(log) &&
            matchesSearch(log)
        }
        
        return filtered.sorted { first, second in
            switch sortOption {
            case .dateDesc:
                return first.date > second.date
            case .dateAsc:
                return first.date < second.date
            }
        }
    }

    private func matchesBasicFilters(_ log: LogEntry) -> Bool {
        matchesCategory(log) &&
        matchesFoods(log) &&
        matchesDateRange(log) &&
        matchesSeverity(log)
    }
    
    private func toggleLogStatus(log: LogEntry) {
        // Toggle the isOngoing status
        log.isOngoing = !(log.isOngoing ?? false)
        
        // If resolving (setting to inactive), also set end date
        if !(log.isOngoing ?? true) {
            log.endDate = Date()
        } else {
            // If reactivating, clear the end date
            log.endDate = nil
        }
        
        // Save the changes
        try? modelContext.save()
    }
    
    private func matchesCategory(_ log: LogEntry) -> Bool {
        // If no category filter is set, show all logs
        if viewModel.selectedCategory.isEmpty || viewModel.selectedCategory == "All" {
            return true
        }
        
        return log.category == viewModel.selectedCategory
       }

    private func matchesSymptoms(_ log: LogEntry) -> Bool {
        // Print for debugging
        print("Log symptoms: \(log.symptoms), Selected symptoms: \(viewModel.selectedSymptoms)")
        
        return viewModel.selectedSymptoms.isEmpty ||
        !viewModel.selectedSymptoms.isDisjoint(with: Set(log.symptoms))
    }

    private func matchesFoods(_ log: LogEntry) -> Bool {
        viewModel.selectedFoods.isEmpty ||
        (log.foodDrinkItem != nil && viewModel.selectedFoods.contains(log.foodDrinkItem!))
    }

    private func matchesDateRange(_ log: LogEntry) -> Bool {
        log.date >= viewModel.startDate && log.date <= viewModel.endDate
    }

    private func matchesSeverity(_ log: LogEntry) -> Bool {
        log.severity >= viewModel.minSeverity
    }

    private func matchesEnvironmentalFilters(_ log: LogEntry) -> Bool {
        let moonMatch = viewModel.selectedMoonPhases.isEmpty ||
            viewModel.selectedMoonPhases.contains(log.moonPhase)
        
        let mercuryMatch = viewModel.selectedMercuryStatus.isEmpty ||
            viewModel.selectedMercuryStatus.contains(log.isMercuryRetrograde ? "In Retrograde" : "Direct")
        
        let pressureMatch = viewModel.selectedAtmosphericPressureCategories.isEmpty ||
            viewModel.selectedAtmosphericPressureCategories.contains(log.atmosphericPressure)
        
        return moonMatch && mercuryMatch && pressureMatch
    }

    private func matchesStatusFilters(_ log: LogEntry) -> Bool {
        if viewModel.showActiveOnly {
            // Use nil-coalescing to provide a default value of false
            return log.isOngoing ?? false
        }
        if viewModel.showResolvedOnly {
            // Treat nil as resolved (not ongoing)
            return !(log.isOngoing ?? true)
        }
        return true
    }

    private func matchesSearch(_ log: LogEntry) -> Bool {
        guard !searchText.isEmpty else { return true }
        
        return log.symptoms.joined(separator: ", ").localizedCaseInsensitiveContains(searchText) ||
            (log.foodDrinkItem?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            log.notes.localizedCaseInsensitiveContains(searchText)
    }

    private func updateAvailableFilters() {
        let logCategories = Set(logs.map { $0.category })
        let logFoods = Set(logs.compactMap { $0.foodDrinkItem }).filter { !$0.isEmpty }
        let logMoonPhases = Set(logs.compactMap { $0.moonPhase }).filter { !$0.isEmpty }
        let logPressures = Set(logs.compactMap { $0.atmosphericPressure }).filter { !$0.isEmpty }
        
        viewModel.availableCategories = ["All"] + Array(logCategories).sorted()
        viewModel.allFoods = Array(logFoods).sorted()
        viewModel.allMoonPhases = Array(logMoonPhases).sorted()
        viewModel.allAtmosphericPressureCategories = Array(logPressures).sorted()
    }
    
    private func getUniqueCategories() -> [String] {
           return ["All"] + Array(Set(logs.map { $0.category })).sorted()
       }
   

    private func handleDelete(offsets: IndexSet) {
        offsets.forEach { index in
            logToDelete = filteredAndSortedLogs[index]
            showDeleteAlert = true
        }
    }

    private func showProtocolSheet(for log: LogEntry) {
        selectedLogForProtocol = log
        showProtocolSheet = true
    }
    
    private func toggleResolved(log: LogEntry) {
        log.isOngoing = !(log.isOngoing ?? false)
        if !(log.isOngoing ?? true) {
            log.endDate = Date() // Set end date when resolving
        } else {
            log.endDate = nil // Clear end date when reopening
        }
        
        try? modelContext.save()
    }

    private func fetchProtocol(withID protocolID: UUID) -> TherapyProtocol? {
        let descriptor = FetchDescriptor<TherapyProtocol>(predicate: #Predicate { $0.id == protocolID })
        return try? modelContext.fetch(descriptor).first
    }

    private func exportLogs() {
        // Export implementation
        print("Export Logs button tapped.")
    }

    @ViewBuilder
    private var severityChartSection: some View {
        if filteredAndSortedLogs.isEmpty {
            Text("No logs to display.")
                .foregroundColor(.gray)
        } else {
            let grouped = Dictionary(grouping: filteredAndSortedLogs, by: \.severity)
            let severityData = grouped.map { SeverityCount(severity: $0.key, count: $0.value.count) }
                .sorted { $0.severity < $1.severity }

            Chart {
                ForEach(severityData) { sc in
                    BarMark(
                        x: .value("Severity", sc.severity),
                        y: .value("Count", sc.count)
                    )
                    .foregroundStyle(colorForSeverity(sc.severity))
                    .cornerRadius(5)
                }
            }
            .frame(height: 200)
            .accessibilityLabel("Severity distribution chart")
            .accessibilityValue(severityData.map { "Severity \($0.severity): \($0.count) logs" }.joined(separator: ", "))
        }
    }

    private func colorForSeverity(_ s: Int) -> Color {
        switch s {
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
}

struct LogsView_Previews: PreviewProvider {
    static var previews: some View {
        LogsView()
            .modelContainer(for: [LogEntry.self, TrackedItem.self, AvoidedItem.self, OngoingSymptom.self, SymptomCheckIn.self], inMemory: true)
    }
}
