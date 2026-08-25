# STRESS Demo Seed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deterministic synthetic corpus that proves the stress exposure end to end — as an automated acceptance test over the real engine, and as a purgeable DEBUG button on device.

**Architecture:** `StressDemoSeed` lives in the package so it is testable, unlike the three existing loaders which build their events inline in the debug view. It plants rated Stress symptoms with correlated headaches. Because a rated Stress log is simultaneously an exposure and an outcome, the same corpus demonstrates both that `highStress → headache` mines and that `highStress → stress` is excluded.

**Tech Stack:** Swift 6, Swift Testing (`@Test`/`#expect`), swift-package `HealthGraphCore`, Xcode app target `Food Intolerances`.

## Global Constraints

- **Do not change `EvidenceConfig`**, the evidence gates, `HighStressExposureSource`, or `ExposureDerivation`. If the seed cannot produce a relationship, that is a finding about the seed — report it rather than moving a threshold.
- The seed must be **deterministic**: same inputs produce the same corpus every run. Use index arithmetic, not a random number generator, matching the WEATHER loader's style.
- Stress events must match the accepted shape exactly: `.symptom` / `HighStressExposureSource.symptomSubtype` / `HighStressExposureSource.symptomUnit`, value in 7...9. Reference the constants, never the string literals.
- The debug button stays `#if DEBUG` and its data stays purgeable via "Clear demo data (keeps real data)".
- Package tests: `swift test --package-path HealthGraphCore`. App tests need `-parallel-testing-enabled NO`.
- Every task ends with a commit.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `HealthGraphCore/Sources/HealthGraphCore/Synthetic/StressDemoSeed.swift` | Generate the corpus | 1 |
| `HealthGraphCore/Sources/HealthGraphCore/Synthetic/DemoBatch.swift` | Add the `stress` batch name | 1 |
| `HealthGraphCore/Tests/HealthGraphCoreTests/StressDemoSeedTests.swift` | Shape + determinism tests | 1 |
| `HealthGraphCore/Tests/HealthGraphCoreTests/StressDemoAcceptanceTests.swift` | End-to-end over the real engine | 2 |
| `Views/HealthGraphDebugView.swift` | The `Load STRESS demo` button | 3 |

---

