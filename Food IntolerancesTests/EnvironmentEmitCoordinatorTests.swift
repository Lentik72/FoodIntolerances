import Testing
import Foundation
@testable import Food_Intolerances

/// The coordinator's whole contract, driven through an injected `perform` stub —
/// no network, no database, no UserDefaults. Everything is `@MainActor`, so the
/// interleavings below are deterministic rather than timing-dependent.
@MainActor
struct EnvironmentEmitCoordinatorTests {

    /// Records every pass: the `bypassThrottles` flag it received, and whether the
    /// task it ran in was already cancelled. Can hold one chosen call open so a test
    /// can provably land a second `emit` while a pass is in flight.
    /// Explicitly `@MainActor` (rather than relying on the enclosing type's isolation)
    /// so its mutable state is provably only touched from the coordinator's actor.
    @MainActor
    final class PassRecorder {
        struct Call: Equatable { let forced: Bool; let wasCancelled: Bool }
        private(set) var calls: [Call] = []
        private let holdCallIndex: Int?
        private var gate: CheckedContinuation<Void, Never>?
        private var startedSignal: CheckedContinuation<Void, Never>?

        /// `holdCallIndex: 0` holds the first pass open; `nil` never holds.
        init(holdCallIndex: Int?) { self.holdCallIndex = holdCallIndex }

        func perform(_ forced: Bool) async {
            calls.append(Call(forced: forced, wasCancelled: Task.isCancelled))
            guard let holdCallIndex, calls.count - 1 == holdCallIndex else { return }
            startedSignal?.resume()
            startedSignal = nil
            await withCheckedContinuation { gate = $0 }
        }

        /// Suspends until the held pass has begun (returns at once if it already has).
        func awaitHeldCallStart() async {
            guard let holdCallIndex else { return }
            if calls.count > holdCallIndex { return }
            await withCheckedContinuation { startedSignal = $0 }
        }

        func release() {
            gate?.resume()
            gate = nil
        }
    }

    private func makeCoordinator(_ recorder: PassRecorder) -> EnvironmentEmitCoordinator {
        EnvironmentEmitCoordinator { forced in await recorder.perform(forced) }
    }

    @Test func ordinaryDuplicateDoesNotStartASecondPass() async {
        let rec = PassRecorder(holdCallIndex: 0)
        let coordinator = makeCoordinator(rec)

        let drain = coordinator.emit(forced: false)
        await rec.awaitHeldCallStart()
        coordinator.emit(forced: false)      // duplicate while a pass is in flight
        rec.release()
        await drain.value

        #expect(rec.calls.count == 1)
    }

    @Test func queuedRecoveryRunsExactlyOneTrailingForcedPass() async {
        let rec = PassRecorder(holdCallIndex: 0)
        let coordinator = makeCoordinator(rec)

        let drain = coordinator.emit(forced: false)
        await rec.awaitHeldCallStart()
        coordinator.emit(forced: true)       // recovery lands mid-pass
        rec.release()
        await drain.value

        #expect(rec.calls.count == 2)
        #expect(rec.calls[1].forced == true) // the trailing pass must bypass throttles
    }

    @Test func multipleRecoveryTicksCoalesceIntoOneTrailingPass() async {
        let rec = PassRecorder(holdCallIndex: 0)
        let coordinator = makeCoordinator(rec)

        let drain = coordinator.emit(forced: false)
        await rec.awaitHeldCallStart()
        coordinator.emit(forced: true)
        coordinator.emit(forced: true)
        coordinator.emit(forced: true)
        rec.release()
        await drain.value

        #expect(rec.calls.count == 2)        // ONE trailing pass, not three
        #expect(rec.calls[1].forced == true)
    }

    /// The second P1 regression guard. `Task { }` schedules its body rather than
    /// running it, so this forced request lands after `drainTask` is stored but BEFORE
    /// the body's first turn — both `emit` calls happen in one main-actor turn with no
    /// `await` between them, which makes the interleaving deterministic rather than
    /// racy. The body must fold that flag into its first pass. A clear-then-read loop
    /// yields one UNFORCED pass here, so `calls[0].forced == true` is the discriminator.
    @Test func forcedRequestArrivingBeforeTheDrainBodyStartsIsNotLost() async {
        let rec = PassRecorder(holdCallIndex: nil)
        let coordinator = makeCoordinator(rec)

        let drain = coordinator.emit(forced: false)
        coordinator.emit(forced: true)       // same turn; the drain body has not run yet
        await drain.value

        #expect(rec.calls.count == 1)
        #expect(rec.calls[0].forced == true)
    }

    /// The P1 regression guard. The original caller awaits the drain the way a
    /// SwiftUI `.task` would; cancelling it must NOT bleed into the queued recovery.
    /// `wasCancelled == false` is the discriminating assertion: if the drain ran
    /// inline in the caller's task, the trailing pass would still *execute* but in a
    /// cancelled context, where the emitter's real fetch guards make it a no-op.
    @Test func trailingForcedPassSurvivesCallerCancellation() async {
        let rec = PassRecorder(holdCallIndex: 0)
        let coordinator = makeCoordinator(rec)

        let caller = Task { await coordinator.emit(forced: false).value }
        await rec.awaitHeldCallStart()
        coordinator.emit(forced: true)       // queue the recovery
        caller.cancel()                      // cancel the ORIGINAL caller
        rec.release()
        await caller.value                   // Task<Void, Never> — completes when the drain does

        #expect(rec.calls.count == 2)
        #expect(rec.calls[1].forced == true)
        #expect(rec.calls[1].wasCancelled == false)
    }

    @Test func coordinatorIsIdleAfterDrainAndAcceptsANewPass() async {
        let rec = PassRecorder(holdCallIndex: nil)
        let coordinator = makeCoordinator(rec)

        await coordinator.emit(forced: false).value
        await coordinator.emit(forced: false).value

        #expect(rec.calls.count == 2)        // the second emit started a fresh pass
    }

    @Test func uncontendedForcedEmitRunsOneForcedPass() async {
        let rec = PassRecorder(holdCallIndex: nil)
        let coordinator = makeCoordinator(rec)

        await coordinator.emit(forced: true).value

        #expect(rec.calls.count == 1)
        #expect(rec.calls[0].forced == true)
    }
}
