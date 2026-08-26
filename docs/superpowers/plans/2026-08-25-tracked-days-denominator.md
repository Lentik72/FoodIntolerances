# Tracked-Days Denominator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the evidence engine treating days the user was not logging as days the symptom did not occur, so imported Apple Health history can no longer inflate every ratio into a false trigger.

**Architecture:** `EvidenceEngine.recompute` computes one `Set<Date>` of tracked days (UTC start-of-day of every `source == .manual` event) and threads it through the three `CooccurrenceAnalyzer.analyze` call sites in place of today's `observation: DateInterval`. The analyzer restricts both sides of the rate computation to those days and returns `nil` when no comparison days remain.

**Tech Stack:** Swift 6, Swift Testing (`@Test`/`#expect`), GRDB, `HealthGraphCore` package.

**Spec:** `docs/superpowers/specs/2026-08-25-tracked-days-denominator-design.md`

## Global Constraints

- **The acceptance suite must pass unedited.** `EvidenceEngineAcceptanceTests.recallAllPlantedPatterns` and `.precisionIsHonestForAnAssociationEngine` run on an all-manual corpus, where tracked days and calendar days are the same set, so this change is a no-op for them. If a task needs to edit either test, the implementation is wrong — stop and report rather than adjusting the test.
- **A tracked day is a day with at least one event whose `source == .manual`.** Not HealthKit, not synthetic-derived, not environment. Imported symptoms (`HealthKitSampleMapper` emits `category: .symptom`) do **not** make a day tracked.
- **No changes to thresholds, weights, the observational ceiling, lag windows, or `ConfidenceScorer`.** This round changes what days are counted, nothing about how the counts are scored.
- **UTC start-of-day throughout,** via the existing `Self.utc` calendar in `CooccurrenceAnalyzer`/`EvidenceEngine`. A local-time calendar would make the tracked set drift with travel.
- **Every task ends with the package suite green:** `cd HealthGraphCore && swift test`.
- Mutation discipline: where a task names a mutant, apply it, confirm the **named** test fails, restore, and report both directions.

---

### Task 1: Settle whether the restriction must apply to both sides

The spec's §2 claims the restriction must cover exposure days as well as the denominator, on the grounds that derived exposures (poor air, short sleep, weather) land on days with no manual capture and would otherwise enter `P(Y|X)` as exposures that could never show an outcome. **That claim is unproven.** An attempt to measure it was inert because `ShortSleepExposureSource` requires a parsed night session with `asleepMinutes` and ignored raw sleep events.

This task settles it before any production code depends on it. It is a measurement, not a feature.

**Files:**
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/TrackedDaysDerivedExposureTests.swift`

**Interfaces:**
- Consumes: `SyntheticDataGenerator`, `EvidenceEngine.extract`, `CooccurrenceAnalyzer.analyze` (current signature, `observation:`), `SleepSessionParser` or whatever `ShortSleepExposureSource` consumes.
- Produces: a written finding in the task report — **does filtering exposure occurrences to tracked days change the classification of a derived-exposure pair, yes or no?**

- [ ] **Step 1: Find the shape `ShortSleepExposureSource` actually consumes**

Read `HealthGraphCore/Sources/HealthGraphCore/Evidence/ShortSleepExposureSource.swift` and whatever it calls to obtain sleep sessions. The guard is `s.kind == .night, s.asleepMinutes < config.shortSleepThresholdMinutes`. Determine exactly what `HealthEvent` rows produce such a session — subtype, unit, value, metadata. Write the finding into the report file before continuing.

- [ ] **Step 2: Build a corpus where a derived exposure lands on untracked days**

The corpus needs three properties:
1. A 400-day span with manual logging (use the standard synthetic config below).
2. Sleep events in that span that DO parse into short-sleep sessions, on days that have **no** manual capture.
3. A symptom the short sleep can pair with, logged manually on tracked days.

```swift
var cfg = SyntheticConfig(
    startDate: now.addingTimeInterval(-400 * 86_400), days: 400, seed: 42,
    patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food,
                              outcomeSubtype: "bloating", lagHours: 8, lagJitterHours: 3,
                              followProbability: 0.7, exposureProbabilityPerDay: 0.5)],
    outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 1...3)