## Task 1: The seed generator

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Synthetic/StressDemoSeed.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Synthetic/DemoBatch.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/StressDemoSeedTests.swift`

**Interfaces:**
- Produces: `StressDemoSeed.days`, `StressDemoSeed.outcomeSubtype`, `StressDemoSeed.events(endingAt:timeZone:) -> [HealthEvent]`, and `DemoBatch.stress`. Tasks 2 and 3 consume all of them.

**Design targets** (checked by the tests below, and the reason the ratio clears `candidateRatioTrigger` of 1.5): 120 days; a rated Stress log on every even day index (60 exposures, vs `minExposures` 5); a headache 3h later on three of every four stress days (45 follows, 75%); a baseline headache on one in seven non-stress days (~9, ~15%). Expected ratio ≈ 0.75 / 0.15 = 5.

- [ ] **Step 1: Write the failing tests**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/StressDemoSeedTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct StressDemoSeedTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let utc = TimeZone(identifier: "UTC")!

    private func seed() -> [HealthEvent] {
        StressDemoSeed.events(endingAt: now, timeZone: utc)
    }

    private func stressEvents(_ events: [HealthEvent]) -> [HealthEvent] {
        events.filter { $0.subtype == HighStressExposureSource.symptomSubtype }
    }

    @Test func everyStressEventMatchesTheShapeTheExposureAccepts() {
        // The whole point of the seed: if these drift from the allowlist, the
        // demo plants data the miner ignores and every downstream assertion
        // becomes vacuous.
        let src = HighStressExposureSource(config: .default)
        let stress = stressEvents(seed())
        #expect(!stress.isEmpty)
        for e in stress {
            #expect(e.category == .symptom)
            #expect(e.unit == HighStressExposureSource.symptomUnit)
            #expect((7...9).contains(e.value ?? 0))
        }
        // Asserted through the real source, not by re-checking the fields above.
        #expect(src.occurrences(from: stress).count == stress.count)
    }

    @Test func thereAreEnoughExposuresAndOutcomesToClearTheGates() {
        let events = seed()
        let config = EvidenceConfig.default
        let exposures = HighStressExposureSource(config: config).occurrences(from: events)
        let outcomes = OutcomeSource(config: config).occurrences(from: events)
            .filter { $0.key == .symptom(StressDemoSeed.outcomeSubtype) }
        #expect(exposures.count >= config.minExposures)
        #expect(outcomes.count >= config.minOutcomeOccurrences)
        #expect(exposures.count == 60)     // 120 days, every even index
    }

    @Test func headachesFollowStressInsideTheLagWindow() throws {
        // Outside 0...24h the pair cannot be mined at all, so a drifting offset
        // would silently produce a corpus with no relationship in it.
        let events = seed()
        let window = EvidenceConfig.default.stressLagHours
        let stressTimes = stressEvents(events).map(\.timestamp).sorted()
        let followers = events.filter {
            $0.subtype == StressDemoSeed.outcomeSubtype
                && stressTimes.contains { s in
                    let hours = $0.timestamp.timeIntervalSince(s) / 3600
                    return window.contains(hours)
                }
        }
        #expect(followers.count == 45)     // three of every four stress days
    }

    @Test func someHeadachesHappenWithoutStressSoTheRatioIsNotDegenerate() {
        // With a zero unexposed rate the ratio is infinite and the demo proves
        // less than it appears to.
        let events = seed()
        let all = events.filter { $0.subtype == StressDemoSeed.outcomeSubtype }
        #expect(all.count > 45)
    }

    @Test func theCorpusIsDeterministic() {
        let a = StressDemoSeed.events(endingAt: now, timeZone: utc)
        let b = StressDemoSeed.events(endingAt: now, timeZone: utc)
        #expect(a.map(\.timestamp) == b.map(\.timestamp))
        #expect(a.map(\.value) == b.map(\.value))
        #expect(a.map(\.subtype) == b.map(\.subtype))
    }

    @Test func theBatchNameIsDistinctFromItsSiblings() {
        let all = [DemoBatch.synthetic, DemoBatch.mood, DemoBatch.outsideFactors,
                   DemoBatch.weather, DemoBatch.stress]
        #expect(Set(all).count == all.count)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path HealthGraphCore --filter StressDemoSeedTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'StressDemoSeed' in scope`.

- [ ] **Step 3: Add the batch name**

In `HealthGraphCore/Sources/HealthGraphCore/Synthetic/DemoBatch.swift`, add one line after `weather`:

```swift
    public static let stress = "stress"
```

- [ ] **Step 4: Implement the seed**

Create `HealthGraphCore/Sources/HealthGraphCore/Synthetic/StressDemoSeed.swift`:

