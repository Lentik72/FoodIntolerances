# Stress as an Exposure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wake the dormant `highStress` exposure by mining the rated "Stress" symptom logs the app can already record, without letting the same log be tested against itself.

**Architecture:** `HighStressExposureSource` gains a second positive allowlist (`.symptom`/`stress`/`severity`) alongside its existing dormant one (`.stress`/`stressRating`/`score`). Because a stress log then produces both an exposure and an outcome from one event, `CandidateGenerator` consults a new shadowing declaration and skips the self-pair. The app side adds "Stress" to the first-run seed grid for discoverability. No new screens, no schema change, no migration.

**Tech Stack:** Swift 6, Swift Testing (`@Test`/`#expect`), swift-package `HealthGraphCore`, Xcode app target `Food Intolerances`.

## Global Constraints

- `highStressThreshold` stays **7**; `stressLagHours` stays **0...24**. Do not change `EvidenceConfig`.
- Both accepted shapes are **positive allowlists with a unit guard**. Never widen to "any `.stress` event" — that is the defect that mined HealthKit Mindful Session *minutes* as high stress.
- The existing `HighStressExposureSourceTests` must keep passing **unchanged**. The new shape is additive; if an existing test needs editing, the change is wrong.
- Only **rated** stress logs count. `CaptureService.logSymptom` writes `unit: "severity"` only when a severity was given, so an unrated log has `nil` value and must be rejected.
- The shadow exclusion is **per-key, not per-event**, and must stay surgical: `highStress → symptom("headache")` must survive.
- Package tests: `swift test --package-path HealthGraphCore`. App tests need `-parallel-testing-enabled NO`.
- Every task ends with a commit. Follow the repo's Conventional Commit style.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `HealthGraphCore/Sources/HealthGraphCore/Evidence/DerivedEventExposureSources.swift` | Accept the second stress shape | 1 |
| `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift` | Extend `HighStressExposureSourceTests` | 1 |
| `HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift` | Declare which exposures shadow which outcomes | 2 |
| `HealthGraphCore/Sources/HealthGraphCore/Evidence/CandidateGenerator.swift` | Skip shadowed pairs | 2 |
| `HealthGraphCore/Tests/HealthGraphCoreTests/CandidateGeneratorTests.swift` | Pin the skip and its narrowness | 2 |
| `HealthGraphCore/Tests/HealthGraphCoreTests/StressExposureIntegrationTests.swift` | Prove the pieces compose | 3 |
| `Views/HealthOS/FirstRun/SeedSymptomGrid.swift` | Offer "Stress" as a seed | 4 |
| `Food IntolerancesTests/SeedCatalogTests.swift` | Pin that it is offered | 4 |

---

## Task 1: Accept the rated stress symptom as a high-stress exposure

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/DerivedEventExposureSources.swift:3-28`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift:119-172` (extend `HighStressExposureSourceTests`)

**Interfaces:**
- Produces: `HighStressExposureSource.symptomSubtype = "stress"`, `HighStressExposureSource.symptomUnit = "severity"` — Tasks 2 and 3 reference `symptomSubtype` by name.
- Consumes: `HighStressExposureSource.ratingSubtype` / `.ratingUnit`, which already exist.

**Context you need:** `SymptomCatalog` already contains a "Stress" entry whose canonical key is `stress`, and `CaptureService.logSymptom` writes `category: .symptom, subtype: <canonicalKey>, unit: "severity"` (or `unit: nil` when severity is nil). `OutcomeSource` separately maps every symptom subtype to an outcome — that is why Task 2 exists.

- [ ] **Step 1: Write the failing tests**

Append these to the existing `HighStressExposureSourceTests` struct in `ExposureSourceTests.swift`, immediately after `rejectsWrongSubtypeWithRightUnit()`. Do not modify any existing test in that struct.

