// LogSymptomView.swift

import SwiftUI
import SwiftData
import Combine

// MARK: - ReviewView

struct ReviewView: View {
    @EnvironmentObject var viewModel: LogItemViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTrackedItem: TrackedItem?
    
    @State private var showProtocolRecommendations = false
    @State private var matchingProtocols: [TherapyProtocol] = []
    @State private var showAllProtocols = false
    @State private var isAnalyzing: Bool = false
    @State private var similarPatterns: [LogEntry] = []
    @State private var potentialTriggers: [String] = []
    @Query private var avoidedItems: [AvoidedItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Review Your Entry")
                .font(.title2)
                .bold()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    reviewRow(
                        title: "Symptom/s",
                        value: viewModel.selectedSymptoms.isEmpty
                        ? viewModel.foodDrinkItem
                        : viewModel.selectedSymptoms.joined(separator: ", ")
                    )
                    
                    reviewRow(title: "Cause Type", value: viewModel.causeType.rawValue)
                    
                    if !viewModel.causeSubcategories.isEmpty {
                        reviewRow(
                            title: "Subcategories",
                            value: viewModel.causeSubcategories.sorted().joined(separator: ", ")
                        )
                    }
                    
                    if viewModel.causeType == .foodAndDrink, !viewModel.foodDrinkItem.isEmpty {
                        reviewRow(title: "Food/Drink", value: viewModel.foodDrinkItem)
                    }
                    
                    if viewModel.causeType == .foodAndDrink && !viewModel.foodDrinkItem.isEmpty {
                        if viewModel.isItemInAvoidList(viewModel.foodDrinkItem, avoidedItems: avoidedItems) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("⚠️ Warning: This item is in your Avoid List!")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                    .padding(.vertical, 4)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    reviewRow(
                        title: "Severity",
                        value: "\(Int(viewModel.severity)) " + severityEmoji(Int(viewModel.severity))
                    )
                    
                    reviewRow(
                        title: "Affected Areas",
                        value: viewModel.isInternalSymptom
                        ? viewModel.internalAffectedArea
                        : viewModel.selectedBodyAreas.sorted().joined(separator: ", ")
                    )
                    
                    reviewRow(
                        title: "Date",
                        value: DateFormatter.localizedString(from: viewModel.date, dateStyle: .medium, timeStyle: .none)
                    )
                    
                    reviewRow(
                        title: "Season",
                        value: viewModel.currentSeason.isEmpty ? "Unknown" : viewModel.currentSeason
                    )
                    
                    // New additions
                    reviewRow(
                        title: "Moon Phase",
                        value: "\(viewModel.autoMoonPhase) 🌙"
                    )
                    
                    reviewRow(
                        title: "Atmospheric Pressure",
                        value: viewModel.atmosphericPressureCategory.contains("Loading")
                        ? "Normal \(pressureIcon("Normal"))"
                        : "\(viewModel.atmosphericPressureCategory) \(pressureIcon(viewModel.atmosphericPressureCategory))"
                    )
                    
                    reviewRow(
                        title: "Mercury Retrograde",
                        value: viewModel.autoMercuryRetrograde ? "Yes (Retrograde)" : "No (Direct)"
                    )
                    
                    if !viewModel.notes.isEmpty {
                        reviewRow(title: "Notes", value: viewModel.notes)
                    }
                    
                    if !viewModel.selectedSymptomTriggers.isEmpty {
                        reviewRow(
                            title: "Potential Triggers",
                            value: viewModel.selectedSymptomTriggers.joined(separator: ", ")
                        )
                    }
                    
                    if !viewModel.additionalNotes.isEmpty {
                        reviewRow(
                            title: "Additional Context",
                            value: viewModel.additionalNotes
                        )
                    }
                }
                .padding()
                .background(Color(UIColor.systemGray6))
                .cornerRadius(10)
            }
            
