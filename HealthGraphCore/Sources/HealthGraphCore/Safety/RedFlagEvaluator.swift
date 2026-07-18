import Foundation

/// Pure, deterministic, severity-independent. Returns a match iff `symptomKey` is a red
/// flag AND (not in `mutedKeys` OR its category is `.mentalHealthCrisis`) — a crisis prompt
/// is never suppressible. No Date(), no I/O, no severity input.
public enum RedFlagEvaluator {
    public static func evaluate(symptomKey: String, mutedKeys: Set<String>) -> RedFlagMatch? {
        guard let rule = RedFlagCatalog.rule(forSymptomKey: symptomKey) else { return nil }
        // A mental-health crisis prompt is NEVER suppressible: even if its key somehow ended up
        // muted, still surface it. Muting applies only to other (e.g. medical) categories.
        if rule.category != .mentalHealthCrisis, mutedKeys.contains(symptomKey) { return nil }
        return RedFlagMatch(symptomKey: symptomKey, category: rule.category, extraGuidance: rule.extraGuidance)
    }
}