```swift
import Foundation

/// A deterministic corpus for the high-stress exposure, and the only thing in
/// the app that produces its accepted shape at any volume.
///
/// It exists because a real device cannot demonstrate this feature: mining
/// needs exposure→outcome pairs, outcomes come almost entirely from manual
/// capture, and a real graph is overwhelmingly imported HealthKit data with a
/// handful of manual events. The relationship report on such a graph is empty,
/// so every assertion about it passes for the wrong reason.
///
/// Deliberately index-arithmetic rather than seeded RNG: the acceptance test
/// asserts an exact follower count, and a generator that could drift by one
/// would make that test flaky rather than precise.
public enum StressDemoSeed {
    public static let days = 120
    public static let outcomeSubtype = "headache"

    /// `endingAt` is the most recent day of the corpus; everything else runs
    /// backwards from it, so the data is always "recent" relative to the
    /// recompute that follows and cannot age out of a staleness window.
    public static func events(endingAt end: Date, timeZone: TimeZone = .current) -> [HealthEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let tz = timeZone.identifier
        let lastDay = cal.startOfDay(for: end)
        var events: [HealthEvent] = []

        for d in 0..<days {
            guard let dayStart = cal.date(byAdding: .day, value: -(days - 1 - d), to: lastDay) else { continue }

            // Stress on every even day index — 60 of 120, comfortably above
            // minExposures (5) and above noEffectMinExposures (20), so the edge
            // is evaluated as a trigger rather than parked as a null result.
            guard d % 2 == 0 else {
                // A headache on one in seven stress-free days (~15%). Without
                // this the unexposed rate is zero, the ratio is degenerate, and
                // the demo proves less than it appears to.
                if (d / 2) % 7 == 0 {
                    events.append(headache(at: dayStart.addingTimeInterval(11 * 3600), tz: tz,
                                           day: d, severity: 4, kind: "base"))
                }
                continue
            }

            let stressAt = dayStart.addingTimeInterval(14 * 3600)
            events.append(HealthEvent(
                timestamp: stressAt, timezoneID: tz, category: .symptom,
                subtype: HighStressExposureSource.symptomSubtype,
                value: Double(7 + (d / 2) % 3),                    // 7, 8, 9 — all ≥ threshold
                unit: HighStressExposureSource.symptomUnit,
                source: .manual,
                dedupKey: "stressDemo|stress|\(d)"))

            // Three of every four stress days are followed (75%), three hours
            // later — well inside stressLagHours (0...24).
            if (d / 2) % 4 != 3 {
                events.append(headache(at: stressAt.addingTimeInterval(3 * 3600), tz: tz,
                                       day: d, severity: 6, kind: "follow"))
            }
        }
        return events
    }

    private static func headache(at timestamp: Date, tz: String, day: Int,
                                 severity: Double, kind: String) -> HealthEvent {
        HealthEvent(timestamp: timestamp, timezoneID: tz, category: .symptom,
                    subtype: outcomeSubtype, value: severity, unit: "severity",
                    source: .manual, dedupKey: "stressDemo|\(kind)|\(day)")
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path HealthGraphCore --filter StressDemoSeedTests 2>&1 | tail -10`
Expected: 6 tests pass. If `thereAreEnoughExposuresAndOutcomesToClearTheGates` reports fewer than 60 exposures, the shape or the threshold is wrong — fix the seed, not the assertion.

- [ ] **Step 6: Demonstrate one mutant**

Change the stress value expression to `Double(4 + (d / 2) % 3)` (below the threshold of 7), run the filtered tests, and confirm `everyStressEventMatchesTheShapeTheExposureAccepts` fails on the real-source assertion. Restore and confirm green. This is the mutant that matters: a seed whose events the miner silently ignores.

- [ ] **Step 7: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Synthetic/StressDemoSeed.swift \
        HealthGraphCore/Sources/HealthGraphCore/Synthetic/DemoBatch.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/StressDemoSeedTests.swift
git commit -m "feat(synthetic): deterministic STRESS demo corpus in the accepted exposure shape"
```

---

## Task 2: The acceptance test the device check could not be

**Files:**
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/StressDemoAcceptanceTests.swift`

**Interfaces:**
- Consumes: `StressDemoSeed.events(endingAt:timeZone:)` from Task 1.

**Why this is separate:** Task 1 proves the corpus has the right shape. This proves the engine does something with it — over the real `recompute`, through the actual statistical gates, which the stress round's existing integration test deliberately stops short of because a hand-built corpus could not clear them.

Assertions go through `EdgeIdentity.parse`, never substring matching: the exposure token is `derived:highStress`, which itself *contains* the string `stress`, so `edgeKey.contains("stress")` would match the very edge that must be absent.

- [ ] **Step 1: Write the test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/StressDemoAcceptanceTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

