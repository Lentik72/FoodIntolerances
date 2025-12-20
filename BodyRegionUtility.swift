import Foundation
import SwiftUI

struct BodyRegionUtility {
    // Centralized region name standardization
    static func standardizeRegionName(_ region: String) -> String {
        // Convert to lowercase and remove any extra spaces
        let standardized = region.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Handle specific cases to ensure consistency
        if standardized == "upperleftarm" {
            return "leftupperarm"
        } else if standardized == "upperrightarm" {
            return "rightupperarm"
        } else if standardized == "lowerleftarm" {
            return "leftlowerarm"
        } else if standardized == "lowerrightarm" {
            return "rightlowerarm"
        } else if standardized == "upperleftleg" {
            return "leftupperleg"
        } else if standardized == "upperrightleg" {
            return "rightupperleg"
        } else if standardized == "lowerleftleg" {
            return "leftlowerleg"
        } else if standardized == "lowerrightleg" {
            return "rightlowerleg"
        } else if standardized == "upperback" {
            return "upperback"
        } else if standardized == "middleback" {
            return "middleback"
        } else if standardized == "lowerback" {
            return "lowerback"
        }
        
        return standardized
    }
    
    // Get color for severity
    static func colorForSeverity(_ severity: Int) -> Color {
        switch severity {
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
    
    // Get emoji for severity
    static func severityEmoji(_ severity: Int) -> String {
        switch severity {
        case 1: return "🙂"
        case 2: return "😐"
        case 3: return "😣"
        case 4: return "😫"
        case 5: return "🤯"
        default: return "❓"
        }
    }
    
    // Check if region is valid
    static func isValidRegion(_ regionId: String) -> Bool {
        let standardRegions = [
            "head", "neck", "chest", "abdomen", "pelvic", 
            "upperLeftArm", "lowerLeftArm", "upperRightArm", "lowerRightArm",
            "upperLeftLeg", "lowerLeftLeg", "upperRightLeg", "lowerRightLeg",
            "upperBack", "middleBack", "lowerBack", "leftArmBack", "rightArmBack",
            "upperLeftArmBack", "lowerLeftArmBack", "upperRightArmBack", "lowerRightArmBack",
            "upperLeftLegBack", "lowerLeftLegBack", "upperRightLegBack", "lowerRightLegBack"
        ]
        
        return standardRegions.contains(regionId) || regionId == "skin"
    }
}