cfg.derivedScenarios = DerivedScenarios(shortSleepFatigue: true)
```

Then add short-sleep events on days OUTSIDE that span (e.g. days 401–1200 back), using the shape found in Step 1.

- [ ] **Step 3: Measure both ways**

`analyze` consumes `observation` only as a day count, so a `DateInterval` of the right LENGTH exercises a candidate denominator without touching the engine. Compute, for the `derived:shortSleep` × `symptom:fatigue` pair:

```swift
// tracked = distinct UTC start-of-day of every source == .manual event
let expAll = exposures[shortSleepKey]!
let expOnTracked = expAll.filter { tracked.contains(cal.startOfDay(for: $0.timestamp)) }
// (a) denominator-only:  analyze(exposure: expAll,       ..., observation: <tracked.count days>)
// (b) both sides:        analyze(exposure: expOnTracked, ..., observation: <tracked.count days>)
```

Print `exposureDayCount`, `baseRate`, `P(Y|X)`, `ratio`, and the `RelationshipClassifier.classify` result for each.

- [ ] **Step 4: Report the finding**

Write to the report file: the two rows of numbers, and a one-line verdict — **"both-sides restriction is required"** or **"denominator-only is sufficient"**. If (a) and (b) classify identically AND `P(Y|X)` differs by less than 0.01, the claim is unsupported; say so plainly rather than defending the spec.

**Do not change any production code in this task.** Report and stop; the controller decides whether Task 2 keeps the exposure-side filtering.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/TrackedDaysDerivedExposureTests.swift
git commit -m "test: measure whether tracked-day filtering must cover exposure days"
```

---

### Task 2: Tracked days in `CooccurrenceAnalyzer`, all three call sites wired

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/CooccurrenceAnalyzer.swift:37-100`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift:84,104-105`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceContext.swift:15,31-34,53-56`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/StabilityValidator.swift:7-9,19-26`
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/CooccurrenceAnalyzerTests.swift:27,38,62`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/CooccurrenceAnalyzerTests.swift`

**Interfaces:**
- Produces: `CooccurrenceAnalyzer.analyze(exposure:outcome:window:trackedDays:) -> PairStats?` — `trackedDays: Set<Date>` of UTC start-of-days. Replaces `observation: DateInterval`. Returns `nil` when the exposure list is empty after filtering, or when no non-exposure tracked days remain.
- Produces: `StabilityValidator.isStable(exposure:outcome:window:fullDirection:trackedDays:config:) -> Bool`.
- Produces: `EvidenceContext.trackedDays: Set<Date>` replacing `observation: DateInterval?`.

- [ ] **Step 1: Write the failing tests**

Add to `CooccurrenceAnalyzerTests.swift`. `day(_:)` builds a UTC start-of-day; anchor at an exact midnight (`1_749_945_600`) — a mid-afternoon anchor makes hour offsets cross day boundaries and produces assertions that look right and test the wrong day.

