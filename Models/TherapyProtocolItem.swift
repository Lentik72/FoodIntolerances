import SwiftData
import Foundation

@Model
class TherapyProtocolItem: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute var itemName: String
    @Attribute var dosageOrQuantity: String?
    @Attribute var usageNotes: String?
    @Attribute var isCompleted: Bool = false
    @Relationship var cabinetItem: CabinetItem?
    @Relationship var parentProtocol: TherapyProtocol

    init(itemName: String,
         parentProtocol: TherapyProtocol,
         dosageOrQuantity: String? = nil,
         usageNotes: String? = nil,
         cabinetItem: CabinetItem? = nil) {
        self.itemName = itemName
        self.dosageOrQuantity = dosageOrQuantity
        self.usageNotes = usageNotes
        self.parentProtocol = parentProtocol
        self.cabinetItem = cabinetItem
    }
}
