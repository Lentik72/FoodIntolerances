import Foundation

// MARK: - Symptom Definition

struct SymptomDefinition: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let regionId: String
    let category: SymptomCategory

    enum SymptomCategory: String, CaseIterable {
        case physical
        case mental
        case digestive
        case respiratory
        case musculoskeletal
        case neurological
        case skin
        case other
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: SymptomDefinition, rhs: SymptomDefinition) -> Bool {
        return lhs.name == rhs.name
    }
}

// MARK: - Symptom Catalog

struct SymptomCatalog {
    /// Returns all predefined symptoms with duplicates removed
    static func allSymptoms() -> [SymptomDefinition] {
        var uniqueSymptoms: [SymptomDefinition] = []
        var seenSymptomNames = Set<String>()

        for symptom in rawSymptoms {
            if seenSymptomNames.insert(symptom.name).inserted {
                uniqueSymptoms.append(symptom)
            }
        }

        return uniqueSymptoms
    }

    /// Get symptoms for a specific body region
    static func symptoms(for regionId: String) -> [SymptomDefinition] {
        return allSymptoms().filter { $0.regionId == regionId }
    }

    /// Build a mapping from symptom name to region ID
    static func symptomToRegionMapping() -> [String: String] {
        var mapping: [String: String] = [:]
        for symptom in allSymptoms() {
            mapping[symptom.name] = symptom.regionId
        }
        return mapping
    }

    /// All predefined symptom names
    static var predefinedSymptomNames: [String] {
        return allSymptoms().map { $0.name }
    }

    // MARK: - Raw Symptom Data

