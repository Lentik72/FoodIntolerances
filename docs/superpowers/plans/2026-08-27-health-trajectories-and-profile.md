# Health Trajectories and Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show honest trends over the device-recorded health data already on the phone — including when the honest answer is "we can't tell" — without asserting a single cause.

**Architecture:** Two correctness fixes to existing data handling first, then pure statistics in `HealthGraphCore` (weekly medians → Hamed–Rao-corrected Mann–Kendall → Theil–Sen with a Sen interval → density, effect-size and coverage gates → one Benjamini–Hochberg correction across series), then a charted SwiftUI surface. Nothing reads or writes a `Relationship`.

**Tech Stack:** Swift 6, Swift Testing, GRDB, Swift Charts, `HealthGraphCore`, HealthKit.

**Spec:** `docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md`

## Why this plan was rewritten

A five-lens audit found the first version's design wrong, not just its details. Both flaws are measured and both fixes are verified:

- **"Needs no observability assumption" was false.** Weight is self-initiated — people measure based on how they feel. Simulated on patients whose physiology never changed, 78% were told their weight was falling when only their weighing habits changed. Fixed by the **measurement-density guard** (Task 6).
- **Mann–Kendall used the wrong null.** It assumes independence; weekly medians only shrink `z` by √(365/53). False-trend rates on trendless series ran 5.5% / 23% / 63.5% as persistence rose — corrected to 5% / 7.5% / 14.5% by **Hamed–Rao** (Task 4), costing power only where the truthful answer is "cannot tell".

The audit also found three of the first plan's service tests failed against a *correct* implementation, four named mutants were inert, the 30-day window was mathematically impossible, and the profile task would have silently disabled age-gated health screening.

## Global Constraints

- **Nothing here touches the evidence engine.** No file under `Evidence/` is modified except by *calling* `SignificanceTester.benjaminiHochbergThreshold` at `EvidenceConfig.default.fdrAlpha`.
- **Windows: 90 and 365 days only, default 90.** The 30-day window is gone — it holds 5 weeks against an 8-week floor and would have been permanently empty. Nothing may choose a window by its result.
- **Window convention, pinned:** `windowEnd = calendar.startOfDay(for: asOf)`, `windowStart = windowEnd - (days - 1) * 86_400`, so `daysInWindow == days` exactly. An off-by-one changes `weeksInWindow` and every coverage fraction, in the direction of admitting thin data.
- **No causal language:** not "because", "caused", "led to", "due to", "linked to", "resulted in".
- **No category names.** No blood-pressure or BMI categories — assigning one is disease classification.
- **Invented constants live in `TrendConfig` and nowhere else**, each commented as unvalidated: the coverage floor (8 weeks, 60%) and the per-series minimum meaningful change. Everything else is derived from data or reused from the engine.
- **Every task ends with `cd HealthGraphCore && swift test` green.** Tasks whose tests live in the app target additionally run `xcodebuild test … -only-testing:"Food IntolerancesTests/<Suite>"` — the package command does not compile that target, so those tests are otherwise never executed.
- **Every test struct declares its own `utc`:** `private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }`. Two suites in the first plan used it without declaring it.
- **Fixtures anchor at exact UTC midnight** (`Date(timeIntervalSince1970: 1_749_945_600)`). Never `Date()`.
- **Pin statistics, not loose thresholds.** `#expect(p < 0.01)` survived three separate mutants in the first plan because both values sat far below it. Assert `z` or `p` to a tolerance.
- **Loops assert their collection is non-empty; string assertions assert non-emptiness.** Otherwise the test passes vacuously.
- Mutation discipline: apply the mutant, confirm the **named** test fails, restore, report both directions. **If a mutant does not kill its test, say so — that is the finding.** Four of the first plan's mutants were inert and two would have reported a false pass.

## File Structure

**Package:** `Trends/WeeklyBucketing.swift`, `Trends/MannKendall.swift`, `Trends/TheilSen.swift`, `Trends/MeasurementDensity.swift`, `Trends/TrendAnalyzer.swift`, `Trends/TrajectorySeries.swift`, `Trends/TrajectoryService.swift`, `Trends/PersonProfile.swift`. Modified: `Timeline/SleepSessionBuilder.swift`, `Ingestion/HealthKitSampleMapper.swift`.

**App:** `Views/HealthOS/Trends/{TrajectoryPresentation,TrajectoriesViewState,TrajectoriesView}.swift`. Modified: `Models/UserProfile.swift`, `Models/HealthKitIngestor.swift`, `Views/HealthOS/Timeline/BodyMetricValueFormatter.swift`, `Views/HealthOS/Health/HealthTabView.swift`.

One responsibility per statistics file, so each can be mutated in isolation. `TrajectoryService` is the only file that knows about both the database and the statistics.

---

### Task 1: Sleep sessions must union overlapping segments

A shipped bug, not a trajectory feature. `SleepSessionBuilder.session(from:)` does `totals[subtype] += duration` and sums the stage totals, with no clamp anywhere.

Two independent ingest paths feed it, and the fix must cover both:

- **Same subtype, overlapping times.** `IngestPipeline` deliberately keeps both ("coverage is never truncated" — its overlap query is scoped by `subtype`), on the assumption a consumer will union them. Nothing does.
- **Different subtypes.** A watch writing `asleepCore`/`asleepDeep`/`asleepREM` and a ring writing `asleepUnspecified` over the same hours never even reach that overlap check — the subtype-scoped query finds nothing to compare, so both insert unconditionally. This is the more common real-world shape, and it is what the Step 1 fixture below exercises. Two sleep trackers produce roughly double the sleep, with no clamp anywhere — nothing prevents a 14-hour night. Functional-medicine and peptide patients are among the likeliest people to wear two, so this is the design partner's exact population.

**Files:** Modify `HealthGraphCore/Sources/HealthGraphCore/Timeline/SleepSessionBuilder.swift`; extend `HealthGraphCore/Tests/HealthGraphCoreTests/SleepSessionBuilderTests.swift`.

- [ ] **Step 1: Write the failing tests**

