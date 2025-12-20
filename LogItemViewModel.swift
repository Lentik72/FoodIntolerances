// LogItemViewModel.swift

import Foundation
import SwiftUI
import Combine
import SwiftData
import CoreLocation

// MARK: - LogItemViewModel
@MainActor
class LogItemViewModel: ObservableObject {
    
    // MARK: - Published Properties
    /// Controls the presentation of the Add Item Sheet
    ///
      
    /// Mapping from body region (a string key) to a set of symptom names selected for that region.
    @Published var regionSymptoms: [String: Set<String>] = [:]
    @Published var isFirstLoad: Bool = true
    @Published var showAddItemSheet: Bool = false
 
    /// Holds the food/drink item entered by the user
    @Published var foodDrinkItem: String = ""
   
    @Published var protocolEffectiveness: Int?
    @Published var protocolNotes: String = ""
    /// Holds the new item name entered in the Add Item Sheet
    @Published var newItemName: String = ""
    @Published var showProtocolRecommendations = false
    @Published var selectedProtocol: TherapyProtocol? = nil
    /// Determines the type of new item being added (Category or Symptom)
    @Published var newItemType: NewItemType = .category
    @Published var locationManager: LocationManager?
    @Published var userZIP: String = ""  // Optional ZIP code entry
    /// Currently selected category
    @Published var selectedCategory: String = "Beverages"
    @Published var environmentalService = EnvironmentalDataService()
    /// Selected cause type from Picker
    @Published var causeType: CauseType = .foodAndDrink
    
    /// Set of selected subcategories based on the selected cause type
    @Published var causeSubcategories: Set<String> = []
    @Published var allSymptoms: [SymptomDefinition] = []
    /// Moon phase information fetched from the API
    @Published var autoMoonPhase: String = "Loading..."
    @Published var lastUpdated: Date = Date() // trigger UI refresh
    /// Anmospheric pressure
    @Published var isLocationReady: Bool = false
    @Published var atmosphericPressure: String = "Loading..." {
        didSet {
            DispatchQueue.main.async {
                self.lastUpdated = Date() // ✅ Trigger UI refresh
            }
        }
    }
    @Published var atmosphericPressureCategory: String = "Unknown"
    @Published var suddenPressureChange: Bool = false
    private var lastRecordedPressure: Double? = nil
    @Published var currentPressure: Double = 0.0
    @Published var previousPressure: Double = 0.0
    
    /// Indicates if Mercury is in retrograde based on the API
    @Published var autoMercuryRetrograde: Bool = false
    
    /// Custom categories added by the user, persisted in UserDefaults
    @Published var customCategories: [String] = UserDefaults.standard.stringArray(forKey: "customCategories") ?? ["Beverages", "Meats", "Nuts & Seeds", "Vegetables", "Supplements", "Other"]
    
    /// List of symptoms filtered based on user search
    @Published var filteredSymptoms: [String] = []
    
    /// Set of symptoms selected by the user
    @Published var selectedSymptoms: Set<String> = []
    