```swift
    // MARK: - The second shape: the rated "Stress" symptom people can already log

    private func symptomStress(_ value: Double?, subtype: String = "stress",
                               unit: String? = "severity") -> HealthEvent {
        HealthEvent(timestamp: t0, timezoneID: "UTC", category: .symptom, subtype: subtype,
                    value: value, unit: unit, source: .manual, createdAt: t0)
    }

    @Test func acceptsARatedStressSymptomAtOrAboveThreshold() {
        // SymptomCatalog has had a "Stress" entry all along, so this is the log
        // people actually make. Before this it fed outcomes only and was
        // invisible to the exposure miner.
        let src = HighStressExposureSource(config: .default)
        #expect(src.occurrences(from: [symptomStress(8)]).map(\.key) == [.derived(.highStress)])
    }

    @Test func rejectsARatedStressSymptomBelowThreshold() {
        let src = HighStressExposureSource(config: .default)
        #expect(src.occurrences(from: [symptomStress(4)]).isEmpty)
    }

    @Test func rejectsAnUnratedStressSymptom() {
        // logSymptom writes unit: nil when no severity was given. "I was
        // stressed" without a number cannot be thresholded at 7, and guessing
        // a value would invent data.
        let src = HighStressExposureSource(config: .default)
        #expect(src.occurrences(from: [symptomStress(nil, unit: nil)]).isEmpty)
    }

    @Test func rejectsOtherSymptomsRatedHigh() {
        // Without the subtype guard, EVERY symptom logged at 7+ would become a
        // high-stress exposure — every bad headache would read as stress.
        let src = HighStressExposureSource(config: .default)
        #expect(src.occurrences(from: [symptomStress(9, subtype: "headache")]).isEmpty)
    }

    @Test func theUnitGuardIsPerShapeNotGlobal() {
        // Each shape owns its unit. A symptom carrying "score" is not the
        // symptom shape, and a .stress event carrying "severity" is not the
        // rating shape — otherwise the two allowlists leak into each other and
        // the Mindful Sessions class of defect reopens.
        let src = HighStressExposureSource(config: .default)
        #expect(src.occurrences(from: [symptomStress(8, unit: "score")]).isEmpty)
        #expect(src.occurrences(from: [symptomStress(8, unit: "min")]).isEmpty)
        #expect(src.occurrences(from: [stress(8, subtype: "stress", unit: "severity")]).isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path HealthGraphCore --filter HighStressExposureSourceTests 2>&1 | tail -12`
Expected: FAIL — `acceptsARatedStressSymptomAtOrAboveThreshold` fails (empty result). The four rejection tests pass already, because nothing is accepted yet; that is expected and they become load-bearing in Step 3.

- [ ] **Step 3: Implement the second shape**

