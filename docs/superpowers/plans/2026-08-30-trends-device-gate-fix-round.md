# Trends device-gate fix round — implementation plan

**Branch:** `health-trajectories` (PR #13). **Spec:** the round's design record
`docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md`
plus the device-gate design approved in chat on 2026-08-30 (reproduced in
the Global Constraints below — that chat approval is the binding authority
for the y-axis rule and the automatic repair).

**Why this round exists.** Leo's device gate on the Trends surface found,
in order of severity:

1. A pre-existing **ingestion defect** that corrupts every daily-statistics
   row two days after it is written: `recomputeRecentDailyStats` passes a
   time-of-day (`now − 2 days`) into `ingestDailyStats`, whose HealthKit
   predicate starts at that instant, so the oldest bucket sums only the
   samples after that time of day — and the pipeline updates the correct
   full-day row in place with the partial one. Confirmed against Apple
   Health: Aug 9–22 steps read 3,504–3,718/day there and 18–656/day in our
   store; today matches exactly because today's day-start is after the
   predicate start. Every daily-stat type's day-2 bucket is affected.
2. The weight **chart plots kilograms** while its summary line converts to
   pounds (`TrajectoriesView` plots `point.value` raw).
3. Each chart's **x-axis shrinks to its own data** (no `chartXScale`), so a
   trailing gap is invisible and cards do not share an axis.
4. The **zero-based auto y-axis** flattens weight (170–173 lb on 0–80) and
   respiratory rate into horizontal lines.
5. The steps summary reads **"91–5944 count"** (raw storage unit, no digit
   grouping).
6. The **"N of 7 days so far" annotation collides** with the line on 52-week
   charts.

## Global Constraints

Binding for every task; reviewers hold implementers to these verbatim.

- **Descriptive only.** No string on the Trends surface may state or imply
  a direction, a cause, or a verdict — no "trend/rising/falling/up/down/
  improving/worsening", no arrows. `TrajectoryPresentationTests.noTrajectoryEverClaimsACauseOrADirection`
  sweeps every summary string; any new user-visible string must be added to
  what that sweep covers or covered by an equivalent assertion.
- **Gaps are gaps.** A week with no data is absent from the series; the
  chart never bridges it and never plots zero for it. No smoothing, no
  fitted line — `interpolationMethod(.linear)` between real weekly points.
- **Chart values are display values.** Whatever unit the summary line shows
  is the unit the chart plots and the axis labels. Weight converts through
  ONE conversion path (`BodyMetricValueFormatter`); no second
  `poundsPerKilogram`-shaped constant anywhere.
- **Whole-day statistics.** Every daily-statistics query HealthKit runs on
  behalf of this app spans whole calendar days: the sample predicate's start
  and the enumeration start are the SAME value, a local-midnight day start.
  A time-of-day must never reach the predicate.
- **Repair is automatic, silent, idempotent, fail-open.** The one-shot
  re-ingest updates rows in place through the existing pipeline (same dedup
  keys), shows no UI, touches neither `HealthImportStatusStore` nor the
  ingestor's user-facing `isRunning`/`progress`/`lastBackfillFailures`, and
  records completion only after every daily type succeeded — a failure
  leaves the version unset so the next launch retries.
- **y-axis rule** (approved 2026-08-30): the y-domain spans the data, is
  never narrower than ±2.5% of the typical value (5% of the midpoint, floor
  1.0), pads 15% of that span below and 40% above (the headroom band the
  "so far" caption lives in), and clamps at 0 — every catalog series is
  non-negative.
- **Shared x-axis:** the x-domain of every card is
  `[windowStart, currentWeekStart]` computed by `TrajectoryService` from the
  same `asOf` it buckets with, carried on the snapshot — the view never
  re-derives the window formula (`WeeklyBucketing.windowStart` stays the
  one place it is written).
- **Core stays UI-free.** Nothing under `HealthGraphCore` imports SwiftUI or
  Charts or names a color. `TrajectorySeries.displayUnit` is a string.
- **No schema change.** UserDefaults keys only (`hg.hk.dailyStatRepairVersion`).
- **Nothing under `HealthGraphCore/Sources/HealthGraphCore/Evidence/` is touched.**
- **TDD** for every behavioral change: write the failing test, run it, see
  it fail for the right reason, implement, see it pass. The report carries
  RED and GREEN evidence.
- **Swift 5 language mode**, Swift 6 toolchain; `HealthKitIngestor` is
  `@MainActor` — statics meant to be called from tests or nonisolated code
  are marked `nonisolated`.
- **Test commands** (use these exact shapes):
  - Package: `cd HealthGraphCore && swift test`
  - App target, focused: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:"Food IntolerancesTests/<SuiteName>"`
  - App build: `xcodebuild -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  - `SwiftDataMigratorTests` is known to crash the runner; never run the
    whole app suite as evidence — run the named suites.
- **Commits:** conventional subject (`fix(scope): …`, `chore(debug): …`),
  a body that explains the root cause when there is one, and the trailer
  lines this repo uses on Claude-authored commits:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01RJE6X52fJ8SX9Pmf7vgfH6`.
  Commit on the current branch; never push.

## File Structure

| File | Task | Change |
|---|---|---|
| `Models/HealthKitProbe.swift` (exists, uncommitted) | 1 | commit as-is (DEBUG diagnostic) |
| `Views/HealthGraphDebugView.swift` (modified, uncommitted) | 1 | commit as-is (probe section) |
| `Models/HealthKitIngestor.swift` | 1 | whole-day windows; `reingestDailyStats(years:)`; error logging; repair version stamped at backfill completion |
| `Models/DailyStatRepair.swift` (new) | 1 | versioned one-shot repair |
| `FoodIntolerancesApp.swift` | 1 | launch hook after `startObserving()` |
| `Food IntolerancesTests/DailyStatWindowTests.swift` (new) | 1 | whole-day window rule |
| `Food IntolerancesTests/DailyStatRepairTests.swift` (new) | 1 | version gate + runner contract |
| `HealthGraphCore/Sources/HealthGraphCore/Trends/TrajectorySnapshot.swift` | 2 | `windowStart`, `currentWeekStart` |
| `HealthGraphCore/Sources/HealthGraphCore/Trends/TrajectoryService.swift` | 2 | populate them |
| `HealthGraphCore/Sources/HealthGraphCore/Trends/TrajectorySeries.swift` | 2 | `displayUnit` |
| `HealthGraphCore/Tests/HealthGraphCoreTests/TrajectoryServiceTests.swift` | 2 | window fields |
| `HealthGraphCore/Tests/HealthGraphCoreTests/TrajectorySeriesTests.swift` | 2 | `displayUnit` |
| `Views/HealthOS/Timeline/BodyMetricValueFormatter.swift` | 2 | numeric `value(kg:unit:)` |
| `Views/HealthOS/Trends/TrajectoryPresentation.swift` | 2 | display values, y-domain, x-domain, grouping, unit |
| `Views/HealthOS/Trends/TrajectoriesView.swift` | 2 | plot display values; pinned axes; headroom caption; hollow ring |
| `Food IntolerancesTests/TrajectoryPresentationTests.swift` | 2 | extended |
| `Food IntolerancesTests/TrajectoryChartRenderTests.swift` | 2 | fixtures gain window fields; imperial render |
| `Food IntolerancesTests/BodyMetricValueFormatterTests.swift` | 2 | `value(kg:unit:)` |

---

### Task 1: Whole-day daily statistics, and a one-shot repair of the rows the old window corrupted

**Where it fits.** The Critical item. Everything Trends charts for steps
(and the daily heart-rate average the evidence engine reads) is only as
good as these rows.

**Step 0 — commit the controller's diagnostic first.** The working tree
already contains two uncommitted files from the gate investigation:
`Models/HealthKitProbe.swift` (new) and the "HealthKit probe" section in
`Views/HealthGraphDebugView.swift`. Do not modify them. Commit them exactly
as they are, before any other change, as their own commit:
`chore(debug): HealthKit probe on the Health Graph Debug screen` with a
one-paragraph body: a DEBUG-only diagnostic that shows raw samples and the
ingestor's daily-statistics query side by side for one quantity type; it is
what proved HRV was absent from HealthKit (Oura does not write it) and
that steps were being clobbered.

**1a. The whole-day window rule (TDD).**

Add to `HealthKitIngestor` (nonisolated, pure, injectable calendar):

```swift
/// The whole-calendar-day range a daily-statistics query covers. `start`
/// is floored to local midnight so the HealthKit sample predicate and the
/// bucket enumeration begin at the SAME instant — a time-of-day reaching
/// the predicate is exactly the defect this pins (the day-2 bucket summed
/// only the samples after that time of day and overwrote the full-day row).
nonisolated static func dailyStatRange(from start: Date, to end: Date,
                                       calendar: Calendar = .current) -> DateInterval

/// The trailing window `recomputeRecentDailyStats` re-reads: the start of
/// the calendar day two days before `now`, through `now`.
nonisolated static func recentDailyStatWindow(now: Date,
                                              calendar: Calendar = .current) -> DateInterval
```

Tests in a new `Food IntolerancesTests/DailyStatWindowTests.swift`
(Swift Testing, `@testable import Food_Intolerances`, a fixed UTC or
America/New_York calendar built in the test — never `.current`):

- `dailyStatRangeFloorsStartToMidnight`: start = 2026-08-28 23:10 local →
  `range.start` == 2026-08-28 00:00 local; `range.end` == the `end` passed.
- `dailyStatRangeIsIdentityAtMidnight`: a start already at 00:00 is unchanged.
- `recentWindowStartsAtMidnightTwoDaysBack`: now = 2026-08-30 23:10 local →
  start == 2026-08-28 00:00 local, end == now. This is the exact input that
  produced Leo's 18-step days.
- `recentWindowSurvivesDSTFallBack`: now = 2025-11-03 08:00 America/New_York
  (the Monday after fall-back) → start == 2025-11-01 00:00 New_York; assert
  via calendar components (year/month/day/hour), not seconds arithmetic.

Then wire them in:

- `ingestDailyStats(for:from:to:)`: `let range = Self.dailyStatRange(from: start, to: end)`;
  the predicate is `HKQuery.predicateForSamples(withStart: range.start, end: range.end)`;
  `anchorDate: range.start`; `enumerateStatistics(from: range.start, to: range.end)`.
  There must be no other `Date` in that function that could reach the
  predicate — one range value, used everywhere.
- `recomputeRecentDailyStats(for:)`: `let window = Self.recentDailyStatWindow(now: Date())`
  → `ingestDailyStats(for: type, from: window.start, to: window.end)`; the
  catch logs the actual error:
  `Logger.error(error, message: "HK daily-stat recompute failed for \(type.identifier)", category: .data)`.
- `backfill(years:)` is untouched apart from step 1c.

**1b. `reingestDailyStats(years:)` on the ingestor.**

```swift
/// Re-reads every daily-statistics type over the last `years` and writes
/// the whole-day values through the normal pipeline (in-place updates via
/// the existing dedup keys). Used by `DailyStatRepair` only. Throws if ANY
/// type failed — after re-ingesting the rest — so a caller can refuse to
/// mark the repair done. Touches none of the user-facing import state
/// (`isRunning`, `progress`, `lastBackfillFailures`, `HealthImportStatusStore`).
func reingestDailyStats(years: Int = 1) async throws -> IngestSummary
```

Implementation: `start = Calendar.current.date(byAdding: .year, value: -years, to: Date())!`,
loop `Self.dailyStatTypes`, accumulate the summary, collect per-type errors,
and after the loop throw a `DailyStatRepairError.typesFailed([String])`
(`LocalizedError`, the failed identifiers in its description) if any
failed. Do not call `requestAuthorization()` here — the repair only runs
after a completed backfill, which already did.

**1c. The one-shot repair — new `Models/DailyStatRepair.swift`.**

```swift
/// One-shot, versioned repair of daily-statistics rows written by the
/// pre-fix trailing-window recompute (see `HealthKitIngestor.dailyStatRange`).
/// Runs once per install after the shell mounts, silently; bumping
/// `currentVersion` schedules another pass on every install.
enum DailyStatRepair {
    static let versionKey = "hg.hk.dailyStatRepairVersion"
    static let currentVersion = 1

    /// Pure gate: due only when a backfill has completed on this install
    /// (there is nothing to repair before one) and the stored version is
    /// behind `currentVersion`.
    static func isDue(storedVersion: Int, backfillCompleted: Bool) -> Bool

    /// Runs `reingest` if due, then stamps `currentVersion` — ONLY on
    /// success. A throw is logged and leaves the version unset so the
    /// next launch retries. `reingest` is injected so the contract is
    /// testable without HealthKit.
    static func runIfDue(defaults: UserDefaults = .standard,
                         reingest: () async throws -> Void) async
}
```

Production call site — `FoodIntolerancesApp.swift`, the shell branch's
existing `.task { healthKitIngestor.startObserving() }` becomes:

```swift
.task {
    healthKitIngestor.startObserving()
    await DailyStatRepair.runIfDue { try await healthKitIngestor.reingestDailyStats() }
}
```

Stamping on fresh installs: at the end of `backfill(years:)`, right after
`UserDefaults.standard.set(true, forKey: Self.backfillCompletedKey)`, also
`UserDefaults.standard.set(DailyStatRepair.currentVersion, forKey: DailyStatRepair.versionKey)` —
a backfill run by the fixed code already wrote whole days, so the repair
must not re-read a year for nothing. (Leo's phone, whose backfill ran on
the old code, has no stamp → the repair runs once on first launch.)

Tests in a new `Food IntolerancesTests/DailyStatRepairTests.swift` (fresh
`UserDefaults(suiteName:)` per test, the pattern in
`HealthKitIngestorProfileSeedTests`):

- `isDue` matrix: (0, true) → true; (1, true) → false; (0, false) → false;
  (currentVersion + 1, true) → false.
- `runIfDueSkipsWhenNotDue`: backfill flag unset → `reingest` never called,
  version stays 0.
- `runIfDueStampsVersionOnSuccess`: flag set, version 0 → `reingest` called
  once, version == `currentVersion`.
- `runIfDueLeavesVersionUnsetOnFailure`: `reingest` throws → version stays
  0 (a second `runIfDue` would call again — assert the call count reaches 2).

**Verification for the report:** `DailyStatWindowTests`,
`DailyStatRepairTests`, and `HealthKitIngestorProfileSeedTests` green with
RED/GREEN evidence; app build succeeds; `cd HealthGraphCore && swift test`
untouched (no package change in this task — say so rather than re-running
it).

**Commit(s):** after step 0's chore commit, one fix commit
`fix(ingestion): whole-day windows for daily statistics, and a one-shot repair of the rows the trailing recompute clobbered`
whose body explains the mechanism in the "Why this round exists" item 1
above in your own words, with the Apple Health numbers.

---

### Task 2: The chart plots what the summary says — display units, a shared window axis, a readable y-axis, honest copy

**Where it fits.** The Trends surface built in the round's Task 8; Task 1
of this round fixed the data underneath it. Read `TrajectoriesView.swift`,
`TrajectoryPresentation.swift`, `TrajectorySnapshot.swift`,
`TrajectoryService.swift`, `TrajectorySeries.swift` and the three existing
test files before starting.

**2a. Snapshot carries its window (package, TDD).**

`TrajectorySnapshot` gains two stored `public let` fields, both required
in `init` (update the four existing call sites — service + three test
fixtures — no defaulted parameters):

```swift
/// First calendar day of the window (`WeeklyBucketing.windowStart`).
public let windowStart: Date
/// Start of the calendar week containing `asOf` — the right edge of the
/// chart and the only week whose dayCount may legitimately be < 7.
public let currentWeekStart: Date
```

`TrajectoryService.snapshots(window:asOf:)` sets `windowStart` from the
`windowStart` it already computes and `currentWeekStart` from
`calendar.dateInterval(of: .weekOfYear, for: asOf)!.start`.

Test (`TrajectoryServiceTests`, using its existing `now`/`utc` fixtures):
`snapshotCarriesItsWindow` — for a weeks13 run over `sixWeeksWeight()`,
the weight snapshot's `windowStart == WeeklyBucketing.windowStart(weeksBack: 13, asOf: now, calendar: utc)`
and `currentWeekStart == utc.dateInterval(of: .weekOfYear, for: now)!.start`;
and `windowStart` is exactly 12 calendar weeks before `currentWeekStart`.

**2b. `TrajectorySeries.displayUnit` (package, TDD).**

```swift
/// The unit label shown to a person. The storage unit stays what
/// `HealthKitSampleMapper` writes ("count" for steps); only the label
/// changes. Weight's label is unit-system-dependent and resolved by the
/// app-side presentation, so it stays "kg" here.
public var displayUnit: String { self == .steps ? "steps" : unit }
```

Test in `TrajectorySeriesTests`: `.steps.displayUnit == "steps"`,
`.steps.unit == "count"` (storage untouched), and every other case's
`displayUnit == unit`.

**2c. Numeric weight conversion (app, TDD).**

`BodyMetricValueFormatter` gains
`static func value(kg: Double, unit: WeightUnit) -> Double` (kg → kg; kg →
kg × poundsPerKilogram), and `line(kg:unit:)` formats `value(kg:unit:)` —
the private constant stays the single conversion source. Tests in
`BodyMetricValueFormatterTests` (extend the existing suite): 74 kg → 74.0
(kilograms); 74 kg → 163.14 ± 0.01 (pounds); `line` still renders
"163.1 lb".

**2d. Presentation helpers (app, TDD) — all in `TrajectoryPresentation`, all pure:**

```swift
/// A weekly value in the unit the summary line shows: weight through
/// BodyMetricValueFormatter.value(kg:unit:); every other series unchanged.
static func displayValue(_ value: Double, for series: TrajectorySeries, system: UnitSystem) -> Double

/// (low, high) of the snapshot's weekly medians in display units.
static func displayRange(for snapshot: TrajectorySnapshot, system: UnitSystem) -> (low: Double, high: Double)

/// The y-axis rule (Global Constraints): span the data, floor the span at
/// 5% of max(|midpoint|, 1), pad 15% of the span below and 40% above, clamp
/// at 0. Always low < high, even for a flat series.
static func yDomain(low: Double, high: Double) -> ClosedRange<Double>

/// Every card's x-domain: windowStart...currentWeekStart.
static func xDomain(for snapshot: TrajectorySnapshot) -> ClosedRange<Date>

/// The label shown for the series' unit: weight → the unit system's
/// abbreviation ("kg"/"lb"); else `series.displayUnit`.
static func unitLabel(for series: TrajectorySeries, system: UnitSystem) -> String
```

`summary(for:system:)` uses `displayRange` + `unitLabel`, and
`formattedNumber` groups digits with a `NumberFormatter` (`.decimal`,
`minimumFractionDigits 0`, `maximumFractionDigits 1`, the current locale)
— "5944" → "5,944", "6.7" → "6.7", "5944.0" → "5,944". Weight keeps one
decimal place as today ("170.2").

Tests to add in `TrajectoryPresentationTests` (keep every existing test
green; the banned-language sweep must keep covering `summary`):

- `stepsSummaryReadsStepsWithGrouping`: a steps snapshot with medians
  91…5944 → the summary contains "91–5,944 steps" and does not contain
  "count".
- `weightRangeConvertsForTheChartToo`: `displayRange` of the 68–74 kg
  fixture under `.imperial` is (149.9…, 163.1…) within 0.05, under
  `.metric` (68, 74); `displayValue(70, .weight, .imperial)` ≈ 154.32;
  `displayValue(70, .steps, .imperial) == 70`.
- `yDomainHasShapeForNarrowData`: `yDomain(low: 77.2, high: 78.5)` → lower
  bound in 75.0…75.6 and upper in 81.0…81.7 (5% of 77.85 = 3.89 span; 15%
  below, 40% above); `yDomain(low: 70, high: 70)` still has `lower < upper`;
  `yDomain(low: 91, high: 9325).lowerBound == 0` (clamped);
  `yDomain(low: 0, high: 0)` → `0...` something > 0.
- `xDomainIsTheWindow`: equals `snapshot.windowStart...snapshot.currentWeekStart`.
- `unitLabelFollowsTheUnitSystemForWeightOnly`.

**2e. The view (`TrajectoriesView.swift`).** Requirements, not a script —
you own the SwiftUI:

- Every `LineMark`/`PointMark` y is `TrajectoryPresentation.displayValue(point.value, for: snapshot.series, system: system)`.
- `.chartYScale(domain: TrajectoryPresentation.yDomain(low:high:))` over
  `displayRange` — replaces `applyingFlatSeriesYDomain` entirely (delete
  it; the y-rule covers the flat case by construction — keep the
  `flatSeriesRendersWithoutTrapping` render test as the proof).
- `.chartXScale(domain: TrajectoryPresentation.xDomain(for: snapshot), range: .plotDimension(startPadding: 8, endPadding: 8))`
  so the current-week point at the right edge is not clipped.
- Explicit x-axis labels: 13 weeks → month + day (e.g. "Jun 7"); 52 weeks →
  abbreviated month + two-digit year (e.g. "Dec '25"); automatic mark
  placement is fine.
- The current-week point is a hollow ring (stroke-bordered circle symbol,
  accent color, larger than the filled dots); the caption
  "\(dayCount) of 7 days so far" is drawn in the headroom band at the
  plot's top-trailing corner via `chartOverlay` (aligned to the plot area,
  4 pt inset), NOT attached to the point. Same font/color as today
  (`.caption2`, `HealthTheme.inkMuted`). The caption is user-visible text:
  add it to the banned-language sweep's coverage (the sweep iterates
  strings the presentation produces — expose the caption as
  `TrajectoryPresentation.currentWeekCaption(dayCount:)` and include it).
- The accessibility value of the chart still reads the summary.
- `currentWeekStart` comes from the snapshot, not `Date()`.

Render tests (`TrajectoryChartRenderTests`): update the fixture for the new
snapshot fields; add `imperialWeightRendersWithoutTrapping` (same
four-week fixture, `system: .imperial`) and
`currentWeekRingAndCaptionRenderWithoutTrapping` (a fixture whose last
week IS `currentWeekStart` with `dayCount: 1`). `ImageRenderer` proves
layout runs; the value-level behavior is pinned by 2d's pure tests.

**Verification for the report:** package `swift test` green (count it);
`TrajectoryPresentationTests`, `TrajectoryChartRenderTests`,
`BodyMetricValueFormatterTests` green with RED/GREEN evidence; app build
succeeds.

**Commits:** you may split package and app work into two commits
(`feat(trends): snapshot carries its window; steps display unit` then
`fix(trends): chart plots display units on a shared window axis with a readable y-domain`)
or make one; either way the body names the four gate findings this closes
(kg chart, shrinking x-axis, zero-based y-axis, "count").

---

## Device verification (controller, after both tasks)

Install on Leo's iPhone; Leo re-checks Trends: weight chart in lb with
shape; every card shares the axis and the weight card shows a hole after
Aug 17; steps history restored (Aug 9–22 in the thousands after the
one-shot repair — visible in the Steps card and the Timeline); "steps" with
grouping; caption in the headroom band; no direction words.