    func toggleSelection(for symptom: String) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if !selectedSymptoms.insert(symptom).inserted {
                    selectedSymptoms.remove(symptom)
                }
            }
            print("Current selectedSymptoms: \(selectedSymptoms)")
        }
    /// Severity rating for the symptom (1 to 5)
    @Published var severity: Double = 1
    
    /// Additional notes entered by the user
    @Published var notes: String = ""
    
    /// Date selected for the symptom log
    @Published var date: Date = Date() {
        didSet {
            currentSeason = determineSeason(for: date) // 🌱 Update season on date change
        }
    }
    @Published var currentSeason: String = "" // 🌱 Added for Seasonal Tracking
    /// Controls the presentation of alert messages
    @Published var showAlert: Bool = false
    
    /// The message displayed in alerts
    @Published var alertMessage: String = ""
    
    /// Controls the presentation of the saved confirmation message
    @Published var showSavedMessage: Bool = false
    
    /// Set of affected body areas selected by the user
    @Published var selectedBodyAreas: Set<String> = []
    
    /// Indicates if the symptom is internal
    @Published var isInternalSymptom: Bool = false
    
    /// Specifies the internal affected area if applicable
    @Published var internalAffectedArea: String = ""
    
    /// Controls the presentation of severity information sheet
    @Published var showSeverityInfo: Bool = false
    
    @Published var imageData: Data? = nil
    @Published var alertType: AlertType = .error
    @Published var suggestedAvoidItem: String = ""
    /// User-entered search text for symptoms (managed by ViewModel)
    @Published var symptomSearchText: String = ""
    
    /// Current step in the logging process
    @Published var currentStep: LogStep = .symptomSelection
    
    @AppStorage("lastPressureReading") var lastPressureReading: Double = 0
    @AppStorage("lastPressureTimestamp") var lastPressureTimestamp: Date = Date()
    @AppStorage("recentSymptoms") private var recentSymptomsData: Data = Data()
    
    private var pressureReadings: [(pressure: Double, timestamp: Date)] = []
    private let pressureChangeThreshold: Double = 6.0
    private let pressureReadingInterval: TimeInterval = 3600 // 1 hour in seconds
    private var lastFetchTime: Date = .distantPast
    private let minimumFetchInterval: TimeInterval = 60 // 1 minute
    // MARK: - Enumerations
    
    /// Enumeration for different types of new items that can be added
    enum NewItemType: String, CaseIterable, Identifiable {
        case category = "Category"
        case symptom = "Symptom"
        var id: String { rawValue }
    }
    
    enum AlertType {
        case error
        case success
        case avoidSuggestion
    }
    
    /// Enumeration for different cause types
    enum CauseType: String, CaseIterable, Identifiable {
        case mental = "Mental"
        case environmental = "Environmental"
        case physical = "Physical"
        case foodAndDrink = "Food/Drink"
        case unknown = "Unknown"
        var id: String { rawValue }
    }
    
    /// Enumeration for the logging steps
    enum LogStep: Int, CaseIterable, Identifiable {
        case symptomSelection
        case causeIdentification
        case severityRating
        case affectedAreas
        case dateNotes
        case review
        
        var id: Int { rawValue }
        
        var title: String {
            switch self {
            case .symptomSelection: return "Select Symptoms"
            case .causeIdentification: return "Identify Cause"
            case .severityRating: return "Rate Severity"
            case .affectedAreas: return "Affected Areas"
            case .dateNotes: return "Date & Notes"
            case .review: return "Review & Save"
            }
        }
    }
    
    // Add this AFTER the existing enums, before the class definition
    enum LogCategory: String, CaseIterable, Identifiable {
        case beverages = "Beverages"
        case meats = "Meats"
        case nutsAndSeeds = "Nuts & Seeds"
        case vegetables = "Vegetables"
        case supplements = "Supplements"
        case mental = "Mental"
        case environmental = "Environmental"
        case physical = "Physical"
        case other = "Other"
        
        var id: String { rawValue }
        
        var subcategories: [String] {
                switch self {
                case .beverages:
                    return ["Water", "Coffee", "Tea", "Juice", "Alcohol", "Energy Drinks"]
                case .meats:
                    return ["Beef", "Chicken", "Pork", "Fish", "Lamb"]
                case .nutsAndSeeds:
                    return ["Almonds", "Walnuts", "Peanuts", "Sunflower Seeds", "Chia Seeds"]
                case .vegetables:
                    return ["Leafy Greens", "Root Vegetables", "Cruciferous", "Nightshades"]
                case .supplements:
                    return ["Vitamins", "Minerals", "Herbal", "Protein"]
                case .mental:
                    return ["Stress", "Anxiety", "Depression", "Burnout"]
                case .environmental:
                    return ["Weather", "Pollution", "Temperature", "Humidity"]
                case .physical:
                    return ["Exercise", "Injury", "Fatigue", "Sleep"]
                case .other:
                    return ["Unexplained", "Random", "Miscellaneous"]
                }
            }
        }
    
    // MARK: - Category Lists
    
    /// Categories under Mental cause type
    @Published var mentalCategories: [String] = [
        "Stress",
        "Anxiety",
        "Depression",
        "Burnout",
        "Trauma",
        "Overthinking",
        "Mood Swings",
        "Emotional Exhaustion"
    ]
    
    // Add to existing properties
    @Published var symptomTriggers: [String] = [
        "Diet Change",
        "Weather Change",
        "Medication",
        "Alcohol",
        "Caffeine",
        "Hormonal Changes",
        "Travel",
        "Work Pressure",
        "Social Interaction"
    ]
    
    @Published var selectedSymptomTriggers: Set<String> = []

    @Published var additionalNotes: String = ""

  
    /// Categories under Environmental cause type
    @Published var environmentalCategories: [String] = [
        "Weather Changes",
        "Allergens",
        "Air Quality",
        "Temperature",
        "Humidity",
        "Noise Pollution",
        "Lighting",
        "Seasonal Changes"
    ]
    
    /// Categories under Physical cause type
    @Published var physicalCategories: [String] = [
        "Exercise",
        "Fatigue",
        "Injury",
        "Posture",
        "Sleep Disruption",
        "Overexertion",
        "Muscle Strain",
        "Dehydration"
    ]
    
    /// Categories under Food & Drink cause type
    @Published var foodAndDrinkCategories: [String] = [
        "Meal",
        "Snack",
        "Drink",
        "Alcohol",
        "Caffeine",
        "Processed Foods",
        "Dairy",
        "Gluten",
        "Sugar",
        "Spicy Foods"
    ]
    
    /// Categories under Unknown cause type
    @Published var unknownCategories: [String] = [
        "Unexplained",
        "Random",
        "No Clear Cause",
        "Other"
    ]
    
    // MARK: - Predefined Symptoms Catalog
    
    /// List of predefined symptoms
    var predefinedSymptoms: [String] {
        return allSymptoms.map { $0.name }
    }
    
    // Replace the existing symptomToRegion dictionary with this computed property
    var symptomToRegion: [String: String] {
        var mapping: [String: String] = [:]
        for symptom in allSymptoms {
            mapping[symptom.name] = symptom.regionId
        }
        return mapping
    }
    
    var headRelatedSymptoms: [String] {
        return Array(symptomToRegion.filter { $0.value == "head" }.keys)
    }
    
    // Group the currently selected symptoms by their mapped region.
    var computedRegionSymptoms: [String: [String]] {
        Dictionary(grouping: selectedSymptoms, by: { symptom in
            return symptomToRegion[symptom] ?? ""
        })
    }
    
    // MARK: - Initializer
    
    /// Initializes the view model and sets up any necessary data
    init() {
        initializeAllSymptoms()
        initializeSymptoms()
        setupSymptomSearchListener()
        currentSeason = determineSeason(for: date)
        
        // Initialize location manager first
        self.locationManager = LocationManager(viewModel: self)
        
        // Initialize environmental service
        self.environmentalService = EnvironmentalDataService()
        
        // Initial data fetch with timeout protection
        Task {
            await fetchAllData()
            
            // If still loading after fetch, set fallback values
            if atmosphericPressureCategory == "Loading..." {
                atmosphericPressureCategory = "Normal"
                atmosphericPressure = "1013 hPa"
            }
        }
        
        // Mercury retrograde periods setup
        self.mercuryRetrogradePeriods = [
            // 2025 periods
            (start: createDate(year: 2025, month: 3, day: 14), end: createDate(year: 2025, month: 4, day: 7)),
            (start: createDate(year: 2025, month: 7, day: 17), end: createDate(year: 2025, month: 8, day: 11)),
            (start: createDate(year: 2025, month: 11, day: 9), end: createDate(year: 2025, month: 11, day: 29)),
            // 2026 periods
            (start: createDate(year: 2026, month: 2, day: 25), end: createDate(year: 2026, month: 3, day: 20)),
            (start: createDate(year: 2026, month: 6, day: 29), end: createDate(year: 2026, month: 7, day: 23)),
            (start: createDate(year: 2026, month: 10, day: 24), end: createDate(year: 2026, month: 11, day: 13))
        ]
    }
    
    private func initializeAllSymptoms() {
        
        var uniqueSymptoms: [SymptomDefinition] = []
            var seenSymptomNames = Set<String>()
            
            for symptom in [
            // Head region
            SymptomDefinition(name: "Headache", regionId: "head", category: .neurological),
            SymptomDefinition(name: "Migraine", regionId: "head", category: .neurological),
            SymptomDefinition(name: "Sinus Pain", regionId: "head", category: .neurological),
            SymptomDefinition(name: "Vertigo", regionId: "head", category: .neurological),
            SymptomDefinition(name: "Dizziness", regionId: "head", category: .neurological),
            SymptomDefinition(name: "Eye Pain", regionId: "head", category: .physical),
            SymptomDefinition(name: "Anxiety", regionId: "head", category: .mental),
            SymptomDefinition(name: "Stress", regionId: "head", category: .mental),
            SymptomDefinition(name: "Depression", regionId: "head", category: .mental),
            SymptomDefinition(name: "Mental Fatigue", regionId: "head", category: .mental),
            SymptomDefinition(name: "Cognitive Fog", regionId: "head", category: .mental),
            
            // Neck region
            SymptomDefinition(name: "Neck Pain", regionId: "neck", category: .musculoskeletal),
            SymptomDefinition(name: "Stiff Neck", regionId: "neck", category: .musculoskeletal),
            SymptomDefinition(name: "Shoulder Pain", regionId: "neck", category: .musculoskeletal),
            SymptomDefinition(name: "Cervical Pain", regionId: "neck", category: .musculoskeletal),
            
            // Chest region
            SymptomDefinition(name: "Chest Pain", regionId: "chest", category: .respiratory),
            SymptomDefinition(name: "Chest Tightness", regionId: "chest", category: .respiratory),
            SymptomDefinition(name: "Breathing Difficulty", regionId: "chest", category: .respiratory),
            SymptomDefinition(name: "Shortness of Breath", regionId: "chest", category: .respiratory),
            SymptomDefinition(name: "Cough", regionId: "chest", category: .respiratory),
            SymptomDefinition(name: "Upper Chest Tightness", regionId: "chest", category: .respiratory),
            SymptomDefinition(name: "Lower Chest Pain", regionId: "chest", category: .respiratory),
            SymptomDefinition(name: "Bronchial Discomfort", regionId: "chest", category: .respiratory),
            SymptomDefinition(name: "Diaphragm Tension", regionId: "chest", category: .respiratory),
            
            // Abdomen region
            SymptomDefinition(name: "Abdominal Pain", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Stomach Pain", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Bloating", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Nausea", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Vomiting", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Loose Stool", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Hard Stool", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Digestive Discomfort", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Upper Abdominal Cramps", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Lower Abdominal Pain", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Indigestion", regionId: "abdomen", category: .digestive),
            SymptomDefinition(name: "Stomach Ache", regionId: "abdomen", category: .digestive),
            
            // Pelvic region
            SymptomDefinition(name: "Pelvic Pain", regionId: "pelvic", category: .physical),
            SymptomDefinition(name: "Groin Discomfort", regionId: "pelvic", category: .physical),
            SymptomDefinition(name: "Menstrual Cramps", regionId: "pelvic", category: .physical),
            SymptomDefinition(name: "Hip Discomfort", regionId: "pelvic", category: .physical),
            
            // Back regions
            SymptomDefinition(name: "Upper Back Pain", regionId: "upperBack", category: .musculoskeletal),
            SymptomDefinition(name: "Middle Back Pain", regionId: "middleBack", category: .musculoskeletal),
            SymptomDefinition(name: "Lower Back Pain", regionId: "lowerBack", category: .musculoskeletal),
            SymptomDefinition(name: "Back Stiffness", regionId: "upperBack", category: .musculoskeletal),
            SymptomDefinition(name: "Sciatica", regionId: "lowerBack", category: .musculoskeletal),
            SymptomDefinition(name: "Buttock Pain", regionId: "buttocks", category: .musculoskeletal),
            SymptomDefinition(name: "Back Pain", regionId: "upperBack", category: .musculoskeletal),
            SymptomDefinition(name: "Upper Back Strain", regionId: "upperBack", category: .musculoskeletal),
            SymptomDefinition(name: "Shoulder Blade Pain", regionId: "upperBack", category: .musculoskeletal),
            SymptomDefinition(name: "Trapezius Pain", regionId: "upperBack", category: .musculoskeletal),
            
            // Left Arm regions - Front
            SymptomDefinition(name: "Upper Left Arm Muscle Pain", regionId: "upperLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Left Bicep Pain", regionId: "upperLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Left Tricep Pain", regionId: "upperLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Shoulder Pain Left", regionId: "upperLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Shoulder Tension Left", regionId: "upperLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Upper Left Arm Pain", regionId: "upperLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Left Forearm Pain", regionId: "lowerLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Left Wrist Pain", regionId: "lowerLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Lower Left Arm Pain", regionId: "lowerLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Left Arm Elbow Pain", regionId: "lowerLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Wrist Strain", regionId: "lowerLeftArm", category: .musculoskeletal),
            SymptomDefinition(name: "Bicep Pain Left", regionId: "upperLeftArm", category: .musculoskeletal),
            
            // Right Arm regions - Front
            SymptomDefinition(name: "Upper Right Arm Muscle Pain", regionId: "upperRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Right Bicep Pain", regionId: "upperRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Right Tricep Pain", regionId: "upperRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Shoulder Pain Right", regionId: "upperRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Shoulder Tension Right", regionId: "upperRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Upper Right Arm Pain", regionId: "upperRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Right Forearm Pain", regionId: "lowerRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Right Wrist Pain", regionId: "lowerRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Lower Right Arm Pain", regionId: "lowerRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Right Arm Elbow Pain", regionId: "lowerRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Right Shoulder Pain", regionId: "upperRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Forearm Pain", regionId: "lowerRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Elbow Strain", regionId: "lowerRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Shoulder Strain", regionId: "upperRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Bicep Pain", regionId: "upperRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Tricep Pain", regionId: "upperRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Bicep Pain Right", regionId: "upperRightArm", category: .musculoskeletal),
            
            // Left Leg regions - Front
            SymptomDefinition(name: "Upper Left Leg Pain", regionId: "upperLeftLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Left Thigh Pain", regionId: "upperLeftLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Left Calf Pain", regionId: "lowerLeftLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Left Ankle Pain", regionId: "lowerLeftLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Calf Pain Left", regionId: "lowerLeftLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Lower Left Leg Pain", regionId: "lowerLeftLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Ankle Pain Left", regionId: "lowerLeftLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Left Knee Pain", regionId: "upperLeftLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Left Leg Cramps", regionId: "lowerLeftLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Hamstring Pain Left", regionId: "upperLeftLeg", category: .musculoskeletal),
            
            // Right Leg regions - Front
            SymptomDefinition(name: "Upper Right Leg Pain", regionId: "upperRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Right Thigh Pain", regionId: "upperRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Right Calf Pain", regionId: "lowerRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Right Ankle Pain", regionId: "lowerRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Calf Pain Right", regionId: "lowerRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Lower Right Leg Pain", regionId: "lowerRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Ankle Pain Right", regionId: "lowerRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Right Knee Pain", regionId: "upperRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Right Leg Cramps", regionId: "lowerRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Shin Splints", regionId: "lowerRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Thigh Pain", regionId: "upperRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Quadriceps Pain", regionId: "upperRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Hamstring Pain Right", regionId: "upperRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Calf Muscle Strain", regionId: "lowerRightLeg", category: .musculoskeletal),
            
            // General Leg symptoms
            SymptomDefinition(name: "Leg Pain", regionId: "upperRightLeg", category: .musculoskeletal),
            SymptomDefinition(name: "Knee Pain", regionId: "upperRightLeg", category: .musculoskeletal),
            
            // Left Arm regions - Back
            SymptomDefinition(name: "Left Arm Back Pain", regionId: "leftArmBack", category: .musculoskeletal),
            SymptomDefinition(name: "Upper Left Arm Back Pain", regionId: "upperLeftArmBack", category: .musculoskeletal),
            SymptomDefinition(name: "Lower Left Arm Back Pain", regionId: "lowerLeftArmBack", category: .musculoskeletal),
            SymptomDefinition(name: "Left Triceps Pain", regionId: "upperLeftArmBack", category: .musculoskeletal),
            
            // Right Arm regions - Back
            SymptomDefinition(name: "Right Arm Back Pain", regionId: "rightArmBack", category: .musculoskeletal),
            SymptomDefinition(name: "Upper Right Arm Back Pain", regionId: "upperRightArmBack", category: .musculoskeletal),
            SymptomDefinition(name: "Lower Right Arm Back Pain", regionId: "lowerRightArmBack", category: .musculoskeletal),
            SymptomDefinition(name: "Right Triceps Pain", regionId: "upperRightArmBack", category: .musculoskeletal),
            
            // Left Leg regions - Back
            SymptomDefinition(name: "Upper Left Leg Back Pain", regionId: "upperLeftLegBack", category: .musculoskeletal),
            SymptomDefinition(name: "Lower Left Leg Back Pain", regionId: "lowerLeftLegBack", category: .musculoskeletal),
            SymptomDefinition(name: "Hamstring Tension Left", regionId: "upperLeftLegBack", category: .musculoskeletal),
            
            // Right Leg regions - Back
            SymptomDefinition(name: "Upper Right Leg Back Pain", regionId: "upperRightLegBack", category: .musculoskeletal),
            SymptomDefinition(name: "Lower Right Leg Back Pain", regionId: "lowerRightLegBack", category: .musculoskeletal),
            SymptomDefinition(name: "Hamstring Tension Right", regionId: "upperRightLegBack", category: .musculoskeletal),
            
            // General symptoms
            SymptomDefinition(name: "Fatigue", regionId: "torso", category: .other),
            SymptomDefinition(name: "Muscle Soreness", regionId: "torso", category: .musculoskeletal),
            SymptomDefinition(name: "Joint Pain", regionId: "torso", category: .musculoskeletal),
            SymptomDefinition(name: "Muscle Strain", regionId: "torso", category: .musculoskeletal),
            
            // Common areas of strain
            SymptomDefinition(name: "Shoulder Blade Tension", regionId: "upperBack", category: .musculoskeletal),
            SymptomDefinition(name: "Elbow Pain", regionId: "lowerRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Wrist Pain", regionId: "lowerRightArm", category: .musculoskeletal),
            SymptomDefinition(name: "Forearm Strain", regionId: "lowerLeftArmBack", category: .musculoskeletal),
            SymptomDefinition(name: "Arm Pain", regionId: "upperRightArm", category: .musculoskeletal),
            
            // Skin conditions
            SymptomDefinition(name: "Skin Rash", regionId: "skin", category: .skin),
            SymptomDefinition(name: "Insect Bite", regionId: "skin", category: .skin),
            
            // Other
            SymptomDefinition(name: "Other", regionId: "torso", category: .other)
        ]  {
        
    
    if seenSymptomNames.insert(symptom.name).inserted {
               uniqueSymptoms.append(symptom)
           }
       }
       
       // Assign the unique symptoms to allSymptoms
       allSymptoms = uniqueSymptoms
   }

   private func initializeSymptoms() {
       // Create a set to track unique symptoms
       var uniqueSymptoms = Set<String>()
       
       // Add predefined symptoms
       uniqueSymptoms.formUnion(predefinedSymptoms)
       
       // Add custom symptoms from UserDefaults
       if let customSymptoms = UserDefaults.standard.stringArray(forKey: "customSymptoms") {
           uniqueSymptoms.formUnion(customSymptoms)
       }
       
       // Convert back to a sorted array
       self.filteredSymptoms = Array(uniqueSymptoms).sorted()
   }
    
    func symptomsForRegionAsBodySymptoms(_ region: String) -> [BodySymptom] {
        return symptomsForRegion(region).map { BodySymptom(name: $0) }
    }
    
    func symptomsForRegion(_ regionId: String) -> [SymptomDefinition] {
        return allSymptoms.filter { $0.regionId == regionId }
    }

    private func setupSymptomSearchListener() {
        $symptomSearchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.filterSymptoms(query: query)
            }
            .store(in: &cancellables)
    }
    
    private func fetchEnvironmentalData() {
        
        let now = Date()
            if now.timeIntervalSince(lastFetchTime) < minimumFetchInterval {
                print("⏱️ Skipping fetch - too soon since last successful fetch")
                return
            }
        
        Task {
            // First, make sure the location is available in the LocationService used by EnvironmentalDataService
            if let location = self.locationManager?.currentLocation {
                // Note: No need to unwrap latitude and longitude as optionals
                // since they're already Double values
                let latitude = location.latitude
                let longitude = location.longitude
                
                // Use centralized API configuration
                guard let url = APIConfig.weatherURL(latitude: latitude, longitude: longitude) else {
                    print("❌ Invalid URL for weather API")
                    return
                }
                
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let decodedResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)
                    
                    let pressureValue = Double(decodedResponse.main.pressure)
                    print("🌬️ Retrieved Atmospheric Pressure: \(pressureValue) hPa")
                    
                    await MainActor.run {
                        self.atmosphericPressure = "\(Int(pressureValue)) hPa"
                        self.atmosphericPressureCategory = self.categorizePressure(pressureValue)
                        self.updateAtmosphericPressure(pressureValue)
                        self.lastUpdated = Date() // ✅ Trigger UI refresh
                    }
                } catch {
                    print("❌ Error fetching atmospheric pressure: \(error.localizedDescription)")
                    await MainActor.run {
                        self.setFallbackAtmosphericPressure()
                    }
                }
                
                self.lastFetchTime = Date()
                
            } else {
                if isLocationReady {
                    // Location service is ready but no location available
                    await MainActor.run {
                        self.setFallbackAtmosphericPressure()
                    }
                } else {
                    // We're still waiting for first location, wait briefly
                    print("📍 Waiting for location data...")
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                    
                    // Try again if location is now ready
                    if isLocationReady && self.locationManager?.currentLocation != nil {
                        // Now we have a location, so retry the API call
                        if let location = self.locationManager?.currentLocation {
                            let latitude = location.latitude
                            let longitude = location.longitude
                            
                            guard let url = APIConfig.weatherURL(latitude: latitude, longitude: longitude) else {
                                print("❌ Invalid URL for weather API")
                                return
                            }
                            
                            do {
                                let (data, _) = try await URLSession.shared.data(from: url)
                                let decodedResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)
                                
                                let pressureValue = Double(decodedResponse.main.pressure)
                                print("🌬️ Retrieved Atmospheric Pressure: \(pressureValue) hPa")
                                
                                await MainActor.run {
                                    self.atmosphericPressure = "\(Int(pressureValue)) hPa"
                                    self.atmosphericPressureCategory = self.categorizePressure(pressureValue)
                                    self.updateAtmosphericPressure(pressureValue)
                                    self.lastUpdated = Date()
                                    self.lastFetchTime = Date()
                                }
                            } catch {
                                print("❌ Error fetching atmospheric pressure: \(error.localizedDescription)")
                                await MainActor.run {
                                    self.setFallbackAtmosphericPressure()
                                }
                            }
                        }
                    } else {
                        // Still no location after waiting, use fallback
                        await MainActor.run {
                            self.setFallbackAtmosphericPressure()
                        }
                    }
                }
            }
            
            // Update moon phase and Mercury retrograde data
            self.fetchMoonPhase(for: date)
            self.autoMercuryRetrograde = self.isMercuryInRetrograde(for: date)
            
            await MainActor.run {
                self.lastUpdated = Date()
                print("✅ Environmental data updated successfully")
            }
        }
    }
    
    func storeRecentSymptom(_ symptom: String) {
        var recentSymptoms = getRecentSymptoms()
        
        // Add to recent symptoms if not already present
        if !recentSymptoms.contains(symptom) {
            recentSymptoms.append(symptom)
        }
        
        // Move to front if already in list
        if let index = recentSymptoms.firstIndex(of: symptom), index != 0 {
            recentSymptoms.remove(at: index)
            recentSymptoms.insert(symptom, at: 0)
        }
        
        // Limit to 10 items
        if recentSymptoms.count > 10 {
            recentSymptoms = Array(recentSymptoms.prefix(10))
        }
        
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(recentSymptoms) {
            recentSymptomsData = encoded
        }
    }

    func getRecentSymptoms() -> [String] {
        if let decoded = try? JSONDecoder().decode([String].self, from: recentSymptomsData) {
            return decoded
        }
        return []
    }
    
    func reportUnmappedSymptom(symptomName: String) {
        print("🚨 Unmapped Symptom Reported: \(symptomName)")
        // Optionally, you can add more logic here like storing unmapped symptoms
    }
    
    func selectMultipleAreas(description: String) {
        // Clear previous selections
        selectedBodyAreas.removeAll()
        
        // Set as internal symptom
        isInternalSymptom = true
        internalAffectedArea = description
    }
    // MARK: - Seasonal Analysis 🌱
    
    func determineSeason(for date: Date) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM" // Abbreviated month
        let monthAbbreviation = dateFormatter.string(from: date)
        
        switch month {
        case 3:
            return day >= 20 ? "Spring - \(monthAbbreviation)" : "Winter - \(monthAbbreviation)"
        case 4, 5:
            return "Spring - \(monthAbbreviation)"
        case 6:
            return day >= 21 ? "Summer - \(monthAbbreviation)" : "Spring - \(monthAbbreviation)"
        case 7, 8:
            return "Summer - \(monthAbbreviation)"
        case 9:
            return day >= 22 ? "Fall - \(monthAbbreviation)" : "Summer - \(monthAbbreviation)"
        case 10, 11:
            return "Fall - \(monthAbbreviation)"
        case 12:
            return day >= 21 ? "Winter - \(monthAbbreviation)" : "Fall - \(monthAbbreviation)"
        default:
            return "Winter - \(monthAbbreviation)"
        }
    }
    
    func checkForSeasonalAllergyRisks() {
        if currentSeason == "Spring" || currentSeason == "Fall" {
            alertMessage = "🌿 Allergy Season Alert: You might experience symptoms triggered by seasonal allergens."
            showAlert = true
        }
    }
    func isMercuryInRetrograde(for date: Date) -> Bool {
        return environmentalService.checkMercuryInRetrograde(for: date)
    }
    
    func isMercuryRetrogradeApproaching(for date: Date) -> Bool {
        return environmentalService.isMercuryRetrogradeApproaching(for: date)
    }
    
    // MARK: - Private Properties
    
    /// Holds any Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Mercury Retrograde Date Ranges
    var mercuryRetrogradePeriods: [(start: Date, end: Date)] = []
    
    // Helper function to create Date objects
    func createDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components) ?? Date()
    }    // MARK: - Methods
    

    /// Adds a symptom to the selectedSymptoms set
    /// - Parameter symptom: The symptom to add
    /// Recalculate the selected body areas based on currently selected symptoms.
    

    // Add to LogItemViewModel class
    func symptomsForRegion(_ region: String) -> [String] {
        return symptomToRegion
            .filter { $0.value == region }
            .map { $0.key }
    }
    
    // MARK: - New Versions of addSymptom(_:) and removeSymptom(_:)
    // In LogItemViewModel.swift, replace the addSymptom function:

 

    func removeSymptom(_ symptom: String) {
        let standardizedSymptom = SymptomManager.shared.standardizeSymptomName(symptom)
        selectedSymptoms.remove(standardizedSymptom)
        
        // Only remove the region if no other symptoms map to it
        if let region = symptomToRegion[standardizedSymptom] {
            let otherSymptomsForRegion = selectedSymptoms.filter {
                symptomToRegion[$0] == region
            }
            
            if otherSymptomsForRegion.isEmpty {
                selectedBodyAreas.remove(region)
                print("✅ Removed region \(region) - no remaining symptoms")
            } else {
                print("ℹ️ Keeping region \(region) - other symptoms exist")
            }
        }
        
        print("❌ Removed symptom: \(standardizedSymptom)")
        print("📍 Remaining symptoms: \(selectedSymptoms)")
        print("🗺️ Remaining body areas: \(selectedBodyAreas)")
        
        verifySymptomRegionMapping()
    }

    func synchronizeBodyAreas() {
        // Start with a clean slate
        selectedBodyAreas.removeAll()
        
        // Add body areas for all selected symptoms
        for symptom in selectedSymptoms {
            if let region = symptomToRegion[symptom] {
                let standardizedRegion = BodyRegionUtility.standardizeRegionName(region)
                selectedBodyAreas.insert(standardizedRegion)
                print("✅ Synchronized: Added region \(standardizedRegion) for symptom \(symptom)")
            }
        }
        
        print("🔄 Body areas synchronized: \(selectedBodyAreas)")
    }
    
    // Add this function to update all selected body areas based on current symptoms
    func updateSelectedBodyAreas() {
        // Clear previous selections
        selectedBodyAreas.removeAll()
        
        // Add mapped regions for each selected symptom
        for symptom in selectedSymptoms {
            if let region = symptomToRegion[symptom] {
                selectedBodyAreas.insert(region)
                print("✅ Added mapped region: \(region) for symptom: \(symptom)")
            } else {
                print("❌ No mapping for symptom: \(symptom)")
            }
        }
        
        print("📍 Final selectedBodyAreas: \(selectedBodyAreas)")
    }
    /// Adds a custom symptom to UserDefaults and updates filteredSymptoms and selectedSymptoms
    /// - Parameter symptom: The custom symptom to add
    func addCustomSymptom(_ symptom: String) {
        let trimmedSymptom = symptom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSymptom.isEmpty else { return }
        
        if SymptomManager.shared.addCustomSymptom(trimmedSymptom) {
            // Update filteredSymptoms
            filteredSymptoms.append(trimmedSymptom)
            // Also add to selectedSymptoms
            addSymptom(trimmedSymptom)
            print("Added custom symptom: \(trimmedSymptom)")
        } else {
            print("Symptom '\(trimmedSymptom)' already exists.")
        }
    }
    
    /// Filters the symptoms based on the search query
    /// - Parameter query: The search query entered by the user
    func filterSymptoms(query: String) {
        if query.isEmpty {
            // Show all predefined and custom symptoms
            filteredSymptoms = predefinedSymptoms + (UserDefaults.standard.stringArray(forKey: "customSymptoms") ?? [])
        } else {
            let lowercasedQuery = query.lowercased()
            filteredSymptoms = predefinedSymptoms.filter {
                $0.lowercased().contains(lowercasedQuery)
            }
            let customSymptoms = UserDefaults.standard.stringArray(forKey: "customSymptoms") ?? []
            filteredSymptoms += customSymptoms.filter {
                $0.lowercased().contains(lowercasedQuery)
            }
        }
        print("Filtered Symptoms: \(filteredSymptoms)")
    }
    
    /// Adds a new category or symptom based on newItemType
    func addNewItem() {
        let trimmedName = self.newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            self.alertMessage = "Item name cannot be empty."
            self.showAlert = true
            return
        }
        
        switch self.newItemType {
        case .category:
            if !self.customCategories.contains(trimmedName) {
                self.customCategories.append(trimmedName)
                self.selectedCategory = trimmedName
                UserDefaults.standard.set(self.customCategories, forKey: "customCategories")
                print("Added new category: \(trimmedName)")
            } else {
                self.alertMessage = "Category '\(trimmedName)' already exists."
                self.showAlert = true
                print("Category '\(trimmedName)' already exists.")
            }
        case .symptom:
            if !self.predefinedSymptoms.contains(trimmedName) && !(UserDefaults.standard.stringArray(forKey: "customSymptoms") ?? []).contains(trimmedName) {
                addCustomSymptom(trimmedName)
                print("Added new symptom: \(trimmedName)")
            } else {
                self.alertMessage = "Symptom '\(trimmedName)' already exists."
                self.showAlert = true
                print("Symptom '\(trimmedName)' already exists.")
            }
        }
        self.newItemName = ""
        self.newItemType = .category
    }
    
    /// Validates the user input before saving
    /// - Returns: A tuple indicating if the input is valid and an associated message
    func validateInput() -> (isValid: Bool, message: String) {
        // First step (Symptom Selection) should always be valid
        if currentStep == .symptomSelection {
            return (true, "")
        }
        
        // For subsequent steps, perform standard validation
        if selectedSymptoms.isEmpty && foodDrinkItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (false, "Please select at least one symptom or enter a food/drink item.")
        }
        
        if causeType == .foodAndDrink && foodDrinkItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (false, "Please enter a specific food or drink item.")
        }
        
        // Modified validation for body areas:
        // If we have unmapped symptoms but no body areas selected, consider it valid
        if !isInternalSymptom && selectedBodyAreas.isEmpty {
            // Check if there are any unmapped symptoms
            let unmappedSymptoms = selectedSymptoms.filter { symptomToRegion[$0] == nil }
            
            if !unmappedSymptoms.isEmpty {
                // Allow to proceed with unmapped symptoms
                return (true, "")
            }
            
            // Otherwise require body area selection
            return (false, "Please select at least one affected body area.")
        }
        
        if isInternalSymptom && internalAffectedArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (false, "Please specify the internal affected area.")
        }
        
        return (true, "")
    }
    
    func showAlert(title: String, message: String) {
        self.alertMessage = message
        self.showAlert = true
    }
    
    /// Saves the log entry to the data store
    /// - Parameters:
    ///   - context: The ModelContext for data persistence
    ///   - linkedTrackedItemID: Optional UUID of a linked tracked item
    func saveLog(using context: ModelContext, linkedTrackedItemID: UUID? = nil) {
        // Add debug prints
        print("Saving log with \(selectedSymptoms.count) symptoms: \(selectedSymptoms)")
        
        let validation = validateInput()
        guard validation.isValid else {
            self.alertMessage = validation.message
            self.showAlert = true
            print("Validation failed: \(validation.message)")
            return
        }
        
        // Map CauseType to ItemType
        let mappedItemType = mapCauseTypeToItemType(causeType)
        
        // Create array of symptoms first
        let symptomsList = Array(selectedSymptoms)
        
        // Convert subcategories to Data before saving - this part is fine
        let subcategoriesArray = Array(causeSubcategories)
        let subcategoriesData: Data
        do {
            subcategoriesData = try JSONEncoder().encode(subcategoriesArray)
        } catch {
            print("Error encoding subcategories: \(error)")
            // Use empty Data as fallback - safer than force unwrap
            subcategoriesData = Data()
        }
        
        // Create new LogEntry without setting complex properties directly
        let newLog = LogEntry(
            itemName: selectedSymptoms.isEmpty ? (foodDrinkItem.isEmpty ? "(No Symptoms Selected)" : foodDrinkItem) : selectedSymptoms.joined(separator: ", "),
            itemType: mappedItemType,
            category: causeSubcategories.joined(separator: ", "),
            symptoms: symptomsList,
            severity: Int(severity),
            notes: notes,
            date: date,
            moonPhase: getMoonPhase(for: date),
            atmosphericPressure: atmosphericPressureCategory,
            suddenChange: suddenPressureChange,
            isMercuryRetrograde: autoMercuryRetrograde,
            season: currentSeason,
            linkedTrackedItemID: linkedTrackedItemID,
            affectedAreas: isInternalSymptom ? [internalAffectedArea] : Array(selectedBodyAreas),
            foodDrinkItem: causeType == .foodAndDrink && !foodDrinkItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? foodDrinkItem : nil,
            symptomTriggers: Array(selectedSymptomTriggers),
            additionalContext: additionalNotes,
            isOngoing: true,
            startDate: Date(),
            usedProtocolID: selectedProtocol?.id,
            symptomPhotoData: self.imageData
        )
        
        newLog.subcategoriesData = subcategoriesData
        
        if let selectedProtocol = selectedProtocol {
            print("Linking protocol: \(selectedProtocol.title) to log")
            // Only set the ID, not the direct relationship
            newLog.protocolID = selectedProtocol.id
        }
        
        // Insert the log first so we can compare with previous logs
        context.insert(newLog)
        
        // Look for the same food item in previous logs that caused the same symptoms
        // Look for the same food item in previous logs that caused the same symptoms
        if let food = newLog.foodDrinkItem, !food.isEmpty {
            let symptomsSet = Set(symptomsList)
            
            // Use a simpler predicate approach to avoid syntax errors
            let descriptor = FetchDescriptor<LogEntry>()
            
            // Fetch all logs and then filter them in memory
            if let allLogs = try? context.fetch(descriptor) {
                // Filter for relevant previous logs
                let previousMatchingLogs = allLogs.filter { log in
                    return log.id != newLog.id && // Not the current log
                           log.foodDrinkItem == food && // Same food
                           log.severity >= 2 && // Only consider moderate+ severity symptoms
                           !Set(log.symptoms).isDisjoint(with: symptomsSet) // Has overlapping symptoms
                }
                
                if !previousMatchingLogs.isEmpty {
                    // This food has been associated with the same symptoms before
                    DispatchQueue.main.async {
                        self.alertMessage = "You've logged symptoms after eating \(food) multiple times. This may indicate a sensitivity. Would you like to add it to your Avoid List?"
                        self.showAlert = true
                        self.alertType = .avoidSuggestion
                        self.suggestedAvoidItem = food
                    }
                }
            }
        }
        
        do {
            try context.save()
            print("Successfully saved log")
            self.showSavedMessage = true
            for symptom in selectedSymptoms {
                storeRecentSymptom(symptom)
            }
        } catch {
            print("❌ Error saving log: \(error.localizedDescription)")
            self.alertMessage = "Failed to save log. Please try again."
            self.showAlert = true
            self.alertType = .error
        }
    }

        
    // Helper function to map CauseType to ItemType
    func mapCauseTypeToItemType(_ cause: CauseType) -> ItemType {
        switch cause {
        case .foodAndDrink:
            return .foodDrink
        default:
            return .symptom
        }
    }
    
    /// Resets all form fields to their default states
    func resetForm() {
        selectedSymptoms.removeAll()
        causeType = .foodAndDrink
        causeSubcategories.removeAll()
        foodDrinkItem = ""
        severity = 1
        notes = ""
        date = Date()
        selectedBodyAreas.removeAll()
        isInternalSymptom = false
        internalAffectedArea = ""
        currentStep = .symptomSelection
    }
    
    /// Determines the color of the severity slider based on its value
    /// - Returns: A Color representing the severity level
    func severityColorFunction() -> Color {
        return BodyRegionUtility.colorForSeverity(Int(severity))
    }
    
    // MARK: - Subcategory Management
    
    /// Adds a subcategory to the set.
    /// - Parameter subcategory: The subcategory to add.
    func addSubcategory(_ subcategory: String) {
        causeSubcategories.insert(subcategory)
    }
    
    /// Removes a subcategory from the set.
    /// - Parameter subcategory: The subcategory to remove.
    func removeSubcategory(_ subcategory: String) {
        causeSubcategories.remove(subcategory)
    }
    
    /// Toggles the presence of a subcategory in the set.
    /// - Parameter subcategory: The subcategory to toggle.
    func toggleSubcategory(_ subcategory: String) {
        if causeSubcategories.contains(subcategory) {
            causeSubcategories.remove(subcategory)
        } else {
            causeSubcategories.insert(subcategory)
        }
    }
    
    // MARK: - API Fetch Functions
    
    
    /// Fetches the moon phase information for a specific date
    /// - Parameter date: The date for which to fetch the moon phase
    func fetchMoonPhase(for date: Date) {
        let phase = getMoonPhase(for: date)
        DispatchQueue.main.async {
            self.autoMoonPhase = phase
        }
    }
    
    @Published private(set) var currentAtmosphericTask: Task<Void, Never>? = nil
    private var currentDataTask: Task<Void, Never>? = nil
    
    // MARK: - Aggregated Data Fetch
    
    /// Fetches all necessary data asynchronously.

    func fetchAllData() async {
        await environmentalService.fetchAllData()
        
        // Update the view model with data from the service
        await MainActor.run {
            self.autoMoonPhase = environmentalService.moonPhase
            self.autoMercuryRetrograde = environmentalService.isMercuryRetrograde
            self.atmosphericPressure = environmentalService.atmosphericPressure
            self.atmosphericPressureCategory = environmentalService.atmosphericPressureCategory
            self.suddenPressureChange = environmentalService.suddenPressureChange
            self.currentPressure = environmentalService.currentPressure
            self.previousPressure = environmentalService.previousPressure
            self.lastUpdated = environmentalService.lastUpdated
        }
    }
    
    // Add this to the main LogItemViewModel class (not the extension)
    func handleUnmappedSymptom(_ symptom: String) {
        // Report for analytics
        self.reportUnmappedSymptom(symptomName: symptom)
        
        // Suggest possible body regions based on symptom name
        let possibleRegions = suggestPossibleRegionsForSymptom(symptom)
        
        if !possibleRegions.isEmpty {
            // Add first suggested region
            self.selectedBodyAreas.insert(possibleRegions[0])
        }
    }

    // Helper function to guess regions based on symptom names
    func suggestPossibleRegionsForSymptom(_ symptom: String) -> [String] {
        let lower = symptom.lowercased()
        
        if lower.contains("arm") {
            return ["upperRightArm"]
        } else if lower.contains("leg") {
            return ["upperRightLeg"]
        } else if lower.contains("head") {
            return ["head"]
        } else if lower.contains("back") {
            return ["upperBack"]
        } else if lower.contains("bite") || lower.contains("rash") {
            return ["abdomen"] // Default for skin conditions
        }
        // Add more heuristics
        
        return []
    }
    func refreshEnvironmentalData() {
        Task {
            print("🔄 Starting environmental data refresh")
            
            // Reset state before refresh
            await MainActor.run {
                environmentalService.resetPressureState()
                self.atmosphericPressureCategory = "Loading..."
            }
            
            // Ensure location data is ready before refreshing
            if let location = self.locationManager?.currentLocation {
                // Pass location to environmental service
                environmentalService.setLocation(latitude: location.latitude, longitude: location.longitude)
                print("📍 Using current location for refresh: \(location.latitude), \(location.longitude)")
            } else if let cached = self.locationManager?.lastKnownLocation {
                // Use cached location
                environmentalService.setLocation(latitude: cached.latitude, longitude: cached.longitude)
                print("📍 Using cached location for refresh: \(cached.latitude), \(cached.longitude)")
            } else {
                print("⚠️ No location available for refresh, using fallback")
            }
            
            // Now delegate to the service with location info
            await environmentalService.fetchAllData()
            
            // Update view model from service
            await MainActor.run {
                self.atmosphericPressure = environmentalService.atmosphericPressure
                self.atmosphericPressureCategory = environmentalService.atmosphericPressureCategory
                self.suddenPressureChange = environmentalService.suddenPressureChange
                self.currentPressure = environmentalService.currentPressure
                self.previousPressure = environmentalService.previousPressure
                self.autoMoonPhase = environmentalService.moonPhase
                self.autoMercuryRetrograde = environmentalService.isMercuryRetrograde
                self.lastUpdated = Date()
                print("🔄 Environmental data refresh completed")
            }
        }
    }

    // MARK: - Atmospheric Pressure Fetch Function
    
    @MainActor
    public func fetchAtmosphericPressure() async {
        print("🌦️ Delegating atmospheric pressure fetch to EnvironmentalDataService")
        
        // Instead of reimplementing the fetch logic here, delegate to the service
        await environmentalService.fetchAtmosphericPressure()
        
        // Update view model properties from the service
        self.atmosphericPressure = environmentalService.atmosphericPressure
        self.atmosphericPressureCategory = environmentalService.atmosphericPressureCategory
        self.suddenPressureChange = environmentalService.suddenPressureChange
        self.currentPressure = environmentalService.currentPressure
        self.previousPressure = environmentalService.previousPressure
        self.lastUpdated = Date() // Trigger UI refresh
        
        print("✅ ViewModel updated with service data: \(self.atmosphericPressureCategory)")
        
        // Force UI refresh by explicitly publishing changes
        // This extra step ensures SwiftUI views respond to the changes
        let category = self.atmosphericPressureCategory
        Task { @MainActor in
            try await Task.sleep(nanoseconds: 100_000_000) // Small delay
            self.atmosphericPressureCategory = category + " " // Minimal change to trigger observers
            try await Task.sleep(nanoseconds: 100_000_000) // Small delay
            self.atmosphericPressureCategory = category // Set back to original
            self.lastUpdated = Date() // Final trigger
        }
    }
    
    /// Fetches the current atmospheric pressure data
    // In LogItemViewModel.swift, replace the fetchAtmosphericPressure() method
    // with this optimized version that reduces logging verbosity

    @MainActor
    public func updateAtmosphericPressure() async {
        print("🔄 Updating atmospheric pressure from service...")

        // Ensure we're not making unnecessary duplicate calls
        if environmentalService.currentAtmosphericTask != nil && !environmentalService.currentAtmosphericTask!.isCancelled {
            print("⏳ Fetch already in progress. Skipping duplicate request.")
            return
        }

        // Call fetch function from EnvironmentalDataService.swift
        await environmentalService.fetchAtmosphericPressure()

        // UI Update
        self.atmosphericPressure = environmentalService.atmosphericPressure
        self.atmosphericPressureCategory = environmentalService.atmosphericPressureCategory
        self.suddenPressureChange = environmentalService.suddenPressureChange
        self.currentPressure = environmentalService.currentPressure
        self.previousPressure = environmentalService.previousPressure
    }
    
    @MainActor
    private func useFallbackPressureData() {
        print("⚠️ Using fallback pressure data")
        
        // Use static value that will still allow the app to function
        let fallbackPressure = 1013.0 // Standard sea level pressure
        
        // Update UI
        self.atmosphericPressure = "\(Int(fallbackPressure)) hPa"
        self.atmosphericPressureCategory = "Normal"
        self.currentPressure = fallbackPressure
        self.previousPressure = fallbackPressure
        self.suddenPressureChange = false
        
        // Set up a listener for location status changes
        NotificationCenter.default.addObserver(
            forName: Notification.Name("LocationPermissionStatus"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let userInfo = notification.object as? [String: String],
                   userInfo["status"] == "denied" {
                    self.atmosphericPressureCategory = "Location Access Denied"
                }
            }
        }
    }
    
    @MainActor
    func fetchAtmosphericPressureWithURL(_ urlString: String) async {
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL.")
            self.atmosphericPressureCategory = "Unknown"
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 HTTP Status Code:", httpResponse.statusCode)
                if httpResponse.statusCode == 429 {
                    print("❌ Rate limit exceeded. Retrying in 60 seconds...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        Task {
                            await self.fetchAtmosphericPressureWithURL(urlString)
                        }
                    }
                    return
                }
            }
            
            if let weatherResponse = try? JSONDecoder().decode(WeatherResponse.self, from: data) {
                let currentPressure = Double(weatherResponse.main.pressure)
                DispatchQueue.main.async {
                    self.updateAtmosphericPressure(currentPressure)
                    self.atmosphericPressureCategory = self.categorizePressure(currentPressure)
                    self.lastUpdated = Date()
                    print("🌬️ Atmospheric Pressure Updated: \(currentPressure) hPa")
                    print("🌬️ Category: \(self.atmosphericPressureCategory)")
                }
            } else {
                print("⚠️ Failed to decode API response.")
                DispatchQueue.main.async {
                    self.atmosphericPressureCategory = "Unknown"
                }
            }
        } catch {
            print("❌ API Error:", error.localizedDescription)
            DispatchQueue.main.async {
                self.atmosphericPressureCategory = "Unknown"
            }
        }
    }
    
    @MainActor
    public func fetchPressureForecast(lat: Double, lon: Double) async {
        guard let url = APIConfig.forecastURL(latitude: lat, longitude: lon) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = json["list"] as? [[String: Any]] {
                
                var upcomingPressures: [Double] = []
                for forecast in list.prefix(5) {
                    if let main = forecast["main"] as? [String: Any],
                       let pressure = main["pressure"] as? Double {
                        upcomingPressures.append(pressure)
                    }
                }
                
                // Only detect changes if we're not in first load
                if !isFirstLoad && upcomingPressures.count >= 2 {
                    detectPressureChanges(pressures: upcomingPressures)
                }
            }
        } catch {
            print("Error parsing forecast JSON: \(error)")
        }
    }
    
    @MainActor
    public func resetPressureState() {
        environmentalService.resetPressureState()
    }
    
    
    private func detectPressureChanges(pressures: [Double]) {
        // Don't detect changes if it's first load or if pressures array is too small
        guard !isFirstLoad, pressures.count >= 2 else {
            print("⚠️ Skipping pressure change detection: first load or insufficient data")
            return
        }
        
        // Only compare the most recent values - use safe unwrap
        let lastTwo = Array(pressures.suffix(2))
        guard let lastValue = lastTwo.last, let firstValue = lastTwo.first else { return }
        let change = abs(lastValue - firstValue)
        
        // Update sudden change state on main thread
        DispatchQueue.main.async { [weak self] in
            if change >= self?.pressureChangeThreshold ?? 6.0 {
                print("⚠️ Significant pressure change detected: \(change) hPa")
                self?.suddenPressureChange = true
            } else {
                self?.suddenPressureChange = false
            }
        }
    }
    /// Helper function for severity emoji
    func severityEmoji(_ severity: Int) -> String {
        return BodyRegionUtility.severityEmoji(severity)
    }
    
    
    // In LogItemViewModel.swift, replace the existing LocationManager implementation
    // with this optimized version that reduces logging verbosity

    class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
        weak var viewModel: LogItemViewModel?
        private let locationManager = CLLocationManager()
        @Published var currentLocation: CLLocationCoordinate2D?
        private var locationUpdateCallback: (() -> Void)?
        private var timeoutTask: Task<Void, Never>?
        private var isDashboardActive = false
        private var lastLocationUpdateTime: Date? = nil
        private var refreshTimer: Timer?
        
        // Add location caching
        @AppStorage("lastKnownLatitude") private var cachedLatitude: Double?
        @AppStorage("lastKnownLongitude") private var cachedLongitude: Double?
        
        // Add these tracking variables to reduce logging
        private var hasLoggedPermissionRequest = false
        private var hasLoggedPermissionDenied = false
        private var lastLoggedLocation: CLLocationCoordinate2D?
        private let significantDistanceThreshold: Double = 100 // in meters
        
        var lastKnownLocation: CLLocationCoordinate2D? {
            guard let lat = cachedLatitude, let lon = cachedLongitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        init(viewModel: LogItemViewModel) {
            self.viewModel = viewModel
            super.init()
            
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyReduced
            locationManager.distanceFilter = 100 // Only update when moved 100m
            
            // Only request location if we haven't shown the alert before
            if !UserDefaults.standard.bool(forKey: "hasShownLocationAlert") {
                switch locationManager.authorizationStatus {
                    case .authorizedWhenInUse, .authorizedAlways:
                        requestLocationUpdate(silent: true) // Silent initial request
                    case .notDetermined:
                        if !hasLoggedPermissionRequest {
                            print("📍 Requesting Location Permission")
                            hasLoggedPermissionRequest = true
                        }
                        locationManager.requestWhenInUseAuthorization()
                    default:
                        startLocationUpdatesWhenAppIsActive()
                }
            }
            
            NotificationCenter.default.addObserver(self,
                selector: #selector(appDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(self,
                selector: #selector(appDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
        }
        
        func requestLocationUpdate(silent: Bool = false) {
            if !silent {
                print("📍 Starting new location request")
            }
            locationManager.stopUpdatingLocation()
            
            // Check current authorization status first
            let status = locationManager.authorizationStatus
            if status == .denied || status == .restricted {
                if !hasLoggedPermissionDenied {
                    print("⚠️ Location permission denied, using alternative source")
                    hasLoggedPermissionDenied = true
                }
                handleLocationPermissionDenied()
                return
            }
            
            // Cancel existing timeout task
            timeoutTask?.cancel()
            
            // Create new timeout task
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 second timeout
                if !Task.isCancelled && currentLocation == nil {
                    await MainActor.run {
                        // Use cached location if available
                        if let cached = lastKnownLocation {
                            print("📍 Using cached location")
                            self.currentLocation = cached
                            if let viewModel = self.viewModel {
                                Task { await viewModel.fetchAtmosphericPressure() }
                            }
                        } else {
                            // Fallback to a default location if we've never had one
                            if !silent {
                                print("📍 Using fallback location")
                            }
                            self.currentLocation = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) // NYC as fallback
                            if let viewModel = self.viewModel {
                                Task { await viewModel.fetchAtmosphericPressure() }
                            }
                        }
                    }
                }
            }
            
            locationManager.requestLocation()
        }
        
        // Add this helper method
        private func handleLocationPermissionDenied() {
            Task {
                await MainActor.run {
                    // Try to use cached location first
                    if let cached = lastKnownLocation {
                        self.currentLocation = cached
                        if let viewModel = self.viewModel {
                            Task { await viewModel.fetchAtmosphericPressure() }
                        }
                    } else {
                        // Use fallback location
                        self.currentLocation = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) // NYC as fallback
                        if let viewModel = self.viewModel {
                            Task { await viewModel.fetchAtmosphericPressure() }
                        }
                    }
                    
                    // Update UI to indicate limited functionality
                    self.viewModel?.atmosphericPressureCategory = "Limited Location Access"
                }
            }
        }
        
        @objc private func appDidEnterBackground() {
            locationManager.stopUpdatingLocation()
            timeoutTask?.cancel()
        }
        
        func startLocationUpdatesWhenAppIsActive() {
            NotificationCenter.default.addObserver(self,
                selector: #selector(appDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }
        
        @objc private func appDidBecomeActive() {
            print("🚀 App became active. Starting location update.")
            requestLocationUpdate()
        }
        
        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let newLocation = locations.last else { return }
            
            // Cancel timeout task since we got a location
            timeoutTask?.cancel()
            timeoutTask = nil
            
            // Calculate distance from last logged location
            let shouldLog: Bool
            if let lastLocation = lastLoggedLocation {
                let lastLocationObj = CLLocation(latitude: lastLocation.latitude, longitude: lastLocation.longitude)
                let distance = lastLocationObj.distance(from: newLocation)
                shouldLog = distance > significantDistanceThreshold
            } else {
                // Always log the first location
                shouldLog = true
            }
            
            DispatchQueue.main.async {
                self.currentLocation = newLocation.coordinate
                
                // Cache the location
                self.cachedLatitude = newLocation.coordinate.latitude
                self.cachedLongitude = newLocation.coordinate.longitude
                
                // Only log if it's a significant change
                if shouldLog {
                    print("📍 Location updated: \(newLocation.coordinate.latitude), \(newLocation.coordinate.longitude)")
                    self.lastLoggedLocation = newLocation.coordinate
                }
                
                // Stop further location updates
                self.locationManager.stopUpdatingLocation()
                
                // Let the viewModel know we have a new location - this is critical
                if let viewModel = self.viewModel {
                    // Set ready flag first
                    viewModel.isLocationReady = true
                    
                    // Then fetch data
                    Task {
                        // Direct fetch using the new location
                        viewModel.fetchEnvironmentalData()
                    }
                }
            }
        }
        
        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    if !hasLoggedPermissionDenied {
                        print("❌ Location access denied. Prompting user to enable permissions.")
                        hasLoggedPermissionDenied = true
                    }
                    Task { @MainActor in
                        await self.handleLocationDenied()
                    }
                default:
                    print("❌ Location Error: \(clError.localizedDescription)")
                    Task { @MainActor in
                        self.viewModel?.atmosphericPressureCategory = "Location Error"
                    }
                }
            }
        }
        
        @MainActor
        private func handleLocationDenied() async {
            // Disable atmospheric pressure but don't show alerts
            await MainActor.run {
                viewModel?.atmosphericPressureCategory = "Location Access Denied"
                viewModel?.atmosphericPressure = "Enable location permissions in Settings"
                
                // Store that we've handled location denial
                UserDefaults.standard.set(true, forKey: "hasHandledLocationDenial")
            }
        }
        
        func setDashboardActive(_ active: Bool) {
            let wasActive = isDashboardActive
            isDashboardActive = active
            
            if active && !wasActive {
                // Dashboard became active - request location if stale
                let timeSinceLastUpdate = Date().timeIntervalSince(lastLocationUpdateTime ?? .distantPast)
                if timeSinceLastUpdate > 300 { // 5 minutes
                    print("📍 Dashboard active - requesting location update")
                    requestLocationUpdate(silent: true)
                }
                
                // Start periodic refresh timer when dashboard is active
                refreshTimer?.invalidate()
                refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
                    print("⏰ Periodic location refresh timer fired")
                    self?.requestLocationUpdate(silent: true)
                }
            } else if !active && wasActive {
                // Dashboard inactive - suspend continuous updates
                print("📍 Dashboard inactive - suspending updates")
                locationManager.stopUpdatingLocation()
                refreshTimer?.invalidate()
                refreshTimer = nil
            }
        }
        
        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                print("✅ Location access granted.")
                requestLocationUpdate()
            case .denied, .restricted:
                if !hasLoggedPermissionDenied {
                    print("❌ Location access denied. Using alternative data source.")
                    hasLoggedPermissionDenied = true
                }
                Task { @MainActor in
                    // Improve handling of location denial
                    viewModel?.atmosphericPressureCategory = "Location Access Denied"
                    
                    // Use cached location if available or a reasonable default
                    if let cachedLat = cachedLatitude, let cachedLon = cachedLongitude {
                        currentLocation = CLLocationCoordinate2D(latitude: cachedLat, longitude: cachedLon)
                        
                        // Attempt to fetch with cached coordinates
                        if let viewModel = self.viewModel {
                            Task { await viewModel.fetchAtmosphericPressure() }
                        }
                    } else {
                        // Use a default location (NYC) as absolute fallback
                        currentLocation = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
                        if let viewModel = self.viewModel {
                            Task { await viewModel.fetchAtmosphericPressure() }
                        }
                    }
                    
                    // Rather than show an intrusive alert, use a non-blocking notification
                    NotificationCenter.default.post(name: Notification.Name("LocationAccessDenied"), object: nil)
                }
            case .notDetermined:
                if !hasLoggedPermissionRequest {
                    print("❓ Location permission not determined.")
                    hasLoggedPermissionRequest = true
                }
                // Only request once
                if !UserDefaults.standard.bool(forKey: "hasRequestedLocation") {
                    locationManager.requestWhenInUseAuthorization()
                    UserDefaults.standard.set(true, forKey: "hasRequestedLocation")
                }
            @unknown default:
                break
            }
        }
        
        deinit {
            timeoutTask?.cancel()
            NotificationCenter.default.removeObserver(self)
        }
    }
    func categorizePressure(_ pressure: Double) -> String {
        switch pressure {
        case ..<1000:
            return "Low"
        case 1000...1020:
            return "Normal"
        default:
            return "High"
        }
    }
    
    // MARK: - MoonPhaseResponse Model
    
    /// Model to decode moon phase API responses
    struct MoonPhaseResponse: Codable {
        let Phase: String
    }
    
    
    // MARK: - WeatherResponse Model
    
    func fetchPressure(from url: URL) async -> Double? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 HTTP Status Code:", httpResponse.statusCode)
                if !(200...299).contains(httpResponse.statusCode) {
                    print("❌ API returned non-successful status code")
                    return nil
                }
            }
            
            let weatherResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)
            let currentPressure = Double(weatherResponse.main.pressure)
            return currentPressure
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("API request was cancelled, not updating atmospheric pressure.")
            } else {
                print("❌ API Error:", error.localizedDescription)
            }
            return nil
        }
    }
    
    struct WeatherResponse: Codable {
        struct Main: Codable {
            let pressure: Int
        }
        let main: Main
    }
    // 📊 Pressure Trend: ⬆️ or ⬇️
    var pressureTrend: String {
        if suddenPressureChange {
            return currentPressure > previousPressure ? "⬆️" : "⬇️"
        } else {
            return ""
        }
    }
       
    // 🌀 Update pressure and detect changes
    func updateAtmosphericPressure(_ pressure: Double) {
        let now = Date()
        
        // Special handling for first pressure reading
        if isFirstLoad {
            pressureReadings = [(pressure: pressure, timestamp: now)]
            currentPressure = pressure
            previousPressure = pressure
            atmosphericPressureCategory = categorizePressure(currentPressure)
            lastPressureReading = currentPressure
            lastPressureTimestamp = now
            suddenPressureChange = false
            isFirstLoad = false
            // Make sure we're updating the UI value
            atmosphericPressure = "\(Int(pressure)) hPa"
            return
        }
        
        // Add new reading and remove old ones
        pressureReadings.append((pressure: pressure, timestamp: now))
        pressureReadings = pressureReadings.filter {
            now.timeIntervalSince($0.timestamp) < 24 * 3600
        }
        
        // Update current pressure
        previousPressure = currentPressure
        currentPressure = pressure
        
        // Compare the last two readings only if we have more than one reading
        if pressureReadings.count >= 2 {
            let lastTwo = Array(pressureReadings.suffix(2))
            let pressureChange = abs(lastTwo[0].pressure - lastTwo[1].pressure)
            let timeChange = lastTwo[1].timestamp.timeIntervalSince(lastTwo[0].timestamp)
            suddenPressureChange = pressureChange >= pressureChangeThreshold &&
                                   timeChange <= pressureReadingInterval
        } else {
            suddenPressureChange = false
        }
        
        atmosphericPressureCategory = categorizePressure(currentPressure)
        // Make sure we're updating the UI value
        atmosphericPressure = "\(Int(pressure)) hPa"
        
        // Persist the latest reading and timestamp
        lastPressureReading = currentPressure
        lastPressureTimestamp = now
        
        print("🌬️ Current Pressure: \(currentPressure) hPa")
        print("⚡ Sudden Change: \(suddenPressureChange)")
        print("🌬️ Category: \(atmosphericPressureCategory)")
    }
    
    
    // Fallback function to use when real data cannot be fetched
    // Also add this fallback method:
    @MainActor
    private func setFallbackAtmosphericPressure() {
        print("⚠️ Using fallback atmospheric pressure")
        
        // Check if we have any previous cached data first
        if let cachedPressure = UserDefaults.standard.object(forKey: "lastKnownPressure") as? Double {
            print("📊 Using cached pressure data: \(cachedPressure)")
            updateAtmosphericPressure(cachedPressure)
            self.atmosphericPressure = "\(Int(cachedPressure)) hPa"
            self.atmosphericPressureCategory = self.categorizePressure(cachedPressure)
            return
        }
        
        // If no cache, generate a realistic fallback with consistent random seed
        let calendar = Calendar.current
        let day = calendar.component(.day, from: Date())
        let month = calendar.component(.month, from: Date())
        
        // Use date components to seed a deterministic "random" value
        let seed = Double(day + month * 31) / 100.0
        let basePressure = 1013.0 // Standard sea level pressure
        let deterministicVariation = sin(seed * 6.28) * 10.0 // ±10 hPa variation
        let fallbackPressure = basePressure + deterministicVariation
        
        print("⚠️ Using deterministic fallback pressure: \(fallbackPressure) hPa")
        
        // Update the UI
        updateAtmosphericPressure(fallbackPressure)
        self.atmosphericPressure = "\(Int(fallbackPressure)) hPa"
        self.atmosphericPressureCategory = self.categorizePressure(fallbackPressure)
        
        // Cache this value for future fallbacks
        UserDefaults.standard.set(fallbackPressure, forKey: "lastKnownPressure")
    }
    
    // 🚀 Handle Atmospheric Pressure Response
    func handlePressureResponse(_ data: Data) {
        do {
            let weatherResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)
            let currentPressure = Double("\(weatherResponse.main.pressure)")
            
            if let pressure = currentPressure {
                updateAtmosphericPressure(pressure)
                atmosphericPressureCategory = categorizePressure(pressure)
                print("🌬️ Atmospheric Pressure Category: \(atmosphericPressureCategory)")
            } else {
                print("⚠️ Failed to convert pressure data.")
                atmosphericPressureCategory = "Unknown"
            }
        } catch {
            print("❌ Failed to parse pressure response:", error.localizedDescription)
            atmosphericPressureCategory = "Unknown"
        }
    }
    
    func ensureEnvironmentalDataLoaded() async {
        // If data is still loading, ensure we have some value
        if atmosphericPressureCategory == "Loading..." || atmosphericPressureCategory.isEmpty {
            print("⚠️ Environmental data still loading, fetching now...")
            
            // Try to fetch one more time
            await fetchAllData()
            
            // If still loading after fetch, use fallback values
            await MainActor.run {
                if atmosphericPressureCategory == "Loading..." || atmosphericPressureCategory.isEmpty {
                    print("⚠️ Using fallback environmental values")
                    atmosphericPressureCategory = "Normal"
                    atmosphericPressure = "1013 hPa"
                    autoMoonPhase = getMoonPhase(for: date)
                    autoMercuryRetrograde = isMercuryInRetrograde(for: date)
                }
            }
        }
    }
    
    func isItemInAvoidList(_ item: String, avoidedItems: [AvoidedItem]) -> Bool {
        let lowerCasedItem = item.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return !lowerCasedItem.isEmpty &&
               avoidedItems.contains(where: { $0.name.lowercased() == lowerCasedItem })
    }
    
    // ✅ Consolidated Environmental Update Function
