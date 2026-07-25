import Foundation

/// Bridges the DEBUG demo seed / clear / DB-reset writes (made on the Health tab,
/// OUTSIDE the keep-alive tabs) to `InsightsView`, which stays mounted and
/// otherwise only re-reads on first appear / foreground / capture. Mirrors
/// `CaptureCoordinator`.
///
/// Bump `graphMutated()` after each such committed demo/reset mutation —
/// INCLUDING when a reset/purge committed but a later insert or recompute failed,
/// because the database has already changed and the mounted Insights feed is now
/// stale. NOTE: this covers only the demo/reset debug handlers; other debug
/// writes that predate demo hygiene (forced SwiftData migration, HealthKit
/// backfill, export import, environmental emission, derived-history backfill) do
/// NOT bump this yet — route them through here if that staleness ever matters.
@MainActor
final class GraphMutationCoordinator: ObservableObject {
    @Published private(set) var revision: Int = 0
    func graphMutated() { revision &+= 1 }   // &+ wraps; monotonic trigger, value itself is unused
}
