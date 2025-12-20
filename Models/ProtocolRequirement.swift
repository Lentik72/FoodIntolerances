//
//  ProtocolRequirement.swift
//  Food IntolerancesI am choosing options
//
//  Created by Leo on 2/1/25.
//

import Foundation
import SwiftData

@Model
class ProtocolRequirement: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    
    // Store a requirement name (e.g., "Vitamin C", "Sauna", "Probiotic")
    @Attribute var itemName: String
    
    // Dosage or serving info
    @Attribute var dosage: String?  // e.g., "100 mg", "1 tsp", "2 capsules"
    
    // Notes or additional instructions
    @Attribute var notes: String?
    
    // The protocol this requirement belongs to
    @Relationship var parentProtocol: TherapyProtocol?

    // Link to an existing item in the Cabinet (if available)
    @Relationship var cabinetItem: CabinetItem?

    init(itemName: String,
         dosage: String? = nil,
         notes: String? = nil,
         parentProtocol: TherapyProtocol? = nil,
         cabinetItem: CabinetItem? = nil) {
        self.itemName = itemName
        self.dosage = dosage
        self.notes = notes
        self.parentProtocol = parentProtocol
        self.cabinetItem = cabinetItem
    }
}