            // Enhanced Protocol Recommendations Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Recommended Protocols", systemImage: "heart.text.square.fill")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Spacer()
                    Button(action: {
                        showAllProtocols = true // Use this instead of showProtocolRecommendations
                    }) {
                        Label("Browse All", systemImage: "rectangle.grid.2x2.fill")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                
                if let selectedProtocol = viewModel.selectedProtocol {
                    // Display selected protocol with more details
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedProtocol.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                HStack {
                                    Text(selectedProtocol.category)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if let symptoms = selectedProtocol.symptoms, !symptoms.isEmpty {
                                        Text("•")
                                            .foregroundColor(.gray)
                                        Text("Targets: \(symptoms.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        
                        Text(selectedProtocol.instructions)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        HStack(spacing: 12) {
                            Label("Frequency: \(selectedProtocol.frequency)", systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if !selectedProtocol.duration.isEmpty {
                                Label("Duration: \(selectedProtocol.duration)", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 4)
                        
                        Button(action: {
                            showProtocolRecommendations = true
                        }) {
                            Text("Change Protocol")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
                } else {
                    // Enhanced recommendation prompt
                    VStack(alignment: .center, spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        
                        Text("Find a Protocol for Your Symptoms")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Protocols can help manage your symptoms with targeted approaches")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button(action: {
                            showProtocolRecommendations = true
                        }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Browse Recommended Protocols")
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        .padding(.top, 6)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Smart Analysis")
                    .font(.headline)
                    .padding(.top)
                
                // Add loading indicator
                if isAnalyzing {
                    ProgressView("Analyzing similar patterns...")
                        .padding()
                } else if !similarPatterns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Similar past incidents:")
                            .font(.subheadline)
                            .bold()
                        
                        ForEach(similarPatterns.prefix(3), id: \.id) { log in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(log.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                    Text(log.foodDrinkItem ?? "Unknown trigger")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("Severity: \(log.severity)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        if !potentialTriggers.isEmpty {
                            Text("Potential triggers:")
                                .font(.subheadline)
                                .bold()
                                .padding(.top, 5)
                            
                            Text(potentialTriggers.joined(separator: ", "))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .onAppear {
                analyzePatterns()
            }
            // Save Button - Enhanced
            Button(action: {
                viewModel.saveLog(using: modelContext, linkedTrackedItemID: selectedTrackedItem?.id)
                viewModel.showSavedMessage = true
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Save Log")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(isReviewValid ?
                            LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing) :
                                LinearGradient(colors: [.gray, .gray.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(10)
                .shadow(color: isReviewValid ? .green.opacity(0.3) : .gray.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .disabled(!isReviewValid)
            .padding(.top, 10)
        }
        .padding()
        .sheet(isPresented: $showProtocolRecommendations) {
            ProtocolRecommendationsView(
                selectedSymptoms: viewModel.selectedSymptoms,
                onSkip: {
                    showProtocolRecommendations = false
                },
                onSelectProtocol: { selectedProtocol in
                    viewModel.selectedProtocol = selectedProtocol
                    showProtocolRecommendations = false
                }
            )
            .environmentObject(viewModel)
        }
        .sheet(isPresented: $showAllProtocols) {
            // Navigate to the main protocols page without filtering
            ProtocolListView()
        }
    }

    // Helper method for creating review rows
    private func reviewRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            if value.contains("Loading...") {
                Text("Normal")  // Fallback value
                    .font(.subheadline)
            } else {
                Text(value.isEmpty ? "(Not Provided)" : value)
                    .font(.subheadline)
            }
        }
    }
    
    // Severity emoji method
    private func severityEmoji(_ severity: Int) -> String {
        switch severity {
        case 1: return "🙂"
        case 2: return "😐"
        case 3: return "😣"
        case 4: return "😫"
        case 5: return "🤯"
        default: return "❓"
        }
    }
    
    // Pressure icon method
    private func pressureIcon(_ pressure: String) -> String {
        switch pressure.lowercased() {
        case "high": return "⬆️"
        case "low": return "⬇️"
        case "normal": return "➡️"
        default: return "❓"
        }
    }
    
    private func analyzePatterns() {
        isAnalyzing = true
        
        // Fetch recent logs with similar symptoms
        Task {
            let predictionService = SymptomPredictionService()
            let triggers = predictionService.predictPotentialTriggers(for: Array(viewModel.selectedSymptoms), using: modelContext)
            
            // Fetch similar logs - fixed version
            let descriptor = FetchDescriptor<LogEntry>(
                sortBy: [SortDescriptor(\LogEntry.date, order: .reverse)]
            )
            let allLogs = try? modelContext.fetch(descriptor)
            let similarLogs = allLogs?.filter { log in
                !Set(log.symptoms).isDisjoint(with: Set(viewModel.selectedSymptoms))
            }
            
            // Update UI on main thread
            await MainActor.run {
                self.similarPatterns = similarLogs?.prefix(5).map { $0 } ?? []
                self.potentialTriggers = triggers
                self.isAnalyzing = false
            }
        }
    }
    
    // Computed property to check if the review is valid
    private var isReviewValid: Bool {
        return !viewModel.selectedSymptoms.isEmpty || !viewModel.foodDrinkItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct LogSymptomView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: LogItemViewModel
    @Query private var trackedItems: [TrackedItem]
    @Query private var avoidedItems: [AvoidedItem]
    
    @State private var selectedTrackedItem: TrackedItem? = nil
    @State private var selectedImage: UIImage?
    @State private var imageData: Data?
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                StepperView(currentStep: $viewModel.currentStep)
                    .padding()
                
                ScrollView {
                    VStack(spacing: 20) {
                        switch viewModel.currentStep {
                        case .symptomSelection:
                            SymptomSelectionView()
                        case .causeIdentification:
                            CauseIdentificationView()
                        case .severityRating:
                            SeverityRatingView()
                        case .affectedAreas:
                            AffectedAreasView()
                        case .dateNotes:
                            DateNotesView()
                        case .review:
                            ReviewView(selectedTrackedItem: $selectedTrackedItem)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Log Symptom")
            .onAppear {
                Task {
                    await viewModel.fetchAllData()
                }
            }
            .sheet(isPresented: $viewModel.showAddItemSheet) {
                AddNewItemSheet()
                    .environmentObject(viewModel)
            }
            
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SuggestAvoidItem"))) { notification in
                if let userInfo = notification.object as? [String: Any],
                   let item = userInfo["item"] as? String,
                   let type = userInfo["type"] as? String {
                    // Show alert with options to add to avoid list
                    let alert = UIAlertController(
                        title: "Add to Avoid List?",
                        message: "Would you like to add \(item) to your Avoid List? This item appears to be associated with your symptoms.",
                        preferredStyle: .alert
                    )
                    
                    alert.addAction(UIAlertAction(title: "Yes", style: .default) { _ in
                        // Add to avoid list
                        let avoidType = AvoidedItemType(rawValue: type) ?? .food
                        let avoidItem = AvoidedItem(name: item, type: avoidType)
                        modelContext.insert(avoidItem)
                        try? modelContext.save()
                    })
                    
                    alert.addAction(UIAlertAction(title: "No", style: .cancel))
                    
                    // Present the alert
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(alert, animated: true)
                    }
                }
            }
            
            
            .alert(isPresented: Binding(
                get: { 
                    // Check either alert condition
                    viewModel.showAlert || viewModel.showSavedMessage  
                },
                set: { newValue in
                    if !newValue {
                        viewModel.showAlert = false
                        viewModel.showSavedMessage = false
                    }
                }
            )) {
                if viewModel.alertType == .avoidSuggestion {
                    return Alert(
                        title: Text("Food Sensitivity Warning"),
                        message: Text(viewModel.alertMessage),
                        primaryButton: .default(Text("Add to Avoid List")) {
                            // Create and save the avoided item
                            let avoidedItem = AvoidedItem(
                                name: viewModel.suggestedAvoidItem,
                                type: .food,
                                reason: "Automatically suggested due to repeated symptoms"
                            )
                            modelContext.insert(avoidedItem)
                            try? modelContext.save()
                            viewModel.showAlert = false
                        },
                        secondaryButton: .cancel(Text("Skip")) {
                            viewModel.showAlert = false
                        }
                    )
                } else if viewModel.showSavedMessage {
                    return Alert(
                        title: Text("Success"),
                        message: Text("Symptom(s) saved successfully!"),
                        dismissButton: .default(Text("OK")) {
                            // Reset form first
                            viewModel.resetForm()
                            viewModel.currentStep = .symptomSelection
                            
                            // Then dismiss and navigate
                            dismiss()
                            
                            // Use a slightly longer delay to ensure alert is fully dismissed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                print("📢 Posting NavigateToDashboard notification...")
                                NotificationCenter.default.post(name: Notification.Name("NavigateToDashboard"), object: nil)
                            }
                        }
                    )
                } else {
                    return Alert(
                        title: Text("Error"),
                        message: Text(viewModel.alertMessage),
                        dismissButton: .default(Text("OK")) {
                            viewModel.showAlert = false
                        }
                    )
                }
            }
        }
    }
}
    
    // MARK: - Stepper View
    struct StepperView: View {
        @Binding var currentStep: LogItemViewModel.LogStep
        
        var body: some View {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 20) { // Correct order
                        ForEach(LogItemViewModel.LogStep.allCases, id: \.self) { step in
                            VStack(spacing: 8) { // Add spacing for better alignment
                                ZStack {
                                    Circle()
                                        .fill(currentStep.rawValue >= step.rawValue ? Color.blue : Color.gray.opacity(0.3))
                                        .frame(width: 40, height: 40)
                                        .shadow(radius: currentStep == step ? 5 : 0)
                                    
                                    Text("\(step.rawValue + 1)")
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                Text(step.title)
                                    .font(.caption)
                                    .foregroundColor(currentStep == step ? .blue : .gray)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: 80)
                                    .lineLimit(2) // Ensure max two lines for cleaner look
                            }
                            .frame(minWidth: 80) // Keep consistent width for all steps
                            .id(step) // Add ID for scrolling
                            .onTapGesture {
                                if step.rawValue <= currentStep.rawValue {
                                    currentStep = step
                                }
                            }
                            .animation(.easeInOut, value: currentStep)
                        }
                    }
                    .padding(.horizontal)
                }
                
                .frame(height: 100)
                .onChange(of: currentStep) { oldStep, newStep in
                    withAnimation {
                        proxy.scrollTo(newStep, anchor: .center) // Auto-scroll to the current step
                    }
                }
            }
            .frame(height: 100)
        }
    }
    
    
    // MARK: - SymptomSelectionView
    
struct SymptomSelectionView: View {
    @EnvironmentObject var viewModel: LogItemViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Select Symptoms")
                .font(.title2)
                .bold()
                .padding(.top)
            
            // Search Bar
            SearchBarView(searchText: $viewModel.symptomSearchText)
            
            // Predefined Symptoms as Tags
            PredefinedSymptomsGrid()
            
            // Selected Symptoms Display
            SelectedSymptomsGrid()
            
            Spacer()
        }
        .padding([.horizontal, .bottom])
    }
}
    
    struct ProtocolRecommendationsSheet: View {
        @Environment(\.modelContext) private var modelContext
        @Environment(\.dismiss) var dismiss
        @EnvironmentObject var viewModel: LogItemViewModel
        
        @State private var selectedProtocol: TherapyProtocol?
        
        @Query(filter: #Predicate<TherapyProtocol> { $0.isActive }, sort: \TherapyProtocol.dateAdded)
        private var activeProtocols: [TherapyProtocol]
        
        var matchingProtocols: [TherapyProtocol] {
            activeProtocols.filter { proto in
                // Safely handle optional symptoms
                guard let protoSymptoms = proto.symptoms else { return false }
                
                // Create a set from protocol symptoms and check for intersection
                return !Set(protoSymptoms).isDisjoint(with: viewModel.selectedSymptoms)
            }
        }
        
        var body: some View {
            NavigationView {
                List {
                    if matchingProtocols.isEmpty {
                        Section {
                            Text("No matching protocols found for your symptoms.")
                                .foregroundColor(.gray)
                            
                            NavigationLink(destination: AddProtocolSheet(isPresented: .constant(false))) {
                                Label("Create New Protocol", systemImage: "plus.circle.fill")
                            }
                        }
                    } else {
                        Section(header: Text("Recommended Protocols")) {
                            ForEach(matchingProtocols) { proto in
                                protocolRow(for: proto)
                            }
                        }
                    }
                }
                .navigationTitle("Protocol Recommendations")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Continue") {
                            if let selected = selectedProtocol {
                                viewModel.selectedProtocol = selected
                            }
                            dismiss()
                        }
                    }
                }
            }
        }
        
        private func protocolRow(for proto: TherapyProtocol) -> some View {
            VStack(alignment: .leading) {
                Text(proto.title)
                    .font(.headline)
                Text(proto.category)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Safely handle optional symptoms
                if let symptoms = proto.symptoms, !symptoms.isEmpty {
                    Text("Targets: \(symptoms.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 4)
            .background(selectedProtocol?.id == proto.id ? Color.blue.opacity(0.1) : Color.clear)
            .onTapGesture {
                selectedProtocol = proto
            }
        }
    }
    
    // MARK: - SearchBarView
    
    struct LogSymptomSearchBarView: View {
        @EnvironmentObject var viewModel: LogItemViewModel
        
        var body: some View {
            HStack {
                Image(systemName: "magnifyingglass")
                
                TextField("Search symptoms...", text: $viewModel.symptomSearchText)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .accessibilityLabel("Symptom Search Field")
                    .accessibilityHint("Enter text to search for symptoms")
                
                if !viewModel.symptomSearchText.isEmpty {
                    Button(action: {
                        viewModel.symptomSearchText = ""
                        print("Cleared search text.")
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .accessibilityLabel("Clear Search")
                            .accessibilityHint("Double tap to clear the search text")
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for index in subviews.indices {
            let point = result.points[index]
            subviews[index].place(at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var points: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentPosition: CGPoint = .zero
            var lineHeight: CGFloat = 0
            var maxSize: CGSize = .zero
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentPosition.x + size.width > maxWidth, currentPosition.x > 0 {
                    currentPosition.x = 0
                    currentPosition.y += lineHeight + spacing
                    lineHeight = 0
                }
                
                points.append(currentPosition)
                lineHeight = max(lineHeight, size.height)
                currentPosition.x += size.width + spacing
                maxSize.width = maxWidth
                maxSize.height = max(maxSize.height, currentPosition.y + lineHeight)
            }
            
            self.size = maxSize
        }
    }
}
    
    // MARK: - PredefinedSymptomsGrid
    
    struct PredefinedSymptomsGrid: View {
        @EnvironmentObject var viewModel: LogItemViewModel
        @State private var showingAddSymptomAlert = false
        @State private var newSymptomName: String = ""
        @State private var showProtocolRecommendations = false
        
        var sortedSymptoms: [String] {
            let sorted = viewModel.filteredSymptoms.sorted()
            if viewModel.symptomSearchText.isEmpty ||
               viewModel.filteredSymptoms.isEmpty ||
               viewModel.symptomSearchText.lowercased().contains("add") {
                return sorted + ["+ Add New Symptom"]
            }
            return sorted
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                // Warning Message only when no symptoms selected
                if viewModel.selectedSymptoms.isEmpty {
                    Text("⚠️ Select at least one symptom to proceed.")
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                
                // Next Button only when symptoms selected
                if !viewModel.selectedSymptoms.isEmpty {
                    // Add state for controlling recommendations sheet
                    
                    
                    Button(action: {
                        
                        viewModel.currentStep = .causeIdentification
                    }) {
                        Text("Next")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                
                // Symptoms Tags
                FlowLayout(spacing: 8) {
                    ForEach(sortedSymptoms, id: \.self) { symptom in
                        Button(action: {
                            if symptom == "+ Add New Symptom" {
                                showingAddSymptomAlert = true
                            } else {
                                toggleSelection(for: symptom)
                            }
                        }) {
                            HStack(spacing: 4) {
                                if symptom == "+ Add New Symptom" {
                                    Image(systemName: "plus.circle")
                                        .font(.caption)
                                }
                                
                                Text(symptom)
                                    .font(.subheadline)
                                
                                if viewModel.selectedSymptoms.contains(symptom) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                symptom == "+ Add New Symptom" ? Color.green.opacity(0.2) :
                                    viewModel.selectedSymptoms.contains(symptom) ? Color.blue : Color.gray.opacity(0.2)
                            )
                            .foregroundColor(
                                symptom == "+ Add New Symptom" ? .green :
                                    viewModel.selectedSymptoms.contains(symptom) ? .white : .primary
                            )
                            .cornerRadius(16)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.selectedSymptoms)
            }
            .padding(.horizontal)
            .alert("Add New Symptom", isPresented: $showingAddSymptomAlert) {
                TextField("Symptom Name", text: $newSymptomName)
                    .autocapitalization(.words)
                Button("Add", action: addCustomSymptom)
                    .disabled(newSymptomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter the name of the new symptom you want to add.")
            }
        }
        
        private func toggleSelection(for symptom: String) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if !viewModel.selectedSymptoms.insert(symptom).inserted {
                    viewModel.selectedSymptoms.remove(symptom)
                }
            }
            print("Current selectedSymptoms: \(viewModel.selectedSymptoms)")
        }
        
        private func addCustomSymptom() {
            let trimmedName = newSymptomName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return }
            
            viewModel.addCustomSymptom(trimmedName)
            newSymptomName = ""
            showingAddSymptomAlert = false
            print("Custom symptom added: \(trimmedName)")
        }
    }
    
    // MARK: - SelectedSymptomsGrid
    
    struct SelectedSymptomsGrid: View {
        @EnvironmentObject var viewModel: LogItemViewModel
        
        let columns: [GridItem] = [
            GridItem(.flexible()),
            GridItem(.flexible())
        ]
        
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.selectedSymptoms.isEmpty {
                    Text("Selected Symptoms")
                        .font(.headline)
                    
                    // Replace the LazyVGrid with this more compact layout
                    FlowLayout(spacing: 8) {
                        ForEach(Array(viewModel.selectedSymptoms), id: \.self) { symptom in
                            HStack(spacing: 4) {
                                Text(symptom)
                                    .font(.subheadline)
                                
                                Button(action: {
                                    viewModel.removeSymptom(symptom)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - CauseIdentificationView
    
    struct CauseIdentificationView: View {
        @EnvironmentObject var viewModel: LogItemViewModel
        @State private var selectedSubcategories: Set<String> = []
        @State private var showingCustomSubcategoryAlert = false
        @State private var customSubcategoryText = ""
        @Query private var avoidedItems: [AvoidedItem]
        
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Identify Cause")
                    .font(.title2)
                    .bold()
                
                // Cause Type Picker with Compact Icons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(LogItemViewModel.CauseType.allCases) { causeType in
                            VStack {
                                Image(systemName: iconForCauseType(causeType))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 40)
                                    .foregroundColor(viewModel.causeType == causeType ? .blue : .gray)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(viewModel.causeType == causeType ? Color.blue.opacity(0.1) : Color.clear)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(viewModel.causeType == causeType ? Color.blue : Color.gray, lineWidth: 1)
                                            )
                                    )
                                    .onTapGesture {
                                        withAnimation {
                                            viewModel.causeType = causeType
                                            selectedSubcategories.removeAll()
                                        }
                                    }
                                
                                Text(causeType.rawValue)
                                    .font(.caption)
                                    .foregroundColor(viewModel.causeType == causeType ? .blue : .gray)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Subcategory Selection
                if let subcategories = getCurrentSubcategories() {
                    Text("Select Subcategories")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            // Predefined Subcategories Tags
                            FlowLayout(spacing: 8) {
                                ForEach(subcategories + ["+ Add Custom"], id: \.self) { subcategory in
                                    if subcategory == "+ Add Custom" {
                                        Button(action: {
                                            showingCustomSubcategoryAlert = true
                                        }) {
                                            Text(subcategory)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(Color.green.opacity(0.2))
                                                .foregroundColor(.green)
                                                .cornerRadius(16)
                                        }
                                    } else {
                                        Button(action: {
                                            if selectedSubcategories.contains(subcategory) {
                                                selectedSubcategories.remove(subcategory)
                                            } else {
                                                selectedSubcategories.insert(subcategory)
                                            }
                                        }) {
                                            Text(subcategory)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(
                                                    selectedSubcategories.contains(subcategory) 
                                                        ? Color.blue.opacity(0.2) 
                                                        : Color.gray.opacity(0.2)
                                                )
                                                .foregroundColor(
                                                    selectedSubcategories.contains(subcategory) 
                                                        ? .blue 
                                                        : .primary
                                                )
                                                .cornerRadius(16)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // Specific Food/Drink Input
                if viewModel.causeType == .foodAndDrink {
                    TextField("Enter specific food/drink item", text: $viewModel.foodDrinkItem)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    // Add avoided item warning
                    if !viewModel.foodDrinkItem.isEmpty &&
                       viewModel.isItemInAvoidList(viewModel.foodDrinkItem, avoidedItems: avoidedItems) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.title3)
                            Text("Warning: This item is in your Avoid List!")
                                .font(.subheadline)
                                .bold()
                                .foregroundColor(.red)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red, lineWidth: 1)
                        )
                        .padding(.vertical, 4)
                    }
                }
                
                Spacer()
                
                // Next Button
                Button(action: {
                    viewModel.causeSubcategories = Set(selectedSubcategories)
                    viewModel.currentStep = .severityRating
                }) {
                    Text("Next")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isCauseSelected ? Color.blue : Color.gray)
                        .cornerRadius(10)
                }
                .disabled(!isCauseSelected)
            }
            .padding()
            .alert("Add Custom Subcategory", isPresented: $showingCustomSubcategoryAlert) {
                TextField("Subcategory Name", text: $customSubcategoryText)
                Button("Add", action: addCustomSubcategory)
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: viewModel.causeType) { oldValue, newValue in
                selectedSubcategories.removeAll()
            }
        }
        
        private func addCustomSubcategory() {
            let trimmedSubcategory = customSubcategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSubcategory.isEmpty else { return }
            
            // Add custom subcategory to selected subcategories
            selectedSubcategories.insert(trimmedSubcategory)
            
            // Reset custom subcategory text
            customSubcategoryText = ""
        }
        
        private func iconForCauseType(_ causeType: LogItemViewModel.CauseType) -> String {
            switch causeType {
            case .mental: return "brain.head.profile"
            case .environmental: return "cloud.sun"
            case .physical: return "figure.walk"
            case .foodAndDrink: return "fork.knife"
            case .unknown: return "questionmark.circle"
            }
        }
        
        private func getCurrentSubcategories() -> [String]? {
            switch viewModel.causeType {
            case .mental: return viewModel.mentalCategories
            case .environmental: return viewModel.environmentalCategories
            case .physical: return viewModel.physicalCategories
            case .foodAndDrink: return viewModel.foodAndDrinkCategories
            case .unknown: return viewModel.unknownCategories
            }
        }
        
        private var isCauseSelected: Bool {
            !selectedSubcategories.isEmpty && 
            (viewModel.causeType != .foodAndDrink || 
             !viewModel.foodDrinkItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // Reusable MultiSelect Button
    struct MultiSelectButton: View {
        let text: String
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(text)
                    .padding()
                    .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(isSelected ? .white : .primary)
                    .cornerRadius(10)
            }
        }
    }
    
    // MARK: - SeverityRatingView
    
    struct SeverityRatingView: View {
        @EnvironmentObject var viewModel: LogItemViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Severity")
                        .font(.title2)
                        .bold()
                    Spacer()
                    Button(action: {
                        viewModel.showSeverityInfo = true
                    }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("Severity Information")
                    .accessibilityHint("Double tap for more information about severity rating")
                    .sheet(isPresented: $viewModel.showSeverityInfo) {
                        VStack(spacing: 20) {
                            Text("Rate the severity of your symptom from 1 (mild) to 5 (severe).")
                                .padding()
                                .multilineTextAlignment(.center)
                            Button("Close") { viewModel.showSeverityInfo = false }
                                .padding()
                                .foregroundColor(.blue)
                        }
                        .padding()
                    }
                }

                HStack(spacing: 10) {
                    Text("\(Int(viewModel.severity))")
                        .bold()
                        .foregroundColor(.blue)
                    Slider(value: $viewModel.severity, in: 1...5, step: 1)
                        .accentColor(BodyRegionUtility.colorForSeverity(Int(viewModel.severity))) // Use the renamed function
                        .accessibilityLabel("Severity Slider")
                        .accessibilityHint("Slide to rate severity from 1 to 5")
                    Text(BodyRegionUtility.severityEmoji(Int(viewModel.severity)))
                        .font(.title)
                        .accessibilityLabel("Severity Emoji")
                        .accessibilityHint("Displays an emoji representing the severity level")
                }

                Spacer()

                // Next Button
                Button(action: {
                    viewModel.currentStep = .affectedAreas
                }) {
                    Text("Next")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .accessibilityLabel("Proceed to Affected Areas")
                .accessibilityHint("Double tap to proceed to affected areas step")
            }
            .padding()
        }
    }
    
    // MARK: - AffectedAreasView
    
struct AffectedAreasView: View {
    @EnvironmentObject var viewModel: LogItemViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Affected Body Areas")
                .font(.title2)
                .bold()
       
            //remove test button later
            
            Button("Verify Mappings") {
                viewModel.verifySymptomRegionMapping()
            }
            .padding()
            .background(Color.orange.opacity(0.2))
            .cornerRadius(8)
            
            //remove test button later 
            
            if viewModel.isInternalSymptom {
                TextField("Specify affected area", text: $viewModel.internalAffectedArea)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                BodyMapView()
                    .frame(height: 400)
                    .background(Color(UIColor.systemGroupedBackground))
                    .cornerRadius(10)
                    .onAppear {
                        autoSelectBodyAreas()
                    }
                    .onChange(of: viewModel.selectedSymptoms) { oldValue, newValue in
                        autoSelectBodyAreas()
                    }
            }
            
            Spacer()
            
            Button(action: {
                viewModel.currentStep = .dateNotes
            }) {
                Text("Next")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isAffectedAreasSelected ? Color.blue : Color.gray)
                    .cornerRadius(10)
            }
            .disabled(!isAffectedAreasSelected)
        }
        .padding()
    }
    
    private var isAffectedAreasSelected: Bool {
        if viewModel.isInternalSymptom {
            return !viewModel.internalAffectedArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            // If no body areas are selected, check if we should allow progression
            if viewModel.selectedBodyAreas.isEmpty {
                // Option 1: Allow progression with a warning
                let unmappedSymptoms = viewModel.selectedSymptoms.filter {
                    viewModel.symptomToRegion[$0] == nil
                }
                return !unmappedSymptoms.isEmpty
                
                // Option 2: Provide a manual override
                // return true
            }
            return !viewModel.selectedBodyAreas.isEmpty
        }
    }
    
    // Add a method to handle unmapped symptoms
    private func handleUnmappedSymptoms() {
        let unmappedSymptoms = viewModel.selectedSymptoms.filter {
            viewModel.symptomToRegion[$0] == nil
        }
        
        if !unmappedSymptoms.isEmpty {
            // Directly call the method on viewModel
            viewModel.selectMultipleAreas(description: unmappedSymptoms.joined(separator: ", "))
            
            // Proceed to next step
            viewModel.currentStep = .dateNotes
        }
    }
    
    // Optional alert for unmapped symptoms
    private func showUnmappedSymptomsAlert(symptoms: [String]) {
        let symptomsList = symptoms.joined(separator: ", ")
        let alert = UIAlertController(
            title: "Unmapped Symptoms",
            message: "The following symptoms are not mapped to a body area: \(symptomsList). Would you like to add a custom area?",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Enter body area"
        }
        
        alert.addAction(UIAlertAction(title: "Add Custom Area", style: .default) { _ in
            if let customArea = alert.textFields?.first?.text, !customArea.isEmpty {
                viewModel.selectMultipleAreas(description: customArea)
                // Proceed to next step
                viewModel.currentStep = .dateNotes
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        // Present the alert (you'll need to adapt this to SwiftUI)
        // UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
    }
    
    // Auto-select body areas based on selected symptoms
    private func autoSelectBodyAreas() {
        // Clear previously selected areas first
        viewModel.selectedBodyAreas.removeAll()
        
        // Build a fresh set based on currently selected symptoms
        var newAreas = Set<String>()
        
        // Process each symptom individually
        for symptom in viewModel.selectedSymptoms {
            if let region = viewModel.symptomToRegion[symptom] {
                // Standardize the region name
                let standardizedRegion = BodyRegionUtility.standardizeRegionName(region)
                newAreas.insert(standardizedRegion)
                print("✅ Mapped region \(standardizedRegion) for symptom \(symptom)")
            } else {
                print("❌ No mapping for symptom: \(symptom)")
            }
        }
        
        // Assign the entire set at once to avoid multiple triggers
        viewModel.selectedBodyAreas = newAreas
        
        // Verify after assignment
        viewModel.verifySymptomRegionMapping()
    }
}
    
    // MARK: - DateNotesView
    
struct DateNotesView: View {
    @EnvironmentObject var viewModel: LogItemViewModel
    
    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Photo (Optional)")
                .font(.headline)
            
            HStack {
                if let uiImage = selectedImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .cornerRadius(8)
                    
                    Button(action: {
                        selectedImage = nil
                        viewModel.imageData = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                } else {
                    HStack {
                        Button(action: {
                            showCamera = true
                        }) {
                            Label("Camera", systemImage: "camera")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {
                            showPhotoLibrary = true
                        }) {
                            Label("Gallery", systemImage: "photo")
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
                    .onDisappear {
                        if let image = selectedImage {
                            viewModel.imageData = image.jpegData(compressionQuality: 0.8)
                        }
                    }
            }
            .sheet(isPresented: $showPhotoLibrary) {
                ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
                    .onDisappear {
                        if let image = selectedImage {
                            viewModel.imageData = image.jpegData(compressionQuality: 0.8)
                        }
                    }
            }
        }
        
        VStack(alignment: .leading, spacing: 20) {
            Text("Date & Notes")
                .font(.title2)
                .bold()
            
            DatePicker("Date", selection: $viewModel.date)
                .datePickerStyle(CompactDatePickerStyle())
            
            TextField("Add any notes...", text: $viewModel.notes)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .accessibilityLabel("Notes")
                .accessibilityHint("Enter additional notes about the symptom")
            
            VoiceInputView(text: $viewModel.notes)
                .padding(.vertical, 5)
            
            // Compact Moon Phase Section
            HStack {
                Text("Moon Phase 🌙")
                    .font(.headline)
                Text(getMoonPhase(for: viewModel.date))
                    .font(.headline)
                    .foregroundColor(.purple)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            
            Spacer()
            
            // Next Button
            Button(action: {
                Task {
                    await viewModel.ensureEnvironmentalDataLoaded()
                    await MainActor.run {
                        viewModel.currentStep = .review
                    }
                }
            }) {
                Text("Next")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .accessibilityLabel("Proceed to Review")
            .accessibilityHint("Double tap to proceed to review step")            .padding()
        }
    }
    // MARK: - Reusable Info Row View
    struct InfoRowView: View {
        let title: String
        let value: String
        
        var body: some View {
            HStack {
                Text("\(title):")
                    .bold()
                Spacer()
                Text(value.isEmpty ? "(Not Provided)" : value)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Preview
    
    struct LogSymptomView_Previews: PreviewProvider {
        static var previews: some View {
            LogSymptomView()
                .environmentObject(LogItemViewModel())
                .modelContainer(for: [LogEntry.self, TrackedItem.self, AvoidedItem.self], inMemory: true)
        }
    }
    
    
    struct SymptomTriggersView: View {
        @EnvironmentObject var viewModel: LogItemViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Possible Symptom Triggers")
                    .font(.title2)
                    .bold()
                
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.symptomTriggers + ["+ Add Custom"], id: \.self) { trigger in
                        if trigger == "+ Add Custom" {
                            Button(action: {
                                // Implement custom trigger addition
                            }) {
                                Text(trigger)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(16)
                            }
                        } else {
                            Button(action: {
                                if viewModel.selectedSymptomTriggers.contains(trigger) {
                                    viewModel.selectedSymptomTriggers.remove(trigger)
                                } else {
                                    viewModel.selectedSymptomTriggers.insert(trigger)
                                }
                            }) {
                                Text(trigger)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        viewModel.selectedSymptomTriggers.contains(trigger)
                                        ? Color.blue.opacity(0.2)
                                        : Color.gray.opacity(0.2)
                                    )
                                    .foregroundColor(
                                        viewModel.selectedSymptomTriggers.contains(trigger)
                                        ? .blue
                                        : .primary
                                    )
                                    .cornerRadius(16)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                TextField("Additional Context", text: $viewModel.additionalNotes)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
            }
        }
    }
}
   
   
