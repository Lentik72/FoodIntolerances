import Foundation

/// Bridges a Health-Graph write made OUTSIDE the keep-alive tabs (e.g. the DEBUG
/// demo seed/clear on the Health tab) to `InsightsView`, which stays mounted and
/// otherwise only re-reads on first appear / foreground / capture. Mirrors
/// `CaptureCoordinator`.
///
/// Bump `graphMutated()` after ANY committed graph mutation — INCLUDING when a
/// reset/purge committed but a later insert or recompute failed, because the
/// database has already changed and the mounted Insights feed is now stale.
@MainActor
final class GraphMutationCoordinator: ObservableObject {
    @Published private(set) var revision: Int = 0
    func graphMutated() { revision &+= 1 }   // &+ wraps; monotonic trigger, value itself is unused
}
