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

    public static func daily(_ category: EventCategory, _ subtype: String?, dayStart: Date) -> String {
        "\(category.rawValue)|\(subtype ?? "")|day|\(minute(dayStart))"
    }
}