```swift
    private static let t0 = Date(timeIntervalSince1970: 1_749_945_600)   // exact UTC midnight
    private func day(_ n: Int) -> Date { Self.t0.addingTimeInterval(Double(n) * 86_400) }
    private func at(_ n: Int, hour: Int) -> Date { day(n).addingTimeInterval(Double(hour) * 3600) }

    @Test func untrackedDaysDoNotDiluteTheBaseRate() {
        // The same exposures and outcomes, judged against 10 tracked days and
        // against 1000. Today the second inflates the ratio ~100x, which is the
        // whole defect: a day nobody was logging is not a day without a symptom.
        let exposures = (0..<5).map { ExposureOccurrence(key: .derived(.shortSleep),
                                                         timestamp: at($0 * 2, hour: 8),
                                                         timezoneID: "UTC", sourceEventID: UUID()) }
        let outcomes = [OutcomeOccurrence(key: .symptom("fatigue"), timestamp: at(0, hour: 12),
                                          value: 5, sourceEventID: UUID()),
                        OutcomeOccurrence(key: .symptom("fatigue"), timestamp: at(1, hour: 12),
                                          value: 5, sourceEventID: UUID())]
        let analyzer = CooccurrenceAnalyzer(config: .default)
        let tenDays = Set((0..<10).map { day($0) })
        let stats = analyzer.analyze(exposure: exposures, outcome: outcomes,
                                     window: 0...18, trackedDays: tenDays)
        // day 1 carries an outcome and no exposure -> exactly one spontaneous day,
        // over the 5 tracked days that carry no exposure.
        #expect(stats?.baseRate == 1.0 / 5.0)
    }

    @Test func daysOutsideTheTrackedSetAreIgnoredEntirely() {
        // An exposure on an untracked day cannot teach us anything: no outcome
        // could have been recorded that day. It must not enter P(Y|X) as a miss.
        let tracked = Set((0..<10).map { day($0) })
        let onTracked = (0..<5).map { ExposureOccurrence(key: .derived(.shortSleep),
                                                         timestamp: at($0, hour: 8),
                                                         timezoneID: "UTC", sourceEventID: UUID()) }
        let plusUntracked = onTracked + (50..<80).map {
            ExposureOccurrence(key: .derived(.shortSleep), timestamp: at($0, hour: 8),
                               timezoneID: "UTC", sourceEventID: UUID()) }
        let outcomes = [OutcomeOccurrence(key: .symptom("fatigue"), timestamp: at(0, hour: 12),
                                          value: 5, sourceEventID: UUID())]
        let analyzer = CooccurrenceAnalyzer(config: .default)
        let a = analyzer.analyze(exposure: onTracked, outcome: outcomes, window: 0...18, trackedDays: tracked)
        let b = analyzer.analyze(exposure: plusUntracked, outcome: outcomes, window: 0...18, trackedDays: tracked)
        #expect(a?.exposureDayCount == b?.exposureDayCount)
        #expect(a?.ratio == b?.ratio)
        #expect(a?.missCount == b?.missCount)     // the 30 untracked exposures are not contradictions
    }

    @Test func noComparisonDaysMeansNoAnswer() {
        // Every tracked day carries the exposure, so there is nothing to compare
        // against. Flooring the denominator to 1 would report "every outcome
        // happened on the single comparison day" and make this look protective.
        let tracked = Set((0..<3).map { day($0) })
        let exposures = (0..<3).map { ExposureOccurrence(key: .derived(.shortSleep),
                                                         timestamp: at($0, hour: 8),
                                                         timezoneID: "UTC", sourceEventID: UUID()) }
        let outcomes = [OutcomeOccurrence(key: .symptom("fatigue"), timestamp: at(0, hour: 12),
                                          value: 5, sourceEventID: UUID())]
        #expect(CooccurrenceAnalyzer(config: .default)
            .analyze(exposure: exposures, outcome: outcomes, window: 0...18, trackedDays: tracked) == nil)
    }

    @Test func anEmptyTrackedSetYieldsNothing() {
        // A user who imported Apple Health and never logged anything.
        let exposures = [ExposureOccurrence(key: .derived(.shortSleep), timestamp: at(0, hour: 8),
                                            timezoneID: "UTC", sourceEventID: UUID())]
        #expect(CooccurrenceAnalyzer(config: .default)
            .analyze(exposure: exposures, outcome: [], window: 0...18, trackedDays: []) == nil)
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd HealthGraphCore && swift test --filter CooccurrenceAnalyzerTests`
Expected: compile failure — `extra argument 'trackedDays' in call` / `missing argument for parameter 'observation'`. That is the correct red for a signature that does not exist yet.

- [ ] **Step 3: Change the analyzer**

In `CooccurrenceAnalyzer.analyze`, replace the parameter and the rate block. Keep the per-occurrence pair loop exactly as it is — it operates on the filtered `exposure` array and needs no other change.

