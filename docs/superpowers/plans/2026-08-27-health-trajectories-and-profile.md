# Health Trajectories and Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the user — and the design partner's practice — honest trends over the device-recorded health data already on the phone, without asserting a single cause.

**Architecture:** Pure statistics in `HealthGraphCore` (weekly bucketing → Mann–Kendall for direction → Theil–Sen for magnitude), a service that runs every series and applies one Benjamini–Hochberg correction across them, and a thin SwiftUI surface following the Workflow/ViewState/thin-View pattern. Nothing reads or writes a `Relationship`.

**Tech Stack:** Swift 6, Swift Testing (`@Test`/`#expect`), GRDB, `HealthGraphCore` package, HealthKit (characteristics only).

**Spec:** `docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md`

## Global Constraints

- **Nothing in this round touches the evidence engine.** No file under `Evidence/` is modified, and no code here reads or writes a `Relationship`. The one thing reused from it is `SignificanceTester.benjaminiHochbergThreshold` at `EvidenceConfig.fdrAlpha` (0.05) — called, not copied, so the two multiplicity policies cannot drift apart.
- **Fixed windows: 30, 90, 365 days, default 90.** Nothing may scan windows and surface the most dramatic. If a task's design would let the app pick a window by its result, stop and report.
- **No causal language anywhere on this surface.** Not "because", not "led to", not "caused". A trajectory states what a number did, never why.
- **Coverage is part of every result** and is rendered with it. A series below the floor is omitted entirely, never shown with a warning.
- **Coverage floor:** a window qualifies only with at least **8 weeks** carrying data and at least **60%** of the window's weeks carrying data. These are the round's only invented constants; put them in one config struct so they are tunable in one place.
- **UTC throughout, anchored to the window.** Week buckets are 7-day spans measured from the window start, never ISO weeks — bucket boundaries must depend only on the window, so the same data analysed on two different days cannot fall into different buckets.
- **Reuse the existing unit machinery** (`UnitSystem`, the global measurement-system preference, `BodyMetricValueFormatter`). No new unit conversion.
- **No SwiftData schema changes.** `UserProfile` fields are added to or stopped being read; none are deleted. `SwiftDataMigratorTests` already crashes the test runner, and a schema change would compound a known-bad area for no benefit here.
- **Every task ends with the package suite green:** `cd HealthGraphCore && swift test`.
- **Fixtures anchor at exact UTC midnight** (`Date(timeIntervalSince1970: 1_749_945_600)`). Never `Date()` — this round is entirely about day bucketing.
- Mutation discipline: where a task names a mutant, apply it, confirm the **named** test fails, restore, and report both directions. If a named mutant does not kill its test, say so — that is a finding.

## File Structure

**Package — pure statistics, no I/O:**
- `HealthGraphCore/Sources/HealthGraphCore/Trends/WeeklyBucketing.swift` — daily points → weekly medians + coverage
- `HealthGraphCore/Sources/HealthGraphCore/Trends/MannKendall.swift` — trend test
- `HealthGraphCore/Sources/HealthGraphCore/Trends/TheilSen.swift` — slope estimate
- `HealthGraphCore/Sources/HealthGraphCore/Trends/TrendAnalyzer.swift` — combines the above, applies the coverage floor
- `HealthGraphCore/Sources/HealthGraphCore/Trends/TrajectorySeries.swift` — the series catalog and event → daily-point extraction
- `HealthGraphCore/Sources/HealthGraphCore/Trends/TrajectoryService.swift` — orchestration and the one BH correction
- `HealthGraphCore/Sources/HealthGraphCore/Trends/PersonProfile.swift` — the demographic value type the package can see

**App:**
- `Views/HealthOS/Trends/TrajectoriesViewState.swift`
- `Views/HealthOS/Trends/TrajectoriesView.swift`
- `Views/HealthOS/Trends/TrajectoryPresentation.swift` — all user-facing strings, pure and testable
- `Models/UserProfile.swift` — DOB as source of truth, stop reading stored age and weight
- `Views/HealthOS/Health/HealthTabView.swift` — one navigation row

Each statistics file is one function's worth of responsibility so it can be reasoned about and mutated in isolation. `TrajectoryService` is the only file that knows about both the database and the statistics.

---