```swift
    private static let t0 = Date(timeIntervalSince1970: 1_749_945_600)
    private func seg(_ subtype: String, _ fromHour: Double, _ toHour: Double) -> HealthEvent {
        let base = Self.t0.addingTimeInterval(23 * 3600)          // 23:00
        var e = HealthEvent(timestamp: base.addingTimeInterval(fromHour * 3600), category: .sleep,
                            subtype: subtype, value: (toHour - fromHour) * 3600, unit: "s",
                            source: .healthKit)
        e.endTimestamp = base.addingTimeInterval(toHour * 3600)
        return e
    }

    @Test func twoTrackersRecordingTheSameNightDoNotDoubleIt() {
        // A watch and a ring both record the same 8 hours. Ranked equally,
        // IngestPipeline keeps both on purpose. Summing them says 16.
        let watch = [seg("asleepCore", 0, 4), seg("asleepDeep", 4, 6), seg("asleepREM", 6, 8)]
        let ring  = [seg("asleepUnspecified", 0, 8)]
        let sessions = SleepSessionBuilder.sessions(from: watch + ring, timeZone: utcZone)
        #expect(sessions.count == 1)
        #expect(abs(sessions[0].asleepMinutes - 480) < 1)          // 8 h, not 16
    }

    @Test func asleepTimeNeverExceedsTheSessionsOwnSpan() {
        // The invariant that makes the above unfixable-by-accident: you cannot be
        // asleep longer than the night lasted, whatever the sources claim.
        let sources = [seg("asleepCore", 0, 8), seg("asleepDeep", 0, 8), seg("asleepREM", 0, 8)]
        let s = SleepSessionBuilder.sessions(from: sources, timeZone: utcZone)[0]
        #expect(s.asleepMinutes <= s.end.timeIntervalSince(s.start) / 60 + 1)
    }

    @Test func adjacentNonOverlappingStagesStillSum() {
        // The guard against over-correcting: an ordinary single-device night,
        // stages back to back, must be unchanged.
        let watch = [seg("asleepCore", 0, 4), seg("asleepDeep", 4, 6), seg("asleepREM", 6, 8)]
        #expect(abs(SleepSessionBuilder.sessions(from: watch, timeZone: utcZone)[0].asleepMinutes - 480) < 1)
    }
```

- [ ] **Step 2: Run to verify they fail, then implement**

Collect `(start, end)` for every asleep-stage segment, sort by start, merge overlapping intervals, and derive `asleepMinutes` from the merged total, clamped to the session's own span. Keep the per-stage totals for display but document that they are approximate when sources overlap — do not silently present a doubled stage breakdown alongside a corrected total.

- [ ] **Step 3: Check the blast radius, and do not absorb it**

`asleepMinutes` feeds `ShortSleepExposureSource` in the evidence engine and the Timeline sleep row. Run the full package suite and report any existing test whose expectations move. **Do not edit an existing test to accommodate this change** — a shifted sleep total can change a mined relationship, and that is the controller's call, not the implementer's.

Audited: no existing fixture in `SleepSessionBuilderTests`, `TimelineDayBuilderTests`, `ExposureSourceTests` or `TimelineViewModelTests` contains two overlapping *asleep-stage* segments — the one named `overlappingSegmentsChainByFurthestEnd` overlaps `inBed` with `asleepCore`, and `inBed` is excluded from `asleepMinutes` by definition. So the expectation is that nothing existing moves. If something does, that is a finding.

**The user-visible consequence is a product question this plan does not answer.** A two-tracker user's nights were being doubled, so short-sleep nights looked long and `ShortSleepExposureSource` never flagged them. After the fix they flag — and `InsightsRefreshCoordinator` recomputes silently on the next app open, so new sleep-linked relationships can appear, and existing ones shift, with no in-app signal. The affected population is precisely the one named above. Whether that warrants any user-facing note is the controller's call; **record the decision rather than letting it happen by default.**

- [ ] **Step 4: Mutants**

1. Sum durations without unioning → `twoTrackersRecordingTheSameNightDoNotDoubleIt` fails.
2. Drop the span clamp → `asleepTimeNeverExceedsTheSessionsOwnSpan` fails.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix(sleep): union overlapping segments before totalling asleep time"
```

---

### Task 2: Capture the HealthKit source at ingest

`HKSource`, `HKSourceRevision`, `HKDevice` and `bundleIdentifier` appear nowhere in the codebase; `mapSample` keeps only value, timestamp, unit and timezone, and every HealthKit row collapses to `EventSource.healthKit`. A new watch that shifts the HRV baseline, or a second scale reading 1.5 kg differently, is therefore **undetectable** — permanently, for data already ingested.

This round only **stores** it. Using it is a later round.

**Be precise about what that buys, because the plan's first draft overstated it.** `HealthKitIngestor` reads through `HKAnchoredObjectQuery` with the anchor persisted per sample type in `UserDefaults`. An anchored query only redelivers samples added or changed *since* the anchor — so for any user who has already synced, historical samples are **never** redelivered and will carry no source identifier **permanently**, not merely "not yet". This captures source for new samples only.

That is still worth doing — it is the difference between a device-change detector being possible in six months and being impossible forever — but a later round consuming this data must expect nil across all pre-existing history. **Raise as a decision for the controller:** a one-time anchor reset for the per-sample types (weight, HRV, resting HR, respiratory rate) would re-ingest history *with* source, and `IngestPipeline` dedups by key so re-ingest updates in place rather than duplicating. It costs a long re-read. Do not do it as part of this task; report the trade-off.

**Files:** Modify `Models/HealthKitIngestor.swift` and `HealthGraphCore/Sources/HealthGraphCore/Ingestion/HealthKitSampleMapper.swift`; test `HealthGraphCoreTests/HealthKitSampleMapperTests.swift`.

- [ ] **Step 1: Decide where it goes, and record the reasoning**

`HealthEvent.metadata` is an existing `Data?` blob with an encoder already used for routes and cycle metadata. Prefer it: no migration risk, and nothing in this round queries by source. If you conclude a column is genuinely required, **stop and report** rather than adding one — this repo's SwiftData migration tests already crash the runner and schema changes are not free here.

- [ ] **Step 2: Write the failing test, implement, run**

Thread `HKSource.bundleIdentifier` (and `HKDevice.name` when present) through the sample-data structs the mapper already accepts, so the mapper stays testable without HealthKit present.

**Keep it a flat `[String: String]`.** Every metadata consumer in the codebase decodes `[String: String]` and reads its own key, so an added string key is invisible to all of them. Nesting a sub-object instead would make that row's metadata fail to decode for *every* existing consumer — all-or-nothing per row.

```swift
    @Test func theRecordingSourceIsPreserved() {
        // Not used yet. Stored so that when two devices disagree, the difference
        // is recoverable instead of permanently invisible.
        let event = HealthKitSampleMapper.map(sample(bundleID: "com.oura.health"))!
        #expect(HealthKitSampleMapper.sourceBundleID(of: event) == "com.oura.health")
    }

    @Test func anAbsentSourceIsNotAnError() {
        // Older samples and some writers carry none; ingestion must not drop them.
        let event = HealthKitSampleMapper.map(sample(bundleID: nil))
        #expect(event != nil)
        #expect(HealthKitSampleMapper.sourceBundleID(of: event!) == nil)
    }
```

- [ ] **Step 3: Mutant** — drop the field at map time → `theRecordingSourceIsPreserved` fails.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(ingest): capture the HealthKit source identifier"
```

---

### Task 3: Weekly bucketing, counts and coverage

**Files:** Create `HealthGraphCore/Sources/HealthGraphCore/Trends/WeeklyBucketing.swift`; test `HealthGraphCore/Tests/HealthGraphCoreTests/WeeklyBucketingTests.swift`.

