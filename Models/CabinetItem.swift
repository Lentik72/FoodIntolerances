//
//  CabinetItem.swift
//  YourProject
//
//  Created by [Your Name] on [Date].
//

import SwiftData
import Foundation

/// An optional “pantry” or “medicine cabinet” item the user might own.
@Model
class CabinetItem: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute var name: String
    @Attribute var quantity: String? // e.g. "2 boxes left"
    @Attribute var notes: String?
    @Attribute var category: String? // ✅ New: Category (e.g., Supplements, Medications, Devices)
    @Attribute var dosage: String?   // ✅ New: Dosage for medications/supplements
    @Attribute var ingredients: String? // ✅ New: Ingredients for supplements
    @Attribute var usageNotes: String?  // ✅ New: Usage Notes (optional)
    @Attribute var usageCount: Int = 0
    @Attribute var lastUsed: Date?
    @Attribute var refillThreshold: Int? // When to notify about low supplies
    @Attribute var currentStock: Int? // Current quantity remaining
    @Attribute var refillNotificationEnabled: Bool = false
    
    init(
        name: String,
        quantity: String? = nil,
        notes: String? = nil,
        category: String? = "Other",
        dosage: String? = nil,
        ingredients: String? = nil,
        usageNotes: String? = nil,
        usageCount: Int = 0,
        lastUsed: Date? = nil,
        refillThreshold: Int? = nil,
        currentStock: Int? = nil,
        refillNotificationEnabled: Bool = false
    ) {
        self.name = name
        self.quantity = quantity
        self.notes = notes
        self.category = category
        self.dosage = dosage
        self.ingredients = ingredients
        self.usageNotes = usageNotes
        self.usageCount = usageCount
        self.lastUsed = lastUsed
        self.refillThreshold = refillThreshold
        self.currentStock = currentStock
        self.refillNotificationEnabled = refillNotificationEnabled    }
    
    func logUsage(amount: Int = 1) {
            usageCount += 1
            lastUsed = Date()
            
            if let current = currentStock {
                currentStock = max(0, current - amount)
                
                // Check if we need to notify about refill
                if refillNotificationEnabled,
                   let threshold = refillThreshold,
                   let stock = currentStock,
                   stock <= threshold {
                    NotificationManager.shared.scheduleRefillReminder(for: self)
                }
            }
        }
    }