### Task 1: Weekly bucketing and coverage

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Trends/WeeklyBucketing.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/WeeklyBucketingTests.swift`

**Interfaces:**
- Produces: `DailyPoint`, `WeeklyPoint`, `SeriesCoverage`, `WeeklyBucketing.bucket(_:windowStart:windowEnd:calendar:)`

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
        // Buckets are anchored to the window, NOT to ISO weeks: the same data
        // analysed on two different days must land in the same buckets, or a
        // trend would change shape depending on when it was viewed.
        let daily = (0..<14).map { DailyPoint(day: day($0), value: Double($0)) }
        let out = WeeklyBucketing.bucket(daily, windowStart: day(0), windowEnd: day(13), calendar: utc)
        #expect(out.weeks.count == 2)
        #expect(out.weeks[0].weekIndex == 0)
        #expect(out.weeks[0].value == 3.0)      // median of 0...6
        #expect(out.weeks[1].value == 10.0)     // median of 7...13
    }

    @Test func aWeeksValueIsItsMedianNotItsMean() {
        // One bad reading — a different scale, a mis-placed cuff — must not move
        // the week. This is why the whole pipeline is median/rank based.
        let daily = [DailyPoint(day: day(0), value: 70),
                     DailyPoint(day: day(1), value: 70.5),
                     DailyPoint(day: day(2), value: 71),
                     DailyPoint(day: day(3), value: 200)]      // outlier
        let out = WeeklyBucketing.bucket(daily, windowStart: day(0), windowEnd: day(6), calendar: utc)
        #expect(out.weeks.count == 1)
        #expect(out.weeks[0].value == 70.75)    // median of the four, not the mean of 102.9
    }

    @Test func emptyWeeksAreAbsentNotZero() {
        // A week with no readings is missing data. Emitting 0 would make a gap
        // look like a crash to the floor — the single most dangerous rendering
        // error available in a weight or heart-rate chart.
        let daily = [DailyPoint(day: day(0), value: 70), DailyPoint(day: day(20), value: 71)]
        let out = WeeklyBucketing.bucket(daily, windowStart: day(0), windowEnd: day(27), calendar: utc)
        #expect(out.weeks.count == 2)
        #expect(out.weeks.map(\.weekIndex) == [0, 2])       // week 1 absent entirely
        #expect(!out.weeks.contains { $0.value == 0 })
    }

    @Test func coverageCountsBothDaysAndWeeks() {
        // Days are what the user is shown; weeks are what the statistics run on.
        // Both are reported so the two can never silently disagree.
        let daily = (0..<10).map { DailyPoint(day: day($0), value: 1) }
        let out = WeeklyBucketing.bucket(daily, windowStart: day(0), windowEnd: day(27), calendar: utc)
        #expect(out.coverage.daysWithData == 10)
        #expect(out.coverage.daysInWindow == 28)
        #expect(out.coverage.weeksWithData == 2)
        #expect(out.coverage.weeksInWindow == 4)
    }

    @Test func multipleReadingsOnOneDayCollapseToThatDaysMedianFirst() {
        // Three weight readings on Monday must not out-vote the other six days.
        let daily = [DailyPoint(day: day(0), value: 70), DailyPoint(day: day(0), value: 72),
                     DailyPoint(day: day(0), value: 74), DailyPoint(day: day(1), value: 80)]
        let out = WeeklyBucketing.bucket(daily, windowStart: day(0), windowEnd: day(6), calendar: utc)
        #expect(out.coverage.daysWithData == 2)              // two days, not four readings
        #expect(out.weeks[0].value == 76.0)                  // median of [72, 80]
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd HealthGraphCore && swift test --filter WeeklyBucketingTests`
Expected: compile failure — nothing exists yet.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct DailyPoint: Sendable, Equatable {
    public let day: Date          // UTC start-of-day
    public let value: Double
    public init(day: Date, value: Double) { self.day = day; self.value = value }
}

public struct WeeklyPoint: Sendable, Equatable {
    public let weekIndex: Int     // 0-based, counted from the window start
    public let value: Double      // median of that week's daily values
    public let dayCount: Int
}

public struct SeriesCoverage: Sendable, Equatable {
    public let daysWithData: Int
    public let daysInWindow: Int
    public let weeksWithData: Int
    public let weeksInWindow: Int
}

public enum WeeklyBucketing {
    /// Seven-day buckets anchored at `windowStart`, in the supplied calendar.
    ///
    /// Deliberately NOT ISO weeks. Bucket boundaries must depend only on the
    /// window, so the same underlying data analysed on two different days lands
    /// in identical buckets — otherwise a trend changes shape with the clock.
    ///
    /// Two levels of median, both load-bearing: several readings on one day
    /// collapse to that day's median first (three weigh-ins on Monday must not
    /// out-vote the rest of the week), then the week is the median of its days
    /// (one bad reading must not move the week).
    public static func bucket(_ daily: [DailyPoint], windowStart: Date, windowEnd: Date,
                              calendar: Calendar) -> (weeks: [WeeklyPoint], coverage: SeriesCoverage) {
        let start = calendar.startOfDay(for: windowStart)
        let end = calendar.startOfDay(for: windowEnd)
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
        let weeks = byWeek.keys.sorted().map { idx in
            WeeklyPoint(weekIndex: idx, value: median(byWeek[idx]!), dayCount: byWeek[idx]!.count)
        }
        return (weeks, SeriesCoverage(daysWithData: byDay.count, daysInWindow: daysInWindow,
                                      weeksWithData: weeks.count, weeksInWindow: weeksInWindow))
    }
}

/// Median of a non-empty list; even counts average the middle pair.
func median(_ xs: [Double]) -> Double {
    precondition(!xs.isEmpty)
    let s = xs.sorted()
    let m = s.count / 2
    return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
}
```

- [ ] **Step 4: Run the tests**

Run: `cd HealthGraphCore && swift test --filter WeeklyBucketingTests`
Expected: all pass.

- [ ] **Step 5: Demonstrate the mutants**

1. Use the mean instead of the median for a week → `aWeeksValueIsItsMedianNotItsMean` must fail.
2. Emit a `WeeklyPoint(value: 0)` for weeks with no data → `emptyWeeksAreAbsentNotZero` must fail.
3. Skip the per-day median and bucket raw readings straight into the week →
   `multipleReadingsOnOneDayCollapseToThatDaysMedianFirst` must fail.

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Trends/WeeklyBucketing.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/WeeklyBucketingTests.swift
git commit -m "feat(trends): weekly bucketing with coverage"
```

---

