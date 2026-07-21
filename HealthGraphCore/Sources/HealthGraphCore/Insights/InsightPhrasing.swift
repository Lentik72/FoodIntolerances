import Foundation

/// Deterministic, template-based user-facing text. NO causal language (spec §7).
public enum InsightPhrasing {
    public static func claim(_ rr: ResolvedRelationship) -> String {
        if rr.relationship.toCategory == "mood" { return moodClaim(rr) }
        switch rr.relationship.type {
        case .improves: return "\(rr.exposureLabel) → fewer \(rr.outcomeLabel)"
        case .noEffect: return "No measurable effect of \(rr.exposureLabel) on \(rr.outcomeLabel)"
        default:        return "\(rr.exposureLabel) → \(rr.outcomeLabel)"
        }
    }

    /// Warm, tentative, directional — never causal. `.improves` reduces the outcome;
    /// everything else (possibleTrigger/worsens/precedes) increases it.
    private static func moodClaim(_ rr: ResolvedRelationship) -> String {
        let x = rr.exposureLabel
        let isGood = (rr.relationship.toSubtype == "good")
        switch rr.relationship.type {
        case .noEffect: return "No clear link between \(x) and your mood"
        case .improves: return isGood ? "\(x) seems to weigh on your mood"
                                      : "\(x) seems to protect against low moods"
        default:        return isGood ? "\(x) seems to lift your mood"
                                      : "\(x) is linked to lower mood"
        }
    }

    /// The outcome noun for supporting lines (countLine). Mood reads naturally
    /// ("a good mood"); other outcomes keep their subtype.
    public static func outcomeLabel(for r: Relationship) -> String {
        guard r.toCategory == "mood" else { return r.toSubtype ?? "outcome" }
        return r.toSubtype == "good" ? "a good mood" : "a low mood"
    }

    public static func badge(confidence: Double, config: InsightsConfig = .default) -> BadgeTier {
        if confidence > config.strongMin { return .strong }
        if confidence >= config.earlyMax { return .moderate }
        return .earlySignal
    }

    /// Lag + severity — for triggers only; nil for improves / noEffect (protective/even-tone).
    public static func subline(_ rr: ResolvedRelationship) -> String? {
        guard rr.relationship.type == .possibleTrigger else { return nil }
        let r = rr.relationship
        var parts: [String] = []
        if let lag = r.lagHours { parts.append("usually within ~\(Int(lag.rounded()))h") }
        if r.toCategory != "mood", let s = r.strength { parts.append(String(format: "avg severity +%.1f", s)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "In K of your last N <exposure> logs, <outcome> followed" from the recent window;
    /// nil when there's no window (noEffect/archive) or it's empty.
    public static func countLine(_ rr: ResolvedRelationship) -> String? {
        let recent = rr.recentOutcomes
        guard !recent.isEmpty, rr.relationship.type != .noEffect else { return nil }
        let k = recent.filter { $0 }.count
        return "In \(k) of your last \(recent.count) \(rr.exposureLabel) logs, \(rr.outcomeLabel) followed"
    }

    /// Human phrase for a derived-exposure `fromCategory` token; nil for object edges
    /// (those resolve via the object's name).
    public static func derivedExposureLabel(fromCategory: String) -> String? {
        switch fromCategory {
        case "shortSleep": return "Short sleep"
        case "highStress": return "High stress"
        case "pressureDrop": return "Pressure drops"
        case "cyclePhase.menstrual": return "Menstrual phase"
        case "cyclePhase.luteal": return "Luteal phase"
        case "fullMoon": return "Full moon"
        case "mercuryRetrograde": return "Mercury retrograde"
        case "hotDay": return "Hot days"
        case "coldDay": return "Cold days"
        case "humidDay": return "Humid days"
        case "swingDay": return "Big temperature swings"
        case "poorAirDay": return "Poor air quality"
        default: return nil
        }
    }
}
