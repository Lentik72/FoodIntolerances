import Foundation
import SwiftData

@Model
class TherapyProtocol: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute var title: String
    @Attribute var category: String
    @Attribute var instructions: String
    @Attribute var frequency: String
    @Attribute var timeOfDay: String
    @Attribute var duration: String
    @Attribute var startDate: Date
    @Attribute var endDate: Date?
    @Attribute var status: String = "Active"
    @Attribute var dateAdded: Date
    @Attribute var notes: String?
    @Attribute var isActive: Bool = false  // Default to inactive
    @Attribute var isWishlist: Bool
    @Relationship var items: [TherapyProtocolItem] = []
    @Relationship(deleteRule: .nullify, inverse: \LogEntry.recommendedProtocol)
    var associatedLogs: [LogEntry]?
    @Attribute var createdDate: Date = Date()
    @Attribute var reminderTime: Date? // ✅ Ensure it is Optional
    @Attribute var protocolEffectiveness: Int?
    @Attribute var completionDate: Date?
    @Attribute(.transformable(by: StringArrayTransformer.self))
    var symptoms: [String]? = []
    @Attribute var symptomsData: Data = Data()
    @Attribute(.transformable(by: StringArrayTransformer.self))
    var tags: [String]? = []

    // 🆕 Reminder Properties
    @Attribute var enableReminder: Bool = false

    init(
        title: String,
        category: String,
        instructions: String,
        frequency: String,
        timeOfDay: String,
        duration: String,
        symptoms: [String],
        startDate: Date,
        endDate: Date? = nil,
        notes: String? = nil,
        isWishlist: Bool = false,
        isActive: Bool = true,
        dateAdded: Date = Date(),
        tags: [String]? = nil,
        enableReminder: Bool = false,
        reminderTime: Date? = nil,
        protocolEffectiveness: Int? = nil,
        completionDate: Date? = nil
    ) {
        self.title = title
        self.category = category
        self.instructions = instructions
        self.frequency = frequency
        self.timeOfDay = timeOfDay
        self.duration = duration
        self.symptoms = symptoms.isEmpty ? [] : symptoms
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.tags = tags
        self.status = "Active"
        self.isWishlist = isWishlist
        self.isActive = isActive
        self.createdDate = Date()
        self.dateAdded = dateAdded
        self.enableReminder = enableReminder
        self.reminderTime = reminderTime
        self.protocolEffectiveness = protocolEffectiveness
        self.completionDate = completionDate
        
        // Create an empty array to avoid nil value issues
        if symptoms.isEmpty {
            self.symptoms = []
        } else {
            // Use StringArrayTransformer to properly encode the symptoms
            do {
                let data = try JSONEncoder().encode(symptoms)
                self.symptomsData = data
            } catch {
                print("Error encoding symptoms array: \(error)")
                // Create an empty data object to avoid crashes
                self.symptomsData = Data()
            }
        }
    }

    // 🆕 Automatically disable reminders when protocol ends
    func shouldDisableReminder() -> Bool {
        guard let endDate = endDate else { return false }
        return Date() > endDate
    }
}
struct ProtocolCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    
    static let defaultCategories: [ProtocolCategory] = [
        ProtocolCategory(name: "Digestive Health", icon: "stomach"),
        ProtocolCategory(name: "Mental Wellness", icon: "brain.head.profile"),
        ProtocolCategory(name: "Respiratory", icon: "lungs.fill"),
        ProtocolCategory(name: "Sleep Improvement", icon: "bed.double.fill"),
        ProtocolCategory(name: "Pain Management", icon: "bandage.fill"),
        ProtocolCategory(name: "Skin & Hair", icon: "hand.raised.fingers.spread"),
        ProtocolCategory(name: "Immune Support", icon: "shield"),
        ProtocolCategory(name: "Energy & Vitality", icon: "bolt.fill"),
        ProtocolCategory(name: "Hormonal Balance", icon: "waveform.path.ecg"),
        ProtocolCategory(name: "Detox & Cleansing", icon: "drop.fill"),
        ProtocolCategory(name: "Physical Therapy", icon: "figure.walk"),
        ProtocolCategory(name: "General Health", icon: "heart.fill")
    ]
}
