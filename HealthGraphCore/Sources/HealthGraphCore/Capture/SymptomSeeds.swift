import Foundation

/// Validation for the first-run "what brings you here?" seed list.
///
/// Runs on BOTH write and read: the stored list outlives catalog changes and
/// future RedFlagCatalog additions, so a key that was fine when saved can
/// become invalid later.
public enum SymptomSeeds {
    /// Keeps only keys that resolve to a current catalog entry, drops every
    /// red-flag key, dedupes preserving selection order, and applies `limit`.
    ///
    /// Membership is checked against `SymptomCatalog.all` — NOT via
    /// `canonicalKey(for:)`, which is total and happily derives a key for
    /// arbitrary garbage, so it would accept anything.
    ///
    /// The red-flag exclusion is a safety requirement, not tidiness: capture
    /// calls the red-flag evaluator after every write, so a seeded "Chest Pain"
    /// chip is a one-tap path to a full-screen emergency takeover on the first
    /// screen a new user sees.
    public static func validate(_ keys: [String], limit: Int) -> [String] {
        let known = Set(SymptomCatalog.all.map(\.canonicalKey))
        let redFlags = Set(RedFlagCatalog.allSymptomKeys)
        var seen = Set<String>()
        var out: [String] = []
        for key in keys {
            guard known.contains(key), !redFlags.contains(key), seen.insert(key).inserted else { continue }
            out.append(key)
            if out.count == limit { break }
        }
        return out
    }
}