### Task 2: Mann–Kendall trend test

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Trends/MannKendall.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/MannKendallTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1 — takes a plain `[Double]`.
- Produces: `MannKendallResult` (`s`, `z`, `pValue` two-sided), `MannKendall.test(_:) -> MannKendallResult?`

- [ ] **Step 1: Write the failing tests**

```swift
struct MannKendallTests {
    @Test func aStrictlyRisingSeriesIsSignificant() {
        let r = MannKendall.test((0..<12).map(Double.init))
        #expect(r != nil)
        #expect(r!.s == 66)                 // every one of the 66 pairs is concordant
        #expect(r!.pValue < 0.01)
    }

    @Test func aStrictlyFallingSeriesIsSignificantAndNegative() {
        let r = MannKendall.test((0..<12).map { Double(11 - $0) })
        #expect(r!.s == -66)
        #expect(r!.z < 0)
        #expect(r!.pValue < 0.01)
    }

    @Test func aFlatSeriesIsNotSignificant() {
        // Every pair is a tie: S is 0 and the variance correction must not blow up.
        let r = MannKendall.test(Array(repeating: 5.0, count: 12))
        #expect(r!.s == 0)
        #expect(r!.pValue > 0.9)
    }

    @Test func tiesReduceTheVarianceRatherThanBeingIgnored() {
        // Without the tie correction the variance is overstated, z is understated,
        // and a real trend in a heavily-tied series (step counts, sleep hours
        // rounded to the half hour) is missed.
        let tied: [Double] = [1,1,1,2,2,2,3,3,3,4,4,4]
        let r = MannKendall.test(tied)
        #expect(r!.pValue < 0.01)
    }

    @Test func tooFewPointsReturnNil() {
        // Below the coverage floor there is no test to run. nil, not a p-value of 1:
        // "we did not test" and "we tested and found nothing" are different answers.
        #expect(MannKendall.test([1, 2, 3, 4, 5, 6, 7]) == nil)
        #expect(MannKendall.test((0..<8).map(Double.init)) != nil)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd HealthGraphCore && swift test --filter MannKendallTests`

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct MannKendallResult: Sendable, Equatable {
    public let s: Int          // concordant minus discordant pairs
    public let z: Double       // normal approximation, continuity-corrected
    public let pValue: Double  // two-sided
}

/// Non-parametric test for a monotonic trend.
///
/// Chosen over a least-squares fit because none of these series are normally
/// distributed, and because it depends only on the ORDER of the values — so a
/// single absurd reading changes one pair's sign rather than dragging a line.
public enum MannKendall {
    /// `nil` when there are too few points to test. This is not the same as a
    /// non-significant result and callers must not conflate them.
    public static func test(_ values: [Double], minimumPoints: Int = 8) -> MannKendallResult? {
        let n = values.count
        guard n >= minimumPoints else { return nil }

        var s = 0
        for i in 0..<(n - 1) {
            for j in (i + 1)..<n {
                let d = values[j] - values[i]
                s += d > 0 ? 1 : (d < 0 ? -1 : 0)
            }
        }

        // Tie correction: without it the variance is overstated and a genuine
        // trend in a heavily-tied series (rounded sleep hours, step counts) is
        // reported as noise.
        var counts: [Double: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        let tieTerm = counts.values.reduce(0.0) { acc, t in
            t > 1 ? acc + Double(t * (t - 1) * (2 * t + 5)) : acc
        }
        let variance = (Double(n * (n - 1) * (2 * n + 5)) - tieTerm) / 18.0
        guard variance > 0 else { return MannKendallResult(s: s, z: 0, pValue: 1) }

        // Continuity correction: S is discrete, the normal approximation is not.
        let z: Double
        if s > 0 { z = Double(s - 1) / variance.squareRoot() }
        else if s < 0 { z = Double(s + 1) / variance.squareRoot() }
        else { z = 0 }

        let p = erfc(abs(z) / 2.0.squareRoot())      // two-sided normal tail
        return MannKendallResult(s: s, z: z, pValue: min(1, max(0, p)))
    }
}
```

- [ ] **Step 4: Run the tests**

- [ ] **Step 5: Demonstrate the mutants**

1. Drop the tie term (`variance = n(n-1)(2n+5)/18`) → `tiesReduceTheVarianceRatherThanBeingIgnored` must fail.
2. Remove the continuity correction (`z = Double(s) / sd`) → report whether any test fails. If none does, say so: it means no test pins it, and the controller should decide whether that matters.
3. Return `MannKendallResult(s: 0, z: 0, pValue: 1)` instead of `nil` below the minimum → `tooFewPointsReturnNil` must fail.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(trends): Mann-Kendall trend test with tie correction"
```

---

### Task 3: Theil–Sen slope

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Trends/TheilSen.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TheilSenTests.swift`

**Interfaces:**
- Produces: `TheilSen.slope(x:y:) -> Double?` — units of y per unit of x.

- [ ] **Step 1: Write the failing tests**

```swift
struct TheilSenTests {
    @Test func recoversAKnownSlope() {
        let x = (0..<12).map(Double.init)
        let y = x.map { 70 + 0.5 * $0 }
        #expect(abs(TheilSen.slope(x: x, y: y)! - 0.5) < 1e-9)
    }

