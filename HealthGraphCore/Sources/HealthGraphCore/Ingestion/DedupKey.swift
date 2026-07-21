import Foundation

/// Stable cross-source dedup keys (spec §5.5): timestamps rounded to the
/// minute. NEVER change these formats — they are persisted in the DB and
/// re-imports must keep matching historical rows.
public enum DedupKey {
    static func minute(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }

    public static func point(_ category: EventCategory, _ subtype: String?, _ timestamp: Date) -> String {
        "\(category.rawValue)|\(subtype ?? "")|\(minute(timestamp))"
    }

    public static func duration(_ category: EventCategory, _ subtype: String?,
                                start: Date, end: Date) -> String {
        "\(category.rawValue)|\(subtype ?? "")|\(minute(start))|\(minute(end))"
    }

    /// Daily key, optionally scoped by temporal provenance. A `.forecast` and an
    /// `.observedCompletedDay` reading for the same day+subtype get DISTINCT keys,
    /// so they never overwrite one another. Omitting `provenance` (nil) reproduces
    /// the pre-provenance format exactly, keeping legacy rows matchable.
    public static func daily(_ category: EventCategory, _ subtype: String?, dayStart: Date,
                             provenance: TemporalProvenance? = nil) -> String {
        let p = provenance.map { "|\($0.rawValue)" } ?? ""
        return "\(category.rawValue)|\(subtype ?? "")\(p)|day|\(minute(dayStart))"
    }
}