```swift
    /// - Parameter trackedDays: UTC start-of-day for every day the person logged
    ///   something themselves. A day outside this set is UNOBSERVED, not negative:
    ///   an Apple Health sleep sample from 2019 is not evidence that no migraine
    ///   occurred. Counting such days as clean drove the base rate toward zero and
    ///   inflated every ratio past the trigger threshold — one 2016 event turned a
    ///   12-edge graph into 16 edges, all possibleTrigger, and inverted a protective
    ///   supplement into a trigger. See the 2026-08-25 spec.
    public func analyze(exposure: [ExposureOccurrence], outcome: [OutcomeOccurrence],
                        window: ClosedRange<Double>, trackedDays: Set<Date>) -> PairStats? {
        guard !exposure.isEmpty else { return nil }
        let cal = Self.utc
        // One rule, both sides. Filtering only the denominator leaves the mirror
        // bug: derived exposures (poor air, short sleep, weather) land on days
        // regardless of logging, so untracked exposure days would enter P(Y|X) as
        // exposures that could never have shown an outcome.
        //
        // Outcomes are filtered too, which drops only IMPORTED symptoms on
        // untracked days — a manually logged symptom makes its own day tracked by
        // definition, so no manual outcome can be lost here.
        let exposure = exposure.filter { trackedDays.contains(cal.startOfDay(for: $0.timestamp)) }
        let outcome = outcome.filter { trackedDays.contains(cal.startOfDay(for: $0.timestamp)) }
        guard !exposure.isEmpty else { return nil }
```

Then, in the "Per-day base rate & ratio" block, replace the three `totalDays`/`nonExposureDays`/`baseRate` lines with:

```swift
        let nonExposureDays = trackedDays.subtracting(exposureDays).count
        // No comparison days means no comparison. A `max(1, …)` floor here would
        // report "every outcome happened on the single comparison day" and make
        // everything look wildly protective.
        guard nonExposureDays > 0 else { return nil }
        let spontaneousOutcomeDays = outcomeDays.subtracting(exposureDays).count
        let baseRate = Double(spontaneousOutcomeDays) / Double(nonExposureDays)
```

Leave `pYgivenX`, `windowDays`, `eps` and the `ratio` expression untouched.

**If Task 1 concluded "denominator-only is sufficient",** drop the `exposure`/`outcome` filter lines and keep only the `nonExposureDays` change — and say so in the report, since two of the Step 1 tests then need their expectations revisited by the controller rather than edited unilaterally.

- [ ] **Step 4: Wire the three call sites so the package compiles**

`EvidenceEngine.recompute` — replace the `observation` binding at line 84:

```swift
        // Tracked days, not calendar days: see CooccurrenceAnalyzer.analyze.
        let trackedDays = Set(events.filter { $0.source == .manual }
                                    .map { cal.startOfDay(for: $0.timestamp) })
```

and the call at line 104: `window: window, trackedDays: trackedDays`. Delete `observation` if the compiler reports it unused.

`EvidenceContext` — replace the stored property and its construction:

```swift
    /// Empty when nothing was logged manually; every per-edge answer is then empty.
    let trackedDays: Set<Date>
```

```swift
        let trackedDays = Set(events.filter { $0.source == .manual }
                                    .map { cal.startOfDay(for: $0.timestamp) })
```

and in `evidence(for:in:)` replace `guard let observation = ctx.observation else { return empty() }` with `guard !ctx.trackedDays.isEmpty else { return empty() }`, passing `trackedDays: ctx.trackedDays` to `analyze`.

`StabilityValidator.isStable` — add `trackedDays: Set<Date>` to the signature (before `config:`), and inside `directional(_:)` narrow it to the half's window:

```swift
            let halfTracked = trackedDays.filter { $0 >= cal.startOfDay(for: lo) && $0 <= obsEnd }
            guard let stats = analyzer.analyze(exposure: half, outcome: halfOutcomes,
                                               window: window, trackedDays: halfTracked) else { return false }
```

`cal` is not currently in scope in `StabilityValidator` — add a UTC calendar the same way `CooccurrenceAnalyzer` does. Update the caller at `EvidenceEngine.swift:137` to pass `trackedDays: trackedDays`.

Update the three existing `analyze` calls in `CooccurrenceAnalyzerTests.swift` (lines 27, 38, 62) to pass a `trackedDays` set covering the days their fixtures use. Do **not** weaken what those tests assert.

