import Foundation

public struct SymptomDefinition: Equatable, Sendable {
    public let displayName: String
    public let canonicalKey: String
    public let regionId: String
    public init(displayName: String, canonicalKey: String, regionId: String) {
        self.displayName = displayName
        self.canonicalKey = canonicalKey
        self.regionId = regionId
    }
}

public enum SymptomCatalog {
    /// (displayName, regionId) ported verbatim from the legacy app's SymptomCatalog.rawSymptoms.
    /// Keep this list append-only-safe: canonicalKey is derived, so renames change the key.
    private static let raw: [(String, String)] = [
        // Head region
        ("Headache", "head"),
        ("Migraine", "head"),
        ("Sinus Pain", "head"),
        ("Vertigo", "head"),
        ("Dizziness", "head"),
        ("Eye Pain", "head"),
        ("Anxiety", "head"),
        ("Stress", "head"),
        ("Depression", "head"),
        ("Mental Fatigue", "head"),
        ("Cognitive Fog", "head"),

        // Neck region
        ("Neck Pain", "neck"),
        ("Stiff Neck", "neck"),
        ("Shoulder Pain", "neck"),
        ("Cervical Pain", "neck"),

        // Chest region
        ("Chest Pain", "chest"),
        ("Chest Tightness", "chest"),
        ("Breathing Difficulty", "chest"),
        ("Shortness of Breath", "chest"),
        ("Cough", "chest"),
        ("Upper Chest Tightness", "chest"),
        ("Lower Chest Pain", "chest"),
        ("Bronchial Discomfort", "chest"),
        ("Diaphragm Tension", "chest"),

        // Abdomen region
        ("Abdominal Pain", "abdomen"),
        ("Stomach Pain", "abdomen"),
        ("Bloating", "abdomen"),
        ("Nausea", "abdomen"),
        ("Vomiting", "abdomen"),
        ("Loose Stool", "abdomen"),
        ("Hard Stool", "abdomen"),
        ("Digestive Discomfort", "abdomen"),
        ("Upper Abdominal Cramps", "abdomen"),
        ("Lower Abdominal Pain", "abdomen"),
        ("Indigestion", "abdomen"),
        ("Stomach Ache", "abdomen"),

        // Pelvic region
        ("Pelvic Pain", "pelvic"),
        ("Groin Discomfort", "pelvic"),
        ("Menstrual Cramps", "pelvic"),
        ("Hip Discomfort", "pelvic"),

        // Back regions
        ("Upper Back Pain", "upperBack"),
        ("Middle Back Pain", "middleBack"),
        ("Lower Back Pain", "lowerBack"),
        ("Back Stiffness", "upperBack"),
        ("Sciatica", "lowerBack"),
        ("Buttock Pain", "buttocks"),
        ("Back Pain", "upperBack"),
        ("Upper Back Strain", "upperBack"),
        ("Shoulder Blade Pain", "upperBack"),
        ("Trapezius Pain", "upperBack"),

        // Left Arm regions - Front
        ("Upper Left Arm Muscle Pain", "upperLeftArm"),
        ("Left Bicep Pain", "upperLeftArm"),
        ("Left Tricep Pain", "upperLeftArm"),
        ("Shoulder Pain Left", "upperLeftArm"),
        ("Shoulder Tension Left", "upperLeftArm"),
        ("Upper Left Arm Pain", "upperLeftArm"),
        ("Left Forearm Pain", "lowerLeftArm"),
        ("Left Wrist Pain", "lowerLeftArm"),
        ("Lower Left Arm Pain", "lowerLeftArm"),
        ("Left Arm Elbow Pain", "lowerLeftArm"),
        ("Wrist Strain", "lowerLeftArm"),
        ("Bicep Pain Left", "upperLeftArm"),

        // Right Arm regions - Front
        ("Upper Right Arm Muscle Pain", "upperRightArm"),
        ("Right Bicep Pain", "upperRightArm"),
        ("Right Tricep Pain", "upperRightArm"),
        ("Shoulder Pain Right", "upperRightArm"),
        ("Shoulder Tension Right", "upperRightArm"),
        ("Upper Right Arm Pain", "upperRightArm"),
        ("Right Forearm Pain", "lowerRightArm"),
        ("Right Wrist Pain", "lowerRightArm"),
        ("Lower Right Arm Pain", "lowerRightArm"),
        ("Right Arm Elbow Pain", "lowerRightArm"),
        ("Right Shoulder Pain", "upperRightArm"),
        ("Forearm Pain", "lowerRightArm"),
        ("Elbow Strain", "lowerRightArm"),
        ("Shoulder Strain", "upperRightArm"),
        ("Bicep Pain", "upperRightArm"),
        ("Tricep Pain", "upperRightArm"),
        ("Bicep Pain Right", "upperRightArm"),

        // Left Leg regions - Front
        ("Upper Left Leg Pain", "upperLeftLeg"),
        ("Left Thigh Pain", "upperLeftLeg"),
        ("Left Calf Pain", "lowerLeftLeg"),
        ("Left Ankle Pain", "lowerLeftLeg"),
        ("Calf Pain Left", "lowerLeftLeg"),
        ("Lower Left Leg Pain", "lowerLeftLeg"),
        ("Ankle Pain Left", "lowerLeftLeg"),
        ("Left Knee Pain", "upperLeftLeg"),
        ("Left Leg Cramps", "lowerLeftLeg"),
        ("Hamstring Pain Left", "upperLeftLeg"),

        // Right Leg regions - Front
        ("Upper Right Leg Pain", "upperRightLeg"),
        ("Right Thigh Pain", "upperRightLeg"),
        ("Right Calf Pain", "lowerRightLeg"),
        ("Right Ankle Pain", "lowerRightLeg"),
        ("Calf Pain Right", "lowerRightLeg"),
        ("Lower Right Leg Pain", "lowerRightLeg"),
        ("Ankle Pain Right", "lowerRightLeg"),
        ("Right Knee Pain", "upperRightLeg"),
        ("Right Leg Cramps", "lowerRightLeg"),
        ("Shin Splints", "lowerRightLeg"),
        ("Thigh Pain", "upperRightLeg"),
        ("Quadriceps Pain", "upperRightLeg"),
        ("Hamstring Pain Right", "upperRightLeg"),
        ("Calf Muscle Strain", "lowerRightLeg"),

        // General Leg symptoms
        ("Leg Pain", "upperRightLeg"),
        ("Knee Pain", "upperRightLeg"),

        // Left Arm regions - Back
        ("Left Arm Back Pain", "leftArmBack"),
        ("Upper Left Arm Back Pain", "upperLeftArmBack"),
        ("Lower Left Arm Back Pain", "lowerLeftArmBack"),
        ("Left Triceps Pain", "upperLeftArmBack"),

        // Right Arm regions - Back
        ("Right Arm Back Pain", "rightArmBack"),
        ("Upper Right Arm Back Pain", "upperRightArmBack"),
        ("Lower Right Arm Back Pain", "lowerRightArmBack"),
        ("Right Triceps Pain", "upperRightArmBack"),

        // Left Leg regions - Back
        ("Upper Left Leg Back Pain", "upperLeftLegBack"),
        ("Lower Left Leg Back Pain", "lowerLeftLegBack"),
        ("Hamstring Tension Left", "upperLeftLegBack"),

        // Right Leg regions - Back
        ("Upper Right Leg Back Pain", "upperRightLegBack"),
        ("Lower Right Leg Back Pain", "lowerRightLegBack"),
        ("Hamstring Tension Right", "upperRightLegBack"),

        // General symptoms
        ("Fatigue", "torso"),
        ("Muscle Soreness", "torso"),
        ("Joint Pain", "torso"),
        ("Muscle Strain", "torso"),

        // Common areas of strain
        ("Shoulder Blade Tension", "upperBack"),
        ("Elbow Pain", "lowerRightArm"),
        ("Wrist Pain", "lowerRightArm"),
        ("Forearm Strain", "lowerLeftArmBack"),
        ("Arm Pain", "upperRightArm"),

        // Skin conditions
        ("Skin Rash", "skin"),
        ("Insect Bite", "skin"),

        // Other
        ("Other", "torso"),
    ]

