import SwiftUI

private struct EmitCoordinatorKey: EnvironmentKey {
    /// Optional: only the app root injects a coordinator. A preview or any detached
    /// hierarchy sees nil, and callers must handle that rather than silently emitting
    /// outside the single-flight invariant.
    static let defaultValue: EnvironmentEmitCoordinator? = nil
}

extension EnvironmentValues {
    /// The app's single-flight environment-emit coordinator.
    var emitCoordinator: EnvironmentEmitCoordinator? {
        get { self[EmitCoordinatorKey.self] }
        set { self[EmitCoordinatorKey.self] = newValue }
    }
}
