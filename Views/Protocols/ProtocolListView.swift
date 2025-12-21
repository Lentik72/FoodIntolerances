import SwiftUI
import SwiftData

struct ProtocolListView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: [SortDescriptor(\TherapyProtocol.dateAdded, order: .reverse)])
    private var protocols: [TherapyProtocol]
    
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var showFilters: Bool = false
    @State private var sortOption: SortOption = .newestFirst
    @State private var showAddSheet: Bool = false
    @State private var showRecommendationSheet: Bool = false
    @State private var showBrowserSheet = false
    @State private var isFileImporterPresented = false
    
    @State private var showWishlistOnly: Bool = false
    @State private var showActiveOnly: Bool = false
    @State private var showSavedProtocolInfo = false
    @State private var lastSavedProtocol: TherapyProtocol?
    @State private var showSaveError = false
    
    enum SortOption: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case alphabetical = "A-Z"
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 12) {
                    Button(action: { showAddSheet = true }) {
                        Text("Add Protocol")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(10)
                    }
                    
                    Button(action: { showRecommendationSheet = true }) {
                        Text("Find Protocols")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                HStack {
                    TextField("Search protocols...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    
                    Button {
                        withAnimation {
                            showFilters.toggle()
                        }
                    } label: {
                        Label("Filters", systemImage: showFilters ? "chevron.up" : "chevron.down")
                    }
                    .padding(.trailing)
                }
                .padding(.horizontal)
                
                if showFilters {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Category", selection: $selectedCategory) {
                            Text("All Categories").tag("All")
                            ForEach(getUniqueCategories(), id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .padding(.horizontal)
                        
                        Toggle("Show Only Wishlist", isOn: $showWishlistOnly)
                            .toggleStyle(SwitchToggleStyle(tint: .yellow))
                            .padding(.horizontal)
                        
                        Toggle("Show Only Active", isOn: $showActiveOnly)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .padding(.horizontal)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 3)
                    .padding(.horizontal)
                    .transition(.slide)
                }
                
                List {
                    if filteredProtocols.isEmpty {
                        Text("No protocols found.")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredProtocols) { proto in
                            NavigationLink(destination: ProtocolDetailView(therapyProtocol: proto)) {
                                HStack {
                                    // Standard icon
                                    Image(systemName: proto.isWishlist ? "star.fill" : "doc.text")
                                        .foregroundColor(proto.isWishlist ? .yellow : .blue)
                                    
                                    VStack(alignment: .leading) {
                                        Text(proto.title)
                                            .font(.headline)
                                        
                                        Text(proto.category)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text(proto.isActive ? "Status: Active" : "Status: Inactive")
                                            .font(.caption2)
                                            .foregroundColor(proto.isActive ? .green : .red)
                                        
                                        // Display tags with special handling for unverified protocols
                                        if let tags = proto.tags, !tags.isEmpty {
                                            HStack {
                                                if tags.contains("Web Source - Unverified") {
                                                    Text("⚠️ Unverified Web Source")
                                                        .font(.caption2)
                                                        .foregroundColor(.orange)
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 2)
                                                        .background(Color.orange.opacity(0.1))
                                                        .cornerRadius(4)
                                                } else {
                                                    Text(tags.joined(separator: ", "))
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .navigationTitle("Protocols")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showAddSheet = true }) {
                            Label("Create New", systemImage: "plus")
                        }
                        
                        Button(action: { showRecommendationSheet = true }) {
                            Label("Find Protocols", systemImage: "magnifyingglass")
                        }
                        
                        Button(action: { showBrowserSheet = true }) {
                            Label("Browse Web", systemImage: "safari")
                        }
                        
                        Button(action: importFromFile) {
                            Label("Import from File", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddProtocolSheet(isPresented: $showAddSheet)
            }
            .sheet(isPresented: $showRecommendationSheet) {
                ProtocolRecommendationsView()
            }
            .sheet(isPresented: $showBrowserSheet) {
                ProtocolBrowserView()
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.therapyProtocol, .json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let fileURL = try result.get().first else {
                        print("No file selected")
                        return
                    }
                    
                    // Start accessing the file
                    guard fileURL.startAccessingSecurityScopedResource() else {
                        print("Failed to access the file")
                        return
                    }
                    
                    defer {
                        fileURL.stopAccessingSecurityScopedResource()
                    }
                    
                    let sharingService = ProtocolSharingService()
                    if let importedProtocol = sharingService.importProtocolFromFile(fileURL) {
                        DispatchQueue.main.async {
                            modelContext.insert(importedProtocol)
                            _ = SaveHelper.save(context: modelContext, showError: $showSaveError)
                        }
                    }
                } catch {
                    print("Failed to import file: \(error)")
                }
            }
            .saveErrorAlert(isPresented: $showSaveError)

            .sheet(item: $lastSavedProtocol) { protocolItem in
                NewProtocolSavedView(
                    protocol: protocolItem,
                    onActivate: { activateProtocol(protocolItem) },
                    onDismiss: { lastSavedProtocol = nil }
                )
            }
            
            .onAppear {
                preloadDefaultProtocols() // ✅ Auto-insert protocols if none exist
                autoDeactivateProtocols()
            }
        }
    }
            // ✅ Pre-load Default Protocols
    private func preloadDefaultProtocols() {
        guard protocols.isEmpty else { return }
        
        // First create all protocols with empty arrays
        let protocol1 = TherapyProtocol(
            title: "Gut Health Support",
            category: "Digestive Health",
            instructions: "Take a probiotic supplement with breakfast daily. Increase fiber intake with vegetables, and drink at least 2 liters of water per day.",
            frequency: "Daily",
            timeOfDay: "Morning",
            duration: "4 weeks",
            symptoms: [], // Empty array initially
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 28, to: Date()),
            notes: "Avoid dairy, processed foods, and sugary beverages. Consider adding fermented foods like yogurt or kefir.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: [] // Empty array initially
        )
        
        let protocol2 = TherapyProtocol(
            title: "Immune Boost Protocol",
            category: "Immune Support",
            instructions: "Take Vitamin C 1000mg and Zinc 25mg with food daily. Add Elderberry syrup during cold seasons.",
            frequency: "Daily",
            timeOfDay: "Morning",
            duration: "3 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 21, to: Date()),
            notes: "Ensure adequate sleep (7-8 hours per night) and moderate physical activity to support immunity.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol3 = TherapyProtocol(
            title: "Sleep Optimization Plan",
            category: "Sleep Improvement",
            instructions: "Take Magnesium Glycinate (200-400mg) 30 minutes before bedtime. Avoid screen exposure 1 hour before sleep.",
            frequency: "Daily",
            timeOfDay: "Evening",
            duration: "6 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 42, to: Date()),
            notes: "Maintain a consistent sleep schedule. Consider meditation or deep breathing exercises before bed.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol4 = TherapyProtocol(
            title: "Anti-Inflammatory Diet Protocol",
            category: "Nutrition",
            instructions: "Focus on whole foods, leafy greens, and omega-3-rich foods like salmon. Avoid processed and fried foods.",
            frequency: "Daily",
            timeOfDay: "Throughout the Day",
            duration: "8 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 56, to: Date()),
            notes: "Consider adding turmeric and ginger supplements to support inflammation reduction.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol5 = TherapyProtocol(
            title: "Detox Support Plan",
            category: "Liver Health",
            instructions: "Take Milk Thistle extract daily with meals. Increase water intake to support detoxification.",
            frequency: "Daily",
            timeOfDay: "Morning",
            duration: "3 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 21, to: Date()),
            notes: "Avoid alcohol and processed foods. Add cruciferous vegetables like broccoli to support liver health.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol6 = TherapyProtocol(
            title: "Anxiety Management Protocol",
            category: "Mental Wellness",
            instructions: "Practice mindfulness meditation daily for 10 minutes. Consider L-theanine supplementation (100-200mg) as needed.",
            frequency: "Daily",
            timeOfDay: "Morning",
            duration: "4 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 28, to: Date()),
            notes: "Limit caffeine intake and engage in light physical activity like walking or yoga.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol7 = TherapyProtocol(
            title: "Neck and Shoulder Pain Management",
            category: "Musculoskeletal Health",
            instructions: "Practice daily neck and shoulder stretches. Use heat therapy for 15 minutes before stretching. Consider ergonomic workspace adjustments.",
            frequency: "Daily",
            timeOfDay: "Morning and Evening",
            duration: "6 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 42, to: Date()),
            notes: "Focus on posture correction. Use a supportive pillow and consider periodic breaks during work.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol8 = TherapyProtocol(
            title: "Mental Wellness and Stress Reduction",
            category: "Mental Health",
            instructions: "Practice daily meditation for 15 minutes. Use breathing techniques. Maintain a gratitude journal.",
            frequency: "Daily",
            timeOfDay: "Morning and Evening",
            duration: "8 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 56, to: Date()),
            notes: "Consider professional counseling. Limit caffeine and screen time before bed.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol9 = TherapyProtocol(
            title: "Headache and Migraine Prevention",
            category: "Neurological Health",
            instructions: "Maintain consistent sleep schedule. Stay hydrated. Identify and avoid personal triggers.",
            frequency: "Daily",
            timeOfDay: "Throughout the Day",
            duration: "12 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 84, to: Date()),
            notes: "Keep a headache diary. Consider magnesium and B-complex supplements after consulting a healthcare professional.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol10 = TherapyProtocol(
            title: "Upper Back and Arm Pain Relief",
            category: "Musculoskeletal Health",
            instructions: "Perform targeted strength and mobility exercises. Use cold/hot therapy alternately.",
            frequency: "Daily",
            timeOfDay: "Morning",
            duration: "8 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 56, to: Date()),
            notes: "Focus on gentle stretching and strengthening. Consider ergonomic workplace setup.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol11 = TherapyProtocol(
            title: "Lower Back and Leg Pain Management",
            category: "Musculoskeletal Health",
            instructions: "Daily low-impact exercises. Practice core strengthening. Use supportive footwear.",
            frequency: "Daily",
            timeOfDay: "Evening",
            duration: "10 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 70, to: Date()),
            notes: "Avoid prolonged sitting. Consider physical therapy consultation.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol12 = TherapyProtocol(
            title: "Chest and Respiratory Wellness",
            category: "Respiratory Health",
            instructions: "Practice deep breathing exercises. Stay hydrated. Use air purifiers.",
            frequency: "Daily",
            timeOfDay: "Morning and Evening",
            duration: "6 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 42, to: Date()),
            notes: "Monitor air quality. Avoid known respiratory irritants.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol13 = TherapyProtocol(
            title: "Pelvic and Menstrual Health",
            category: "Reproductive Health",
            instructions: "Track menstrual cycle. Practice gentle yoga. Manage stress levels.",
            frequency: "Daily",
            timeOfDay: "Various",
            duration: "12 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 84, to: Date()),
            notes: "Consult with a gynecologist for personalized advice.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol14 = TherapyProtocol(
            title: "Whole Body Inflammation Reduction",
            category: "Holistic Health",
            instructions: "Anti-inflammatory diet. Gentle full-body stretching. Adequate hydration.",
            frequency: "Daily",
            timeOfDay: "Throughout the Day",
            duration: "8 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 56, to: Date()),
            notes: "Consider omega-3 supplements. Prioritize sleep and stress management.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol15 = TherapyProtocol(
            title: "Comprehensive Digestive Wellness",
            category: "Digestive Health",
            instructions: "Eat slowly. Practice mindful eating. Identify food sensitivities.",
            frequency: "Daily",
            timeOfDay: "Meal Times",
            duration: "10 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 70, to: Date()),
            notes: "Consider food diary. Gradually introduce probiotics.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        let protocol16 = TherapyProtocol(
            title: "Full Body Mobility and Flexibility",
            category: "Physical Therapy",
            instructions: "Daily mobility exercises. Progressive stretching routine. Use foam rolling.",
            frequency: "Daily",
            timeOfDay: "Morning",
            duration: "12 weeks",
            symptoms: [],
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 84, to: Date()),
            notes: "Listen to your body. Modify exercises as needed.",
            isWishlist: false,
            isActive: false,
            dateAdded: Date(),
            tags: []
        )
        
        // Insert all protocols
        modelContext.insert(protocol1)
        modelContext.insert(protocol2)
        modelContext.insert(protocol3)
        modelContext.insert(protocol4)
        modelContext.insert(protocol5)
        modelContext.insert(protocol6)
        modelContext.insert(protocol7)
        modelContext.insert(protocol8)
        modelContext.insert(protocol9)
        modelContext.insert(protocol10)
        modelContext.insert(protocol11)
        modelContext.insert(protocol12)
        modelContext.insert(protocol13)
        modelContext.insert(protocol14)
        modelContext.insert(protocol15)
        modelContext.insert(protocol16)
        
        do {
            try modelContext.save()
            print("✅ Base protocols created successfully!")
            
            // Now update them with the actual symptoms and tags
            protocol1.symptoms = ["Bloating", "Indigestion", "Irregular Bowel Movements"]
            protocol1.tags = ["Gut Health", "Probiotics", "Fiber"]
            
            protocol2.symptoms = ["Fatigue", "Low Immunity", "Frequent Colds"]
            protocol2.tags = ["Immunity", "Vitamins", "Zinc", "Elderberry"]
            
            protocol3.symptoms = ["Insomnia", "Poor Sleep Quality", "Fatigue"]
            protocol3.tags = ["Sleep", "Magnesium", "Relaxation"]
            
            protocol4.symptoms = ["Chronic Inflammation", "Joint Pain", "Digestive Issues"]
            protocol4.tags = ["Anti-Inflammatory", "Omega-3", "Turmeric"]
            
            protocol5.symptoms = ["Fatigue", "Skin Issues", "Digestive Sluggishness"]
            protocol5.tags = ["Detox", "Liver", "Milk Thistle"]
            
            protocol6.symptoms = ["Anxiety", "Stress", "Restlessness"]
            protocol6.tags = ["Anxiety", "Mindfulness", "L-theanine"]
            
            protocol7.symptoms = ["Neck Pain", "Shoulder Tension Left", "Shoulder Tension Right", "Stiff Neck"]
            protocol7.tags = ["Neck Pain", "Stretching", "Ergonomics"]
            
            protocol8.symptoms = ["Anxiety", "Stress", "Depression", "Mental Fatigue", "Cognitive Fog"]
            protocol8.tags = ["Meditation", "Mental Health", "Stress Management"]
            
            protocol9.symptoms = ["Headache", "Migraine", "Sinus Pain", "Vertigo", "Dizziness"]
            protocol9.tags = ["Headache", "Migraine", "Hydration"]
            
            protocol10.symptoms = ["Upper Back Pain", "Shoulder Pain", "Arm Pain", "Elbow Pain", "Wrist Pain"]
            protocol10.tags = ["Upper Body", "Pain Management", "Mobility"]
            
            protocol11.symptoms = ["Lower Back Pain", "Sciatica", "Leg Pain", "Knee Pain", "Thigh Pain"]
            protocol11.tags = ["Back Pain", "Exercise", "Mobility"]
            
            protocol12.symptoms = ["Chest Pain", "Chest Tightness", "Breathing Difficulty", "Shortness of Breath"]
            protocol12.tags = ["Breathing", "Respiratory Health", "Air Quality"]
            
            protocol13.symptoms = ["Pelvic Pain", "Groin Discomfort", "Menstrual Cramps"]
            protocol13.tags = ["Menstrual Cramps", "Women's Wellness", "Pelvic Pain"]
            
            protocol14.symptoms = ["Joint Pain", "Muscle Soreness", "Fatigue"]
            protocol14.tags = ["Inflammation", "Diet", "Wellness"]
            
            protocol15.symptoms = ["Abdominal Pain", "Stomach Pain", "Digestive Discomfort", "Indigestion"]
            protocol15.tags = ["Digestion", "Gut Health", "Nutrition"]
            
            protocol16.symptoms = ["Muscle Strain", "Muscle Soreness", "Restricted Movement"]
            protocol16.tags = ["Mobility", "Stretching", "Recovery"]
            
            try modelContext.save()
            print("✅ Protocols updated with symptoms and tags!")
        } catch {
            print("❌ Error saving protocols: \(error)")
        }
    }
            
            private func preloadRecommendedProtocols() {
                let recommendedProtocols = [
                    
                    TherapyProtocol(
                        title: "Gut Health Support",
                        category: "Digestive Health",
                        instructions: "Take a probiotic supplement with breakfast daily. Increase fiber intake with vegetables, and drink at least 2 liters of water per day.",
                        frequency: "Daily",
                        timeOfDay: "Morning",
                        duration: "4 weeks",
                        symptoms: ["Bloating", "Indigestion", "Irregular Bowel Movements"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 28, to: Date()),
                        notes: "Avoid dairy, processed foods, and sugary beverages. Consider adding fermented foods like yogurt or kefir.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Gut Health", "Probiotics", "Fiber"]
                    ),
                    TherapyProtocol(
                        title: "Immune Boost Protocol",
                        category: "Immune Support",
                        instructions: "Take Vitamin C 1000mg and Zinc 25mg with food daily. Add Elderberry syrup during cold seasons.",
                        frequency: "Daily",
                        timeOfDay: "Morning",
                        duration: "3 weeks",
                        symptoms: ["Fatigue", "Low Immunity", "Frequent Colds"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 21, to: Date()),
                        notes: "Ensure adequate sleep (7-8 hours per night) and moderate physical activity to support immunity.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Immunity", "Vitamins", "Zinc", "Elderberry"]
                    ),
                    TherapyProtocol(
                        title: "Sleep Optimization Plan",
                        category: "Sleep Improvement",
                        instructions: "Take Magnesium Glycinate (200-400mg) 30 minutes before bedtime. Avoid screen exposure 1 hour before sleep.",
                        frequency: "Daily",
                        timeOfDay: "Evening",
                        duration: "6 weeks",
                        symptoms: ["Insomnia", "Poor Sleep Quality", "Fatigue"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 42, to: Date()),
                        notes: "Maintain a consistent sleep schedule. Consider meditation or deep breathing exercises before bed.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Sleep", "Magnesium", "Relaxation"]
                    ),
                    TherapyProtocol(
                        title: "Anti-Inflammatory Diet Protocol",
                        category: "Nutrition",
                        instructions: "Focus on whole foods, leafy greens, and omega-3-rich foods like salmon. Avoid processed and fried foods.",
                        frequency: "Daily",
                        timeOfDay: "Throughout the Day",
                        duration: "8 weeks",
                        symptoms: ["Chronic Inflammation", "Joint Pain", "Digestive Issues"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 56, to: Date()),
                        notes: "Consider adding turmeric and ginger supplements to support inflammation reduction.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Anti-Inflammatory", "Omega-3", "Turmeric"]
                    ),
                    TherapyProtocol(
                        title: "Detox Support Plan",
                        category: "Liver Health",
                        instructions: "Take Milk Thistle extract daily with meals. Increase water intake to support detoxification.",
                        frequency: "Daily",
                        timeOfDay: "Morning",
                        duration: "3 weeks",
                        symptoms: ["Fatigue", "Skin Issues", "Digestive Sluggishness"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 21, to: Date()),
                        notes: "Avoid alcohol and processed foods. Add cruciferous vegetables like broccoli to support liver health.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Detox", "Liver", "Milk Thistle"]
                    ),
                    TherapyProtocol(
                        title: "Anxiety Management Protocol",
                        category: "Mental Wellness",
                        instructions: "Practice mindfulness meditation daily for 10 minutes. Consider L-theanine supplementation (100-200mg) as needed.",
                        frequency: "Daily",
                        timeOfDay: "Morning",
                        duration: "4 weeks",
                        symptoms: ["Anxiety", "Stress", "Restlessness"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 28, to: Date()),
                        notes: "Limit caffeine intake and engage in light physical activity like walking or yoga.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Anxiety", "Mindfulness", "L-theanine"]
                    ),
                    TherapyProtocol(
                        title: "Neck and Shoulder Pain Management",
                        category: "Musculoskeletal Health",
                        instructions: "Practice daily neck and shoulder stretches. Use heat therapy for 15 minutes before stretching. Consider ergonomic workspace adjustments.",
                        frequency: "Daily",
                        timeOfDay: "Morning and Evening",
                        duration: "6 weeks",
                        symptoms: ["Neck Pain", "Shoulder Tension Left", "Shoulder Tension Right", "Stiff Neck"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 42, to: Date()),
                        notes: "Focus on posture correction. Use a supportive pillow and consider periodic breaks during work.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Neck Pain", "Stretching", "Ergonomics"]
                    ),
                    TherapyProtocol(
                        title: "Mental Wellness and Stress Reduction",
                        category: "Mental Health",
                        instructions: "Practice daily meditation for 15 minutes. Use breathing techniques. Maintain a gratitude journal.",
                        frequency: "Daily",
                        timeOfDay: "Morning and Evening",
                        duration: "8 weeks",
                        symptoms: ["Anxiety", "Stress", "Depression", "Mental Fatigue", "Cognitive Fog"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 56, to: Date()),
                        notes: "Consider professional counseling. Limit caffeine and screen time before bed.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Meditation", "Mental Health", "Stress Management"]
                    ),
                    TherapyProtocol(
                        title: "Headache and Migraine Prevention",
                        category: "Neurological Health",
                        instructions: "Maintain consistent sleep schedule. Stay hydrated. Identify and avoid personal triggers.",
                        frequency: "Daily",
                        timeOfDay: "Throughout the Day",
                        duration: "12 weeks",
                        symptoms: ["Headache", "Migraine", "Sinus Pain", "Vertigo", "Dizziness"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 84, to: Date()),
                        notes: "Keep a headache diary. Consider magnesium and B-complex supplements after consulting a healthcare professional.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Headache", "Migraine", "Hydration"]
                    ),
                    TherapyProtocol(
                        title: "Upper Back and Arm Pain Relief",
                        category: "Musculoskeletal Health",
                        instructions: "Perform targeted strength and mobility exercises. Use cold/hot therapy alternately.",
                        frequency: "Daily",
                        timeOfDay: "Morning",
                        duration: "8 weeks",
                        symptoms: ["Upper Back Pain", "Shoulder Pain", "Arm Pain", "Elbow Pain", "Wrist Pain"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 56, to: Date()),
                        notes: "Focus on gentle stretching and strengthening. Consider ergonomic workplace setup.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Upper Body", "Pain Management", "Mobility"]
                    ),
                    TherapyProtocol(
                        title: "Lower Back and Leg Pain Management",
                        category: "Musculoskeletal Health",
                        instructions: "Daily low-impact exercises. Practice core strengthening. Use supportive footwear.",
                        frequency: "Daily",
                        timeOfDay: "Evening",
                        duration: "10 weeks",
                        symptoms: ["Lower Back Pain", "Sciatica", "Leg Pain", "Knee Pain", "Thigh Pain"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 70, to: Date()),
                        notes: "Avoid prolonged sitting. Consider physical therapy consultation.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Back Pain", "Exercise", "Mobility"]
                    ),
                    TherapyProtocol(
                        title: "Chest and Respiratory Wellness",
                        category: "Respiratory Health",
                        instructions: "Practice deep breathing exercises. Stay hydrated. Use air purifiers.",
                        frequency: "Daily",
                        timeOfDay: "Morning and Evening",
                        duration: "6 weeks",
                        symptoms: ["Chest Pain", "Chest Tightness", "Breathing Difficulty", "Shortness of Breath"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 42, to: Date()),
                        notes: "Monitor air quality. Avoid known respiratory irritants.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Breathing", "Respiratory Health", "Air Quality"]
                    ),
                    TherapyProtocol(
                        title: "Pelvic and Menstrual Health",
                        category: "Reproductive Health",
                        instructions: "Track menstrual cycle. Practice gentle yoga. Manage stress levels.",
                        frequency: "Daily",
                        timeOfDay: "Various",
                        duration: "12 weeks",
                        symptoms: ["Pelvic Pain", "Groin Discomfort", "Menstrual Cramps"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 84, to: Date()),
                        notes: "Consult with a gynecologist for personalized advice.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Menstrual Cramps", "Women's Wellness"]
                    ),
                    TherapyProtocol(
                        title: "Whole Body Inflammation Reduction",
                        category: "Holistic Health",
                        instructions: "Anti-inflammatory diet. Gentle full-body stretching. Adequate hydration.",
                        frequency: "Daily",
                        timeOfDay: "Throughout the Day",
                        duration: "8 weeks",
                        symptoms: ["Joint Pain", "Muscle Soreness", "Fatigue"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 56, to: Date()),
                        notes: "Consider omega-3 supplements. Prioritize sleep and stress management.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Inflammation", "Diet", "Wellness"]
                    ),
                    TherapyProtocol(
                        title: "Comprehensive Digestive Wellness",
                        category: "Digestive Health",
                        instructions: "Eat slowly. Practice mindful eating. Identify food sensitivities.",
                        frequency: "Daily",
                        timeOfDay: "Meal Times",
                        duration: "10 weeks",
                        symptoms: ["Abdominal Pain", "Stomach Pain", "Digestive Discomfort", "Indigestion"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 70, to: Date()),
                        notes: "Consider food diary. Gradually introduce probiotics.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Digestion", "Gut Health", "Nutrition"]
                    ),
                    TherapyProtocol(
                        title: "Full Body Mobility and Flexibility",
                        category: "Physical Therapy",
                        instructions: "Daily mobility exercises. Progressive stretching routine. Use foam rolling.",
                        frequency: "Daily",
                        timeOfDay: "Morning",
                        duration: "12 weeks",
                        symptoms: ["Muscle Strain", "Muscle Soreness", "Restricted Movement"],
                        startDate: Date(),
                        endDate: Calendar.current.date(byAdding: .day, value: 84, to: Date()),
                        notes: "Listen to your body. Modify exercises as needed.",
                        isWishlist: false,
                        isActive: false,
                        dateAdded: Date(),
                        tags: ["Mobility", "Stretching", "Recovery"]
                    )
                ]
                
                for proto in recommendedProtocols {
                    modelContext.insert(proto)
                }
            }
            
            private func importFromFile() {
                isFileImporterPresented = true
            }
            
            private func deleteProtocol(at offsets: IndexSet) {
                for index in offsets {
                    let protocolToDelete = protocols[index]
                    modelContext.delete(protocolToDelete)
                }
                do {
                    try modelContext.save()
                } catch {
                    print("❌ Error deleting protocol: \(error)")
                }
            }
            
            private func autoDeactivateProtocols() {
                let today = Date()
                
                for proto in protocols where proto.isActive {
                    if let endDate = proto.endDate, endDate < today {
                        proto.isActive = false
                        print("⏸️ Protocol '\(proto.title)' has been auto-deactivated.")
                    }
                }
                
                do {
                    try modelContext.save()
                } catch {
                    print("❌ Error auto-deactivating protocols: \(error)")
                }
            }
            
            private var filteredProtocols: [TherapyProtocol] {
                let lowerSearch = searchText.lowercased().trimmingCharacters(in: .whitespaces)
                
                return protocols.filter { proto in
                    let titleMatch = proto.title.lowercased().contains(lowerSearch)
                    let tagMatch = (proto.tags ?? []).contains { $0.lowercased().contains(lowerSearch) }
                    let categoryMatch = selectedCategory == "All" || proto.category == selectedCategory
                    let wishlistMatch = showWishlistOnly ? proto.isWishlist : true
                    let activeMatch = showActiveOnly ? proto.isActive : true
                    
                    return (titleMatch || tagMatch || lowerSearch.isEmpty) && categoryMatch && wishlistMatch && activeMatch
                }
            }
            
            private func getUniqueCategories() -> [String] {
                let categories = protocols.map { $0.category }
                return Array(Set(categories)).sorted()
            }
    
    private func activateProtocol(_ `protocol`: TherapyProtocol) {
        `protocol`.isActive = true
        do {
            try modelContext.save()
        } catch {
            print("Error activating protocol: \(error)")
        }
    }
        }

