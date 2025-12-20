import Foundation
import SwiftUI

class SymptomManager {
    static let shared = SymptomManager()
    
    private init() {} // Enforce singleton usage
    
    // MARK: - Custom Symptoms Management
    func addCustomSymptom(_ symptom: String) -> Bool {
        let trimmedSymptom = symptom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSymptom.isEmpty else { return false }
        
        var currentCustomSymptoms = UserDefaults.standard.stringArray(forKey: "customSymptoms") ?? []
        
        // Check if symptom already exists
        if currentCustomSymptoms.contains(trimmedSymptom) {
            return false
        }
        
        // Add and save
        currentCustomSymptoms.append(trimmedSymptom)
        UserDefaults.standard.set(currentCustomSymptoms, forKey: "customSymptoms")
        return true
    }
    
    func standardizeSymptomName(_ symptom: String) -> String {
        let standardized = symptom.trimmingCharacters(in: .whitespaces)
        
        // Handle common variations
        switch standardized.lowercased() {
        case let name where name.contains("left arm muscle"):
            return "Upper Left Arm Muscle Pain"
        case let name where name.contains("right arm muscle"):
            return "Upper Right Arm Muscle Pain"
        case let name where name.contains("left shoulder"):
            return "Shoulder Pain Left"
        case let name where name.contains("right shoulder"):
            return "Shoulder Pain Right"
        case let name where name.contains("left calf"):
            return "Calf Pain Left"
        case let name where name.contains("right calf"):
            return "Calf Pain Right"
        default:
            return standardized
        }
    }
    
    func getAllCustomSymptoms() -> [String] {
        return UserDefaults.standard.stringArray(forKey: "customSymptoms") ?? []
    }
    