    @Test func survivesOutliersThatWouldBreakLeastSquares() {
        // The whole reason for choosing this estimator. One catastrophic reading
        // (a suitcase on the scale) must not become a trend.
        var y = (0..<12).map { 70 + 0.5 * Double($0) }
        y[6] = 400
        let slope = TheilSen.slope(x: (0..<12).map(Double.init), y: y)!
        #expect(abs(slope - 0.5) < 0.2)
    }

    @Test func handlesGapsInX() {
        // Weeks are indices, and missing weeks are absent — so x is not contiguous.
        let x: [Double] = [0, 1, 2, 5, 6, 9]
        let y = x.map { 100 - 2 * $0 }
        #expect(abs(TheilSen.slope(x: x, y: y)! + 2) < 1e-9)
    }

    @Test func tooFewPointsReturnNil() {
        #expect(TheilSen.slope(x: [1], y: [2]) == nil)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Median of all pairwise slopes.
///
/// Chosen over least squares because a single extreme reading changes one slope
/// out of many rather than tilting the whole line: with n points there are
/// n(n-1)/2 pairwise slopes and the median tolerates nearly 30% contamination.
/// At most 52 weekly points, so the O(n²) pass is ~1,300 divisions.
public enum TheilSen {
    public static func slope(x: [Double], y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        var slopes: [Double] = []
        slopes.reserveCapacity(x.count * (x.count - 1) / 2)
        for i in 0..<(x.count - 1) {
            for j in (i + 1)..<x.count {
                let dx = x[j] - x[i]
                guard dx != 0 else { continue }      // same week: no slope defined
                slopes.append((y[j] - y[i]) / dx)
            }
        }
        return slopes.isEmpty ? nil : median(slopes)
    }
}
```

- [ ] **Step 4: Run the tests**

- [ ] **Step 5: Demonstrate the mutant**

Replace the median of pairwise slopes with a least-squares fit → `survivesOutliersThatWouldBreakLeastSquares` must fail.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(trends): Theil-Sen slope"
```

---

### Task 4: `TrendAnalyzer` — coverage floor and an unjudged result

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Trends/TrendAnalyzer.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TrendAnalyzerTests.swift`

**Interfaces:**
- Consumes: `WeeklyPoint`, `SeriesCoverage` (Task 1), `MannKendall` (Task 2), `TheilSen` (Task 3)
- Produces: `TrendConfig`, `TrendMeasurement`, `TrendAnalyzer.measure(weeks:coverage:config:) -> TrendMeasurement?`

**Note on the split:** this task returns a measurement carrying a p-value and a slope but **no direction**. Direction is assigned in Task 6, after Benjamini–Hochberg across all series — assigning it here would apply an uncorrected threshold and quietly defeat the correction.

- [ ] **Step 1: Write the failing tests**

```swift
struct TrendAnalyzerTests {
    private func weeks(_ values: [Double]) -> [WeeklyPoint] {
        values.enumerated().map { WeeklyPoint(weekIndex: $0.offset, value: $0.element, dayCount: 7) }
    }
    private func fullCoverage(_ n: Int) -> SeriesCoverage {
        SeriesCoverage(daysWithData: n * 7, daysInWindow: n * 7, weeksWithData: n, weeksInWindow: n)
    }

    @Test func belowTheWeekFloorThereIsNoMeasurement() {
        // nil means "not enough data to look", which the surface renders as
        // absence. A measurement with a wide interval would invite reading it.
        #expect(TrendAnalyzer.measure(weeks: weeks([1,2,3,4,5,6,7]),
                                      coverage: fullCoverage(7), config: .default) == nil)
    }

    @Test func belowTheCoverageFractionThereIsNoMeasurement() {
        // 8 weeks of data inside a 52-week window is 15% coverage: enough points
        // to compute something, nowhere near enough to describe the year.
        let sparse = SeriesCoverage(daysWithData: 8, daysInWindow: 364,
                                    weeksWithData: 8, weeksInWindow: 52)
        #expect(TrendAnalyzer.measure(weeks: weeks([1,2,3,4,5,6,7,8]),
                                      coverage: sparse, config: .default) == nil)
    }

    @Test func slopeIsPerWeekAndChangeIsAcrossTheWindow() {
        // The user is shown a change over the window; the estimator produces a
        // rate. Conflating them misstates the magnitude by a factor of n.
        let m = TrendAnalyzer.measure(weeks: weeks((0..<12).map { 70 + 0.5 * Double($0) }),
                                      coverage: fullCoverage(12), config: .default)!
        #expect(abs(m.slopePerWeek - 0.5) < 1e-9)
        #expect(abs(m.changeOverWindow - 5.5) < 1e-9)      // 0.5 * (12 - 1) spans
    }

    @Test func aFlatNoisySeriesIsNotSignificant() {
        // The primary guard, and the trajectory equivalent of the null-pair test
        // that caught two bad denominator designs upstream.
        let noisy: [Double] = [70.1, 69.9, 70.2, 70.0, 69.8, 70.3, 69.95, 70.05,
                               70.15, 69.85, 70.0, 70.1]
        #expect(TrendAnalyzer.measure(weeks: weeks(noisy),
                                      coverage: fullCoverage(12), config: .default)!.pValue > 0.05)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct TrendConfig: Sendable {
    /// Fewest weeks carrying data before a window may be described at all.
    public var minimumWeeksWithData = 8
    /// Fraction of the window's weeks that must carry data.
    public var minimumWeekCoverage = 0.6
    public static let `default` = TrendConfig()
    public init() {}
}

