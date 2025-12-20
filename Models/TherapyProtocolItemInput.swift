import Foundation
import SwiftData

/// A temporary structure to hold protocol item input data during creation and editing.
struct TherapyProtocolItemInput: Identifiable {
    var id: UUID = UUID()
    var itemName: String
    var dosageOrQuantity: String
    var usageNotes: String
    var selectedCabinetItem: CabinetItem?  // Optional Cabinet Item reference
    
    init(itemName: String = "", dosageOrQuantity: String = "", usageNotes: String = "", selectedCabinetItem: CabinetItem? = nil) {
        self.itemName = itemName
        self.dosageOrQuantity = dosageOrQuantity
        self.usageNotes = usageNotes
        self.selectedCabinetItem = selectedCabinetItem
    }
}
