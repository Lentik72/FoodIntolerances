import Foundation
import SwiftData

enum AvoidedItemType: String, CaseIterable, Codable, Identifiable {
    case food = "Food"
    case drink = "Drink"
    case activity = "Activity"
    case supplement = "Supplement"

    var id: String { self.rawValue }
}

@Model
class AvoidedItem: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute var name: String
    @Attribute var type: AvoidedItemType
    @Attribute var dateAdded: Date = Date()
    @Attribute var reason: String? = nil
    
    /// If `isRecommended = true`, this item is suggested by the app
    /// until user confirms it into their official avoid list.
    @Attribute var isRecommended: Bool = false

    init(name: String,
         type: AvoidedItemType,
         reason: String? = nil,
         isRecommended: Bool = false) {
        self.name = name
        self.type = type
        self.reason = reason
        self.isRecommended = isRecommended
    }
}
