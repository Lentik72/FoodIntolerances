import Foundation

/// Pure, deterministic, severity-independent. Returns a match iff `symptomKey`
/// is a red flag AND not in `mutedKeys`. No Date(), no I/O, no severity input.
public enum RedFlagEvaluator {
    public static func evaluate(symptomKey: String, mutedKeys: Set<String>) -> RedFlagMatch? {
        guard !mutedKeys.contains(symptomKey),
              let rule = RedFlagCatalog.rule(forSymptomKey: symptomKey) else { return nil }
        return RedFlagMatch(symptomKey: symptomKey, category: rule.category, extraGuidance: rule.extraGuidance)
    }
}
