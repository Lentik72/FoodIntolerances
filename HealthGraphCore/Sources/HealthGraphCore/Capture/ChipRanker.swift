import Foundation

/// Ranks recent items for one-tap quick-log chips.
public enum ChipRanker {
    /// Ranks the distinct (category, subtype) pairs in `history` for quick-log chips.
    /// Score = frequency (log-damped) × recency (exponential, ~14-day half-life)
    ///       × time-of-day affinity (share of this item's logs within ±2h of `now`'s hour).
    /// Returns the top `limit`, highest first. `history` is any recent event slice.
    ///
    /// `seeds` fill ONLY the slots left over after history-ranked items and never
    /// displace them. They are appended after the sort — injecting them into the
    /// scored set with a synthetic score would make ties nondeterministic, since
    /// the intermediate dictionary order is not stable. No expiry: as real
    /// history accumulates it outranks and pushes seeds out naturally.
    public static func rank(history: [HealthEvent], category: EventCategory, now: Date,
                            timeZone: TimeZone, limit: Int, seeds: [String] = []) -> [String] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let nowHour = cal.component(.hour, from: now)
        let relevant = history.filter { $0.category == category && $0.deletedAt == nil && $0.subtype != nil }
        var byKey: [String: [HealthEvent]] = [:]
        for e in relevant { byKey[e.subtype!, default: []].append(e) }
        func hourDistance(_ h: Int) -> Int { let d = abs(h - nowHour); return min(d, 24 - d) }
        let scored: [(String, Double, Date)] = byKey.map { key, events in
            let count = events.count
            let mostRecent = events.map(\.timestamp).max() ?? now
            let ageDays = max(0, now.timeIntervalSince(mostRecent) / 86_400)
            let frequency = log2(1 + Double(count))
            let recency = exp(-ageDays / 14)
            let near = events.filter { hourDistance(cal.component(.hour, from: $0.timestamp)) <= 2 }.count
            let tod = 0.5 + 0.5 * (Double(near) / Double(count))
            return (key, frequency * recency * tod, mostRecent)
        }
        let ranked = scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }
            .prefix(limit).map(\.0)
        guard ranked.count < limit, !seeds.isEmpty else { return ranked }
        var out = ranked
        // `existing` must grow as seeds are appended: `seeds` is a public
        // parameter, so an internally-duplicated array (e.g. ["bloating",
        // "bloating"]) would otherwise yield a duplicate chip — dedup can't
        // depend on every caller having run SymptomSeeds.validate first.
        var existing = Set(ranked)
        for seed in seeds where existing.insert(seed).inserted {
            out.append(seed)
            if out.count == limit { break }
        }
        return out
    }
}
