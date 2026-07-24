# Double-Emit Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make at most one environment emit pass run at a time, with a coalesced trailing forced pass so a location-recovery signal arriving mid-pass is never lost.

**Architecture:** A small `@MainActor final class EnvironmentEmitCoordinator` sits between the app's three triggers and `EnvironmentalEventEmitter.emitIfNeeded`. It **owns** the pass as an unstructured `Task<Void, Never>` (inherits actor isolation, *not* cancellation), so the drain outlives whichever trigger started it. Ordinary duplicates are ignored while a pass runs; a forced (recovery) request arriving mid-pass sets a pending flag that the running loop drains as exactly one trailing pass with `bypassThrottles: true`. The coordinator takes an injectable `perform` closure, so its entire behaviour is unit-tested with no network, database, or `UserDefaults`.

**Tech Stack:** Swift, SwiftUI, Swift Concurrency (unstructured `Task`, `CheckedContinuation`), Swift Testing (`import Testing`, `@Test`, `#expect`).

## Global Constraints

- **No `HealthGraphCore` changes.** Files touched are in the app target (`Food Intolerances`) or its test target (`Food IntolerancesTests`).
- **No changes to `EnvironmentalEventEmitter.emitIfNeeded` or anything it calls** — watermarks, throttles, grace, contiguity, classification, scope recording, the trusted-coordinate seam, the pressure carry, the resolver, and both UI surfaces are all unchanged. This round only controls *how many* passes run and *when*.
- **Test command** (swap the suite per step):
  `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/<Suite>" -parallel-testing-enabled NO`
