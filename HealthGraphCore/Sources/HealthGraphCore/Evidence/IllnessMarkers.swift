import Foundation

/// Illness-day classification from ordinary symptom events.
///
/// The engine treats illness as an always-on confounder, but nothing ever wrote
/// an `.illness` event, so the confounder pool was permanently empty on real
/// data. Rather than add a sixth capture type, illness is derived from symptoms
/// the user can already log through the existing symptom path.
public enum IllnessMarkers {
    /// HealthKit symptom subtypes that indicate illness. HK subtypes are derived
    /// by stripping `HKCategoryTypeIdentifier` and lowercasing the first char;
    /// catalog keys come from `SymptomCatalog.canonicalize`. Those two agree for
    /// six of these and diverge for exactly two — hence `normalize`.
    public static let healthKitIdentifierSubtypes: Set<String> = [
        "coughing", "fever", "chills", "soreThroat",
        "runnyNose", "sinusCongestion", "nightSweats", "generalizedBodyAche",
    ]

    /// The only two genuine mismatches between the HK-derived subtype and the
    /// catalog key. Everything else is identity.
    private static let aliases: [String: String] = [
        "coughing": "cough",
        "sinusCongestion": "congestion",
    ]

    /// Fever alone is specific enough to call the day an illness day.
    private static let strong: Set<String> = ["fever"]

    /// Any two of these together indicate illness. Individually they are too
    /// common to justify penalising every exposure on that day.
    /// `runnyNose` is deliberately ABSENT: allergies make it near-useless as a
    /// signal, though it is still normalized and searchable.
    private static let composite: Set<String> = [
        "chills", "nightSweats", "soreThroat", "congestion", "cough", "generalizedBodyAche",
    ]

    public static func normalize(healthKitSubtype subtype: String) -> String {
        aliases[subtype] ?? subtype
    }

    /// True when the day's symptom subtypes indicate illness: fever alone, or
    /// at least two distinct composite markers. Inputs must already be
    /// normalized via `normalize(healthKitSubtype:)`.
    public static func isIllnessDay(subtypes: Set<String>) -> Bool {
        if !strong.isDisjoint(with: subtypes) { return true }
        return composite.intersection(subtypes).count >= 2
    }
}
