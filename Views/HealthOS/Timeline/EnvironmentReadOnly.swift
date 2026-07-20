import HealthGraphCore

extension HealthEvent {
    /// Auto-logged environment readings are immutable in the UI: no edit, no
    /// delete, anywhere they surface. Single source of truth for the swipe and
    /// the detail-sheet Delete gating.
    var isReadOnlyEnvironment: Bool { category == .environment }
}
