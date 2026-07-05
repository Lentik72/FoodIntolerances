import Foundation

/// Normalizes object names for dedup: lowercased, dose tokens stripped,
/// whitespace collapsed. "Magnesium Glycinate 400mg" -> "magnesium glycinate".
public enum NameNormalizer {
    public static func normalize(_ raw: String) -> String {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let dose = #"\b\d+([.,]\d+)?\s*(mg|mcg|µg|ug|g|kg|iu|ml|l|caps?|capsules?|tabs?|tablets?|drops?|units?)\b"#
        s = s.replacingOccurrences(of: dose, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
