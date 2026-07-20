import Foundation

/// How plausible a *causal* link from this exposure is — the honesty layer over
/// the evidence gates. Established = known mechanism; contested = plausible but
/// weak/mixed evidence; novelty = no known mechanism (a curious coincidence).
public enum PlausibilityTier: Sendable, Equatable { case established, contested, novelty }

public enum PlausibilityCatalog {
    /// Keyed on the resolved `fromCategory` token (object categories like "food",
    /// or derived tokens like "fullMoon"). Everything not listed is established.
    public static func tier(forExposureCategory category: String?) -> PlausibilityTier {
        switch category {
        case "fullMoon":          return .contested
        case "mercuryRetrograde": return .novelty
        case "hotDay", "coldDay", "humidDay": return .contested
        default:                  return .established
        }
    }
}
