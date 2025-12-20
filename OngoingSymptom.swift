//
//  OngoingSymptom.swift
//  YourProject
//
//  This model tracks a symptom over multiple days until the user closes it.
//

import SwiftData
import Foundation

@Model
class OngoingSymptom: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    @Attribute var name: String
    @Attribute var startDate: Date
    @Attribute var endDate: Date?
    @Attribute var isOpen: Bool
    @Attribute var notes: String
    
    @Attribute var usedProtocolID: UUID?
    @Attribute var protocolNotes: String?
    @Attribute var protocolEffectiveness: Int?
    @Attribute var protocolLastUpdated: Date?

    init(name: String,
         startDate: Date = Date(),
         endDate: Date? = nil,
         isOpen: Bool = true,
         notes: String = "",
         usedProtocolID: UUID? = nil,
         protocolNotes: String? = nil,
         protocolEffectiveness: Int? = nil) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.isOpen = isOpen
        self.notes = notes
        self.usedProtocolID = usedProtocolID
        self.protocolNotes = protocolNotes
        self.protocolEffectiveness = protocolEffectiveness
        self.protocolLastUpdated = Date()
    }
}
