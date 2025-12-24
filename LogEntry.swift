import Foundation
import SwiftData

@Model
class LogEntry: Identifiable {
    // MARK: - Basic Information
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute var itemName: String = ""
    @Attribute var itemType: ItemType = ItemType.symptom
    @Attribute var category: String = "Other"
    @Attribute var foodDrinkItem: String? = nil
    @Attribute var subcategoriesData: Data = Data()
    var subcategories: [String] {
        get {
            guard !subcategoriesData.isEmpty else { return [] }
            do {
                return try JSONDecoder().decode([String].self, from: subcategoriesData)
            } catch {
                Logger.error(error, message: "Error decoding subcategories", category: .data)
                return []
            }
        }
        set {
            do {
                subcategoriesData = try JSONEncoder().encode(newValue)
            } catch {
                Logger.error(error, message: "Error encoding subcategories", category: .data)
                subcategoriesData = Data()
            }
        }
    }
              
    // MARK: - Time and Tracking
    @Attribute(.unique) var date: Date = Date()
    @Attribute var endDate: Date? = nil
    
    // MARK: - Severity and Areas
    @Attribute var severity: Int = 1
    
    // MARK: - Environmental Factors
    @Attribute var moonPhase: String = ""
    @Attribute var atmosphericPressure: String = "Normal"
    @Attribute var suddenChange: Bool = false
    @Attribute var season: String = ""
    @Attribute var isMercuryRetrograde: Bool = false
    
    // MARK: - Protocol and Treatment
    @Attribute var protocolID: UUID? = nil
    @Attribute var protocolEffectiveness: Int? = nil
    @Attribute var protocolNotes: String? = nil
    
    // For storing serialized data
    @Attribute var symptomsData: Data = Data()
    @Attribute var affectedAreasData: Data = Data()
    @Attribute var symptomTriggersData: Data = Data()
    @Attribute var treatmentsData: Data = Data()
    @Attribute var resolutionFactorData: Data = Data()
    
    // MARK: - Additional Information
    @Attribute var linkedTrackedItemID: UUID? = nil
    @Attribute var notes: String = ""
    @Attribute var timeOfDay: Date? = nil
    @Attribute var additionalContext: String = ""

