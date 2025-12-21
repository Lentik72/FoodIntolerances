import SwiftUI

/// Which side of the body is displayed
enum BodySide {
    case front
    case back
}

/// Front-side regions
enum BodyRegionFront: String, CaseIterable, Identifiable {
    // Existing regions
    case head
    case chest
    case abdomen
    case pelvic
    case upperLeftArm
    case lowerLeftArm
    case upperRightArm
    case lowerRightArm
    case upperLeftLeg
    case lowerLeftLeg
    case upperRightLeg
    case lowerRightLeg

    var id: String { rawValue }
}

enum BodyRegionBack: String, CaseIterable, Identifiable {
    case neck
    case upperBack
    case middleBack
    case lowerBack
    case leftArmBack
    case upperLeftArmBack
    case lowerLeftArmBack
    case rightArmBack
    case upperRightArmBack
    case lowerRightArmBack
    case upperLeftLegBack
    case lowerLeftLegBack
    case upperRightLegBack
    case lowerRightLegBack

    var id: String { rawValue }
}

/// Simple model for a symptom
struct BodySymptom: Identifiable {
    let id = UUID()
    let name: String
}

struct SelectedRegion: Identifiable {
    let id = UUID()
    let name: String
}

/// Main BodyMapView that toggles front/back images and areas
struct BodyMapView: View {
    @EnvironmentObject var viewModel: LogItemViewModel
    
    // Tracks which side is currently shown
    @State private var side: BodySide = .front
    
    // For front and back regions
    @State private var selectedRegion: SelectedRegion? = nil
    
    // Track selected body areas
    @State private var selectedBodyAreas: Set<String> = []
    
    var body: some View {
        VStack(spacing: 10) {
            Button(action: {
                withAnimation {
                    side = (side == .front) ? .back : .front
                }
            }) {
                Text(side == .front ? "Switch to Back View" : "Switch to Front View")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                    .shadow(radius: 3)
            }
            .padding(.top, 10)
            
            GeometryReader { geometry in
                ZStack {
                    if side == .front {
                        Image("bodyFront")
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .accessibilityHidden(true)
                        
                        ForEach(BodyRegionFront.allCases, id: \.rawValue) { region in
                            let frame = frameForFrontRegion(region, in: geometry)
                            regionButton(region.rawValue, frame: frame)
                        }
                    } else {
                        Image("bodyBack")
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .accessibilityHidden(true)
                        
                        ForEach(BodyRegionBack.allCases, id: \.rawValue) { region in
                            let frame = frameForBackRegion(region, in: geometry)
                            regionButton(region.rawValue, frame: frame)
                        }
                    }
                }
            }
            .onChange(of: viewModel.selectedBodyAreas) { oldValue, newValue in
                print("selectedBodyAreas changed to: \(newValue)")
                selectedBodyAreas = newValue
            }
        }
        .onAppear {
            viewModel.synchronizeBodyAreas()
        }
        .onChange(of: viewModel.selectedSymptoms) { oldValue, newValue in
            viewModel.synchronizeBodyAreas()
        }
        .sheet(item: $selectedRegion) { selected in
            let region = selected.name
            if side == .front, let frontRegion = BodyRegionFront(rawValue: region) {
                SymptomSelectionSheetFront(
                    region: frontRegion,
                    symptoms: viewModel.symptomsForRegionAsBodySymptoms(region)
                )
                .environmentObject(viewModel)
            } else if side == .back, let backRegion = BodyRegionBack(rawValue: region) {
                SymptomSelectionSheetBack(
                    region: backRegion,
                    symptoms: viewModel.symptomsForRegionAsBodySymptoms(region)
                )
                .environmentObject(viewModel)
            }
        }
    }
    
    private func toggleRegionSelection(_ region: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let standardizedRegion = BodyRegionUtility.standardizeRegionName(region)
            print("🔄 Region toggled: \(standardizedRegion)")
            
            // Open the symptom selection sheet
            selectedRegion = SelectedRegion(name: region)
            
            // Toggle selection in ViewModel
            if viewModel.selectedBodyAreas.contains(standardizedRegion) {
                viewModel.selectedBodyAreas.remove(standardizedRegion)
                // Consider: Maybe also remove related symptoms?
            } else {
                viewModel.selectedBodyAreas.insert(standardizedRegion)
            }
            
            // Ensure local state stays synced with ViewModel
            selectedBodyAreas = viewModel.selectedBodyAreas
            print("📍 Current selected areas: \(selectedBodyAreas)")
        }
        
