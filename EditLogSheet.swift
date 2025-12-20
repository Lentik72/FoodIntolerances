import SwiftUI
import SwiftData
import PhotosUI

struct EditLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var log: LogEntry

    @State private var trackOverTime: Bool = false
    @State private var showProtocolRecommendations = false
    @State private var selectedProtocol: TherapyProtocol?
    @State private var showFullScreenImage = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    @Query(filter: #Predicate<TherapyProtocol> { $0.isActive }, sort: \TherapyProtocol.dateAdded)
    private var activeProtocols: [TherapyProtocol]

    private func getSubcategoriesForCategory(_ category: String) -> [String] {
        switch category {
        case "Mental":
            return ["Stress", "Anxiety", "Depression", "Burnout", "Trauma", "Overthinking",
                   "Mood Swings", "Emotional Exhaustion"]
        case "Environmental":
            return ["Weather Changes", "Allergens", "Air Quality", "Temperature", "Humidity",
                   "Noise Pollution", "Lighting", "Seasonal Changes"]
        case "Physical":
            return ["Exercise", "Fatigue", "Injury", "Posture", "Sleep Disruption",
                   "Overexertion", "Muscle Strain", "Dehydration"]
        case "Food/Drink":
            return ["Meal", "Snack", "Drink", "Alcohol", "Caffeine", "Processed Foods",
                   "Dairy", "Gluten", "Sugar", "Spicy Foods"]
        case "Beverages":
            return ["Water", "Coffee", "Tea", "Alcohol", "Juice", "Energy Drinks",
                   "Smoothies", "Carbonated Drinks"]
        case "Unknown":
            return ["Unexplained", "Random", "No Clear Cause", "Other"]
        default:
            return []
        }
    }
    
    private var trackingBinding: Binding<Bool> {
            Binding<Bool>(
                get: {
                    // Explicit conversion with nil handling
                    guard let ongoing = log.isOngoing else { return false }
                    return ongoing
                },
                set: { newValue in
                    // Explicitly manage optional bool and start date
                    log.isOngoing = newValue
                    
                    if newValue {
                        log.startDate = Date()
                    } else {
                        log.startDate = nil
                    }
                }
            )
        }
    
    private func subcategoryBinding(for subcategory: String) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                // Safely check if subcategories contains the item
                (log.subcategories).contains(subcategory)
            },
            set: { isSelected in
                // Create a mutable copy of subcategories
                var currentSubcategories = log.subcategories 
                
                if isSelected {
                    // Add only if not already present
                    if !currentSubcategories.contains(subcategory) {
                        currentSubcategories.append(subcategory)
                    }
                } else {
                    // Remove the subcategory
                    currentSubcategories.removeAll { $0 == subcategory }
                }
                
                // Update the log's subcategories
                log.subcategories = currentSubcategories
            }
        )
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Symptoms & Basic Info
                Section(header: Text("Symptom Details")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Symptom/s:")
                                .foregroundColor(.secondary)
                            Text(log.itemName)
                                .bold()
                        }
                        
                        if let foodDrink = log.foodDrinkItem, !foodDrink.isEmpty {
                            HStack {
                                Text("Food/Drink:")
                                    .foregroundColor(.secondary)
                                Text(foodDrink)
                                    .bold()
                            }
                        }
                    }
                    
                    // Severity with stars
                    HStack {
                        Text("Severity:")
                            .foregroundColor(.secondary)
                        Spacer()
                        ForEach(1...5, id: \.self) { rating in
                            Image(systemName: rating <= log.severity ? "star.fill" : "star")
                                .foregroundColor(rating <= log.severity ? .yellow : .gray)
                                .onTapGesture {
                                    log.severity = rating
                                }
                        }
                    }
                    
                    DatePicker("Date", selection: $log.date, displayedComponents: .date)
                }

                // Tracking Status
                Section(header: Text("Tracking Status")) {
                    Toggle("Track Over Time", isOn: trackingBinding)
                        .tint(.green)
                    
                    if log.isOngoing == true {
                        if let startDate = log.startDate {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.green)
                                Text("Tracking since: \(startDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                // Protocol Management
                Section(header: Text("Protocol Management")) {
                    if let protocolID = log.protocolID {
                        ProtocolStatusView(protocolID: protocolID)
                        
                        HStack {
                            Button(action: {
                                showProtocolRecommendations = true
                            }) {
                                Label("Change Protocol", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .foregroundColor(.blue)
                            
                            Spacer()
                            
                            Button(action: {
                                log.protocolID = nil
                                try? modelContext.save()
                            }) {
                                Label("Remove", systemImage: "trash")
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        Button(action: {
                            showProtocolRecommendations = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Protocol")
                            }
                        }
                        .foregroundColor(.blue)
                    }
                }

                // Environmental Factors
                Section(header: Text("Environmental Factors")) {
                    if !log.atmosphericPressure.isEmpty {
                        HStack {
                            Image(systemName: "wind")
                            Text("Pressure: \(log.atmosphericPressure)")
                        }
                    }
                    
                    if !log.moonPhase.isEmpty {
                        HStack {
                            Image(systemName: "moon.fill")
                            Text("Moon Phase: \(log.moonPhase)")
                        }
                    }
                    
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Mercury: \(log.isMercuryRetrograde ? "In Retrograde ☿" : "Direct ☿")")
                    }
                }

                Section(header: Text("Time and Category")) {
                    DatePicker("Time", selection: Binding(
                        get: { log.timeOfDay ?? Date() },
                        set: { log.timeOfDay = $0 }
                    ), displayedComponents: .hourAndMinute)
                    
                    Picker("Category", selection: Binding(
                        get: {
                            LogCategory(rawValue: log.category) ?? .other
                        },
                        set: {
                            log.category = $0.rawValue
                            // Reset subcategories when category changes
                            log.subcategories = []  // Use empty array instead of nil
                        }
                    )) {
                        ForEach(LogCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }

                    if let selectedCategory = LogCategory(rawValue: log.category) {
                        Picker("Subcategory", selection: Binding(
                            get: {
                                log.subcategories.first ?? ""
                            },
                            set: { newSubcategory in
                                // If newSubcategory is empty, set to an empty array
                                // Otherwise, create a single-item array
                                log.subcategories = newSubcategory.isEmpty ? [] : [newSubcategory]
                            }
                        )) {
                            Text("None").tag("")
                            ForEach(selectedCategory.subcategories, id: \.self) { subcategory in
                                Text(subcategory).tag(subcategory)
                            }
                        }
                    }
                }
                
                // Pictures
                Section(header: Text("Pictures")) {
                    if let imageData = log.symptomPhotoData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .onTapGesture {
                                showFullScreenImage = true
                            }
                    }
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(log.symptomPhotoData == nil ? "Add Photo" : "Change Photo", systemImage: "photo")
                    }
                    
                    if log.symptomPhotoData != nil {
                        Button(role: .destructive) {
                            log.symptomPhotoData = nil
                        } label: {
                            Label("Delete Photo", systemImage: "trash")
                        }
                    }
                }

                // Notes
                Section(header: Text("Notes")) {
                    TextEditor(text: $log.notes)
                        .frame(height: 100)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        log.symptomPhotoData = data
                    }
                }
            }
            .fullScreenCover(isPresented: $showFullScreenImage) {
                ZStack {
                    Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
                    
                    if let imageData = log.symptomPhotoData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .pinchToZoom()
                    }
                    
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                showFullScreenImage = false
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                        }
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("Edit Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if trackOverTime {
                            let newSymptom = OngoingSymptom(
                                name: log.itemType.rawValue == "Symptom" ? log.itemName : (log.foodDrinkItem ?? "Unknown"),
                                notes: log.notes
                            )
                            modelContext.insert(newSymptom)
                        }
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            print("Error saving edited log:", error)
                        }
                    }
                }
            }
            .sheet(isPresented: $showProtocolRecommendations) {
                ProtocolRecommendationsView(
                    selectedSymptoms: Set(log.symptoms),
                    onSkip: {
                        showProtocolRecommendations = false
                    },
                    onSelectProtocol: { selectedProtocol in
                        log.protocolID = selectedProtocol.id
                        try? modelContext.save()
                        showProtocolRecommendations = false
                    }
                )
            }
        }
    }
}

// Custom View Modifier for Pinch to Zoom
struct PinchToZoom: ViewModifier {
    @State var scale: CGFloat = 1.0
    @State var lastScale: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale *= delta
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        if scale < 1.0 {
                            scale = 1.0
                        }
                    }
            )
    }
}

extension View {
    func pinchToZoom() -> some View {
        modifier(PinchToZoom())
    }
}