/// A measured series with NO verdict attached. Direction is assigned only after
/// the multiplicity correction across series (see `TrajectoryService`).
public struct TrendMeasurement: Sendable {
    public let slopePerWeek: Double
    public let changeOverWindow: Double
    public let firstWeekValue: Double
    public let lastWeekValue: Double
    public let pValue: Double
    public let coverage: SeriesCoverage
    public let weeks: [WeeklyPoint]
}

public enum TrendAnalyzer {
    /// `nil` when the window is too thin to describe. Deliberately not a
    /// low-confidence measurement: an absent row reads as "no data", a present
    /// row with a caveat gets read anyway.
    public static func measure(weeks: [WeeklyPoint], coverage: SeriesCoverage,
                               config: TrendConfig) -> TrendMeasurement? {
        guard coverage.weeksWithData >= config.minimumWeeksWithData,
              coverage.weeksInWindow > 0,
              Double(coverage.weeksWithData) / Double(coverage.weeksInWindow) >= config.minimumWeekCoverage
        else { return nil }

        let sorted = weeks.sorted { $0.weekIndex < $1.weekIndex }
        let values = sorted.map(\.value)
        guard let mk = MannKendall.test(values, minimumPoints: config.minimumWeeksWithData),
              let slope = TheilSen.slope(x: sorted.map { Double($0.weekIndex) }, y: values)
        else { return nil }

        // Span between the first and last week that HAVE data, not the nominal
        // window: a slope multiplied by weeks nobody measured would overstate it.
        let span = Double((sorted.last?.weekIndex ?? 0) - (sorted.first?.weekIndex ?? 0))
        return TrendMeasurement(slopePerWeek: slope, changeOverWindow: slope * span,
                                firstWeekValue: values.first!, lastWeekValue: values.last!,
                                pValue: mk.pValue, coverage: coverage, weeks: sorted)
    }
}
```

- [ ] **Step 4: Run the tests**

- [ ] **Step 5: Demonstrate the mutants**

1. Drop the coverage-fraction guard → `belowTheCoverageFractionThereIsNoMeasurement` must fail.
2. Set `changeOverWindow = slopePerWeek` → `slopeIsPerWeekAndChangeIsAcrossTheWindow` must fail.
3. Multiply by `coverage.weeksInWindow` rather than the observed span → the same test must fail.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(trends): trend analyzer with the coverage floor"
```

---

### Task 5: The series catalog and extraction

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Trends/TrajectorySeries.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TrajectorySeriesTests.swift`

**Interfaces:**
- Consumes: `HealthEvent`, `SleepSessionBuilder.sessions(from:timeZone:)`, `DailyPoint`
- Produces: `TrajectorySeries` (enum, `CaseIterable`), `.displayName`, `.unit`, and `TrajectorySeries.dailyPoints(from:calendar:) -> [DailyPoint]` (instance method on the enum case)

The series and their canonical subtypes come from `HealthKitSampleMapper`'s existing tables — read that file rather than retyping them, and use exactly the subtypes it writes: `.bodyMetric`/`weight`, `.exercise`/`steps`, `.vitals`/`restingHeartRate`, `hrv`, `respiratoryRate`, `bloodPressureSystolic`, `bloodPressureDiastolic`.

- [ ] **Step 1: Write the failing tests**

```swift
struct TrajectorySeriesTests {
    private static let t0 = Date(timeIntervalSince1970: 1_749_945_600)

    @Test func weightIsReadFromBodyMetricEvents() {
        let events = [HealthEvent(timestamp: Self.t0.addingTimeInterval(8 * 3600),
                                  category: .bodyMetric, subtype: "weight",
                                  value: 70.5, unit: "kg", source: .healthKit)]
        let points = TrajectorySeries.weight.dailyPoints(from: events, calendar: utc)
        #expect(points.count == 1)
        #expect(points[0].value == 70.5)
    }

    @Test func sleepUsesNightSessionsAndIsAttributedToTheWakingDay() {
        // A night starting 23:00 Monday and ending 07:00 Tuesday is TUESDAY's
        // sleep — that is how people read it, and attributing it to Monday would
        // shift every night by one against whatever it is later compared with.
        let bedtime = Self.t0.addingTimeInterval(23 * 3600)          // Mon 23:00
        let wakeTime = Self.t0.addingTimeInterval(31 * 3600)         // Tue 07:00
        var asleep = HealthEvent(timestamp: bedtime, category: .sleep,
                                 subtype: "asleepCore", value: 8 * 3600, unit: "s",
                                 source: .healthKit)
        asleep.endTimestamp = wakeTime
        let points = TrajectorySeries.sleepDuration.dailyPoints(from: [asleep], calendar: utc)
        #expect(points.count == 1)
        #expect(points[0].day == utc.startOfDay(for: wakeTime))
        #expect(abs(points[0].value - 8.0) < 0.01)                   // hours, not minutes
    }

    @Test func aSeriesReadsOnlyItsOwnSubtype() {
        // restingHeartRate and heartRate are different series with the same unit;
        // reading both would silently average a resting rate with exercise peaks.
        let events = [HealthEvent(timestamp: Self.t0, category: .vitals,
                                  subtype: "heartRate", value: 150, unit: "bpm", source: .healthKit),
                      HealthEvent(timestamp: Self.t0, category: .vitals,
                                  subtype: "restingHeartRate", value: 58, unit: "bpm", source: .healthKit)]
        let points = TrajectorySeries.restingHeartRate.dailyPoints(from: events, calendar: utc)
        #expect(points.count == 1)
        #expect(points[0].value == 58)
    }