- [ ] **Step 5: Run the package suite**

Run: `cd HealthGraphCore && swift test`
Expected: all green, including `EvidenceEngineAcceptanceTests` **unedited** (see Global Constraints).

- [ ] **Step 6: Demonstrate the mutants**

1. Replace `trackedDays.subtracting(exposureDays).count` with a calendar-day count → `untrackedDaysDoNotDiluteTheBaseRate` must fail.
2. Change the tracked-day filter to accept every source → `untrackedDaysDoNotDiluteTheBaseRate` must fail.
3. Replace `guard nonExposureDays > 0` with `max(1, nonExposureDays)` → `noComparisonDaysMeansNoAnswer` must fail.

Restore after each. Report both directions for all three.

- [ ] **Step 7: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence HealthGraphCore/Tests/HealthGraphCoreTests/CooccurrenceAnalyzerTests.swift
git commit -m "fix(evidence): count tracked days, not calendar days, in the base rate"
```

---

### Task 3: The end-to-end regressions this round exists for

Task 2's tests work on hand-built occurrences. These drive the whole engine, which is where the defect was found and the only place it can be shown fixed.

**Files:**
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/TrackedDaysRegressionTests.swift`

**Interfaces:**
- Consumes: `SyntheticDataGenerator`, `AppDatabase.inMemory()`, `EvidenceEngine.recompute`, `GRDBRelationshipStore`, `GRDBObjectStore`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct TrackedDaysRegressionTests {
    /// The 400-day corpus with a planted PROTECTIVE supplement: magnesium taken
    /// ~half of days, migraine on 5% of magnesium days against 30% of the others.
    private func config(now: Date) -> SyntheticConfig {
        var c = SyntheticConfig(
            startDate: now.addingTimeInterval(-400 * 86_400), days: 400, seed: 42,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food,
                                      outcomeSubtype: "bloating", lagHours: 8, lagJitterHours: 3,
                                      followProbability: 0.7, exposureProbabilityPerDay: 0.5)],
            outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 1...3)
        c.derivedScenarios = DerivedScenarios(protectiveSupplement: true)
        return c
    }

    private func minedMagnesiumEdge(extra: [HealthEvent], now: Date) async throws -> Relationship? {
        let db = try AppDatabase.inMemory()
        try await SyntheticDataGenerator.generate(config: config(now: now)).insert(into: db)
        for e in extra { try await GRDBEventStore(database: db).save(e) }
        _ = try await EvidenceEngine(database: db).recompute(asOf: now)
        let mag = try await GRDBObjectStore(database: db)
            .objects(kind: .supplement, includeArchived: false)
            .first { $0.name.lowercased().contains("magnesium") }
        return try await GRDBRelationshipStore(database: db).all()
            .first { $0.fromObjectID == mag?.id && $0.toSubtype == "migraine" }
    }

    @Test func oneImportedEventFromADecadeAgoDoesNotChangeAnyVerdict() async throws {
        // The defect, named. A single HealthKit sleep sample dated 2016 — a
        // category not involved in this pair at all — used to widen the
        // denominator to 3650 calendar days, invert this protective edge into a
        // trigger, and take the whole graph from 1 trigger / 1 improves /
        // 10 noEffect to 16 triggers / 0 / 0.
        let now = Date()
        let clean = try await minedMagnesiumEdge(extra: [], now: now)
        let withImport = try await minedMagnesiumEdge(extra: [
            HealthEvent(timestamp: now.addingTimeInterval(-3650 * 86_400), category: .sleep,
                        subtype: "asleep", value: 7 * 3600, unit: "s", source: .healthKit)
        ], now: now)
        #expect(clean?.type == .improves)
        #expect(clean?.status == .active)
        #expect(withImport?.type == clean?.type)
        #expect(withImport?.status == clean?.status)
    }

    @Test func aSingleForgottenSymptomFromYearsAgoDoesNotChangeAnyVerdict() async throws {
        // The gappy logger. This is the case that killed the two alternative
        // denominators that looked correct on every other input: one migraine
        // logged 8 years ago and never followed up reopened the window and
        // flipped the verdict.
        let now = Date()
        let clean = try await minedMagnesiumEdge(extra: [], now: now)
        let withGap = try await minedMagnesiumEdge(extra: [
            HealthEvent(timestamp: now.addingTimeInterval(-2920 * 86_400), category: .symptom,
                        subtype: "migraine", value: 6, unit: "severity", source: .manual)
        ], now: now)
        #expect(withGap?.type == clean?.type)
        #expect(withGap?.status == clean?.status)
    }

    @Test func aCorpusWithNoManualLoggingMinesNothing() async throws {
        // Imported Apple Health and never logged: there is no day on which we
        // know whether a symptom occurred, so there is nothing to mine. The
        // failure mode being excluded is a fabricated relationship built on a
        // denominator floored to 1.
        let now = Date()
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        for d in 0..<400 {
            try await store.save(HealthEvent(timestamp: now.addingTimeInterval(-Double(d) * 86_400),
                                             category: .sleep, subtype: "asleep",
                                             value: 4 * 3600, unit: "s", source: .healthKit))
        }
        _ = try await EvidenceEngine(database: db).recompute(asOf: now)
        #expect(try await GRDBRelationshipStore(database: db).all().isEmpty)
    }
}
```

- [ ] **Step 2: Run them**

Run: `cd HealthGraphCore && swift test --filter TrackedDaysRegressionTests`
Expected: PASS, because Task 2 fixed the engine. If `oneImportedEventFromADecadeAgoDoesNotChangeAnyVerdict` fails, Task 2 is incomplete — report rather than adjusting the test.

- [ ] **Step 3: Demonstrate the mutant**

Revert `EvidenceEngine`'s `trackedDays` binding to the old `DateInterval(start: times.min()!, end: times.max()!)` day count. `oneImportedEventFromADecadeAgoDoesNotChangeAnyVerdict` must fail with `improves` vs `possibleTrigger`. Restore, report both directions.

- [ ] **Step 4: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/TrackedDaysRegressionTests.swift
git commit -m "test: pin the imported-history and gappy-logger regressions"
```