    private static let rawSymptoms: [SymptomDefinition] = [
        // Head region
        SymptomDefinition(name: "Headache", regionId: "head", category: .neurological),
        SymptomDefinition(name: "Migraine", regionId: "head", category: .neurological),
        SymptomDefinition(name: "Sinus Pain", regionId: "head", category: .neurological),
        SymptomDefinition(name: "Vertigo", regionId: "head", category: .neurological),
        SymptomDefinition(name: "Dizziness", regionId: "head", category: .neurological),
        SymptomDefinition(name: "Eye Pain", regionId: "head", category: .physical),
        SymptomDefinition(name: "Anxiety", regionId: "head", category: .mental),
        SymptomDefinition(name: "Stress", regionId: "head", category: .mental),
        SymptomDefinition(name: "Depression", regionId: "head", category: .mental),
        SymptomDefinition(name: "Mental Fatigue", regionId: "head", category: .mental),
        SymptomDefinition(name: "Cognitive Fog", regionId: "head", category: .mental),

        // Neck region
        SymptomDefinition(name: "Neck Pain", regionId: "neck", category: .musculoskeletal),
        SymptomDefinition(name: "Stiff Neck", regionId: "neck", category: .musculoskeletal),
        SymptomDefinition(name: "Shoulder Pain", regionId: "neck", category: .musculoskeletal),
        SymptomDefinition(name: "Cervical Pain", regionId: "neck", category: .musculoskeletal),

        // Chest region
        SymptomDefinition(name: "Chest Pain", regionId: "chest", category: .respiratory),
        SymptomDefinition(name: "Chest Tightness", regionId: "chest", category: .respiratory),
        SymptomDefinition(name: "Breathing Difficulty", regionId: "chest", category: .respiratory),
        SymptomDefinition(name: "Shortness of Breath", regionId: "chest", category: .respiratory),
        SymptomDefinition(name: "Cough", regionId: "chest", category: .respiratory),
        SymptomDefinition(name: "Upper Chest Tightness", regionId: "chest", category: .respiratory),
        SymptomDefinition(name: "Lower Chest Pain", regionId: "chest", category: .respiratory),
        SymptomDefinition(name: "Bronchial Discomfort", regionId: "chest", category: .respiratory),
        SymptomDefinition(name: "Diaphragm Tension", regionId: "chest", category: .respiratory),

        // Abdomen region
        SymptomDefinition(name: "Abdominal Pain", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Stomach Pain", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Bloating", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Nausea", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Vomiting", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Loose Stool", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Hard Stool", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Digestive Discomfort", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Upper Abdominal Cramps", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Lower Abdominal Pain", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Indigestion", regionId: "abdomen", category: .digestive),
        SymptomDefinition(name: "Stomach Ache", regionId: "abdomen", category: .digestive),

        // Pelvic region
        SymptomDefinition(name: "Pelvic Pain", regionId: "pelvic", category: .physical),
        SymptomDefinition(name: "Groin Discomfort", regionId: "pelvic", category: .physical),
        SymptomDefinition(name: "Menstrual Cramps", regionId: "pelvic", category: .physical),
        SymptomDefinition(name: "Hip Discomfort", regionId: "pelvic", category: .physical),

        // Back regions
        SymptomDefinition(name: "Upper Back Pain", regionId: "upperBack", category: .musculoskeletal),
        SymptomDefinition(name: "Middle Back Pain", regionId: "middleBack", category: .musculoskeletal),
        SymptomDefinition(name: "Lower Back Pain", regionId: "lowerBack", category: .musculoskeletal),
        SymptomDefinition(name: "Back Stiffness", regionId: "upperBack", category: .musculoskeletal),
        SymptomDefinition(name: "Sciatica", regionId: "lowerBack", category: .musculoskeletal),
        SymptomDefinition(name: "Buttock Pain", regionId: "buttocks", category: .musculoskeletal),
        SymptomDefinition(name: "Back Pain", regionId: "upperBack", category: .musculoskeletal),
        SymptomDefinition(name: "Upper Back Strain", regionId: "upperBack", category: .musculoskeletal),
        SymptomDefinition(name: "Shoulder Blade Pain", regionId: "upperBack", category: .musculoskeletal),
        SymptomDefinition(name: "Trapezius Pain", regionId: "upperBack", category: .musculoskeletal),

        // Left Arm regions - Front
        SymptomDefinition(name: "Upper Left Arm Muscle Pain", regionId: "upperLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Left Bicep Pain", regionId: "upperLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Left Tricep Pain", regionId: "upperLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Shoulder Pain Left", regionId: "upperLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Shoulder Tension Left", regionId: "upperLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Upper Left Arm Pain", regionId: "upperLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Left Forearm Pain", regionId: "lowerLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Left Wrist Pain", regionId: "lowerLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Lower Left Arm Pain", regionId: "lowerLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Left Arm Elbow Pain", regionId: "lowerLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Wrist Strain", regionId: "lowerLeftArm", category: .musculoskeletal),
        SymptomDefinition(name: "Bicep Pain Left", regionId: "upperLeftArm", category: .musculoskeletal),

        // Right Arm regions - Front
        SymptomDefinition(name: "Upper Right Arm Muscle Pain", regionId: "upperRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Right Bicep Pain", regionId: "upperRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Right Tricep Pain", regionId: "upperRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Shoulder Pain Right", regionId: "upperRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Shoulder Tension Right", regionId: "upperRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Upper Right Arm Pain", regionId: "upperRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Right Forearm Pain", regionId: "lowerRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Right Wrist Pain", regionId: "lowerRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Lower Right Arm Pain", regionId: "lowerRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Right Arm Elbow Pain", regionId: "lowerRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Right Shoulder Pain", regionId: "upperRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Forearm Pain", regionId: "lowerRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Elbow Strain", regionId: "lowerRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Shoulder Strain", regionId: "upperRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Bicep Pain", regionId: "upperRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Tricep Pain", regionId: "upperRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Bicep Pain Right", regionId: "upperRightArm", category: .musculoskeletal),

        // Left Leg regions - Front
        SymptomDefinition(name: "Upper Left Leg Pain", regionId: "upperLeftLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Left Thigh Pain", regionId: "upperLeftLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Left Calf Pain", regionId: "lowerLeftLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Left Ankle Pain", regionId: "lowerLeftLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Calf Pain Left", regionId: "lowerLeftLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Lower Left Leg Pain", regionId: "lowerLeftLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Ankle Pain Left", regionId: "lowerLeftLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Left Knee Pain", regionId: "upperLeftLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Left Leg Cramps", regionId: "lowerLeftLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Hamstring Pain Left", regionId: "upperLeftLeg", category: .musculoskeletal),

        // Right Leg regions - Front
        SymptomDefinition(name: "Upper Right Leg Pain", regionId: "upperRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Right Thigh Pain", regionId: "upperRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Right Calf Pain", regionId: "lowerRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Right Ankle Pain", regionId: "lowerRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Calf Pain Right", regionId: "lowerRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Lower Right Leg Pain", regionId: "lowerRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Ankle Pain Right", regionId: "lowerRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Right Knee Pain", regionId: "upperRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Right Leg Cramps", regionId: "lowerRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Shin Splints", regionId: "lowerRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Thigh Pain", regionId: "upperRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Quadriceps Pain", regionId: "upperRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Hamstring Pain Right", regionId: "upperRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Calf Muscle Strain", regionId: "lowerRightLeg", category: .musculoskeletal),

        // General Leg symptoms
        SymptomDefinition(name: "Leg Pain", regionId: "upperRightLeg", category: .musculoskeletal),
        SymptomDefinition(name: "Knee Pain", regionId: "upperRightLeg", category: .musculoskeletal),

        // Left Arm regions - Back
        SymptomDefinition(name: "Left Arm Back Pain", regionId: "leftArmBack", category: .musculoskeletal),
        SymptomDefinition(name: "Upper Left Arm Back Pain", regionId: "upperLeftArmBack", category: .musculoskeletal),
        SymptomDefinition(name: "Lower Left Arm Back Pain", regionId: "lowerLeftArmBack", category: .musculoskeletal),
        SymptomDefinition(name: "Left Triceps Pain", regionId: "upperLeftArmBack", category: .musculoskeletal),

        // Right Arm regions - Back
        SymptomDefinition(name: "Right Arm Back Pain", regionId: "rightArmBack", category: .musculoskeletal),
        SymptomDefinition(name: "Upper Right Arm Back Pain", regionId: "upperRightArmBack", category: .musculoskeletal),
        SymptomDefinition(name: "Lower Right Arm Back Pain", regionId: "lowerRightArmBack", category: .musculoskeletal),
        SymptomDefinition(name: "Right Triceps Pain", regionId: "upperRightArmBack", category: .musculoskeletal),

        // Left Leg regions - Back
        SymptomDefinition(name: "Upper Left Leg Back Pain", regionId: "upperLeftLegBack", category: .musculoskeletal),
        SymptomDefinition(name: "Lower Left Leg Back Pain", regionId: "lowerLeftLegBack", category: .musculoskeletal),
        SymptomDefinition(name: "Hamstring Tension Left", regionId: "upperLeftLegBack", category: .musculoskeletal),

        // Right Leg regions - Back
        SymptomDefinition(name: "Upper Right Leg Back Pain", regionId: "upperRightLegBack", category: .musculoskeletal),
        SymptomDefinition(name: "Lower Right Leg Back Pain", regionId: "lowerRightLegBack", category: .musculoskeletal),
        SymptomDefinition(name: "Hamstring Tension Right", regionId: "upperRightLegBack", category: .musculoskeletal),

        // General symptoms
        SymptomDefinition(name: "Fatigue", regionId: "torso", category: .other),
        SymptomDefinition(name: "Muscle Soreness", regionId: "torso", category: .musculoskeletal),
        SymptomDefinition(name: "Joint Pain", regionId: "torso", category: .musculoskeletal),
        SymptomDefinition(name: "Muscle Strain", regionId: "torso", category: .musculoskeletal),

        // Common areas of strain
        SymptomDefinition(name: "Shoulder Blade Tension", regionId: "upperBack", category: .musculoskeletal),
        SymptomDefinition(name: "Elbow Pain", regionId: "lowerRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Wrist Pain", regionId: "lowerRightArm", category: .musculoskeletal),
        SymptomDefinition(name: "Forearm Strain", regionId: "lowerLeftArmBack", category: .musculoskeletal),
        SymptomDefinition(name: "Arm Pain", regionId: "upperRightArm", category: .musculoskeletal),

        // Skin conditions
        SymptomDefinition(name: "Skin Rash", regionId: "skin", category: .skin),
        SymptomDefinition(name: "Insect Bite", regionId: "skin", category: .skin),

        // Other
        SymptomDefinition(name: "Other", regionId: "torso", category: .other)
    ]
}