    @Test func deletedEventsAreExcluded() {
        // Soft deletes are how this app removes data; a trajectory that ignored
        // them would resurrect a reading the person deleted on purpose.
        var deleted = HealthEvent(timestamp: Self.t0.addingTimeInterval(8 * 3600),
                                  category: .bodyMetric, subtype: "weight",
                                  value: 70.5, unit: "kg", source: .healthKit)
        deleted.deletedAt = Self.t0.addingTimeInterval(9 * 3600)
        #expect(TrajectorySeries.weight.dailyPoints(from: [deleted], calendar: utc).isEmpty)
    }

    @Test func everySeriesHasADisplayNameAndUnit() {
        for s in TrajectorySeries.allCases {
            #expect(!s.displayName.isEmpty)
            #expect(!s.unit.isEmpty)
        }
    }
}
```

Fill the elided fixtures with the same shape as the first test. Check how `deletedAt` is filtered elsewhere (`GRDBEventStore`) and match it exactly rather than inventing a second rule.

- [ ] **Step 2: Run, implement, run again**

Weight, HR, HRV, respiratory rate and blood pressure are direct reads of `(category, subtype)`. Steps are already daily-aggregated on ingest — do not re-aggregate, just read. Sleep goes through `SleepSessionBuilder.sessions(from:timeZone:)`, filtered to `kind == .night`, value `asleepMinutes / 60`, attributed to the start-of-day of the session **end**.

- [ ] **Step 3: Demonstrate the mutants**

1. Attribute sleep to the session start → `sleepUsesNightSessionsAndIsAttributedToTheWakingDay` must fail.
2. Match on category only, ignoring subtype → `aSeriesReadsOnlyItsOwnSubtype` must fail.
3. Stop filtering `deletedAt` → `deletedEventsAreExcluded` must fail.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(trends): series catalog and extraction"
```

---

### Task 6: `TrajectoryService` — orchestration and one correction

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Trends/TrajectoryService.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TrajectoryServiceTests.swift`

**Interfaces:**
- Consumes: `EventStore`, Tasks 1-5, `SignificanceTester.benjaminiHochbergThreshold`, `EvidenceConfig.fdrAlpha`
- Produces:

```swift
public enum TrendWindow: Int, CaseIterable, Sendable { case days30 = 30, days90 = 90, days365 = 365 }
public enum TrendDirection: String, Sendable { case rising, falling, noClearChange }

/// A measured series with its verdict. This is a VALUE, not a rendered string:
/// the doctor-report round renders the same values rather than recomputing them,
/// so nothing here may be formatted for display.
public struct Trajectory: Sendable {
    public let series: TrajectorySeries
    public let window: TrendWindow
    public let direction: TrendDirection
    public let measurement: TrendMeasurement
}