---

### Task 4: The Insights drill-down must agree with the card it explains

`EvidenceContext.evidence(for:in:)` computes its own stats for the drill-down. Task 2 wired it, but nothing yet proves the numbers it produces match the ones `recompute` stored on the relationship — and `makeContext`'s own doc comment warns about exactly this class of divergence.

**Files:**
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceContextTrackedDaysTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
    @Test func theDrillDownReportsTheSameCountsAsTheStoredRelationship() async throws {
        // A card says "12 of 20"; tapping it must not say "18 of 40". The two
        // numbers come from different code paths over the same corpus, so a
        // call site left on the calendar denominator diverges silently.
        let now = Date()
        let db = try AppDatabase.inMemory()
        try await SyntheticDataGenerator.generate(config: config(now: now)).insert(into: db)
        // imported history — the condition under which the two paths diverge
        try await GRDBEventStore(database: db).save(
            HealthEvent(timestamp: now.addingTimeInterval(-3650 * 86_400), category: .sleep,
                        subtype: "asleep", value: 7 * 3600, unit: "s", source: .healthKit))
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)

        let stored = try await GRDBRelationshipStore(database: db).all()
        #expect(!stored.isEmpty)
        let events = try await GRDBEventStore(database: db)
            .events(in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        let ctx = engine.makeContext(events)
        for r in stored where r.status != .userDismissed {
            let ev = engine.evidence(for: r, in: ctx)
            guard ev.followCount != 0 || ev.missCount != 0 else { continue }  // fail-soft empties
            #expect(ev.followCount == r.evidenceCount, "follow mismatch on \(r.edgeKey ?? "?")")
            #expect(ev.missCount == r.contradictionCount, "miss mismatch on \(r.edgeKey ?? "?")")
        }
    }