    // MARK: - Symptom-Region Mapping
    private var symptomToRegionMap: [String: String] = [
        // Head region
        "Headache": "head",
        "Migraine": "head",
        "Sinus Pain": "head",
        "Vertigo": "head",
        "Dizziness": "head",
        "Eye Pain": "head",
        "Anxiety": "head",
        "Stress": "head",
        "Depression": "head",
        "Mental Fatigue": "head",
        "Cognitive Fog": "head",
        "Bloody Nose": "head",
        
        // Neck region
        "Neck Pain": "neck",
        "Stiff Neck": "neck",
        "Shoulder Pain": "neck",
        "Cervical Pain": "neck",
        
        // Chest region
        "Chest Pain": "chest",
        "Chest Tightness": "chest",
        "Breathing Difficulty": "chest",
        "Shortness of Breath": "chest",
        "Cough": "chest",
        "Upper Chest Tightness": "chest",
        "Lower Chest Pain": "chest",
        "Bronchial Discomfort": "chest",
        "Diaphragm Tension": "chest",
        
        // Abdomen region
        "Abdominal Pain": "abdomen",
        "Stomach Pain": "abdomen",
        "Bloating": "abdomen",
        "Nausea": "abdomen",
        "Vomiting": "abdomen",
        "Loose Stool": "abdomen",
        "Hard Stool": "abdomen",
        "Digestive Discomfort": "abdomen",
        "Upper Abdominal Cramps": "abdomen",
        "Lower Abdominal Pain": "abdomen",
        "Indigestion": "abdomen",
        "Stomach Ache": "abdomen",
        
        // Pelvic region
        "Pelvic Pain": "pelvic",
        "Groin Discomfort": "pelvic",
        "Menstrual Cramps": "pelvic",
        "Hip Discomfort": "pelvic",
        
        // Back regions
        "Upper Back Pain": "upperBack",
        "Middle Back Pain": "middleBack",
        "Lower Back Pain": "lowerBack",
        "Back Stiffness": "upperBack",
        "Sciatica": "lowerBack",
        "Buttock Pain": "buttocks",
        "Back Pain": "upperBack",
        "Upper Back Strain": "upperBack",
        "Shoulder Blade Pain": "upperBack",
        "Trapezius Pain": "upperBack",
        
        // Left Arm regions - Front
        "Upper Left Arm Muscle Pain": "upperLeftArm",
        "Left Bicep Pain": "upperLeftArm",
        "Left Tricep Pain": "upperLeftArm",
        "Shoulder Pain Left": "upperLeftArm",
        "Shoulder Tension Left": "upperLeftArm",
        "Upper Left Arm Pain": "upperLeftArm",
        "Left Forearm Pain": "lowerLeftArm",
        "Left Wrist Pain": "lowerLeftArm",
        "Lower Left Arm Pain": "lowerLeftArm",
        "Left Arm Elbow Pain": "lowerLeftArm",
        "Wrist Strain": "lowerLeftArm",
        "Bicep Pain Left": "upperLeftArm",
        
        // Right Arm regions - Front
        "Upper Right Arm Muscle Pain": "upperRightArm",
        "Right Bicep Pain": "upperRightArm",
        "Right Tricep Pain": "upperRightArm",
        "Shoulder Pain Right": "upperRightArm",
        "Shoulder Tension Right": "upperRightArm",
        "Upper Right Arm Pain": "upperRightArm",
        "Right Forearm Pain": "lowerRightArm",
        "Right Wrist Pain": "lowerRightArm",
        "Lower Right Arm Pain": "lowerRightArm",
        "Right Arm Elbow Pain": "lowerRightArm",
        "Right Shoulder Pain": "upperRightArm",
        "Forearm Pain": "lowerRightArm",
        "Elbow Strain": "lowerRightArm",
        "Shoulder Strain": "upperRightArm",
        "Bicep Pain": "upperRightArm",
        "Tricep Pain": "upperRightArm",
        "Bicep Pain Right": "upperRightArm",
        
        // Left Leg regions - Front
        "Upper Left Leg Pain": "upperLeftLeg",
        "Left Thigh Pain": "upperLeftLeg",
        "Left Calf Pain": "lowerLeftLeg",
        "Left Ankle Pain": "lowerLeftLeg",
        "Calf Pain Left": "lowerLeftLeg",
        "Lower Left Leg Pain": "lowerLeftLeg",
        "Ankle Pain Left": "lowerLeftLeg",
        "Left Knee Pain": "upperLeftLeg",
        "Left Leg Cramps": "lowerLeftLeg",
        "Hamstring Pain Left": "upperLeftLeg",
        
        // Right Leg regions - Front
        "Upper Right Leg Pain": "upperRightLeg",
        "Right Thigh Pain": "upperRightLeg",
        "Right Calf Pain": "lowerRightLeg",
        "Right Ankle Pain": "lowerRightLeg",
        "Calf Pain Right": "lowerRightLeg",
        "Lower Right Leg Pain": "lowerRightLeg",
        "Ankle Pain Right": "lowerRightLeg",
        "Right Knee Pain": "upperRightLeg",
        "Right Leg Cramps": "lowerRightLeg",
        "Shin Splints": "lowerRightLeg",
        "Thigh Pain": "upperRightLeg",
        "Quadriceps Pain": "upperRightLeg",
        "Hamstring Pain Right": "upperRightLeg",
        "Calf Muscle Strain": "lowerRightLeg",
        
        // General Leg symptoms
        "Leg Pain": "upperRightLeg",
        "Knee Pain": "upperRightLeg",
        
        // Left Arm regions - Back
        "Left Arm Back Pain": "leftArmBack",
        "Upper Left Arm Back Pain": "upperLeftArmBack",
        "Lower Left Arm Back Pain": "lowerLeftArmBack",
        "Left Triceps Pain": "upperLeftArmBack",
        
        // Right Arm regions - Back
        "Right Arm Back Pain": "rightArmBack",
        "Upper Right Arm Back Pain": "upperRightArmBack",
        "Lower Right Arm Back Pain": "lowerRightArmBack",
        "Right Triceps Pain": "upperRightArmBack",
        
        // Left Leg regions - Back
        "Upper Left Leg Back Pain": "upperLeftLegBack",
        "Lower Left Leg Back Pain": "lowerLeftLegBack",
        "Hamstring Tension Left": "upperLeftLegBack",
        
        // Right Leg regions - Back
        "Upper Right Leg Back Pain": "upperRightLegBack",
        "Lower Right Leg Back Pain": "lowerRightLegBack",
        "Hamstring Tension Right": "upperRightLegBack",
        
        // General symptoms
        "Fatigue": "torso",
        "Muscle Soreness": "torso",
        "Joint Pain": "torso",
        "Muscle Strain": "torso",
        
        // Common areas of strain
        "Shoulder Blade Tension": "upperBack",
        "Elbow Pain": "lowerRightArm",
        "Wrist Pain": "lowerRightArm",
        "Forearm Strain": "lowerLeftArmBack",
        "Arm Pain": "upperRightArm",
        
        // Skin conditions
        "Skin Rash": "skin",
        "Insect Bite": "skin",
        
        // Other
        "Other": "torso"
    ]
    
    func getRegionForSymptom(_ symptom: String) -> String? {
        return symptomToRegionMap[symptom]
    }
    
    func addSymptomRegionMapping(_ symptom: String, region: String) {
        symptomToRegionMap[symptom] = region
    }
    
    // Return all symptoms for a given region
    func getSymptomsForRegion(_ region: String) -> [String] {
        return symptomToRegionMap.filter { $0.value == region }.map { $0.key }
    }
    
    // MARK: - Custom Categories Management
    func addCustomCategory(_ category: String) -> Bool {
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCategory.isEmpty else { return false }
        
        var currentCustomCategories = UserDefaults.standard.stringArray(forKey: "customCategories") ?? []
        
        if currentCustomCategories.contains(trimmedCategory) {
            return false
        }
        
        currentCustomCategories.append(trimmedCategory)
        UserDefaults.standard.set(currentCustomCategories, forKey: "customCategories")
        return true
    }
    
    func getAllCustomCategories() -> [String] {
        return UserDefaults.standard.stringArray(forKey: "customCategories") ?? []
    }
}
