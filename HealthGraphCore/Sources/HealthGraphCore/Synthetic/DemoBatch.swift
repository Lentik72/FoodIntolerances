import Foundation

/// The single source of truth for demo/seed-data identity. Not `#if DEBUG`:
/// the marker column and the Release purge are always-compiled; only the seed
/// UI that produces demo rows is DEBUG.
///
/// Every demo row is marked with a batch id (`syntheticBatch`) and has its
/// dedup key and object identity namespaced with `prefix(batch)`, so a demo row
/// can never collide with — or overwrite — a real row.
public enum DemoBatch {
    public static let synthetic = "synthetic"
    public static let mood = "mood"
    public static let outsideFactors = "outsideFactors"
    public static let weather = "weather"

    /// The namespace applied to a demo row's dedup key and normalized name.
    public static func prefix(_ batch: String) -> String { "demo:\(batch)|" }

    /// A batch-scoped dedup key: the real key with the demo namespace in front.
    public static func dedupKey(_ base: String, batch: String) -> String {
        prefix(batch) + base
    }

    /// A batch-scoped normalized name. Normalizes the display name the SAME way
    /// `HealthObject` does, then prefixes — so the lookup key and the persisted
    /// key are computed identically and cannot diverge.
    public static func normalizedName(_ displayName: String, batch: String) -> String {
        prefix(batch) + NameNormalizer.normalize(displayName)
    }

    /// Marks events as belonging to `batch` and namespaces any dedup key they
    /// already carry. Events without a dedup key keep `nil` (nothing to collide).
    public static func stamp(_ events: [HealthEvent], batch: String) -> [HealthEvent] {
        events.map { event in
            var e = event
            e.syntheticBatch = batch
            if let key = e.dedupKey { e.dedupKey = dedupKey(key, batch: batch) }
            return e
        }
    }
}