```

Reuse the `config(now:)` helper from Task 3 by copying it into this file — the two suites are independent and a shared fixture across suites is worse than four duplicated lines.

- [ ] **Step 2: Run it**

Run: `cd HealthGraphCore && swift test --filter EvidenceContextTrackedDaysTests`
Expected: PASS after Task 2. If it fails, `EvidenceContext` is still computing a different day set than `recompute` — fix `EvidenceContext`, not the test.

- [ ] **Step 3: Demonstrate the mutant**

In `makeContext`, drop the `source == .manual` filter so every event contributes a tracked day. The test must fail on a count mismatch. Restore, report both directions.

- [ ] **Step 4: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceContextTrackedDaysTests.swift
git commit -m "test: drill-down counts match the stored relationship"
```

---

### Task 5: The stability gate must compare like with like

`StabilityValidator` splits exposures at their median and requires both halves to be directional, comparing each half's ratio against `candidateRatioTrigger` / `candidateRatioProtective` — the same thresholds the full pass uses. Task 2 narrowed each half's tracked set. This task proves the gate still means what it says, because nothing else in the suite would notice if it silently stopped working.

**Files:**
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/StabilityTrackedDaysTests.swift`

- [ ] **Step 1: Write the test**

```swift
    @Test func aGenuinelyStableEdgeStillPassesTheGate() async throws {
        // The planted magnesium effect is present in both halves of the corpus by
        // construction, so it must survive the stability gate. If the halves were
        // scored on a calendar-day denominator while the full pass uses tracked
        // days, the two ratios sit on different scales and this edge fails the
        // gate for a reason that has nothing to do with stability.
        let now = Date()
        let db = try AppDatabase.inMemory()
        try await SyntheticDataGenerator.generate(config: config(now: now)).insert(into: db)
        try await GRDBEventStore(database: db).save(
            HealthEvent(timestamp: now.addingTimeInterval(-3650 * 86_400), category: .sleep,
                        subtype: "asleep", value: 7 * 3600, unit: "s", source: .healthKit))
        _ = try await EvidenceEngine(database: db).recompute(asOf: now)

        let mag = try await GRDBObjectStore(database: db)
            .objects(kind: .supplement, includeArchived: false)
            .first { $0.name.lowercased().contains("magnesium") }
        let edge = try await GRDBRelationshipStore(database: db).all()
            .first { $0.fromObjectID == mag?.id && $0.toSubtype == "migraine" }
        // .active requires significance AND effect floor AND stability; a stability
        // failure is the only one that can regress from this task's change.
        #expect(edge?.status == .active)
    }
```

- [ ] **Step 2: Run it**

Run: `cd HealthGraphCore && swift test --filter StabilityTrackedDaysTests`
Expected: PASS.

- [ ] **Step 3: Demonstrate the mutant**

In `StabilityValidator.directional`, pass the FULL `trackedDays` instead of `halfTracked`. Each half's exposures then sit against the whole corpus's tracked days, deflating both half-ratios. The test must fail with `.candidate` instead of `.active`. Restore, report both directions.

If the mutant does **not** fail the test, say so — it means this task's assertion is not actually pinning the half-window narrowing, and the controller needs to know rather than have a green result implied.

- [ ] **Step 4: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/StabilityTrackedDaysTests.swift
git commit -m "test: stability gate stays coherent under tracked days"
```

---

### Task 6: Pin the path that carries the fix onto an existing install

The spec said this round "must force one recompute after the update". Investigation says
otherwise, and the plan follows the code rather than the spec: `InsightsRefreshCoordinator`
holds `lastRecomputeAt` in memory only, and `RecomputePolicy.shouldRecompute` opens with
`guard let lastRunAt else { return true }`. So the first `refreshIfNeeded()` of every launch
recomputes unconditionally, and the corrected edges land the first time the user opens Insights
after updating. **No new forcing mechanism is needed — do not add one.**

What is missing is a test saying so. That behaviour is currently incidental: anyone who later
persists `lastRecomputeAt` across launches (an obvious-looking optimisation) would silently
strand every existing install on its stale graph.

**Files:**
- Test: `Food IntolerancesTests/InsightsRefreshCoordinatorTests.swift` (create if absent)

**Interfaces:**
- Consumes: `InsightsRefreshCoordinator(database:minInterval:now:)`, `RecomputePolicy.shouldRecompute`.