        viewModel.verifySymptomRegionMapping()
    }

    private func standardizeRegionName(_ region: String) -> String {
        return BodyRegionUtility.standardizeRegionName(region)
    }
    
    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    private func syncSelectedAreas() {
        // Clear first to avoid stale data
        selectedBodyAreas.removeAll()
        
        // Get from ViewModel to local
        selectedBodyAreas = viewModel.selectedBodyAreas
        
        // Make sure body areas match selected symptoms
        for symptom in viewModel.selectedSymptoms {
            if let region = viewModel.symptomToRegion[symptom] {
                let standardizedRegion = BodyRegionUtility.standardizeRegionName(region)
                viewModel.selectedBodyAreas.insert(standardizedRegion)
                selectedBodyAreas.insert(standardizedRegion)
            }
        }
    }
    
    /// Returns the tappable frame for a front region
    private func frameForFrontRegion(_ region: BodyRegionFront, in geometry: GeometryProxy) -> CGRect {
        switch region {
        case .upperLeftArm:
            return CGRect(x: geometry.size.width * 0.25,
                          y: geometry.size.height * 0.18,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.15)
        
        case .lowerLeftArm:
            return CGRect(x: geometry.size.width * 0.25,
                          y: geometry.size.height * 0.33,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.20)
        
        case .upperRightArm:
            return CGRect(x: geometry.size.width * 0.65,
                          y: geometry.size.height * 0.18,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.15)
        
        case .lowerRightArm:
            return CGRect(x: geometry.size.width * 0.65,
                          y: geometry.size.height * 0.33,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.20)
        
        case .upperLeftLeg:
            return CGRect(x: geometry.size.width * 0.43,
                          y: geometry.size.height * 0.53,
                          width: geometry.size.width * 0.08,
                          height: geometry.size.height * 0.21)
        
        case .lowerLeftLeg:
            return CGRect(x: geometry.size.width * 0.43,
                          y: geometry.size.height * 0.74,
                          width: geometry.size.width * 0.08,
                          height: geometry.size.height * 0.24)
        
        case .upperRightLeg:
            return CGRect(x: geometry.size.width * 0.49,
                          y: geometry.size.height * 0.53,
                          width: geometry.size.width * 0.08,
                          height: geometry.size.height * 0.21)
        
        case .lowerRightLeg:
            return CGRect(x: geometry.size.width * 0.49,
                          y: geometry.size.height * 0.74,
                          width: geometry.size.width * 0.08,
                          height: geometry.size.height * 0.24)
        
        // Additional regions with existing frame configurations
        case .head:
            return CGRect(x: geometry.size.width * 0.45,
                          y: geometry.size.height * 0.03,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.1)
        
        case .chest: // Combined chest region
                return CGRect(x: geometry.size.width * 0.38,
                             y: geometry.size.height * 0.18,
                             width: geometry.size.width * 0.24,
                             height: geometry.size.height * 0.15)
        
            
        case .abdomen: // Single larger abdomen region
                return CGRect(x: geometry.size.width * 0.42,
                             y: geometry.size.height * 0.33,
                             width: geometry.size.width * 0.16,
                             height: geometry.size.height * 0.12)
        
        case .pelvic:
            return CGRect(x: geometry.size.width * 0.42,
                          y: geometry.size.height * 0.45,
                          width: geometry.size.width * 0.16,
                          height: geometry.size.height * 0.08)
        }
    }
    
    /// Returns the tappable frame for a back region
    private func frameForBackRegion(_ region: BodyRegionBack, in geometry: GeometryProxy) -> CGRect {
        switch region {
        case .neck:
            return CGRect(x: geometry.size.width * 0.46,
                          y: geometry.size.height * 0.12,
                          width: geometry.size.width * 0.08,
                          height: geometry.size.height * 0.05)
            
        case .upperBack:
            return CGRect(x: geometry.size.width * 0.38,
                          y: geometry.size.height * 0.17,
                          width: geometry.size.width * 0.24,
                          height: geometry.size.height * 0.12)
            
        case .middleBack:
            return CGRect(x: geometry.size.width * 0.38,
                          y: geometry.size.height * 0.29,
                          width: geometry.size.width * 0.24,
                          height: geometry.size.height * 0.10)
            
        case .lowerBack:
            return CGRect(x: geometry.size.width * 0.42,
                          y: geometry.size.height * 0.39,
                          width: geometry.size.width * 0.16,
                          height: geometry.size.height * 0.15)
            
        case .leftArmBack:
            return CGRect(x: geometry.size.width * 0.25,
                          y: geometry.size.height * 0.18,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.35)
            
        case .upperLeftArmBack:
            return CGRect(x: geometry.size.width * 0.25,
                          y: geometry.size.height * 0.18,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.18)
            
        case .lowerLeftArmBack:
            return CGRect(x: geometry.size.width * 0.25,
                          y: geometry.size.height * 0.36,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.17)
            
        case .rightArmBack:
            return CGRect(x: geometry.size.width * 0.65,
                          y: geometry.size.height * 0.18,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.35)
            
        case .upperRightArmBack:
            return CGRect(x: geometry.size.width * 0.65,
                          y: geometry.size.height * 0.18,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.18)
            
        case .lowerRightArmBack:
            return CGRect(x: geometry.size.width * 0.65,
                          y: geometry.size.height * 0.36,
                          width: geometry.size.width * 0.1,
                          height: geometry.size.height * 0.17)
            
        case .upperLeftLegBack:
            return CGRect(x: geometry.size.width * 0.43,
                          y: geometry.size.height * 0.54,
                          width: geometry.size.width * 0.08,
                          height: geometry.size.height * 0.19)
            
        case .lowerLeftLegBack:
            return CGRect(x: geometry.size.width * 0.43,
                          y: geometry.size.height * 0.73,
                          width: geometry.size.width * 0.08,
                          height: geometry.size.height * 0.24)
            
        case .upperRightLegBack:
            return CGRect(x: geometry.size.width * 0.49,
                          y: geometry.size.height * 0.54,
                          width: geometry.size.width * 0.08,
                          height: geometry.size.height * 0.19)
            
        case .lowerRightLegBack:
            return CGRect(x: geometry.size.width * 0.49,
                          y: geometry.size.height * 0.73,
                          width: geometry.size.width * 0.08,
                          height: geometry.size.height * 0.24)
            
        }
    }
    
    /// Creates a tappable button overlay for any region (front or back)
    private func regionButton(_ region: String, frame: CGRect) -> some View {
        // Standardize the region name consistently
        let standardizedRegion = BodyRegionUtility.standardizeRegionName(region)
        
        // Simple check if the standardized region is in selectedBodyAreas
        let isSelected = selectedBodyAreas.contains(standardizedRegion)
        
        return Button(action: {
            toggleRegionSelection(region)
            hapticFeedback()
            print("🎯 Tapped region: \(region), isSelected: \(isSelected)")
        }) {
            Rectangle()
                .fill(isSelected ? Color.green.opacity(0.5) : Color.clear)
                .frame(width: frame.width, height: frame.height)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.green : Color.blue, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0.5)
                )
                .padding(2)
        }
        .position(x: frame.midX, y: frame.midY)
        .accessibilityLabel("\(region.replacingOccurrences(of: "_", with: " ").capitalized) body region")
        .accessibilityHint(isSelected ? "Selected. Double tap to deselect and view symptoms" : "Double tap to select and add symptoms")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Front/Back Symptom Selection Sheets