- `iPhone 17 Pro` is the only runnable simulator on this toolchain. `-parallel-testing-enabled NO` is mandatory. A lone `** TEST FAILED **` originating only from `SwiftDataMigratorTests` teardown is a known pre-existing crash — treat a run as green when your suite's `#expect`s pass.
- **`emit(forced:)` is synchronous and returns a non-optional `Task<Void, Never>`** (every path yields a task), marked `@discardableResult`. The stored `drainTask` stays optional — `nil` genuinely means idle.
- The coordinator is held as plain **`@State`**, not `@StateObject`. Do **not** add `ObservableObject` conformance purely for ownership — it has no observable state the UI reads.
- The three trigger sites keep their existing structure and gating (especially the recovery trigger's live-location-failure gate, which is what bounds the trailing-pass loop). They only change *what they call*.
- New app-target and test-target files are picked up automatically (`PBXFileSystemSynchronizedRootGroup`) — no `.pbxproj` edit. After an `xcodebuild` run the tree may show a cosmetic `.pbxproj` re-sort and an `xcuserstate` change; **never stage or commit either**.
- Editor SourceKit errors ("No such module 'Testing'", "Cannot find type … in scope") on freshly added files are index-lag artifacts; the `xcodebuild` result is authoritative.

---

## File Structure

**New**
- `Models/EnvironmentEmitCoordinator.swift` — the coordinator. One responsibility: decide whether a pass starts now, is ignored, or is queued as a trailing forced pass; own the task that runs them.
- `Food IntolerancesTests/EnvironmentEmitCoordinatorTests.swift` — the suite plus its `PassRecorder` stub.

**Modified**
- `FoodIntolerancesApp.swift` — construct the coordinator in `init()`; the three triggers call `emitCoordinator.emit(forced:)`.

Task 1 delivers the coordinator with its full test suite (independently testable — it never touches the emitter). Task 2 wires it in, verified by a build and the existing suites.

---

### Task 1: `EnvironmentEmitCoordinator`

**Files:**
- Create: `Models/EnvironmentEmitCoordinator.swift`
- Test: `Food IntolerancesTests/EnvironmentEmitCoordinatorTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks (the coordinator is dependency-free — it takes a `perform` closure).
- Produces: `@MainActor final class EnvironmentEmitCoordinator`, `init(perform: @escaping (Bool) async -> Void)`, and `@discardableResult func emit(forced: Bool) -> Task<Void, Never>`. Task 2 constructs it and calls `emit(forced:)`.

- [ ] **Step 1: Write the failing tests**

Create `Food IntolerancesTests/EnvironmentEmitCoordinatorTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/EnvironmentEmitCoordinatorTests" -parallel-testing-enabled NO`
Expected: FAIL — `EnvironmentEmitCoordinator` is undefined (compile error: "Cannot find 'EnvironmentEmitCoordinator' in scope").

- [ ] **Step 3: Write minimal implementation**

Create `Models/EnvironmentEmitCoordinator.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/EnvironmentEmitCoordinatorTests" -parallel-testing-enabled NO`
Expected: PASS (7 tests).

- [ ] **Step 5: (Optional) Prove the cancellation test is discriminating**

The P1 this design exists to prevent is invisible to a test that only asserts the trailing pass "ran", so it is worth confirming `trailingForcedPassSurvivesCallerCancellation` actually fails against the pre-fix shape. Unlike a one-line mutation, this requires temporarily reproducing the old structure, so it is **optional** — skip it if the churn isn't worth it; the task reviewer verifies the structural property (an unstructured `Task { }` owned by the coordinator, not an inline loop) by inspection either way.

If you do it, the temporary mutation is: make `emit(forced:)` `async` and return nothing, delete the `Task { [weak self] in … }` wrapper so the `while` loop runs inline in `emit` (using `self` directly, and clearing `drainTask` — now unused — accordingly), and update all `emit` invocations across the seven tests from `coordinator.emit(…)` / `.value` to `await coordinator.emit(…)` (several tests call `emit` more than once, so this is more edits than tests). Re-run `trailingForcedPassSurvivesCallerCancellation` and confirm it **fails on `wasCancelled == false`** (the pass still executes — it just executes cancelled, which is exactly the silent no-op the real emitter would produce). Then **revert every one of those edits**, confirm `git diff` is empty against the implementation from Step 3, and re-run the suite to a clean 7/7.

Report whether you ran this and what you observed.

- [ ] **Step 6: Commit**

```bash
git add "Models/EnvironmentEmitCoordinator.swift" "Food IntolerancesTests/EnvironmentEmitCoordinatorTests.swift"
git commit -m "feat(env-emit): single-flight coordinator with coalesced trailing forced pass"
```

---

### Task 2: Wire the three triggers through the coordinator

**Files:**
- Modify: `FoodIntolerancesApp.swift` — declaration (near `:12-23`), `init()` (`:25-50`), and the three triggers (`:129-145`).

**Interfaces:**
- Consumes: Task 1's `EnvironmentEmitCoordinator(perform:)` and `@discardableResult func emit(forced: Bool) -> Task<Void, Never>`.
- Produces: nothing further — this is the terminal wiring.

- [ ] **Step 1: Hold the coordinator and build it in `init()`**

Add the property alongside the existing ones (it is `@State`, **not** `@StateObject` — no `ObservableObject` conformance exists or should be added):

```swift
    @State private var emitCoordinator: EnvironmentEmitCoordinator
```

In `init()`, the service is currently constructed inline inside `StateObject(wrappedValue:)`. Hoist it to a local so the coordinator's closure can capture it, then build the coordinator from the same two instances. Replace:

```swift
        let statusStore = EnvironmentStatusStore()
        _environmentStatusStore = StateObject(wrappedValue: statusStore)
        _environmentalService = StateObject(wrappedValue:
            EnvironmentalDataService(locationManager: LocationService(), statusStore: statusStore))
```

with:

```swift
        let statusStore = EnvironmentStatusStore()
        _environmentStatusStore = StateObject(wrappedValue: statusStore)
        let service = EnvironmentalDataService(locationManager: LocationService(), statusStore: statusStore)
        _environmentalService = StateObject(wrappedValue: service)
        // Captures the SAME service + store the triggers and emitter use. Neither of
        // them holds the coordinator, so there is no retain cycle.
        _emitCoordinator = State(wrappedValue: EnvironmentEmitCoordinator { forced in
            await EnvironmentalEventEmitter.emitIfNeeded(
                service: service, statusStore: statusStore, bypassThrottles: forced)
        })
```

- [ ] **Step 2: Route the three triggers through the coordinator**

Replace the trigger block (currently `:130-145`) with the following. Note the `Task { }` wrappers disappear — `emit` is synchronous and hands back the coordinator-owned task, and the `.task` closure returning immediately is the *intended* consequence (SwiftUI cancelling it then has nothing to cancel). The recovery trigger's live-location-failure gate is unchanged:

```swift
                .task { emitCoordinator.emit(forced: false) }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    emitCoordinator.emit(forced: false)
                }
                .onChange(of: environmentalService.locationRecoveryTick) { _, _ in
                    // A trusted coordinate (re)appeared. Only force a bypass emit when a
                    // live location failure actually exists — this bounds the throttle/
                    // cooldown bypass to real recovery and prevents a fetch storm on every
                    // routine device fix.
                    let hasLiveLocationFailure = environmentStatusStore.statuses.values.contains {
                        $0.liveFailure?.reason == .locationDenied || $0.liveFailure?.reason == .locationUnavailable
                    }
                    guard hasLiveLocationFailure else { return }
                    emitCoordinator.emit(forced: true)
                }
```

Leave `.task { healthKitIngestor.startObserving() }` (`:129`) untouched.

If the compiler objects to calling the `@MainActor` `emit` from an `.onChange` closure (isolation inference varies by SwiftUI version), wrap only that call as `Task { @MainActor in emitCoordinator.emit(forced: …) }` — harmless, because `emit` returns immediately and the drain is coordinator-owned either way. Prefer the direct call if it compiles.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the environment suites to confirm no regression**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/EnvironmentEmitCoordinatorTests" -only-testing:"Food IntolerancesTests/EnvironmentalEmitterTests" -only-testing:"Food IntolerancesTests/EnvironmentFailureClassificationTests" -parallel-testing-enabled NO`
Expected: PASS. (The emitter itself is unchanged; these confirm the wiring didn't disturb it.)

- [ ] **Step 5: Commit**

```bash
git add "FoodIntolerancesApp.swift"
git commit -m "feat(env-emit): route the three environment triggers through the single-flight coordinator"
```

---

## Device Verification (after Task 2)

- **Cold launch, location permitted but a cold fix:** the Health → Environment screen must **not** flash a false "Unavailable" for Observed history (weather or air quality), and those rows' `Updated` time should reflect a real pass rather than being locked out for an hour.
- **Cold launch with Location denied, then granted:** still heals in one pass — the behaviour verified in the previous round must not regress. This is precisely the path the queued trailing pass protects.

## Self-Review Notes (author)

- **Spec coverage:** §3A coordinator → Task 1; §3B wiring → Task 2; all eight §5 tests → Task 1 Step 1 as seven `@Test`s (the "queued recovery" and "force-flag preservation" bullets are the same scenario, so they are one test asserting both the count and the flag); §5 device pass → Device Verification.
- **Step 5 of Task 1 is optional and explicitly revert-after.** It is marked optional because, unlike a one-line mutation, reproducing the pre-fix shape means changing `emit`'s signature and every `emit` invocation across the seven tests. The structural property it would prove (unstructured coordinator-owned task, not an inline loop) is checkable by inspection, so the task reviewer is the backstop if it's skipped.
- The `PassRecorder` relies on `@MainActor` serialization for determinism: `perform` installs its gate continuation in the same synchronous block that resumes `startedSignal`, so by the time the test resumes, `release()` has something to resume.
