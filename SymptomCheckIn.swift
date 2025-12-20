//
//  SymptomCheckIn.swift
//  YourProject
//
//  This model stores individual severity/protocol updates for an ongoing symptom.
//

import SwiftData
import Foundation

@Model
class SymptomCheckIn: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    /// The ID of the OngoingSymptom this check-in belongs to.
    @Attribute var parentSymptomID: UUID

    @Attribute var date: Date
    @Attribute var severity: Int
    @Attribute var protocolUsed: String
    @Attribute var notes: String
    @Attribute var usedProtocolID: UUID?
    @Attribute var protocolEffectiveness: Int?
    @Attribute var protocolNotes: String?

    init(parentSymptomID: UUID,
         date: Date = Date(),
         severity: Int = 3,
         protocolUsed: String = "",
         notes: String = "") {
        self.parentSymptomID = parentSymptomID
        self.date = date
        self.severity = severity
        self.protocolUsed = protocolUsed
        self.notes = notes
    }
}