    public static let all: [SymptomDefinition] = {
        var seen = Set<String>()
        var out: [SymptomDefinition] = []
        for (name, region) in raw {
            let key = canonicalize(name)
            guard seen.insert(key).inserted else { continue }
            out.append(SymptomDefinition(displayName: name, canonicalKey: key, regionId: region))
        }
        return out.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }()

    public static func canonicalKey(for displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hit = all.first(where: { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return hit.canonicalKey
        }
        return canonicalize(trimmed)
    }

    public static func displayName(for canonicalKey: String) -> String {
        if let hit = all.first(where: { $0.canonicalKey == canonicalKey }) { return hit.displayName }
        // Fallback: split camelCase, capitalize first letter (mirrors EventDisplay.title).
        var out = ""
        for (i, ch) in canonicalKey.enumerated() {
            if i == 0 { out.append(contentsOf: ch.uppercased()) }
            else if ch.isUppercase { out.append(" "); out.append(ch) }
            else { out.append(ch) }
        }
        return out
    }

    public static func search(_ query: String) -> [SymptomDefinition] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let matches = all.filter { $0.displayName.lowercased().contains(q) }
        return matches.sorted { a, b in
            let ap = a.displayName.lowercased().hasPrefix(q), bp = b.displayName.lowercased().hasPrefix(q)
            if ap != bp { return ap }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    private static func canonicalize(_ name: String) -> String {
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard let first = words.first else { return "" }
        return ([first] + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }).joined()
    }
}
