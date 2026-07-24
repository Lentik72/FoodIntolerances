import Foundation

/// Serializes environment emit passes so the app's triggers can never overlap,
/// while guaranteeing a location-recovery signal is queued rather than dropped.
///
/// Ordinary duplicates (`.task` + scenePhase `.active` at cold launch) are ignored
/// while a pass runs. A `forced` request arriving mid-pass sets `pendingForced`,
/// which the running loop drains as exactly one trailing pass with
/// `bypassThrottles: true` — N recovery ticks collapse into that single pass.
///
/// The coalescing is asymmetric BY DESIGN: forced requests coalesce (queued and
/// drained as one trailing pass) but ordinary unforced requests arriving while a
/// pass is in flight are simply dropped. Consequence: if the app is suspended
/// mid-pass, a next-day foreground's `.active` request can be dropped, and the
/// resumed pass ingests only the reading it had already built — that day gets no
/// new today-reading until the FOLLOWING foreground. This is intentional:
/// coalescing unforced requests too would reintroduce the second overlapping pass
/// this feature removes, and the dropped-day outcome is strictly better than the
/// pre-fix behaviour, which produced a corrupt nil-valued emit for the same
/// interleaving.
///
/// The pass runs inside a coordinator-owned UNSTRUCTURED `Task`, which inherits
/// actor isolation but NOT cancellation. That is load-bearing: if the loop ran
/// inline in `emit`, it would execute in whichever trigger's task called first, and
/// SwiftUI cancelling that `.task` would leave a queued recovery pass running in a
/// cancelled context — where the emitter's `Task.isCancelled` fetch guards turn it
/// into a silent no-op. The queueing would look correct and heal nothing.
///
/// KNOWN EDGE, no limiter yet: every drain iteration after the first runs with
/// `bypassThrottles: true`, so a flapping location-trust signal (denied ↔ granted
/// in quick succession) could chain several unthrottled backfill passes back to
/// back. A hard cap on trailing passes is deliberately NOT implemented here — it
/// could drop a genuine heal and reintroduce the bug this queue exists to prevent.
/// A diagnostic log fires once a drain schedules more than its first trailing
/// forced pass, so this can be observed without limiting it.
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

            // Diagnostic only — does not gate anything. Counts trailing forced passes so a
            // second (or later) one can be logged; an ordinary single-heal drain (0 or 1
            // trailing passes) stays silent.
            var trailingPasses = 0
            while true {
                await self.perform(runForced)
                guard self.pendingForced else { break }
                self.pendingForced = false
                trailingPasses += 1
                if trailingPasses > 1 {
                    Logger.info("Environment drain scheduling trailing forced pass #\(trailingPasses) — possible location-trust flapping", category: .data)
                }
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
