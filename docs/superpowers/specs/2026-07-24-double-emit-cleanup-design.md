# Double-Emit Cleanup (Single-Flight the Environment Pass) — Design

**Date:** 2026-07-24
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Make at most one environment emit pass run at a time, with a coalesced trailing pass so a location-recovery signal arriving mid-pass is never lost. Introduces one small `@MainActor` coordinator between the app's three triggers and `EnvironmentalEventEmitter.emitIfNeeded`.

Follow-up #2 of the queue after the weather-unavailable-UI round ("harden before expanding").

**Not touched:** `HealthGraphCore`. The emitter's watermark/throttle/grace/contiguity logic, the fetch classification, the trusted-coordinate seam, the pressure carry, the resolver, and both UI surfaces are unchanged — this round only controls *how many* passes run and *when*. The three trigger sites keep firing exactly as they do today.

---

## 1. Problem

`FoodIntolerancesApp` fires `EnvironmentalEventEmitter.emitIfNeeded` from three places:

| Trigger | Line | `bypassThrottles` |
|---|---|---|
| `.task` (view appears) | `:130` | `false` |
| `.onChange(of: scenePhase)` → `.active` | `:131-133` | `false` |
| `.onChange(of: environmentalService.locationRecoveryTick)` | `:135-144` | `true` |

Nothing prevents them overlapping. At a cold launch the first two **can** both fire — this is *inferred*, not measured: it is SwiftUI's standard behaviour (`.task` on appearance plus an `.inactive → .active` transition) and it matches the symptom this round was queued for, but it has not been directly observed on this app. The design does not depend on it: single-flighting is required regardless, because the recovery trigger can overlap a foreground pass on its own.

