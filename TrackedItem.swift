import SwiftUI
import SwiftData

// MARK: - TrackedItemType Enumeration
enum TrackedItemType: String, CaseIterable, Identifiable, Codable {
    case supplement = "Supplement"
    case medication = "Medication"
    case food = "Food"

    var id: String { self.rawValue }
}

// MARK: - TrackedItem Model
@Model
class TrackedItem: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute var name: String
    @Attribute var type: TrackedItemType
    @Attribute var brand: String?
    @Attribute var startDate: Date = Date()
    @Attribute var notes: String = ""
    @Attribute var isActive: Bool = true

    init(name: String, type: TrackedItemType, brand: String? = nil, startDate: Date = Date(), notes: String = "", isActive: Bool = true) {
        self.name = name
        self.type = type
        self.brand = brand
        self.startDate = startDate
        self.notes = notes
        self.isActive = isActive
    }
}
