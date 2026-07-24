import Foundation

/// Serializes environment emit passes so the app's triggers can never overlap,
/// while guaranteeing a location-recovery signal is queued rather than dropped.
///
/// Ordinary duplicates (`.task` + scenePhase `.active` at cold launch) are ignored
/// while a pass runs. A `forced` request arriving mid-pass sets `pendingForced`,
/// which the running loop drains as exactly one trailing pass with
/// `bypassThrottles: true` — N recovery ticks collapse into that single pass.
///
/// The pass runs inside a coordinator-owned UNSTRUCTURED `Task`, which inherits
/// actor isolation but NOT cancellation. That is load-bearing: if the loop ran
/// inline in `emit`, it would execute in whichever trigger's task called first, and
/// SwiftUI cancelling that `.task` would leave a queued recovery pass running in a
/// cancelled context — where the emitter's `Task.isCancelled` fetch guards turn it
/// into a silent no-op. The queueing would look correct and heal nothing.
@MainActor
final class EnvironmentEmitCoordinator {
    /// Runs one environment pass. The `Bool` is `bypassThrottles`.
    private let perform: (Bool) async -> Void
    private var drainTask: Task<Void, Never>?
    private var pendingForced = false

    init(perform: @escaping (Bool) async -> Void) {
        self.perform = perform
    }

    /// Signals that a pass should run. Returns the coordinator-owned drain task —
    /// newly started, or the one already running — so a caller (or a test) may await
    /// it. The app's triggers ignore the result.
    @discardableResult
    func emit(forced: Bool) -> Task<Void, Never> {
        // Set BEFORE the early return, so a recovery request is recorded even when
        // this call doesn't start a pass. This is what preserves the self-heal.
        if forced { pendingForced = true }
        if let drainTask { return drainTask }   // a drain is active; it will pick the flag up

        let initialForced = forced
        let task = Task { [weak self] in
            guard let self else { return }
            // CONSUME the flag rather than clearing it. `Task { }` SCHEDULES this body
            // rather than running it, so a forced request can land after `drainTask` is
            // stored but before this first turn — in the same main-actor turn as the
            // initial `emit`. Clearing at the top of the loop would wipe it and run one
            // UNFORCED pass: the recovery silently downgraded, not merely delayed.
            var runForced = initialForced || self.pendingForced
            self.pendingForced = false

            while true {
                await self.perform(runForced)
                guard self.pendingForced else { break }
                self.pendingForced = false
                runForced = true                // any queued follow-up is a recovery pass
            }
            // No `await` between the guard above and here, so on the main actor a
            // trigger cannot slip in after the loop decides to exit but before the
            // handle clears — that gap is where a naive implementation drops a heal.
            self.drainTask = nil
        }
        // Assigned synchronously, before the task body's first turn can run, so an
        // `emit` can never observe a started-but-unrecorded drain.
        drainTask = task
        return task
    }
}