- [ ] **Step 1: Write the failing test**

Test `RecomputePolicy` directly — it is pure, in the package, and is where the guarantee lives:

```swift
    @Test func aFreshLaunchAlwaysRecomputes() {
        // The only thing that carries a corrected engine onto an existing install:
        // lastRecomputeAt is in-memory, so every launch starts nil and the first
        // refresh recomputes. Persisting it across launches would strand every
        // existing graph on the old maths with nothing to signal it.
        #expect(RecomputePolicy.shouldRecompute(lastRunAt: nil, lastWatermark: 500,
                                                now: Date(), currentWatermark: 500,
                                                minInterval: 900))
    }
```

Put it in `HealthGraphCore/Tests/HealthGraphCoreTests/RecomputePolicyTests.swift` (create if
absent) rather than the app target — no simulator needed, and it lives beside the type it pins.

- [ ] **Step 2: Run it**

Run: `cd HealthGraphCore && swift test --filter RecomputePolicyTests`
Expected: PASS immediately — this pins existing behaviour rather than changing it. Say so in the
report; a test that passes on first run is only worth keeping if the mutant below kills it.

- [ ] **Step 3: Demonstrate the mutant**

Change the guard to `guard let lastRunAt else { return false }`. The test must fail. Restore and
report both directions. If it does not fail, the test is not pinning anything — report that.

- [ ] **Step 4: Note the one surface that reads relationships before any recompute**

`PoorAirPersonalization` filters on `.active`, and Home renders before Insights is ever opened, so
a stale wrong edge can personalise the Home banner for one session after updating. Do not fix it
in this round — record it in the report as a finding for the controller.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/RecomputePolicyTests.swift
git commit -m "test: a fresh launch always recomputes, which is what carries this fix"
```

---

### Task 7: Say what the drill-down count means

Filtering the pairs changes a number the user may already have seen — "12 times" where it once said "20". The number is now correct, but nothing on screen explains the change.

**Files:**
- Modify: `Views/HealthOS/Insights/InsightDetailView.swift:156-172` (`rawNumbersCard`, the
  "Evidence / contradictions" row)
- Test: `Food IntolerancesTests/InsightDetailPresentationTests.swift` (create if absent)

Note the count rendered there comes from the stored `Relationship` (`r.evidenceCount` /
`r.contradictionCount`), not from `RelationshipEvidence` — so Task 4's consistency test is what
guarantees this row and the drill-down dots agree.

- [ ] **Step 1: Write the failing test**

Assert the drill-down includes a line stating the count covers days the person was logging. Assert on meaning, not an exact sentence: `localizedCaseInsensitiveContains("days you logged")` or equivalent, chosen to survive a copy edit that keeps the meaning.

- [ ] **Step 2: Run it, implement, run again**

Keep it to one short line in the existing secondary-text style. No new screen, no explainer sheet, no mention of "tracked days" as jargon.

- [ ] **Step 3: Run the full app suite**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO`
Note: `SwiftDataMigratorTests` crashes the runner (pre-existing), so the final "Test run with N tests" line under-counts. Verify by counting `✔ Suite` lines and grepping for `✘`.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(insights): say the evidence count covers days you were logging"
```

---

## Device verification

Not a task — the gate before merge, run by the human partner.

1. Health → Health Graph Debug → **Load synthetic dataset (400 days)**.
2. **Dump relationship report.** Before this round the dump was almost entirely `possibleTrigger` at 0.750, including pure-noise demo foods. Expect a much smaller set, `improves` present for the DEMO magnesium → migraine edge, and `confirmedNoEffect` rows appearing at all.
3. Protocols & experiments → **+** → the **DEMO**-tagged magnesium → Migraine → Repeated → backdate 90 days → Start → End → tap in. Expect an actual verdict rather than "Here's what happened" — the Phase A check that has never been completable on a real device.
4. Confirm the ~15 pre-existing false triggers are **not visible** anywhere in Insights. They become `.decayed` rows rather than being deleted; the spec flags confirming that decayed edges are invisible on every surface.
