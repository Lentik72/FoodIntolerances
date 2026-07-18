import Foundation

/// The category of a red flag — determines the guidance surfaced.
public enum RedFlagCategory: Sendable, Equatable {
    case medicalEmergency
    case mentalHealthCrisis
}

public struct RedFlagRule: Sendable, Equatable {
    public let symptomKeys: [String]      // SymptomCatalog canonicalKeys
    public let category: RedFlagCategory
    public let extraGuidance: String?     // e.g. anaphylaxis epinephrine line; nil otherwise
    public init(symptomKeys: [String], category: RedFlagCategory, extraGuidance: String?) {
        self.symptomKeys = symptomKeys
        self.category = category
        self.extraGuidance = extraGuidance
    }
}

public struct RedFlagMatch: Sendable, Equatable, Identifiable {
    public let symptomKey: String
    public let category: RedFlagCategory
    public let extraGuidance: String?
    public var id: String { symptomKey }
    public init(symptomKey: String, category: RedFlagCategory, extraGuidance: String?) {
        self.symptomKey = symptomKey
        self.category = category
        self.extraGuidance = extraGuidance
    }
}

/// The static red-flag table. Keys are DERIVED from SymptomCatalog display names
/// (single source of truth) so a rename can't silently drift a rule out of sync —
/// RedFlagCatalogTests.everyRuleKeyResolvesToARealSymptom guards that.
public enum RedFlagCatalog {
    private static func key(_ displayName: String) -> String {
        SymptomCatalog.canonicalKey(for: displayName)
    }

    public static let rules: [RedFlagRule] = [
        RedFlagRule(
            symptomKeys: ["Chest Pain", "Lower Chest Pain", "Chest Tightness",
                          "Upper Chest Tightness", "Breathing Difficulty", "Shortness of Breath"].map(key),
            category: .medicalEmergency,
            extraGuidance: nil),
        RedFlagRule(
            symptomKeys: [key("Severe Allergic Reaction")],
            category: .medicalEmergency,
            extraGuidance: "If you have an epinephrine auto-injector (EpiPen), use it now, then call 911."),
        RedFlagRule(
            symptomKeys: [key("Thoughts of self-harm or suicide")],
            category: .mentalHealthCrisis,
            extraGuidance: nil),
    ]

    public static func rule(forSymptomKey symptomKey: String) -> RedFlagRule? {
        rules.first { $0.symptomKeys.contains(symptomKey) }
    }

    /// Every red-flag symptom key, across all rules — used by the Settings list.
    public static var allSymptomKeys: [String] { rules.flatMap(\.symptomKeys) }

    /// Red-flag keys that MAY be muted in Settings — excludes `.mentalHealthCrisis`.
    /// A crisis prompt is never suppressible (design §6); it must not appear as a toggle.
    public static var mutableSymptomKeys: [String] {
        rules.filter { $0.category != .mentalHealthCrisis }.flatMap(\.symptomKeys)
    }
}
