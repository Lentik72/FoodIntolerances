import Foundation

/// Deterministic, template-based user-facing text. NO causal language (spec §7).
public enum InsightPhrasing {
    public static func claim(_ rr: ResolvedRelationship) -> String {
        switch rr.relationship.type {
        case .improves: return "\(rr.exposureLabel) → fewer \(rr.outcomeLabel)"
        case .noEffect: return "No measurable effect of \(rr.exposureLabel) on \(rr.outcomeLabel)"
        default:        return "\(rr.exposureLabel) → \(rr.outcomeLabel)"
        }
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
        if let s = r.strength { parts.append(String(format: "avg severity +%.1f", s)) }
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
        default: return nil
        }
    }
}