func updateEnvironmentalFactors() {
        Task {
            await environmentalService.fetchAtmosphericPressure()
            await fetchPressureForecast(lat: locationManager?.currentLocation?.latitude ?? 0.0,
                                        lon: locationManager?.currentLocation?.longitude ?? 0.0)
            fetchMoonPhase(for: Date()) // Updates moon phase
            autoMercuryRetrograde = isMercuryInRetrograde(for: Date())
            
            if isMercuryRetrogradeApproaching(for: Date()) {
                alertMessage = "☿ Heads up! Mercury Retrograde starts in less than 3 days."
                showAlert = true
            }
        }
    }
}

extension LogItemViewModel {
    // Standard region names enum
    // Add or update this in LogItemViewModel.swift, inside the StandardRegion enum

    
    func standardizeBodyAreas() {
        // Convert all areas to standard format
        selectedBodyAreas = Set(selectedBodyAreas.map { BodyRegionUtility.standardizeRegionName($0) })
    }
    
    // Replace your existing addSymptom function
    func addSymptom(_ symptom: String) {
        let standardizedSymptom = SymptomManager.shared.standardizeSymptomName(symptom)
        selectedSymptoms.insert(standardizedSymptom)
        
        // Find and add the corresponding body region
        if let region = symptomToRegion[standardizedSymptom] {
            let standardizedRegion = BodyRegionUtility.standardizeRegionName(region)
            selectedBodyAreas.insert(standardizedRegion)
            print("✅ Added region \(standardizedRegion) for symptom \(standardizedSymptom)")
        } else {
            // Report unmapped symptom
            reportUnmappedSymptom(symptomName: standardizedSymptom)
        }
        
        print("📍 Selected symptoms: \(selectedSymptoms)")
        print("🗺️ Selected body areas: \(selectedBodyAreas)")
        
        verifySymptomRegionMapping()
    }
    