struct SymptomSelectionSheetFront: View {
    let region: BodyRegionFront
    let symptoms: [BodySymptom]
    
    @EnvironmentObject var viewModel: LogItemViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: SymptomDefinition.SymptomCategory? = nil

    var filteredSymptoms: [BodySymptom] {
        if selectedCategory == nil {
            // No category filter, return all symptoms
            return symptoms
        }
        
        // Filter symptoms based on selected category
        return symptoms.filter { symptom in
            // Find the symptom definition to check its category
            if let definition = viewModel.allSymptoms.first(where: { $0.name == symptom.name }) {
                return definition.category == selectedCategory
            }
            return false // If not found in allSymptoms, don't include it
        }
    }
    
    // Helper computed properties for head region
    private var physicalHeadSymptoms: [BodySymptom] {
        symptoms.filter { symptom in
            ["Headache", "Migraine", "Sinus Pain", "Head Pain"].contains(symptom.name)
        }
    }
    
    private var mentalHeadSymptoms: [BodySymptom] {
        symptoms.filter { symptom in
            ["Anxiety", "Stress", "Depression", "Mental Fatigue", "Cognitive Fog"].contains(symptom.name)
        }
    }
    
    var body: some View {
        VStack {
            // Category filter
        
            
            // Symptoms list
            symptomsListView
        }
    }
    
      
    // Extract each category button to a method
    private func categoryButton(for category: SymptomDefinition.SymptomCategory) -> some View {
        Button(action: {
            selectedCategory = (selectedCategory == category) ? nil : category
        }) {
            Text(category.rawValue.capitalized)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selectedCategory == category
                        ? Color.blue.opacity(0.3)
                        : Color.gray.opacity(0.2)
                )
                .cornerRadius(12)
        }
    }
    
    // Extract the symptoms list view to a computed property
    private var symptomsListView: some View {
        NavigationStack {
            Group {
                // For the head section in SymptomSelectionSheetFront
                if region == .head {
                    // Special layout for head region
                    VStack {
                        ScrollView {
                            // Add filter indicator if a category is selected
                            if let selectedCategory = selectedCategory {
                                HStack {
                                    Text("Filtered by: \(selectedCategory.rawValue.capitalized)")
                                    Spacer()
                                    Button("Clear") {
                                        self.selectedCategory = nil
                                    }
                                    .foregroundColor(.blue)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }
                            
                            VStack(alignment: .leading, spacing: 16) {
                                // Physical Symptoms Section
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Physical Symptoms")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    
                                    ForEach(physicalHeadSymptoms.filter { symptom in
                                        if selectedCategory == nil {
                                            return true
                                        }
                                        return viewModel.allSymptoms.first(where: { $0.name == symptom.name })?.category == selectedCategory
                                    }) { symptom in
                                        SymptomRow(symptom: symptom, viewModel: viewModel)
                                    }
                                }
                                
                                Divider()
                                    .padding(.vertical, 8)
                                
                                // Mental Symptoms Section
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Mental/Emotional Symptoms")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    
                                    ForEach(mentalHeadSymptoms.filter { symptom in
                                        if selectedCategory == nil {
                                            return true
                                        }
                                        return viewModel.allSymptoms.first(where: { $0.name == symptom.name })?.category == selectedCategory
                                    }) { symptom in
                                        SymptomRow(symptom: symptom, viewModel: viewModel)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                    .navigationTitle("Head Symptoms")
                } else {
                    // For non-head regions
                    VStack {
                        // Add filter indicator if a category is selected
                        if let selectedCategory = selectedCategory {
                            HStack {
                                Text("Filtered by: \(selectedCategory.rawValue.capitalized)")
                                Spacer()
                                Button("Clear") {
                                    self.selectedCategory = nil
                                }
                                .foregroundColor(.blue)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .padding(.bottom, 8)
                        }
                        
                        List(filteredSymptoms) { symptom in
                            SymptomRow(symptom: symptom, viewModel: viewModel)
                        }
                    }
                    .navigationTitle(region == .head ? "Head Symptoms" : "Select Symptoms - \(region.rawValue.capitalized)")
                }
            }
        }
    }
}

// Reusable symptom row
struct SymptomRow: View {
    let symptom: BodySymptom
    @ObservedObject var viewModel: LogItemViewModel
    
    var body: some View {
        Button(action: {
            if viewModel.selectedSymptoms.contains(symptom.name) {
                viewModel.removeSymptom(symptom.name)
            } else {
                viewModel.addSymptom(symptom.name)
                
                if let region = viewModel.symptomToRegion[symptom.name] {
                    let standardizedRegion = BodyRegionUtility.standardizeRegionName(region)
                    viewModel.selectedBodyAreas.insert(standardizedRegion)
                }
            }
        }) {
                    HStack {
                Text(symptom.name)
                    .foregroundColor(.primary)
                Spacer()
                if viewModel.selectedSymptoms.contains(symptom.name) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
    }
}

struct SideIndicator: View {
    let isBack: Bool
    
    var body: some View {
        Text(isBack ? "Back View" : "Front View")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color(.systemBackground))
            .cornerRadius(4)
            .shadow(radius: 1)
    }
}

struct SymptomSelectionSheetBack: View {
    let region: BodyRegionBack
    let symptoms: [BodySymptom]
    
    @EnvironmentObject var viewModel: LogItemViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: SymptomDefinition.SymptomCategory? = nil

    var filteredSymptoms: [BodySymptom] {
        if selectedCategory == nil {
            return symptoms
        }
        
        return symptoms.filter { symptom in
            if let definition = viewModel.allSymptoms.first(where: { $0.name == symptom.name }) {
                return definition.category == selectedCategory
            }
            return false
        }
    }
       
    var body: some View {
        NavigationStack {
            Group {
                VStack {
                    // Add filter indicator if a category is selected
                    if let selectedCategory = selectedCategory {
                        HStack {
                            Text("Filtered by: \(selectedCategory.rawValue.capitalized)")
                            Spacer()
                            Button("Clear") {
                                self.selectedCategory = nil
                            }
                            .foregroundColor(.blue)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .padding(.bottom, 8)
                    }

                    List(filteredSymptoms) { symptom in
                        SymptomRow(symptom: symptom, viewModel: viewModel)
                    }
                }
                .navigationTitle("Select Symptoms - \(region.rawValue.capitalized)")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            print("Back view symptoms count: \(symptoms.count)")
            print("Current selected symptoms: \(viewModel.selectedSymptoms)")
            print("Back view symptoms for \(region.rawValue): \(symptoms.map { $0.name }.joined(separator: ", "))")
        }
    }
}

// MARK: - Preview
struct BodyMapView_Previews: PreviewProvider {
    static var previews: some View {
        BodyMapView()
            .environmentObject(LogItemViewModel())
            .previewDevice("iPhone 14")
    }
}