Replace the body of `HighStressExposureSource` in `DerivedEventExposureSources.swift` (keep the file's other sources untouched):

```swift
/// High-stress exposures: stress events at or above the threshold.
public struct HighStressExposureSource: ExposureSource {
    /// Shape 1 — a dedicated stress rating. Currently DORMANT: nothing in the
    /// app writes it. Kept because it is already tested and documents the exact
    /// shape any future writer must produce (a dedicated capture surface, or an
    /// Apple State of Mind import).
    public static let ratingSubtype = "stressRating"
    /// Unit guard. Not redundant with the subtype: it is what makes a future
    /// producer that reuses the subtype with different units fail closed
    /// rather than silently mis-scale, which is exactly how minutes got in.
    public static let ratingUnit = "score"

    /// Shape 2 — the "Stress" entry that already exists in SymptomCatalog,
    /// logged through symptom capture. This is the log people actually make;
    /// before it was mined here it fed outcomes only. `logSymptom` writes this
    /// unit only when a severity was given, so an unrated stress log has a nil
    /// value and is rejected by the range check below.
    public static let symptomSubtype = "stress"
    public static let symptomUnit = "severity"

    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard Self.isRatedStress(e),
                  let v = e.value, (1...10).contains(v),
                  v >= config.highStressThreshold else { return nil }
            return ExposureOccurrence(key: .derived(.highStress), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }

    /// TWO positive allowlists, each with its own unit guard — never a denylist.
    /// The previous rule accepted any `.stress` event, and the only real
    /// producer was HealthKit Mindful Sessions carrying duration in MINUTES, so
    /// every meditation of 7+ min was mined as a high-stress exposure with
    /// inverted semantics. Keeping the units pinned per shape is what stops
    /// that class of defect returning through either door.
    private static func isRatedStress(_ e: HealthEvent) -> Bool {
        (e.category == .stress && e.subtype == ratingSubtype && e.unit == ratingUnit)
            || (e.category == .symptom && e.subtype == symptomSubtype && e.unit == symptomUnit)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path HealthGraphCore --filter HighStressExposureSourceTests 2>&1 | tail -12`
Expected: all 11 tests pass (6 pre-existing + 5 new).

- [ ] **Step 5: Run the whole package suite**

Run: `swift test --package-path HealthGraphCore 2>&1 | tail -3`
Expected: 390 + 5 = 395 tests pass. The synthetic generator emits the `.stress`/`stressRating` shape, so the acceptance corpus is unaffected by this change.

- [ ] **Step 6: Demonstrate the two mutants**

For each: apply the mutation, run `swift test --package-path HealthGraphCore --filter HighStressExposureSourceTests`, confirm the named test FAILS, restore the original, confirm it passes again. Report both directions.

1. **Drop the symptom unit guard** — delete `&& e.unit == symptomUnit` from `isRatedStress`.
   Expected failure: `rejectsAnUnratedStressSymptom` and `theUnitGuardIsPerShapeNotGlobal`.
2. **Drop the symptom subtype guard** — delete `e.subtype == symptomSubtype &&` from `isRatedStress`.
   Expected failure: `rejectsOtherSymptomsRatedHigh`.

- [ ] **Step 7: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/DerivedEventExposureSources.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "feat(evidence): mine the rated Stress symptom as a high-stress exposure"
```

---

## Task 2: Never test an exposure against the outcome it came from

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift` (append after `OutcomeOccurrence`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/CandidateGenerator.swift:16-23`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/CandidateGeneratorTests.swift`

**Interfaces:**
- Consumes: `HighStressExposureSource.symptomSubtype` from Task 1.
- Produces: `ExposureOutcomeShadowing.shadows(_ exposure: ExposureKey, _ outcome: OutcomeKey) -> Bool`.

**Why this exists:** after Task 1, one stress log yields an exposure (`derived:highStress`) and an outcome (`symptom("stress")`) from the **same event**. `CandidateGenerator` pairs every qualifying exposure with every qualifying outcome, so it would generate `highStress → stress`, whose co-occurrence is perfect by construction. That passes every evidence gate and surfaces as a confident insight reading "High stress → Stress" — a tautology sitting beside real findings.

- [ ] **Step 1: Write the failing tests**

Append to `CandidateGeneratorTests` (keep `gatesOnMinCounts` unchanged):

```swift
    @Test func neverPairsHighStressWithTheStressOutcomeItIsDerivedFrom() {
        // The same log produces both sides, so this pair co-occurs perfectly by
        // construction and would pass every gate as "High stress → Stress".
        let exposures = [ExposureKey.derived(.highStress): exp(.derived(.highStress), 8)]
        let outcomes = [OutcomeKey.symptom("stress"): out(.symptom("stress"), 8)]
        let cands = CandidateGenerator(config: .default)
            .candidates(exposuresByKey: exposures, outcomesByKey: outcomes)
        #expect(cands.isEmpty)
    }

    @Test func stillPairsHighStressWithEveryOtherSymptom() {
        // The exclusion must be surgical. "Stress exposures don't pair with
        // symptoms" would delete the entire feature.
        let exposures = [ExposureKey.derived(.highStress): exp(.derived(.highStress), 8)]
        let outcomes = [OutcomeKey.symptom("stress"): out(.symptom("stress"), 8),
                        OutcomeKey.symptom("headache"): out(.symptom("headache"), 8)]
        let cands = CandidateGenerator(config: .default)
            .candidates(exposuresByKey: exposures, outcomesByKey: outcomes)
        #expect(cands == [Candidate(exposure: .derived(.highStress), outcome: .symptom("headache"))])
    }

    @Test func otherExposuresAreUnaffectedByShadowing() {
        // Only an exposure DERIVED FROM an outcome's events shadows it. A food
        // trigger has no such relationship to the stress outcome.
        let dairy = ExposureKey.object(UUID(), .food)
        let cands = CandidateGenerator(config: .default)
            .candidates(exposuresByKey: [dairy: exp(dairy, 8)],
                        outcomesByKey: [OutcomeKey.symptom("stress"): out(.symptom("stress"), 8)])
        #expect(cands == [Candidate(exposure: dairy, outcome: .symptom("stress"))])
    }

    @Test func shadowingIsDeclaredNotInferred() {
        // Direct unit coverage of the declaration, so the rule is pinned even if
        // CandidateGenerator is later restructured.
        #expect(ExposureOutcomeShadowing.shadows(.derived(.highStress), .symptom("stress")))
        #expect(!ExposureOutcomeShadowing.shadows(.derived(.highStress), .symptom("headache")))
        #expect(!ExposureOutcomeShadowing.shadows(.derived(.shortSleep), .symptom("stress")))
        #expect(!ExposureOutcomeShadowing.shadows(.derived(.highStress), .lowMood))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path HealthGraphCore --filter CandidateGeneratorTests 2>&1 | tail -12`
Expected: FAIL — `cannot find 'ExposureOutcomeShadowing' in scope`.

- [ ] **Step 3: Declare the shadowing rule**

Append to `ExposureModel.swift`, after the `OutcomeOccurrence` struct:

```swift
/// Which exposures are derived FROM outcome events, and therefore must never be
/// tested against them.
///
/// A stress log is both an exposure (`derived:highStress`) and an outcome
/// (`symptom("stress")`) — the SAME event on both sides. Pairing them yields a
/// perfect co-occurrence by construction, which clears every evidence gate and
/// surfaces as a confident "High stress → Stress". Not a crash; a statistically
/// immaculate tautology sitting beside real findings and devaluing them.
///
/// Declared rather than written as an `if` at the call site so the REASON lives
/// with the model: the next exposure derived from an outcome event adds itself
/// here and is correct automatically, instead of reproducing this bug and
/// waiting for someone to notice a suspiciously perfect result.
///
/// Deliberately per-KEY, not per-event. Both occurrence types carry a
/// `sourceEventID`, so this could exclude only the same log — but that would
/// still permit "your 9am stress predicts your 3pm stress", which is
/// autocorrelation dressed as insight. Any stress→stress edge is uninformative.
public enum ExposureOutcomeShadowing {
    public static func shadows(_ exposure: ExposureKey, _ outcome: OutcomeKey) -> Bool {
        switch (exposure, outcome) {
        case (.derived(.highStress), .symptom(let subtype)):
            return subtype == HighStressExposureSource.symptomSubtype
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Consult it when generating candidates**

In `CandidateGenerator.swift`, replace the pairing loop:

```swift
        var out: [Candidate] = []
        // Skip pairs where the exposure was derived from the outcome's own
        // events — excluded HERE so the tautology is never scored, never
        // stored, and never displayed. Hiding it at the Insights layer would
        // leave the engine believing something false.
        for e in exposures {
            for o in outcomes where !ExposureOutcomeShadowing.shadows(e, o) {
                out.append(Candidate(exposure: e, outcome: o))
            }
        }
        return out
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path HealthGraphCore --filter CandidateGeneratorTests 2>&1 | tail -8`
Expected: 5 tests pass (1 pre-existing + 4 new).

- [ ] **Step 6: Run the whole package suite**

Run: `swift test --package-path HealthGraphCore 2>&1 | tail -3`
Expected: all pass. Watch the acceptance suite in particular — it plants a `.stress`/`stressRating` scenario paired with a `tension` symptom, so `highStress → tension` must survive.

- [ ] **Step 7: Demonstrate the two mutants**

1. **Remove the rule** — change `shadows` to `return false` unconditionally.
   Expected failure: `neverPairsHighStressWithTheStressOutcomeItIsDerivedFrom` and `shadowingIsDeclaredNotInferred`.
2. **Over-broaden it** — change the case body to `return true` (every symptom shadowed by high stress).
   Expected failure: `stillPairsHighStressWithEveryOtherSymptom`. This is the important one: the "safe" over-correction silently deletes the feature.

Restore after each and confirm green.

- [ ] **Step 8: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/CandidateGenerator.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/CandidateGeneratorTests.swift
git commit -m "fix(evidence): never test an exposure against the outcome it is derived from"
```

---

## Task 3: Prove the pieces compose

**Files:**
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/StressExposureIntegrationTests.swift`

**Interfaces:**
- Consumes: Task 1's second shape, Task 2's `ExposureOutcomeShadowing`, and `EvidenceEngine.extract(_:)` (internal, reachable via `@testable`).

**Why this is a separate task:** Tasks 1 and 2 each pin their own unit in isolation, and neither proves the wiring. `HighStressExposureSource` must actually be registered in `EvidenceEngine.extract` (it is, at `EvidenceEngine.swift:35`) for any of this to reach a real recompute. This test runs the real extraction over a hand-built corpus.

It deliberately stops at candidate generation rather than a full `recompute`. The evidence gates need hundreds of days of planted data to fire, so a small corpus would produce zero relationships and an "absence of tautology" assertion would pass vacuously. Asserting on candidates is non-vacuous and deterministic.

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/StressExposureIntegrationTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

/// End-to-end over the REAL extraction path: a rated "Stress" symptom log is
/// simultaneously a high-stress exposure and a stress outcome, and the pair
/// they would form with each other is never generated — while the pair that
/// matters, high stress against another symptom, still is.
struct StressExposureIntegrationTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)
    private func day(_ i: Int) -> Date { t0.addingTimeInterval(Double(i) * 86_400) }

    private func corpus() -> [HealthEvent] {
        var events: [HealthEvent] = []
        for i in 0..<8 {
            events.append(HealthEvent(timestamp: day(i), timezoneID: "UTC", category: .symptom,
                                      subtype: "stress", value: 8, unit: "severity",
                                      source: .manual, createdAt: day(i)))
            events.append(HealthEvent(timestamp: day(i).addingTimeInterval(3 * 3600),
                                      timezoneID: "UTC", category: .symptom, subtype: "headache",
                                      value: 6, unit: "severity", source: .manual,
                                      createdAt: day(i)))
        }
        return events
    }

    @Test func aRatedStressLogIsBothAnExposureAndAnOutcome() throws {
        let engine = EvidenceEngine(database: try AppDatabase.inMemory())
        let extracted = engine.extract(corpus())
        #expect(extracted.exposures[.derived(.highStress)]?.count == 8)
        #expect(extracted.outcomes[.symptom("stress")]?.count == 8)
    }

    @Test func theSelfPairIsExcludedWhileTheRealPairSurvives() throws {
        let engine = EvidenceEngine(database: try AppDatabase.inMemory())
        let extracted = engine.extract(corpus())
        let cands = CandidateGenerator(config: .default)
            .candidates(exposuresByKey: extracted.exposures, outcomesByKey: extracted.outcomes)
        #expect(cands.contains(Candidate(exposure: .derived(.highStress),
                                         outcome: .symptom("headache"))))
        #expect(!cands.contains(Candidate(exposure: .derived(.highStress),
                                          outcome: .symptom("stress"))))
    }
}
```

- [ ] **Step 2: Run the tests**

Run: `swift test --package-path HealthGraphCore --filter StressExposureIntegrationTests 2>&1 | tail -8`
Expected: both pass, because Tasks 1 and 2 are already in. If `aRatedStressLogIsBothAnExposureAndAnOutcome` fails with a nil count, `HighStressExposureSource` is not registered in `EvidenceEngine.extract` — fix the registration, do not weaken the test.

- [ ] **Step 3: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/StressExposureIntegrationTests.swift
git commit -m "test(evidence): pin that stress exposure and outcome compose without a self-pair"
```

---

## Task 4: Offer "Stress" as a first-run seed

**Files:**
- Modify: `Views/HealthOS/FirstRun/SeedSymptomGrid.swift` (the `offeredNames` array)
- Test: `Food IntolerancesTests/SeedCatalogTests.swift`

**Interfaces:**
- Consumes: `SeedSymptomGrid.offeredNames` / `.offered`, and `SeedSelection.limit`, all existing.

**Context:** the grid is a curated, ORDERED list of catalog DISPLAY NAMES — deliberately not derived from `SymptomCatalog.all`, which is alphabetical. `canonicalKey(for:)` is total, so a wrong name yields a plausible key that matches nothing; `everyOfferedNameIsARealCatalogEntry` guards that. "Stress" exists in the catalog with canonical key `stress`, which is exactly the subtype Task 1 mines.

- [ ] **Step 1: Write the failing test**

Append to `SeedCatalogTests`:

```swift
    @Test func stressIsOfferedSoTheExposureHasAOneTapPath() {
        // The high-stress exposure mines the rated "Stress" symptom log. If the
        // grid stops offering it, the feature still works but loses its
        // discoverable entry point, which is the whole reason it is here.
        #expect(SeedSymptomGrid.offeredNames.contains("Stress"))
        #expect(SeedSymptomGrid.offered.contains("stress"))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/SeedCatalogTests" -parallel-testing-enabled NO 2>&1 | grep -E "✘|Test run"`
Expected: FAIL — `stressIsOfferedSoTheExposureHasAOneTapPath`.

- [ ] **Step 3: Add it to the grid**

In `SeedSymptomGrid.swift`, add `"Stress"` to `offeredNames`, after `"Anxiety"`:

```swift
    static let offeredNames: [String] = [
        "Headache", "Migraine", "Bloating", "Upper Abdominal Cramps", "Nausea",
        "Loose Stool", "Hard Stool", "Indigestion", "Fatigue", "Cognitive Fog",
        "Joint Pain", "Muscle Soreness", "Skin Rash", "Congestion",
        "Anxiety", "Stress", "Dizziness",
    ]
```

- [ ] **Step 4: Run the seed suites**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/SeedCatalogTests" -only-testing:"Food IntolerancesTests/SeedSelectionTests" -parallel-testing-enabled NO 2>&1 | grep -E "✘|Test run"`
Expected: all pass. `everyOfferedNameIsARealCatalogEntry`, `noRedFlagKeyIsOffered`, `offeredKeysAreUnique` and `everyOfferedKeySurvivesSeedValidation` all validate the addition for free.

- [ ] **Step 5: Build the app**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Views/HealthOS/FirstRun/SeedSymptomGrid.swift "Food IntolerancesTests/SeedCatalogTests.swift"
git commit -m "feat(first-run): offer Stress as a seed so the exposure has a one-tap path"
```

---

## Final verification

- [ ] `swift test --package-path HealthGraphCore 2>&1 | tail -3` — expect 390 + 11 = 401 passing.
- [ ] Full app suite: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO`. **The banner will read `** TEST FAILED **` with exit 65** because `SwiftDataMigratorTests.migratesObjectsFromAvoidedCabinetAndProtocols()` crashes the runner — a documented pre-existing issue that reproduces on clean `main`. Verify by counting `✔ Suite` lines (expect 70) and grepping for `✘` (expect none), not by the trailing total, which only covers the post-restart launch.

## Device check

Not a full device gate — this round adds no screens. Two observations on hardware:

- [ ] Log **Stress at 8** from symptom capture. It appears in Timeline as a symptom, as before.
- [ ] Health tab → Health Graph Debug → **Dump relationship report**. With enough rated stress history the report may now contain `derived:highStress` rows; it must **never** contain a `highStress → stress` edge. On a graph with little manual history, expect no new rows at all — that is consistent, not a failure.

## Notes carried from the spec

- This change is **retroactive**: existing `.symptom`/`stress` logs rated ≥ 7 become exposures on the next recompute, so relationships can appear without the user logging anything new.
- Out of scope, do not drift in: stress as an outcome family, a dedicated stress capture surface, HRV-derived stress, stress as a confounder, mindfulness as a protective family, and any change to thresholds or gates.