    // Add this function to LogItemViewModel.swift
    // In LogItemViewModel.swift, update the verifySymptomRegionMapping method
    func verifySymptomRegionMapping() {
        print("🔍 VERIFYING SYMPTOM-REGION MAPPING")
        print("=================================")
        
        // First pass - collect all changes to make
        var regionsToAdd = Set<String>()
        _ = [String: String]()
        
        // Check all selected symptoms
        print("📋 CHECKING SELECTED SYMPTOMS:")
        for symptom in selectedSymptoms {
            if let region = symptomToRegion[symptom] {
                let standardRegion = BodyRegionUtility.standardizeRegionName(region)
                print("✅ Symptom '\(symptom)' maps to region '\(region)' (standardized: '\(standardRegion)')")
                
                // Check if region is selected
                if selectedBodyAreas.contains(standardRegion) {
                    print("  ✓ Region '\(standardRegion)' is selected")
                } else {
                    print("  ❌ Region '\(standardRegion)' is NOT selected")
                    regionsToAdd.insert(standardRegion)
                }
            } else {
                print("⚠️ Symptom '\(symptom)' has no region mapping!")
            }
        }
        
        // Now apply all changes at once
        for regionToAdd in regionsToAdd {
            selectedBodyAreas.insert(regionToAdd)
            print("  🔧 Added region '\(regionToAdd)' to selectedBodyAreas")
        }
        
        print("=================================")
    }
}

// Add this to LogItemViewModel.swift, outside the class definition
struct SymptomDefinition: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let regionId: String
    let category: SymptomCategory
    
    enum SymptomCategory: String, CaseIterable {
        case physical
        case mental
        case digestive
        case respiratory
        case musculoskeletal
        case neurological
        case skin
        case other
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    static func == (lhs: SymptomDefinition, rhs: SymptomDefinition) -> Bool {
        return lhs.name == rhs.name
    }
}