    // MARK: - Contributing Factors (cause context)
    @Attribute var contributingFactorsData: Data = Data()
    var contributingFactors: [String] {
        get {
            guard !contributingFactorsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: contributingFactorsData)) ?? []
        }
        set {
            contributingFactorsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    @Attribute var usedProtocolID: UUID?
    @Attribute var isOngoing: Bool? = nil
    @Attribute var startDate: Date? = nil
    @Attribute var isActive: Bool = true
    @Attribute var symptomPhotoData: Data?
    @Relationship(deleteRule: .nullify)
    var recommendedProtocol: TherapyProtocol?
    
    // Using String Array Transformer for subcategories only
    
    
    
    // MARK: - Initializers
    init() {}
    
    init(
        itemName: String,
        itemType: ItemType,
        category: String,
        symptoms: [String],
        severity: Int,
        notes: String,
        date: Date,
        timeOfDay: Date? = nil,
        moonPhase: String,
        atmosphericPressure: String,
        suddenChange: Bool,
        isMercuryRetrograde: Bool,
        season: String,
        linkedTrackedItemID: UUID? = nil,
        affectedAreas: [String] = [],
        foodDrinkItem: String? = nil,
        symptomTriggers: [String]? = nil,
        additionalContext: String? = nil,
        isOngoing: Bool = false,
        startDate: Date = Date(),
        endDate: Date? = nil,
        protocolID: UUID? = nil,
        protocolEffectiveness: Int? = nil,
        protocolNotes: String? = nil,
        treatments: [Treatment] = [],
        resolutionFactor: ResolutionFactor? = nil,
        usedProtocolID: UUID? = nil,
        subcategories: [String]? = nil,
        symptomPhotoData: Data? = nil
    ) {
        self.itemName = itemName
        self.itemType = itemType
        self.category = category
        do {
                self.symptomsData = try JSONEncoder().encode(symptoms)
                Logger.debug("Successfully encoded symptoms of size: \(symptoms.count)", category: .data)
            } catch {
                Logger.error(error, message: "Error encoding symptoms in init", category: .data)
                self.symptomsData = Data() // Empty data to avoid nil
            }
        self.severity = severity
        self.notes = notes
        self.date = date
        self.timeOfDay = timeOfDay
        self.moonPhase = moonPhase
        self.atmosphericPressure = atmosphericPressure
        self.suddenChange = suddenChange
        self.season = season
        self.isMercuryRetrograde = isMercuryRetrograde
        self.linkedTrackedItemID = linkedTrackedItemID
        self.affectedAreas = affectedAreas
        self.foodDrinkItem = foodDrinkItem
        self.isOngoing = isOngoing
        self.startDate = startDate
        self.endDate = endDate
        self.protocolID = protocolID
        self.protocolEffectiveness = protocolEffectiveness
        self.protocolNotes = protocolNotes
        if let subcats = subcategories {
            do {
                self.subcategoriesData = try JSONEncoder().encode(subcats)
            } catch {
                Logger.error(error, message: "Error encoding subcategories in init", category: .data)
                self.subcategoriesData = Data()
            }
        } else {
            do {
                self.subcategoriesData = try JSONEncoder().encode([String]())
            } catch {
                Logger.error(error, message: "Error encoding empty subcategories in init", category: .data)
                self.subcategoriesData = Data()
            }
        }
        
        if let triggers = symptomTriggers {
           self.symptomTriggers = triggers
        }
        if let context = additionalContext {
           self.additionalContext = context
        }
        self.treatments = treatments
        if let factor = resolutionFactor {
            self.resolutionFactor = factor
        }
        self.usedProtocolID = usedProtocolID
        self.symptomPhotoData = symptomPhotoData
    }
    
    // MARK: - Computed Properties
    var symptoms: [String] {
        get {
            // Use a static flag to avoid duplicate logging
            struct LogControl {
                static var lastLogTime = Date(timeIntervalSince1970: 0)
                static var shouldLog = true
            }
            
            // Only log once per second
            let now = Date()
            if now.timeIntervalSince(LogControl.lastLogTime) < 0.1 {
                LogControl.shouldLog = false
            } else {
                LogControl.lastLogTime = now
                LogControl.shouldLog = true
            }
            
            if LogControl.shouldLog {
                Logger.debug("Getting symptoms from data of size: \(symptomsData.count)", category: .data)
            }

            guard !symptomsData.isEmpty else {
                if LogControl.shouldLog {
                    Logger.debug("Empty symptoms data", category: .data)
                }
                return []
            }

            do {
                let decoded = try JSONDecoder().decode([String].self, from: symptomsData)
                if LogControl.shouldLog {
                    Logger.debug("Successfully decoded \(decoded.count) symptoms", category: .data)
                }
                return decoded
            } catch {
                if LogControl.shouldLog {
                    Logger.error(error, message: "Error decoding symptoms", category: .data)
                }

                // Add recovery mechanism for corrupted data
                if let symptomString = String(data: symptomsData, encoding: .utf8),
                   !symptomString.isEmpty {
                    if LogControl.shouldLog {
                        Logger.debug("Attempting recovery from string: \(symptomString)", category: .data)
                    }
                    // Try to recover if it's a single string
                    return [symptomString]
                }

                return []
            }
        }
        set {
            // Similar logic for set operations
            Logger.debug("Setting symptoms to: \(newValue)", category: .data)
            do {
                symptomsData = try JSONEncoder().encode(newValue)
                Logger.debug("Successfully encoded symptoms of size: \(symptomsData.count)", category: .data)
            } catch {
                Logger.error(error, message: "Error encoding symptoms", category: .data)
                symptomsData = Data()
            }
        }
    }

    var affectedAreas: [String] {
        get {
            guard !affectedAreasData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: affectedAreasData)) ?? []
        }
        set {
            affectedAreasData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    var symptomTriggers: [String] {
        get {
            guard !symptomTriggersData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: symptomTriggersData)) ?? []
        }
        set {
            symptomTriggersData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    var treatments: [Treatment] {
        get {
            guard !treatmentsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([Treatment].self, from: treatmentsData)) ?? []
        }
        set {
            treatmentsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    var resolutionFactor: ResolutionFactor? {
        get {
            guard !resolutionFactorData.isEmpty else { return nil }
            return try? JSONDecoder().decode(ResolutionFactor.self, from: resolutionFactorData)
        }
        set {
            if let newValue = newValue {
                resolutionFactorData = (try? JSONEncoder().encode(newValue)) ?? Data()
            } else {
                resolutionFactorData = Data()
            }
        }
    }
}

// MARK: - Supporting Types
struct Treatment: Codable, Hashable {
    let type: String
    let name: String
    let startDate: Date
    let endDate: Date?
    let dosage: String?
    let effectiveness: Int?
    let notes: String?
}

enum ResolutionFactor: String, Codable {
    case naturalHealing = "Natural Healing"
    case protocolUsed = "Protocol"  // Changed from 'protocol' to 'protocolUsed'
    case medication = "Medication"
    case environmentalChange = "Environmental Change"
    case moonPhase = "Moon Phase"
    case other = "Other"
}