1. `.task` fires pass **A**. It wins the refresh cooldown and starts a network fetch.
2. scenePhase becomes `.active` → pass **B** fires. `requestRefreshWithCooldown` sees `lastRefreshRequest` already claimed and returns `false` **immediately — B does not await A's fetch** (`EnvironmentalDataService.swift`, the `if !bypassCooldown, currentTime.timeIntervalSince(lastRefreshRequest) < minimumRefreshInterval { return false }` early return).
3. B proceeds anyway, reading `latestFetchedPressure` / `forecastHighC` / … which A has not populated yet — so B emits a today reading with nil weather values.
4. B runs both backfills against a location that is usually still cold at launch. Its retry guards pass (the previous session's attempt is older than the interval, or unset), so each backfill **stamps its attempt watermark** and then fails on the cold location, recording `locationUnavailable` for `observedWeather` and `observedAirQuality` (`EnvironmentalEventEmitter.swift:139-140` and `:212-213` — the guard, then the unconditional `store.set(now(), for: attemptKey)` immediately after it).
5. A's fetch completes and it emits the real today reading — but A's backfills now hit the watermarks B just stamped and **return early, locked out for an hour**.

Three consequences, in descending severity:

- **A false "Unavailable" is recorded and shown.** Before the weather-unavailable round this was invisible; now B's spurious `locationUnavailable` surfaces on the Health screen and can mark Timeline days. It is a lie about fetch health caused purely by our own trigger race.
- **The observed backfills are locked out for an hour** after a launch in which they never actually succeeded.
- **Duplicated work** — two today-ingests, two backfill passes attempted.

The harm is conditional on the location being cold when the app launches, which is the normal cold-launch case.

**Why a naive single-flight is not enough (the ordering hazard).** If a second trigger is simply dropped while a pass runs, this sequence loses the self-heal added last round:

1. Pass A starts with a cold location.
2. Location resolves mid-pass → `locationRecoveryTick` fires → **dropped**.
3. A finishes and records `locationUnavailable` — *after* the only signal that would have healed it is gone.

The marker then persists until some unrelated foreground. The recovery trigger must therefore be **queued**, not discarded.

## 2. Decisions (Leo, 2026-07-24)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Mechanism | **Single-flight with one coalesced trailing pass.** Rejected: removing a redundant trigger (leans on SwiftUI reliably delivering `.active` at every cold launch — if it ever doesn't, the app silently stops emitting at startup, exactly the silent-failure class this feature exists to prevent, and it leaves the recovery trigger able to overlap a foreground one). Rejected: making the cooldown loser await the winner (fixes the stale-values half but not the backfill lockout — B still stamps both watermarks). |
| 2 | Ordinary duplicates | **Ignored** while a pass runs (`.task` + `.active` at cold launch produce exactly one pass). `emit` still *returns* the coordinator-owned drain task, so a caller that wants to join can — the triggers don't, tests do. |
| 3 | Recovery mid-pass | **Queued as a pending forced refresh**, never dropped — this is what preserves the self-heal against the ordering hazard above. |
| 4 | Coalescing | Multiple recovery ticks during one pass collapse into **exactly one** trailing pass, not N. |
| 5 | Trailing pass flag | The trailing pass runs with **`bypassThrottles: true`**. A trailing pass that ran un-forced would hit the very throttles it exists to bypass — including ones the pass it followed may have just stamped. |
| 6 | Trigger sites | **Unchanged.** Single-flighting makes the trigger count irrelevant, so there is no launch-path behaviour risk. They only change *what they call* — and get simpler, since a synchronous `emit` removes their `Task { }` wrappers. |
| 7 | Task ownership (Leo, P1) | The coordinator **owns the pass as an unstructured `Task<Void, Never>`**, rather than running the drain loop inline in `emit`. Inline, `perform` executes in whichever trigger's task called first; SwiftUI cancelling that `.task` would leave a queued recovery pass running in a cancelled context, where the fetch-level `Task.isCancelled` guards added last round turn it into a silent no-op — the queueing would look right and heal nothing. An unstructured `Task { }` inherits actor isolation but not cancellation, so the drain outlives its starter. Pinned by a dedicated regression test asserting the trailing pass runs with `Task.isCancelled == false`. |

## 3. Architecture

### A. `EnvironmentEmitCoordinator` (new, app layer)

A small `@MainActor final class` that **owns the pass as an unstructured task**. It does not know about the emitter, the database, or the store — it takes an injectable `perform` closure, so tests drive it with a stub and never touch the network or DB.

```swift
@MainActor
final class EnvironmentEmitCoordinator {
    /// Runs one environment pass. `Bool` is `bypassThrottles`.
    private let perform: (Bool) async -> Void
    private var drainTask: Task<Void, Never>?
    private var pendingForced = false

    init(perform: @escaping (Bool) async -> Void) { self.perform = perform }

    /// Signals that a pass should run. Returns the coordinator-owned drain task —
    /// newly started, or the one already running — so a caller (or a test) may await
    /// it. Non-optional: every path yields a task. The three triggers ignore the result.
    @discardableResult
    func emit(forced: Bool) -> Task<Void, Never> {
        if forced { pendingForced = true }
        if let drainTask { return drainTask }   // a drain is active; it will pick the flag up

        let initialForced = forced
        let task = Task { [weak self] in        // UNSTRUCTURED: independent of any caller's cancellation
            guard let self else { return }
            var runForced = initialForced
            while true {
                self.pendingForced = false
                await self.perform(runForced)
                if !self.pendingForced { break }
                runForced = true                // any queued follow-up is a recovery pass
            }
            self.drainTask = nil
        }
        drainTask = task
        return task
    }
}
```

**Why the coordinator must own the task (the correction that motivates this shape).** An earlier draft ran the drain loop inline inside `emit`, which meant `await perform(...)` executed in *whichever trigger's task called first*. SwiftUI cancels a `.task` when its view goes away — so a queued recovery pass would run inside an already-cancelled task context, and last round deliberately added `Task.isCancelled` guards to every fetch. The trailing forced pass would return immediately having done nothing: the queueing would look correct and heal nothing. A `Task { }` created here is **unstructured** — it inherits actor isolation (staying on the main actor) but *not* cancellation — so the drain outlives whichever trigger happened to start it.

Properties this shape gives us:

- **Dedup:** a second `emit` while a drain is active returns the existing task without starting a pass.
- **Queued recovery:** a `forced` call sets `pendingForced` *before* the early return, so it is recorded even when it returns early; the running loop drains it after its current `perform`.
- **Coalescing:** `pendingForced` is a Bool, so N recovery ticks during one pass yield one trailing pass.
- **Recovery during the trailing pass** queues one more, via the same loop — no special case.
- **Cancellation-independent:** the drain survives cancellation of any caller, which is what makes the queued recovery actually heal.
- **No lost-wakeup window.** Everything is `@MainActor`, and there is no `await` between the final `pendingForced` check, the loop `break`, and `drainTask = nil`. A trigger cannot slip in after the loop decides to exit but before the handle clears — precisely the gap where a naive implementation drops a heal. Likewise `drainTask = task` is assigned synchronously before the task body's first turn can run, so an `emit` can never observe a started-but-unrecorded drain.
- **Termination:** the app already gates the recovery trigger on a live location failure existing, so once the trailing pass heals it, no further ticks call in. The loop is not unbounded in practice.

### B. Wiring

`FoodIntolerancesApp` constructs the coordinator in `init()`, after the service and status store it depends on (same pattern the store and service already use):

```swift
let coordinator = EnvironmentEmitCoordinator { forced in
    await EnvironmentalEventEmitter.emitIfNeeded(
        service: service, statusStore: statusStore, bypassThrottles: forced)
}
```

The closure captures the service and store; neither holds the coordinator, so there is no retain cycle. (The coordinator does hold its own `drainTask`, and the task captures `self` weakly, so that cycle is broken too — and closes anyway when the task clears the handle.) The coordinator has no observable state the UI reads, so it is held as plain `@State` rather than `@StateObject` — there is no reason to add `ObservableObject` conformance purely for ownership.

Because `emit` is now synchronous (it signals and hands back the coordinator-owned task), the trigger sites get *simpler* — the `Task { }` wrappers they need today disappear:

- `.task` → `coordinator.emit(forced: false)`
- scenePhase `.active` → `coordinator.emit(forced: false)`
- `locationRecoveryTick` → `coordinator.emit(forced: true)`, **keeping its existing live-location-failure gate** (that gate is what bounds the trailing-pass loop).

Note the `.task` closure now returns immediately rather than staying alive for the duration of the pass. That is the intended consequence: SwiftUI cancelling that `.task` no longer has anything to cancel.

`EnvironmentalEventEmitter.emitIfNeeded` is unchanged.

## 4. Files

**New**
- `Models/EnvironmentEmitCoordinator.swift` — the coordinator.
- `Food IntolerancesTests/EnvironmentEmitCoordinatorTests.swift` — the tests below.

**Modified**
- `FoodIntolerancesApp.swift` — construct the coordinator in `init()`; the three triggers call `coordinator.emit(forced:)` instead of `emitIfNeeded` directly.

## 5. Testing

All against the injected `perform` closure — no network, no database, no `UserDefaults`. The stub records each call's `forced` value **and whether `Task.isCancelled` was set on entry**, and can be held open (awaiting a continuation the test resumes) so a second `emit` provably lands mid-pass.

- **Normal dedup:** two `emit(forced: false)` with one in flight → `perform` runs **once**.
- **Queued recovery:** `emit(forced: true)` arriving while a pass is in flight → exactly **two** passes total, no more.
- **Force-flag preservation:** that second pass receives `bypassThrottles == true`. (A trailing pass that ran un-forced would hit the throttles it exists to bypass — this is the assertion that makes the queueing worth anything.)
- **Coalescing:** *multiple* recovery ticks during one pass → exactly **one** trailing pass, not N.
- **Survives caller cancellation (the P1 regression guard):** start a pass from inside a task that awaits the returned drain handle; while `perform` #1 is held open, queue `emit(forced: true)`, then **cancel that caller task**; release #1. Assert the trailing pass **ran**, received `forced == true`, **and observed `Task.isCancelled == false`**. The cancellation assertion is the one that matters — under the inline-drain design the trailing pass would still "run" but in a cancelled context, where the emitter's real fetch guards make it a silent no-op. Merely asserting it ran would pass on the broken design.
- **Cleanup:** after everything settles, a later `emit` starts a fresh pass — `drainTask` is back to `nil` and `pendingForced` is reset.
- **First-call forced:** `emit(forced: true)` with nothing in flight runs a single pass with `bypassThrottles == true` (the recovery trigger's normal, uncontended path).

App suites run with `-parallel-testing-enabled NO` on the `iPhone 17 Pro` simulator; a lone `** TEST FAILED **` from `SwiftDataMigratorTests` teardown is a known pre-existing crash unrelated to this work.

**Device pass**
- Cold launch with location permitted but a cold fix: the Health screen must **not** flash a false "Unavailable" for observed weather/AQI, and the observed backfills must not be locked out (their `Updated` time should reflect a real pass).
- Cold launch with Location denied, then granted: still heals in one pass (the behaviour verified last round must not regress — this is the path the trailing pass protects).

## 6. Out of scope

- Any change to `emitIfNeeded`'s internals: watermarks, throttles, grace, contiguity, classification, scope recording.
- The refresh cooldown in `requestRefreshWithCooldown` — single-flighting means a second pass no longer races it, so the loser-proceeds-with-stale-values path stops being reachable from the app's triggers. The cooldown itself stays as-is.
- Demo-data hygiene (queue #3) and proactive poor-air warnings (queue #4).
- The `fetchAtmosphericPressure` internal 5-second timeout-fallback's no-status window (a bounded, self-correcting Minor recorded in the previous round).