public struct TrajectoryService: Sendable {
    public init(eventStore: any EventStore, config: TrendConfig = .default)
    public func trajectories(window: TrendWindow, asOf: Date) async throws -> [Trajectory]
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct TrajectoryServiceTests {
    private static let now = Date(timeIntervalSince1970: 1_749_945_600)   // exact UTC midnight
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func day(_ n: Int) -> Date { Self.now.addingTimeInterval(Double(n) * 86_400) }

    /// Deterministic pseudo-noise: no Date(), no SystemRandomNumberGenerator, so a
    /// failure is reproducible. Seeded LCG, values in -0.5...0.5.
    private func noise(_ i: Int, seed: UInt64) -> Double {
        var x = seed &+ UInt64(i) &* 6_364_136_223_846_793_005
        x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33
        return Double(x % 1000) / 1000.0 - 0.5
    }

    private func events(_ series: TrajectorySeries, days: Int,
                        value: (Int) -> Double) -> [HealthEvent] {
        (0..<days).map { d in
            HealthEvent(timestamp: day(-days + d).addingTimeInterval(8 * 3600),
                        category: series.category, subtype: series.subtype,
                        value: value(d), unit: series.unit, source: .healthKit)
        }
    }

    private func service(_ events: [HealthEvent]) async throws -> TrajectoryService {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        for e in events { try await store.save(e) }
        return TrajectoryService(eventStore: store)
    }

    @Test func directionIsAssignedOnlyAfterTheCorrection() async throws {
        // Several flat series and one real trend. Judged per-series at 0.05 a
        // flat one can cross by chance; the BH correction is what stops that,
        // and it can only be applied across the whole set at once.
        var all: [HealthEvent] = []
        for (i, s) in [TrajectorySeries.restingHeartRate, .hrv, .respiratoryRate,
                       .bloodPressureSystolic, .bloodPressureDiastolic, .steps].enumerated() {
            all += events(s, days: 365) { 60 + self.noise($0, seed: UInt64(i + 1)) }
        }
        all += events(.weight, days: 365) { 90 - 0.02 * Double($0) }      // ~7kg over the year
        let results = try await service(all).trajectories(window: .days365, asOf: Self.now)
        #expect(results.first { $0.series == .weight }?.direction == .falling)
        #expect(results.filter { $0.direction != .noClearChange }.count == 1)
    }

    @Test func aRandomWalkIsNotATrend() async throws {
        // A random walk drifts and is strongly autocorrelated but has NO monotonic
        // trend. This is the test that proves weekly aggregation is load-bearing
        // rather than decorative: the same series tested daily reports a trend.
        var walk = 70.0
        let values: [Double] = (0..<365).map { i in walk += noise(i, seed: 99); return walk }
        let results = try await service(events(.weight, days: 365) { values[$0] })
            .trajectories(window: .days365, asOf: Self.now)
        #expect(results.first { $0.series == .weight }?.direction == .noClearChange)
    }

    @Test func aSeriesBelowTheFloorIsAbsentEntirely() async throws {
        // Six weeks of HRV inside a 365-day window: enough points to compute
        // something, far below the coverage floor. Absent, not caveated.
        let results = try await service(events(.hrv, days: 42) { 45 + Double($0) })
            .trajectories(window: .days365, asOf: Self.now)
        #expect(!results.contains { $0.series == .hrv })
    }

    @Test func theWindowIsTheOneAskedForNotTheBestLooking() async throws {
        // A sharp swing in the last 30 days inside an otherwise flat year. Asking
        // for 365 must answer about the year; an implementation that scanned
        // windows and surfaced the most dramatic would report the swing.
        let results = try await service(events(.weight, days: 365) { d in
            d >= 335 ? 90 - 0.4 * Double(d - 335) : 90 + self.noise(d, seed: 7)
        }).trajectories(window: .days365, asOf: Self.now)
        #expect(results.first { $0.series == .weight }?.direction == .noClearChange)

        let month = try await service(events(.weight, days: 365) { d in
            d >= 335 ? 90 - 0.4 * Double(d - 335) : 90 + self.noise(d, seed: 7)
        }).trajectories(window: .days30, asOf: Self.now)
        #expect(month.first { $0.series == .weight }?.direction == .falling)
    }
}
```

`TrajectorySeries` must therefore expose `category`, `subtype` and `unit` publicly — add them in Task 5 if they are not already public.

- [ ] **Step 2: Run, implement, run again**

The service: for each `TrajectorySeries`, extract daily points, bucket, measure; collect the measurements; run `SignificanceTester.benjaminiHochbergThreshold` over their p-values at `EvidenceConfig.default.fdrAlpha`; assign `.rising`/`.falling` by the sign of `slopePerWeek` for those at or under the threshold, `.noClearChange` for the rest. Series with no measurement are omitted.

- [ ] **Step 3: Demonstrate the mutants**

1. Judge each series at 0.05 with no correction → `directionIsAssignedOnlyAfterTheCorrection` must fail.
2. Feed daily points straight to `TrendAnalyzer`, skipping weekly bucketing → `aRandomWalkIsNotATrend` must fail. **This is the most important mutant in the round** — it is the one that proves the autocorrelation handling is load-bearing rather than decorative.
3. Pick the window with the largest absolute slope → `theWindowIsTheOneAskedForNotTheBestLooking` must fail.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(trends): trajectory service with one BH correction across series"
```

---

### Task 7: Profile — date of birth as the source of truth

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Trends/PersonProfile.swift`
- Modify: `Models/UserProfile.swift`
- Modify: whichever HealthKit type requests authorization — find it with `grep -rn "requestAuthorization" --include=*.swift .`
- Test: `Food IntolerancesTests/PersonProfileTests.swift`

**Interfaces:**
- Produces: `PersonProfile` — `dateOfBirth: Date?`, `biologicalSex: String?`, `heightCm: Double?`, and `age(asOf:calendar:) -> Int?`
- Produces: `UserProfile.currentAge(asOf:)`, computed from `dateOfBirth`

**No SwiftData schema change.** `age` and `weightKg` stay as columns; they stop being *read*. Deleting them would touch a migration path whose tests already crash the runner.

- [ ] **Step 1: Write the failing tests**

```swift
    @Test func ageIsDerivedFromDateOfBirthNotStored() {
        // A stored age is correct the day it is entered and wrong every day after.
        let dob = Date(timeIntervalSince1970: 0)                      // 1970-01-01
        let asOf = Date(timeIntervalSince1970: 1_749_945_600)         // 2025-06-15
        #expect(PersonProfile(dateOfBirth: dob, biologicalSex: nil, heightCm: nil)
                    .age(asOf: asOf, calendar: utc) == 55)
    }

    @Test func aBirthdayLaterThisYearHasNotHappenedYet() {
        // The off-by-one every hand-rolled age calculation gets wrong. Born
        // 1970-12-31, asked on 2025-06-15: 54, not 55.
        let dob = Date(timeIntervalSince1970: 31_507_200)             // 1970-12-31 UTC
        let asOf = Date(timeIntervalSince1970: 1_749_945_600)         // 2025-06-15 UTC
        let age = PersonProfile(dateOfBirth: dob, biologicalSex: nil, heightCm: nil)
            .age(asOf: asOf, calendar: utc)
        #expect(age == 54)
    }

    @Test func noDateOfBirthMeansNoAge() {
        #expect(PersonProfile(dateOfBirth: nil, biologicalSex: nil, heightCm: nil)
                    .age(asOf: Date(), calendar: utc) == nil)
    }