/// End-to-end over the real engine: seed → recompute → inspect relationships.
/// This is the check the device gate was meant to be, made deterministic and
/// permanent — a real graph is outcome-empty and mines nothing, so the on-device
/// version of this assertion passes for the wrong reason.
struct StressDemoAcceptanceTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func minedDB() async throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        let events = StressDemoSeed.events(endingAt: now, timeZone: TimeZone(identifier: "UTC")!)
        try await GRDBEventStore(database: db).save(events)
        _ = try await EvidenceEngine(database: db).recompute(asOf: now)
        return db
    }

    @Test func highStressToHeadacheIsMinedAndActive() async throws {
        let active = try await GRDBRelationshipStore(database: minedDB()).relationships(status: .active)
        let pairs = active.compactMap(EdgeIdentity.parse)
        #expect(pairs.contains { $0.exposure == .derived(.highStress)
                                 && $0.outcome == .symptom(StressDemoSeed.outcomeSubtype) })
    }

    @Test func theSelfPairIsNeverMinedInAnyStatus() async throws {
        // The tautology has PERFECT co-occurrence available to it — same event
        // on both sides — so it is the edge most likely to clear every gate if
        // ExposureDerivation were broken. Checked across all statuses, not just
        // active, because a demoted tautology is still a mined tautology.
        let all = try await GRDBRelationshipStore(database: minedDB()).all()
        let pairs = all.compactMap(EdgeIdentity.parse)
        #expect(!pairs.contains { $0.exposure == .derived(.highStress)
                                  && $0.outcome == .symptom(HighStressExposureSource.symptomSubtype) })
        #expect(!pairs.isEmpty)   // non-vacuous: something WAS mined
    }
}
```

- [ ] **Step 2: Run it**

Run: `swift test --package-path HealthGraphCore --filter StressDemoAcceptanceTests 2>&1 | tail -10`

Expected: both pass. **If `highStressToHeadacheIsMinedAndActive` fails**, the corpus does not clear the significance, effect-size or stability gates. Do NOT raise the follow probability, lower a threshold, or weaken the assertion to `.count >= 0`. Instead: report the actual confidence and status of the edge (dump `relationships(status:)` for every status and print the parsed pairs), and stop. Whether a realistic effect size can clear these gates is exactly the question this task exists to answer, and an inflated corpus would answer it dishonestly.

- [ ] **Step 3: Run the whole package suite**

Run: `swift test --package-path HealthGraphCore 2>&1 | tail -3`
Expected: all pass — 401 existing + 6 from Task 1 + 2 here = 409.

- [ ] **Step 4: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/StressDemoAcceptanceTests.swift
git commit -m "test(evidence): acceptance test — the STRESS corpus mines the pair and not the tautology"
```

---

## Task 3: The device button

**Files:**
- Modify: `Views/HealthGraphDebugView.swift`

**Interfaces:**
- Consumes: `StressDemoSeed.events(endingAt:timeZone:)` and `DemoBatch.stress` from Task 1.

- [ ] **Step 1: Add the button**

In `Views/HealthGraphDebugView.swift`, immediately after the `Button("Load WEATHER demo")` block and before `Button("Clear demo data (keeps real data)")`, add:

```swift
                Button("Load STRESS demo") {
                    Task { await loadStressDemo() }
                }
                .disabled(isWorking)
```

- [ ] **Step 2: Add the loader**

Add this method immediately after `loadWeatherDemo()`, following its siblings exactly — reset the batch, save stamped events, recompute, refresh:

```swift
    /// Plants the one corpus that exercises the high-stress exposure, because a
    /// real graph cannot: it is overwhelmingly imported HealthKit data with a
    /// handful of manual events, so it has almost no outcomes to mine and its
    /// relationship report comes back empty.
    ///
    /// Marked and namespaced like its siblings, so "Clear demo data" removes it
    /// completely — no invented stress logs left behind in a real history.
    private func loadStressDemo() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false; graphMutation.graphMutated() }
        do {
            let events = StressDemoSeed.events(endingAt: Date())
            try await database.resetForSeedReload(batch: DemoBatch.stress)
            try await GRDBEventStore(database: database)
                .save(DemoBatch.stamp(events, batch: DemoBatch.stress))
            _ = try await EvidenceEngine(database: database).recompute(asOf: Date())
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }
```

- [ ] **Step 3: Build the app**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Views/HealthGraphDebugView.swift
git commit -m "feat(debug): Load STRESS demo — a purgeable corpus that exercises the exposure"
```

---

## Final verification

- [ ] `swift test --package-path HealthGraphCore 2>&1 | tail -3` — expect 409 passing.
- [ ] App suite: expect 70 suites, zero failures, and the familiar exit-65 banner from the pre-existing `SwiftDataMigratorTests` runner crash. Verify by counting `✔ Suite` lines and grepping `✘`, not by the trailing total.

## Device check

Now genuinely non-vacuous, and it leaves nothing behind:

- [ ] Health → Health Graph Debug → **Load STRESS demo**. It recomputes on its own; no need to visit Insights first.
- [ ] **Dump relationship report.** Expect a `derived:highStress|symptom:headache|...` row. Expect NO row whose outcome token is `symptom:stress` paired with `derived:highStress`.
- [ ] **Clear demo data (keeps real data)** → dump again. The stress rows are gone and the real graph is untouched.
