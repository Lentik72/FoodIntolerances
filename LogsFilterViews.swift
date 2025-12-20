import SwiftUI

// MARK: - Basic Filter View
struct MultiSelectFilterView: View {
    let title: String
    let options: [String]
    @Binding var selection: Set<String>
    
    var body: some View {
        DisclosureGroup(title) {
            VStack(alignment: .leading) {
                ForEach(options, id: \.self) { option in
                    HStack {
                        Text(option)
                        Spacer()
                        if selection.contains(option) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selection.contains(option) {
                            selection.remove(option)
                        } else {
                            selection.insert(option)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Date Filter View
struct DateFilterView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
            DatePicker("End Date", selection: $endDate, displayedComponents: .date)
        }
    }
}

// MARK: - Status Filter View
struct StatusFilterView: View {
    @Binding var showActiveOnly: Bool
    @Binding var showResolvedOnly: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            Toggle("Show Only Active Symptoms", isOn: $showActiveOnly)
                .toggleStyle(SwitchToggleStyle(tint: .green))
            
            if !showActiveOnly {
                Toggle("Show Only Resolved", isOn: $showResolvedOnly)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
            }
        }
    }
}

// MARK: - Severity Filter View
struct SeverityFilterView: View {
    @Binding var minSeverity: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Minimum Severity: \(minSeverity)")
            Slider(
                value: Binding(
                    get: { Double(minSeverity) },
                    set: { minSeverity = Int($0) }
                ),
                in: 1...5,
                step: 1
            )
            .accentColor(.blue)
        }
    }
}

// MARK: - Environmental Filter View
struct EnvironmentalFilterView: View {
    @Binding var selectedMoonPhases: Set<String>
    @Binding var selectedMercuryStatus: Set<String>
    @Binding var selectedAtmosphericPressureCategories: Set<String>
    let moonPhases: [String]
    let mercuryStatuses: [String]
    let pressureCategories: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MultiSelectFilterView(
                title: "Moon Phases",
                options: moonPhases,
                selection: $selectedMoonPhases
            )
            
            MultiSelectFilterView(
                title: "Mercury Status",
                options: mercuryStatuses,
                selection: $selectedMercuryStatus
            )
            
            MultiSelectFilterView(
                title: "Atmospheric Pressure",
                options: pressureCategories,
                selection: $selectedAtmosphericPressureCategories
            )
        }
    }
}

// MARK: - Combined Filters View
struct CombinedFiltersView: View {
    @ObservedObject var viewModel: LogsViewModel
    @Binding var showFilters: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Basic Filters Section
            Section(header: Text("Basic Filters")) {
                MultiSelectFilterView(
                    title: "Symptoms",
                    options: viewModel.allSymptoms,
                    selection: $viewModel.selectedSymptoms
                )
                
                MultiSelectFilterView(
                    title: "Foods",
                    options: viewModel.allFoods,
                    selection: $viewModel.selectedFoods
                )
            }
            
            // Status Filters
            Section(header: Text("Status")) {
                StatusFilterView(
                    showActiveOnly: $viewModel.showActiveOnly,
                    showResolvedOnly: $viewModel.showResolvedOnly
                )
            }
            
            // Date and Severity Filters
            DisclosureGroup("Advanced Filters", isExpanded: $showFilters) {
                VStack(alignment: .leading, spacing: 10) {
                    DateFilterView(
                        startDate: $viewModel.startDate,
                        endDate: $viewModel.endDate
                    )
                    
                    SeverityFilterView(minSeverity: $viewModel.minSeverity)
                    
                    EnvironmentalFilterView(
                        selectedMoonPhases: $viewModel.selectedMoonPhases,
                        selectedMercuryStatus: $viewModel.selectedMercuryStatus,
                        selectedAtmosphericPressureCategories: $viewModel.selectedAtmosphericPressureCategories,
                        moonPhases: viewModel.allMoonPhases,
                        mercuryStatuses: viewModel.allMercuryStatuses,
                        pressureCategories: viewModel.allAtmosphericPressureCategories
                    )
                }
                .padding(.vertical, 5)
            }
        }
    }
}

// MARK: - Preview Provider
struct LogsFilterViews_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            CombinedFiltersView(
                viewModel: LogsViewModel(),
                showFilters: .constant(true)
            )
        }
    }
}