```

- [ ] **Step 2: Implement**

`age` uses `calendar.dateComponents([.year], from: dob, to: asOf).year` — which handles the birthday case correctly and is why it must not be hand-rolled as a division.

Add DOB and biological sex to the HealthKit authorization request as *characteristic* reads, and populate `UserProfile` from them when granted. Ask only for what HealthKit cannot supply.

- [ ] **Step 3: Stop reading the stored fields**

Replace reads of `profile.age` with `profile.currentAge(asOf:)`, and reads of `profile.weightKg` with the latest `.bodyMetric`/`weight` event. Find them with `grep -rn "\.age\b\|weightKg" --include=*.swift Views Models`. Leave the stored properties in place, with a comment saying why they are no longer read.

- [ ] **Step 4: Demonstrate the mutant**

Compute age by dividing the interval by 365.25 → `aBirthdayLaterThisYearHasNotHappenedYet` must fail.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(profile): derive age from date of birth, stop reading stored weight"
```

---

### Task 8: The surface

**Files:**
- Create: `Views/HealthOS/Trends/TrajectoryPresentation.swift`
- Create: `Views/HealthOS/Trends/TrajectoriesViewState.swift`
- Create: `Views/HealthOS/Trends/TrajectoriesView.swift`
- Modify: `Views/HealthOS/Health/HealthTabView.swift`
- Test: `Food IntolerancesTests/TrajectoryPresentationTests.swift`

Follow the pattern the screen work settled on: a `ViewState` owning published state and a synchronous double-invocation guard, exposing its in-flight `Task` read-only so tests await deterministically; the View is thin wiring. All user-facing strings live in `TrajectoryPresentation` as pure static functions — the precedent is `EmptyStateCopyTests` over `TimelineView.emptyStateMessage`, and it exists because there is no ViewInspector in this project, so a string built inside a `body` cannot be tested at all.

- [ ] **Step 1: Write the failing copy tests**

`sample(_:_:)` builds a `Trajectory` with fixed coverage so the assertions are hand-checkable:

```swift
    private func sample(_ series: TrajectorySeries, _ direction: TrendDirection) -> Trajectory {
        let weeks = (0..<12).map { WeeklyPoint(weekIndex: $0, value: 90 - Double($0), dayCount: 7) }
        let m = TrendMeasurement(slopePerWeek: -1, changeOverWindow: -11,
                                 firstWeekValue: 90, lastWeekValue: 79, pValue: 0.01,
                                 coverage: SeriesCoverage(daysWithData: 284, daysInWindow: 365,
                                                          weeksWithData: 41, weeksInWindow: 52),
                                 weeks: weeks)
        return Trajectory(series: series, window: .days365, direction: direction, measurement: m)
    }
```

```swift
    @Test func aTrajectoryNeverClaimsACause() {
        // The one rule this surface exists under. Checked across every direction
        // and series rather than on one sample string.
        for direction in [TrendDirection.rising, .falling, .noClearChange] {
            for series in TrajectorySeries.allCases {
                let text = TrajectoryPresentation.summary(for: sample(series, direction))
                for banned in ["because", "caused", "led to", "due to", "thanks to"] {
                    #expect(!text.localizedCaseInsensitiveContains(banned),
                            "\(series)/\(direction) implied causation: \(text)")
                }
            }
        }
    }

    @Test func noClearChangeSaysSoPlainlyAndGivesNoNumberForTheChange() {
        let text = TrajectoryPresentation.summary(for: sample(.weight, .noClearChange))
        #expect(text.localizedCaseInsensitiveContains("no clear change"))
        #expect(!text.contains("↓") && !text.contains("↑"))
    }

    @Test func coverageIsAlwaysStated() {
        for direction in [TrendDirection.rising, .falling, .noClearChange] {
            let text = TrajectoryPresentation.coverageNote(for: sample(.weight, direction))
            #expect(text.contains("284"))
            #expect(text.contains("365"))
        }
    }

    @Test func weightRendersInThePreferredSystem() {
        // Reuses the shipped Imperial/Metric preference; no second conversion path.
        #expect(TrajectoryPresentation.summary(for: sample(.weight, .falling), system: .imperial)
                    .localizedCaseInsensitiveContains("lb"))
    }
```

- [ ] **Step 2: Implement the presentation, then the state, then the view**

The view: a list of trajectory rows, each with the series name, the summary line, the coverage note, and the window picker (30/90/365, default 90). Series with no measurement are absent. Add one navigation row to `HealthTabView` beside the existing Data sources / Environment rows.

- [ ] **Step 3: Demonstrate the mutant**

Add "because" to any summary string → `aTrajectoryNeverClaimsACause` must fail.

- [ ] **Step 4: Run both suites**

Run: `cd HealthGraphCore && swift test`
Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO`

`SwiftDataMigratorTests` crashes the runner (pre-existing), so the trailing "Test run with N tests" line under-counts. Verify by counting `✔ Suite` lines and grepping for `✘`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(trends): trajectories surface"
```

---

## Device verification

The gate before merge, run by the human partner on a device with real Apple Health history.

1. Health tab → **Trends**. Expect rows only for series with real coverage — on a device without a connected scale, weight should be **absent**, not empty.
2. Check one number against Apple Health directly. Open Health.app, look at the same series over the same window, and confirm the direction and rough magnitude agree. A trajectory that disagrees with Apple's own chart is worse than no trajectory.
3. Switch the window between 30 / 90 / 365. Expect the answer to change with the window — and expect at least one series to say **"no clear change"**. If everything trends on every window, the correction is not working.
4. Toggle Imperial/Metric in the Health tab and confirm weight re-renders.
5. Confirm no row anywhere implies a cause, and that nothing mentions symptoms.