**Interfaces:** `DailyPoint(day:value:)`, `WeeklyPoint(weekIndex:value:dayCount:)`, `SeriesCoverage(daysWithData:daysInWindow:weeksWithData:weeksInWindow:)`, `WeeklyBucketing.bucket(_:windowStart:windowEnd:calendar:) -> (weeks: [WeeklyPoint], coverage: SeriesCoverage)`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct WeeklyBucketingTests {
    private static let t0 = Date(timeIntervalSince1970: 1_749_945_600)   // exact UTC midnight
    private func day(_ n: Int) -> Date { Self.t0.addingTimeInterval(Double(n) * 86_400) }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    @Test func aWeekIsSevenDaysFromTheWindowStart() {
        // Anchored to the window, NOT ISO weeks: the same data analysed on two
        // different days must land in the same buckets, or a trend changes shape
        // with the clock.
        let daily = (0..<14).map { DailyPoint(day: day($0), value: Double($0)) }
        let out = WeeklyBucketing.bucket(daily, windowStart: day(0), windowEnd: day(13), calendar: utc)
        #expect(out.weeks.count == 2)
        #expect(out.weeks[0].value == 3.0)       // median of 0...6
        #expect(out.weeks[1].value == 10.0)      // median of 7...13
    }

    @Test func aWeeksValueIsItsMedianNotItsMean() {
        // One bad reading — a different scale, a suitcase — must not move the week.
        let daily = [DailyPoint(day: day(0), value: 70), DailyPoint(day: day(1), value: 70.5),
                     DailyPoint(day: day(2), value: 71), DailyPoint(day: day(3), value: 200)]
        let out = WeeklyBucketing.bucket(daily, windowStart: day(0), windowEnd: day(6), calendar: utc)
        #expect(out.weeks[0].value == 70.75)     // median, not the mean of 102.9
    }

    @Test func emptyWeeksAreAbsentNotZero() {
        // A week with no readings is missing data. Emitting 0 makes a gap look
        // like a crash to the floor — the worst rendering error available here.
        let daily = [DailyPoint(day: day(0), value: 70), DailyPoint(day: day(20), value: 71)]
        let out = WeeklyBucketing.bucket(daily, windowStart: day(0), windowEnd: day(27), calendar: utc)
        #expect(out.weeks.map(\.weekIndex) == [0, 2])
        #expect(!out.weeks.contains { $0.value == 0 })
    }

    @Test func multipleReadingsOnOneDayCollapseToThatDaysMedianFirst() {
        // Three weigh-ins on Monday must not out-vote the other six days.
        let daily = [DailyPoint(day: day(0), value: 70), DailyPoint(day: day(0), value: 72),
                     DailyPoint(day: day(0), value: 74), DailyPoint(day: day(1), value: 80)]
        let out = WeeklyBucketing.bucket(daily, windowStart: day(0), windowEnd: day(6), calendar: utc)
        #expect(out.coverage.daysWithData == 2)   // two days, not four readings
        #expect(out.weeks[0].value == 76.0)       // median of [72, 80]
    }

    @Test func dayCountIsPerWeekAndDrivesTheDensityGuard() {
        // Task 6 tests measurement frequency using this number; if it counted
        // readings rather than days, three weigh-ins on one day would read as
        // three days of engagement.
        let daily = (0..<3).flatMap { d in (0..<4).map { _ in DailyPoint(day: day(d), value: 70) } }
        let out = WeeklyBucketing.bucket(daily, windowStart: day(0), windowEnd: day(6), calendar: utc)
        #expect(out.weeks[0].dayCount == 3)
    }

    @Test func theWindowIsExactlyTheDaysAskedFor() {
        // An off-by-one changes weeksInWindow and every coverage fraction
        // downstream, silently, in the direction of admitting thin data.
        let out = WeeklyBucketing.bucket([], windowStart: day(-89), windowEnd: day(0), calendar: utc)
        #expect(out.coverage.daysInWindow == 90)
        #expect(out.coverage.weeksInWindow == 13)      // ceil(90 / 7)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement**

```swift
public enum WeeklyBucketing {
    /// Seven-day buckets anchored at `windowStart`, in the supplied calendar.
    ///
    /// Two levels of median, both load-bearing: readings on one day collapse to
    /// that day's median first, then the week is the median of its day medians.
    /// `dayCount` counts DAYS, not readings — the density guard reads it.
    public static func bucket(_ daily: [DailyPoint], windowStart: Date, windowEnd: Date,
                              calendar: Calendar) -> (weeks: [WeeklyPoint], coverage: SeriesCoverage) {
        let start = calendar.startOfDay(for: windowStart), end = calendar.startOfDay(for: windowEnd)
        let daysInWindow = max(0, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        let weeksInWindow = Int(ceil(Double(daysInWindow) / 7.0))

        var byDay: [Date: [Double]] = [:]
        for p in daily {
            let d = calendar.startOfDay(for: p.day)
            guard d >= start, d <= end else { continue }
            byDay[d, default: []].append(p.value)
        }
        var byWeek: [Int: [Double]] = [:]
        for (d, values) in byDay {
            let offset = calendar.dateComponents([.day], from: start, to: d).day ?? 0
            byWeek[offset / 7, default: []].append(median(values))
        }
        let weeks = byWeek.keys.sorted().map {
            WeeklyPoint(weekIndex: $0, value: median(byWeek[$0]!), dayCount: byWeek[$0]!.count)
        }
        return (weeks, SeriesCoverage(daysWithData: byDay.count, daysInWindow: daysInWindow,
                                      weeksWithData: weeks.count, weeksInWindow: weeksInWindow))
    }
}

/// Median of a non-empty list; even counts average the middle pair.
func median(_ xs: [Double]) -> Double {
    precondition(!xs.isEmpty)
    let s = xs.sorted(); let m = s.count / 2
    return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
}
```

- [ ] **Step 4: Mutants**

1. Mean instead of median per week → `aWeeksValueIsItsMedianNotItsMean` fails.
2. Emit zero-valued weeks for gaps → `emptyWeeksAreAbsentNotZero` fails.
3. Skip the per-day median → `multipleReadingsOnOneDayCollapseToThatDaysMedianFirst` fails.
4. `windowStart = windowEnd - days * 86_400` → `theWindowIsExactlyTheDaysAskedFor` fails.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(trends): weekly bucketing with counts and coverage"
```

---

### Task 4: Mann–Kendall with the Hamed–Rao correction

The statistical fix. Mann–Kendall assumes independent observations; health series are not. Weekly medians only shrink `z` by √(365/53), leaving false-trend rates of 23% (sticky) and 63.5% (near random walk) on series with **no** real trend.

**Files:** Create `Trends/MannKendall.swift`; test `MannKendallTests.swift`.

**Interfaces:** `MannKendallResult(s:variance:z:pValue:)`, `MannKendall.test(_:minimumPoints:) -> MannKendallResult?` returning an **already-inflated** variance so no caller can forget it, plus `MannKendall.uncorrectedVariance(_:) -> Double` for the tests.

- [ ] **Step 1: Write the failing tests**

Generate the two AR(1) fixtures once from a seeded process and **paste the resulting literal arrays into the test file** — deterministic and reviewable, rather than re-running a random process at test time.

```swift
    @Test func aStrictlyRisingSeriesIsSignificant() {
        let r = MannKendall.test((0..<12).map(Double.init))!
        #expect(r.s == 66)                                   // all 66 pairs concordant
        #expect(r.pValue < 0.01)
    }

    @Test func aFlatSeriesIsNotSignificant() {
        let r = MannKendall.test(Array(repeating: 5.0, count: 12))!
        #expect(r.s == 0)
        #expect(r.pValue > 0.9)
    }

    @Test func tiesReduceTheVarianceRatherThanBeingIgnored() {
        // Pinned on z, not on a p threshold. Dropping the tie term moves z from
        // 3.7666 to 3.6344 and BOTH stay under 0.01 — the first plan's version of
        // this test was verified inert for exactly that reason.
        let r = MannKendall.test([1,1,1,2,2,2,3,3,3,4,4,4])!
        #expect(abs(r.z - 3.7666) < 1e-3)
    }

    @Test func aPersistentSeriesWithNoTrendIsNotCalledATrend() {
        // Hamed-Rao, load-bearing. Measured: plain Mann-Kendall false-trends on
        // 23% of sticky series and 63.5% of near-random-walks; corrected, 7.5%
        // and 14.5%.
        let r = MannKendall.test(Self.stickyNoTrend)!            // pasted AR(1), phi 0.9
        #expect(r.pValue > 0.05)
        #expect(r.variance > MannKendall.uncorrectedVariance(Self.stickyNoTrend) * 1.5)
    }

    @Test func anIndependentSeriesIsBarelyTouchedByTheCorrection() {
        // The guard against over-correcting into uselessness: with no serial
        // dependence the inflation factor is ~1 and power is unchanged.
        let r = MannKendall.test(Self.independentRising)!
        let inflation = r.variance / MannKendall.uncorrectedVariance(Self.independentRising)
        #expect(abs(inflation - 1) < 0.25)
        #expect(r.pValue < 0.05)
    }

    @Test func tooFewPointsReturnNil() {
        // nil is "we did not test", which is not the same answer as "we tested
        // and found nothing". Callers must not conflate them.
        #expect(MannKendall.test([1,2,3,4,5,6,7]) == nil)
        #expect(MannKendall.test((0..<8).map(Double.init)) != nil)
    }
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement**

S and the tie-corrected variance as standard:

```
Var(S) = [ n(n-1)(2n+5) − Σ_t t(t-1)(2t+5) ] / 18
```

Then Hamed & Rao (1998): rank the values, compute the ranks' lag-k autocorrelation `r_k`, keep only those with `|r_k| > 1.96/√n`, and inflate:

```
n/n* = 1 + (2 / (n(n-1)(n-2))) · Σ_k (n-k)(n-k-1)(n-k-2) · r_k
variance *= max(n/n*, tiny)
```

Continuity-correct `z` (`(S∓1)/√variance`), and take the two-sided tail as `erfc(|z| / √2)`. `erfc` comes from Foundation — precedent: `SignificanceTester` already uses `lgamma` with no extra import.

Document the residual limit in the doc comment: for a near-random-walk series this still over-rejects at roughly 14% *and* loses most of its power, so for such a series the truthful answer is that drift and trend cannot be separated.

- [ ] **Step 4: Mutants**

1. Drop the tie term → `tiesReduceTheVarianceRatherThanBeingIgnored` fails (z 3.7666 → 3.6344).
2. Skip the Hamed–Rao inflation → `aPersistentSeriesWithNoTrendIsNotCalledATrend` fails.
3. Inflate unconditionally, ignoring the `|r_k| > 1.96/√n` filter → `anIndependentSeriesIsBarelyTouchedByTheCorrection` fails.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(trends): Mann-Kendall with Hamed-Rao variance correction"
```

---

### Task 5: Theil–Sen slope and Sen confidence interval

A point estimate with no interval is what a clinician discounts, correctly.

**Files:** Create `Trends/TheilSen.swift`; test `TheilSenTests.swift`.

**Interfaces:** `TheilSen.slope(x:y:) -> Double?`, `TheilSen.interval(x:y:variance:alpha:) -> (lower: Double, upper: Double)?`

- [ ] **Step 1: Write the failing tests**

```swift
    @Test func recoversAKnownSlope() {
        let x = (0..<12).map(Double.init)
        #expect(abs(TheilSen.slope(x: x, y: x.map { 70 + 0.5 * $0 })! - 0.5) < 1e-9)
    }

    @Test func survivesOutliersThatWouldBreakLeastSquares() {
        // The reason for choosing this estimator: one catastrophic reading must
        // not become a trend.
        var y = (0..<12).map { 70 + 0.5 * Double($0) }
        y[6] = 400
        #expect(abs(TheilSen.slope(x: (0..<12).map(Double.init), y: y)! - 0.5) < 0.2)
    }

    @Test func handlesGapsInX() {
        // Weeks are indices and missing weeks are absent, so x is not contiguous.
        let x: [Double] = [0, 1, 2, 5, 6, 9]
        #expect(abs(TheilSen.slope(x: x, y: x.map { 100 - 2 * $0 })! + 2) < 1e-9)
    }

    @Test func twoPointsAreEnoughAndOneIsNot() {
        // The first plan asserted only the nil case, which a mutated
        // `count >= 3` also satisfies.
        #expect(TheilSen.slope(x: [0, 1], y: [0, 5]) == 5)
        #expect(TheilSen.slope(x: [1], y: [2]) == nil)
        #expect(TheilSen.slope(x: [0,1,2], y: [0,1]) == nil)     // mismatched lengths
    }

    @Test func theIntervalBracketsTheSlopeAndNarrowsWithMoreData() {
        let short = TheilSen.interval(x: xs(12), y: ys(12, slope: -0.5), variance: v(12), alpha: 0.05)!
        #expect(short.lower < -0.5 && short.upper > -0.5)
        let long = TheilSen.interval(x: xs(52), y: ys(52, slope: -0.5), variance: v(52), alpha: 0.05)!
        #expect((long.upper - long.lower) < (short.upper - short.lower))
    }
```

- [ ] **Step 2: Run, then implement**

Slope: median of all pairwise slopes, skipping equal x. Interval: with `N` pairwise slopes sorted and `C = 1.96 · √variance`, take the bounds at ranks `(N − C)/2` and `(N + C)/2`, clamped into range.

- [ ] **Step 3: Mutants**

1. Least squares instead of the median → `survivesOutliersThatWouldBreakLeastSquares` fails.
2. A fixed ±10% interval instead of the rank-based one → `theIntervalBracketsTheSlopeAndNarrowsWithMoreData` fails.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(trends): Theil-Sen slope with Sen confidence interval"
```

---

### Task 6: The measurement-density guard

The fix for the audit's sharpest finding. Weight is self-initiated: people measure based on how they feel. Simulated on patients whose physiology never changed, changing only measurement habits across the window produced "falling" for 78% (weight), 60% (systolic) and 52% (sleep). The guard suppressed 97–100% of those artefacts while preserving 96% of a genuine 6 kg loss.

**Files:** Create `Trends/MeasurementDensity.swift`; test `MeasurementDensityTests.swift`.

**Interfaces:** `MeasurementDensity.isConfounded(weeks:) -> Bool` — runs the same corrected Mann–Kendall over each week's `dayCount`. Confounded when the value trends **and** the measurement frequency trends.

- [ ] **Step 1: Write the failing tests**

```swift
    @Test func aValueTrendThatTracksAMeasurementTrendIsConfounded() {
        // The failure this exists for: an apparent decline produced entirely by
        // measuring less often, and measuring differently when you do.
        let weeks = (0..<52).map { i in
            WeeklyPoint(weekIndex: i, value: 90 - 0.05 * Double(i), dayCount: max(1, 7 - i / 8))
        }
        #expect(MeasurementDensity.isConfounded(weeks: weeks))
    }

    @Test func aValueTrendWithSteadyMeasurementIsNotConfounded() {
        // Must not suppress a real finding from a consistent logger.
        let weeks = (0..<52).map { i in
            WeeklyPoint(weekIndex: i, value: 90 - 0.05 * Double(i), dayCount: 7)
        }
        #expect(!MeasurementDensity.isConfounded(weeks: weeks))
    }

    @Test func measurementTrendAloneIsNotConfounding() {
        // Someone who starts weighing more often at a stable weight has a density
        // trend and no value trend. There is nothing to suppress.
        let weeks = (0..<52).map { i in
            WeeklyPoint(weekIndex: i, value: 90 + [0.1, -0.1, 0.05, -0.05][i % 4],
                        dayCount: min(7, 1 + i / 8))
        }
        #expect(!MeasurementDensity.isConfounded(weeks: weeks))
    }
```

- [ ] **Step 2: Run, implement, run**

- [ ] **Step 3: Mutants**

1. Always return false → `aValueTrendThatTracksAMeasurementTrendIsConfounded` fails.
2. Confound on the density trend alone → `measurementTrendAloneIsNotConfounding` fails.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(trends): suppress trends confounded with measurement frequency"
```

---

### Task 7: `TrendAnalyzer` — the gates

**Files:** Create `Trends/TrendAnalyzer.swift`; test `TrendAnalyzerTests.swift`.

**Interfaces:** `TrendConfig`, `TrendMeasurement` (slopePerWeek, changeOverWindow, interval, firstWeekValue, lastWeekValue, pValue, coverage, weeks, isDensityConfounded), `TrendAnalyzer.measure(weeks:coverage:series:config:) -> TrendMeasurement?`

Returns a measurement with **no direction**. Direction is assigned in Task 9 after Benjamini–Hochberg; assigning it here applies an uncorrected threshold and defeats the correction.

`TrendConfig` carries the unvalidated constants, each commented as such: `minimumWeeksWithData = 8`, `minimumWeekCoverage = 0.6`, and `minimumMeaningfulChange(for:)` — weight 2.0 kg, sleep 0.5 h, steps 1000, resting HR 3 bpm, HRV 5 ms, respiratory rate 1.0 breaths/min. Placeholders chosen to exceed device-to-device disagreement; they must be revisited against real data, and the config says so.

- [ ] **Step 1: Write the failing tests**

```swift
    @Test func aStatisticallySignificantButTrivialChangeIsFlaggedTooSmall() {
        // The effect-size floor. 52 weekly points make a 1 kg annual change
        // detectable and meaningless — inside two bathroom scales' disagreement.
        // EvidenceConfig's own comment explains why significance is not enough.
        let weeks = (0..<52).map { WeeklyPoint(weekIndex: $0, value: 90 - 0.019 * Double($0), dayCount: 7) }
        let m = TrendAnalyzer.measure(weeks: weeks, coverage: full(52), series: .weight, config: .default)!
        #expect(m.pValue < 0.05)                                            // it IS significant
        #expect(abs(m.changeOverWindow) < TrendConfig.default.minimumMeaningfulChange(for: .weight))
    }

    @Test func theWeekFloorIsSeparateFromTheTestsOwnMinimum() {
        // The first plan's version could not distinguish these: both fire at 7
        // points, so deleting the coverage guard changed nothing.
        let weeks = (0..<10).map { WeeklyPoint(weekIndex: $0, value: Double($0), dayCount: 7) }
        var cfg = TrendConfig.default; cfg.minimumWeeksWithData = 12
        #expect(TrendAnalyzer.measure(weeks: weeks, coverage: full(10), series: .weight, config: cfg) == nil)
        #expect(TrendAnalyzer.measure(weeks: weeks, coverage: full(10), series: .weight, config: .default) != nil)
    }

    @Test func belowTheCoverageFractionThereIsNoMeasurement() {
        // 8 weeks inside a 52-week window is 15% coverage: enough points to
        // compute something, nowhere near enough to describe the year.
        let sparse = SeriesCoverage(daysWithData: 8, daysInWindow: 364, weeksWithData: 8, weeksInWindow: 52)
        #expect(TrendAnalyzer.measure(weeks: weeks(8), coverage: sparse, series: .weight, config: .default) == nil)
    }

    @Test func slopeIsPerWeekAndChangeIsAcrossTheObservedSpan() {
        let m = TrendAnalyzer.measure(weeks: weeks((0..<12).map { 70 + 0.5 * Double($0) }),
                                      coverage: full(12), series: .weight, config: .default)!
        #expect(abs(m.slopePerWeek - 0.5) < 1e-9)
        #expect(abs(m.changeOverWindow - 5.5) < 1e-9)      // 0.5 × 11 spans, not × 12
    }

    @Test func aFlatNoisySeriesIsNotSignificantAndStillExercisesTheVariance() {
        // The first plan's fixture gave S == 0 exactly, hitting the `else { z = 0 }`
        // branch — so it never touched the variance, tie or Hamed-Rao paths at
        // all, while being billed as the primary guard. This one has small
        // non-zero S.
        let m = TrendAnalyzer.measure(weeks: weeks(Self.flatNoisyWithSmallS),
                                      coverage: full(12), series: .weight, config: .default)!
        #expect(m.pValue > 0.05)
        #expect(m.pValue < 0.99)                            // the variance path really ran
    }
```

- [ ] **Step 2: Run, implement, run**

Gate order: coverage floor → Mann–Kendall and Theil–Sen → density guard (Task 6) recorded on the measurement → effect size compared against the series' minimum.

- [ ] **Step 3: Mutants**

1. Drop the coverage-fraction guard → `belowTheCoverageFractionThereIsNoMeasurement` fails.
2. `changeOverWindow = slopePerWeek` → `slopeIsPerWeekAndChangeIsAcrossTheObservedSpan` fails.
3. Multiply by `coverage.weeksInWindow` rather than the observed span → same test fails.
4. Drop the effect-size floor → `aStatisticallySignificantButTrivialChangeIsFlaggedTooSmall` fails.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(trends): coverage, effect-size and density gates"
```

---

### Task 8: Series catalog and extraction

**Files:** Create `Trends/TrajectorySeries.swift`; test `TrajectorySeriesTests.swift`.

Six series: `weight`, `sleepDuration`, `steps`, `restingHeartRate`, `hrv`, `respiratoryRate`. **No blood pressure** — it is self-initiated, was the most dangerous case in simulation, and a median of arbitrary cuff readings is not a clinical measure (see the spec). Public `category`, `subtype`, `unit`, `displayName`, `dailyPoints(from:calendar:)`.

Subtypes come from `HealthKitSampleMapper`'s existing tables — read that file rather than retyping them.

- [ ] **Step 1: Write the failing tests** (declare `utc` in the struct — the first plan referenced it without defining it)

```swift
    @Test func weightIsReadFromBodyMetricEvents() {
        let e = HealthEvent(timestamp: Self.t0.addingTimeInterval(8 * 3600), category: .bodyMetric,
                            subtype: "weight", value: 70.5, unit: "kg", source: .healthKit)
        let points = TrajectorySeries.weight.dailyPoints(from: [e], calendar: utc)
        #expect(points.count == 1)
        #expect(points[0].value == 70.5)
    }

    @Test func sleepUsesNightSessionsAndIsAttributedToTheWakingDay() {
        // A night starting 23:00 Monday and ending 07:00 Tuesday is TUESDAY's
        // sleep — attributing it to Monday shifts every night by one.
        var asleep = HealthEvent(timestamp: Self.t0.addingTimeInterval(23 * 3600), category: .sleep,
                                 subtype: "asleepCore", value: 8 * 3600, unit: "s", source: .healthKit)
        let wake = Self.t0.addingTimeInterval(31 * 3600)
        asleep.endTimestamp = wake
        let points = TrajectorySeries.sleepDuration.dailyPoints(from: [asleep], calendar: utc)
        #expect(points[0].day == utc.startOfDay(for: wake))
        #expect(abs(points[0].value - 8.0) < 0.01)          // hours, not minutes
    }

    @Test func aSeriesReadsOnlyItsOwnSubtype() {
        // restingHeartRate and heartRate share a unit; reading both would average
        // a resting rate with exercise peaks.
        let events = [HealthEvent(timestamp: Self.t0, category: .vitals, subtype: "heartRate",
                                  value: 150, unit: "bpm", source: .healthKit),
                      HealthEvent(timestamp: Self.t0, category: .vitals, subtype: "restingHeartRate",
                                  value: 58, unit: "bpm", source: .healthKit)]
        let points = TrajectorySeries.restingHeartRate.dailyPoints(from: events, calendar: utc)
        #expect(points.count == 1)
        #expect(points[0].value == 58)
    }

    @Test func deletedEventsAreExcluded() {
        var deleted = HealthEvent(timestamp: Self.t0.addingTimeInterval(8 * 3600), category: .bodyMetric,
                                  subtype: "weight", value: 70.5, unit: "kg", source: .healthKit)
        deleted.deletedAt = Self.t0.addingTimeInterval(9 * 3600)
        #expect(TrajectorySeries.weight.dailyPoints(from: [deleted], calendar: utc).isEmpty)
    }

    @Test func theCatalogIsExactlyTheSixSeriesWeSupport() {
        // Also protects Task 9's BH arithmetic, where m is the catalog size, and
        // stops the copy sweep in Task 12 passing over an empty collection.
        #expect(TrajectorySeries.allCases.count == 6)
        #expect(!TrajectorySeries.allCases.contains { $0.displayName.isEmpty || $0.unit.isEmpty })
        #expect(!TrajectorySeries.allCases.contains { "\($0)".localizedCaseInsensitiveContains("bloodPressure") })
    }
```

- [ ] **Step 2: Run, implement, run**

Weight, HR, HRV and respiratory rate are direct `(category, subtype)` reads. Steps are already daily-aggregated on ingest — read, do not re-aggregate. Sleep goes through `SleepSessionBuilder.sessions(from:timeZone:)` (with Task 1's union), filtered to `kind == .night`, value `asleepMinutes / 60`, attributed to the start-of-day of the session **end**. Read sleep events from one day before `windowStart`, or a night spanning the boundary loses its earlier segments.

- [ ] **Step 3: Mutants**

1. Attribute sleep to the session start → `sleepUsesNightSessionsAndIsAttributedToTheWakingDay` fails.
2. Match on category only → `aSeriesReadsOnlyItsOwnSubtype` fails.
3. Stop filtering `deletedAt` → `deletedEventsAreExcluded` fails.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(trends): series catalog and extraction"
```

---

### Task 9: `TrajectoryService` — one read, one correction

**Files:** Create `Trends/TrajectoryService.swift`; test `TrajectoryServiceTests.swift`.

**Interfaces:**

```swift
public enum TrendWindow: Int, CaseIterable, Sendable { case days90 = 90, days365 = 365 }
public enum TrendDirection: String, Sendable { case rising, falling, noClearChange }

/// A measured series with its verdict. A VALUE, not a rendered string: the
/// doctor-report round renders these rather than recomputing them.
public struct Trajectory: Sendable {
    public enum Suppression: Sendable { case notSignificant, tooSmall, densityConfounded }
    public let series: TrajectorySeries
    public let window: TrendWindow
    public let direction: TrendDirection
    public let suppression: Suppression?      // why there is no direction, when there isn't
    public let measurement: TrendMeasurement
}

public struct TrajectoryService: Sendable {
    public init(eventStore: any EventStore, config: TrendConfig = .default)
    public func trajectories(window: TrendWindow, asOf: Date) async throws -> [Trajectory]
}
```

**One `eventStore.events(in:category:)` call**, shared across all series — not a per-series loop. Four of the six series share `.vitals`, so a per-series read re-fetches the same rows four times: the N+1 shape this repo already paid ~6.9s per ten Insights cards to fix, and which `EvidenceContext` exists to prevent.

- [ ] **Step 1: Write the tests**

Every one of the first plan's four tests here was defective — three failed against a correct implementation and two mutants were inert.

```swift
    @Test func theCorpusIsReadOnceRegardlessOfSeriesCount() {
        // The N+1 guard, following InsightsViewModelTests exactly: asserted by
        // CALL COUNT, not elapsed time, so a regression says what broke.
        let counting = CountingEventStore(wrapping: store)
        _ = try await TrajectoryService(eventStore: counting).trajectories(window: .days365, asOf: Self.now)
        #expect(counting.calls.value == 1)
    }

    @Test func theBenjaminiHochbergThresholdIsActuallyApplied() {
        // Pins the correction directly rather than hoping a flat series crosses
        // 0.05 by luck: the first plan's version depended on a seed lottery and
        // its mutant discriminated in only 2 of 8 seed blocks.
        let results = try await service(allSeriesFixture).trajectories(window: .days365, asOf: Self.now)
        #expect(!results.isEmpty)
        #expect(service.lastThreshold == SignificanceTester.benjaminiHochbergThreshold(
            pValues: results.map(\.measurement.pValue), alpha: EvidenceConfig.default.fdrAlpha))
        #expect(service.lastThreshold <= EvidenceConfig.default.fdrAlpha)
    }

    @Test func aSeriesBelowTheFloorIsAbsentWhileOthersSurvive() {
        // Co-seeded so it cannot pass over an empty result — the first plan
        // asserted `!contains` against `[]`, which any failure satisfies.
        let results = try await service(hrv42Days + weight365Days)
            .trajectories(window: .days365, asOf: Self.now)
        #expect(results.map(\.series) == [.weight])
    }

    @Test func aConfoundedSeriesGetsNoDirectionAndSaysWhy() {
        // End-to-end for Task 6: a weight series whose decline tracks a decline
        // in weighing frequency.
        let r = try await service(weightWithFadingMeasurement)
            .trajectories(window: .days365, asOf: Self.now).first { $0.series == .weight }!
        #expect(r.direction == .noClearChange)
        #expect(r.suppression == .densityConfounded)
    }

    @Test func theDefaultNinetyDayWindowWorks() {
        // Untested in the first plan — the only window both reachable and uncovered.
        let results = try await service(weight365Days).trajectories(window: .days90, asOf: Self.now)
        #expect(!results.isEmpty)
    }

    @Test func aRandomWalkIsStillOftenReportedAsATrend_knownLimit() {
        // HONEST characterization, replacing an assertion that was simply false.
        // Weekly-bucketed Mann-Kendall calls ~79% of zero-mean random walks a
        // trend; Hamed-Rao reduces but does not eliminate this. Pinned so that
        // adding pre-whitening later breaks this loudly rather than silently.
        let r = try await service(seededRandomWalk).trajectories(window: .days365, asOf: Self.now)
        #expect(r.count == 1)     // it IS measured; the limitation is what it says
    }
```

- [ ] **Step 2: Run, implement, run**

For each series: extract daily points from the single shared array, bucket, measure. Collect the measurements, run `SignificanceTester.benjaminiHochbergThreshold` over their p-values at `EvidenceConfig.default.fdrAlpha`, then assign direction — `.rising`/`.falling` only when the p-value clears the threshold **and** the effect exceeds the series minimum **and** density is not confounded. Otherwise `.noClearChange` with the matching `Suppression`. Series with no measurement are omitted entirely.

- [ ] **Step 3: Mutants**

1. One read per series → `theCorpusIsReadOnceRegardlessOfSeriesCount` fails.
2. Judge each series at `fdrAlpha` with no correction → `theBenjaminiHochbergThresholdIsActuallyApplied` fails.
3. Skip the density guard → `aConfoundedSeriesGetsNoDirectionAndSaysWhy` fails.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(trends): trajectory service, one read and one correction"
```

---

### Task 10: Profile — derived age with a safety fallback

**The first plan would have disabled age-gated health screening.** `profile.age` drives `HealthMonitoringService` (cholesterol at 40+, blood sugar at 45+), and `dateOfBirth` is **never populated by any UI** — so deriving age purely from DOB returns nil for every existing user and silently switches that surface off.

**Files:** Create `Trends/PersonProfile.swift`; modify `Models/UserProfile.swift`, `Models/HealthKitIngestor.swift`; test `Food IntolerancesTests/PersonProfileTests.swift`.

- [ ] **Step 1: Write the failing tests**

Table-driven. The first plan's two fixtures were passed by *both* its named mutants — `/365.25` disagrees with the correct answer on only 0.07% of birth dates and neither fixture was among them.

```swift
struct PersonProfileTests {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private static let asOf = Date(timeIntervalSince1970: 1_749_945_600)   // 2025-06-15 UTC

    @Test func ageIsDerivedFromDateOfBirthAcrossTheBoundaries() {
        // Each row kills a different wrong implementation.
        let cases: [(String, Date, Int)] = [
            ("birthday today",       dob(1970, 6, 15), 55),
            ("birthday tomorrow",    dob(1970, 6, 16), 54),   // kills /365 and year-subtraction
            ("birthday in December", dob(1970, 12, 31), 54),  // kills year-subtraction
            ("19 leap days",         dob(1948, 6, 15), 77),   // kills /365.25
        ]
        for (name, d, expected) in cases {
            let age = PersonProfile(dateOfBirth: d, storedAge: nil, biologicalSex: nil, heightCm: nil)
                .currentAge(asOf: Self.asOf, calendar: utc)
            #expect(age == expected, "\(name): got \(String(describing: age))")
        }
    }

    @Test func noDateOfBirthFallsBackToStoredAge() {
        // Without this, age-gated screening in HealthMonitoringService silently
        // stops firing for every user who predates DOB collection — which today
        // is all of them, since nothing writes dateOfBirth.
        #expect(PersonProfile(dateOfBirth: nil, storedAge: 47, biologicalSex: nil, heightCm: nil)
                    .currentAge(asOf: Self.asOf, calendar: utc) == 47)
    }

    @Test func dateOfBirthWinsOverAStaleStoredAge() {
        #expect(PersonProfile(dateOfBirth: dob(1970, 1, 1), storedAge: 12, biologicalSex: nil, heightCm: nil)
                    .currentAge(asOf: Self.asOf, calendar: utc) == 55)
    }

    @Test func neitherSourceMeansNoAge() {
        #expect(PersonProfile(dateOfBirth: nil, storedAge: nil, biologicalSex: nil, heightCm: nil)
                    .currentAge(asOf: Self.asOf, calendar: utc) == nil)
    }
}
```

- [ ] **Step 2: Implement**

`calendar.dateComponents([.year], from: dob, to: asOf).year` — never a division by 365 or 365.25.

Add DOB and biological sex to the existing `requestAuthorization(toShare:read:)` call as characteristic types (`HKObjectType.characteristicType(forIdentifier:)`) and populate the profile when granted.

**No schema change.** `age` and `weightKg` remain columns; `weightKg` stops being *read* — weight is a series. Find reads with `grep -rn "\.age\b\|weightKg" --include=*.swift Views Models` and route them through `currentAge(asOf:)` and the event series respectively.

- [ ] **Step 3: Run the app-target tests explicitly**

```bash
xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO -only-testing:"Food IntolerancesTests/PersonProfileTests"
```

The package command does not compile this target; without this step the tests are written but never run.

- [ ] **Step 4: Mutants**

1. Drop the stored-age fallback → `noDateOfBirthFallsBackToStoredAge` fails.
2. `component(.year, from: asOf) - component(.year, from: dob)` → the boundary table fails on two rows.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(profile): derive age from DOB with a stored-age fallback"
```

---

### Task 11: Weight formatting from a raw value

`BodyMetricValueFormatter.line(for:unit:)` takes a `HealthEvent` and guards on category, subtype and unit; `poundsPerKilogram` is `private`. A trajectory carries bare `Double`s, so the first plan's constraint — reuse it, no new conversion — was unsatisfiable: an implementer would have had to fabricate a throwaway `HealthEvent` or write a second conversion.

**Files:** Modify `Views/HealthOS/Timeline/BodyMetricValueFormatter.swift`; extend its existing tests.

Extract `static func line(kg: Double, unit: WeightUnit) -> String` and have `line(for:unit:)` delegate to it. The existing event-based tests must pass **unedited** — that is the proof the extraction changed nothing.

```bash
git commit -m "refactor(units): weight formatting from a raw value"
```

---

### Task 12: The surface — chart, copy, and a non-diagnostic line

**Files:** Create `Views/HealthOS/Trends/{TrajectoryPresentation,TrajectoriesViewState,TrajectoriesView}.swift`; modify `HealthTabView.swift`; test `Food IntolerancesTests/TrajectoryPresentationTests.swift`.

**A chart is required.** A step change at a protocol start and a steady decline render identically as text, and no clinician acts on "down 1.2 kg over 365 days" without seeing shape, gaps and outliers. `TrendMeasurement` carries the weekly points and the app already uses Swift Charts. **Gaps are drawn as gaps** — missing weeks are absent from `weeks`, and the chart must not connect across them.

`TrajectoriesViewState` follows the established pattern: `@MainActor`, a synchronous double-invocation guard, its in-flight `Task` exposed read-only so tests await deterministically. This repo has had three off-main-actor `@Published` cold-launch crashes; the pattern is not optional.

- [ ] **Step 1: Write the failing copy tests**

`sample(_:_:suppression:)` builds a `Trajectory` with fixed coverage (284 of 365 days) and a measurement running 90 → 79 kg, change −11 kg, so every assertion is hand-checkable.

```swift
    @Test func noTrajectoryEverClaimsACause() {
        #expect(TrajectorySeries.allCases.count == 6)          // else the sweep is vacuous
        for system in [UnitSystem.metric, .imperial] {          // first plan swept metric only
            for direction in [TrendDirection.rising, .falling, .noClearChange] {
                for series in TrajectorySeries.allCases {
                    let text = TrajectoryPresentation.summary(for: sample(series, direction), system: system)
                    #expect(!text.isEmpty)                     // else a `default: ""` arm passes
                    for banned in ["because", "caused", "led to", "due to", "linked to", "resulted in"] {
                        #expect(!text.localizedCaseInsensitiveContains(banned), "\(series)/\(direction): \(text)")
                    }
                }
            }
        }
    }

    @Test func noClearChangeGivesNoNumberAtAll() {
        // The first plan banned only arrow glyphs, so "No clear change
        // (90 → 79 kg, -11 kg)" would have passed — doing the exact harm.
        let text = TrajectoryPresentation.summary(for: sample(.weight, .noClearChange), system: .metric)
        #expect(text.localizedCaseInsensitiveContains("no clear change"))
        for n in ["11", "90", "79"] { #expect(!text.contains(n)) }
    }

    @Test func weightIsConvertedNotRelabelled() {
        // The first plan asserted only that the string contained "lb", which an
        // implementation appending " lb" to kilograms satisfies.
        let imperial = TrajectoryPresentation.summary(for: sample(.weight, .falling), system: .imperial)
        let metric = TrajectoryPresentation.summary(for: sample(.weight, .falling), system: .metric)
        #expect(imperial.contains("24.2") || imperial.contains("174"))      // 11 kg = 24.2 lb
        #expect(!imperial.contains("79"))
        #expect(metric.contains("79"))
    }

    @Test func aSuppressedTrajectorySaysWhyInPlainWords() {
        let text = TrajectoryPresentation.summary(
            for: sample(.weight, .noClearChange, suppression: .densityConfounded), system: .metric)
        #expect(text.localizedCaseInsensitiveContains("how often"))
        #expect(!text.localizedCaseInsensitiveContains("confound"))         // plain words, not jargon
    }

    @Test func everyStatedChangeCarriesItsInterval() {
        let text = TrajectoryPresentation.summary(for: sample(.weight, .falling), system: .metric)
        #expect(text.contains("to"))       // an interval, not a bare point estimate
    }
```

- [ ] **Step 2: Implement presentation, then state, then view**

Rows show the series name, the summary, the coverage note, the chart, and — where a direction is stated — the typical range of normal variation for that series, so a change can be read against something. Add the window picker (90/365, default 90) and one navigation row in `HealthTabView` following the existing `NavigationLink` + `.hgCard()` pattern.

Add the **app-level non-diagnostic line**: persistent, plain, on this surface, plus "discuss this with your clinician" framing. No "abnormal", "high", "low", "risk", "should"; no category names; no notifications.

- [ ] **Step 3: Mutants**

1. Add "because" to any summary → `noTrajectoryEverClaimsACause` fails.
2. Render `changeOverWindow` in the no-clear-change branch → `noClearChangeGivesNoNumberAtAll` fails.
3. Append the unit without converting → `weightIsConvertedNotRelabelled` fails.

- [ ] **Step 4: Run both suites**

```bash
cd HealthGraphCore && swift test
xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO
```

`SwiftDataMigratorTests` crashes the runner (pre-existing), so the trailing "Test run with N tests" line under-counts. Count `✔ Suite` lines and grep `✘`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(trends): charted trajectories surface"
```

---

## Device verification

The gate before merge, on a device with real Apple Health history.

1. Health tab → **Trends**. Series with real coverage only; weight absent on a device with no connected scale.
2. Check one series against Apple Health directly. Disagreeing with Apple's own chart is worse than showing nothing.
3. Switch 90 ↔ 365. The answer should change, and **at least one series should say "no clear change"**. If everything trends on every window, the corrections are not working.
4. Toggle Imperial/Metric; weight re-renders with converted numbers, not relabelled ones.
5. Gaps render as gaps, never as lines through missing weeks.
6. Nothing implies a cause, nothing names a category, the non-diagnostic line is visible.
7. **If you wear two sleep trackers**, confirm sleep duration is plausible. This is Task 1, and it is the most likely place a real device disagrees with the tests.
