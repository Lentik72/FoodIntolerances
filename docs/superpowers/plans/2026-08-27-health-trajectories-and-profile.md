# Health Trajectories and Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show what the device-recorded health data actually did — a chart of weekly medians with
gaps drawn as gaps, the coverage it rests on, and the observed range — without asserting a single
cause **or a single direction**.

**Architecture:** Two correctness fixes to existing data handling first, then pure description in
`HealthGraphCore` (calendar-week medians → coverage → range, packaged as structured snapshot
values), then a charted SwiftUI surface. Nothing reads or writes a `Relationship`. No trend
statistic exists anywhere in this plan.

**Tech Stack:** Swift 6, Swift Testing, GRDB, Swift Charts, `HealthGraphCore`, HealthKit.

**Spec:** `docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md` (revised
2026-08-28). **Decision record:** `docs/OPEN-QUESTION-trends-verdict.md`.

## Why this plan was rewritten (again)

The previous version shipped a directional verdict (Mann–Kendall + Hamed–Rao, Theil–Sen with a Sen
interval, a measurement-density guard, effect floors, Benjamini–Hochberg). Two adversarial audit
rounds each found that design substantively wrong, and the recorded decision cut it: selection in
self-initiated series lives in *which* days a person measures while any guard sees only *how
many*, so the verdict machinery was unfixable in principle for weight and dishonest at the default
window for everything else. **Tasks 4–7 and 9 of the previous plan are deleted, not deferred-in-
place.** A restricted, wear-guarded direction layer for device-recorded series is a possible
future round with its own requirements (see the spec's Follow-ups); nothing here builds toward it
except by keeping snapshots as structured values.

This revision also fixes defects that were independent of the decision: the window convention
broke in DST timezones (86 400-second arithmetic), the bucketing rationale was inverted
(window-anchored buckets shift daily; calendar anchoring is what delivers stability), whole-week
windows replace the 365 = 52×7+**1** stub bucket, the service's calendar is now injected rather
than implied, and "chartable" is decoupled from any coverage gate.

## Global Constraints

- **Nothing here touches the evidence engine.** No file under `Evidence/` is modified or called.
- **Windows: the last 13 or 52 calendar weeks, default 13.** Whole calendar weeks in the injected
  calendar (respecting `firstWeekday`), ending with the week containing `asOf` (possibly
  partial). **All date arithmetic uses calendar operations** (`date(byAdding:)`,
  `dateInterval(of:)`) — never 86 400-second math. The previous convention produced a 91-day
  "90-day window" across spring-forward, and its UTC-midnight fixtures could not catch it: at
  least one bucketing test must run in a DST-observing timezone (`America/New_York`).
- **No causal language:** not "because", "caused", "led to", "due to", "linked to", "resulted in".
- **No directional language in any trajectory copy:** no "trend"/"trending", "rising", "falling",
  "increas…", "decreas…", "improv…", "worsen…", "declin…", "climb…", no `↑`/`↓`, and no
  whole-word "up"/"down". Say what was recorded, over what period, from how many days, and stop.
- **No category names.** No blood-pressure or BMI categories — assigning one is disease
  classification.
- **No invented statistical constants remain.** The previous plan's `TrendConfig` (coverage
  floors, effect floors) is gone with the verdict. The only parameters are the two window lengths.
- **Snapshots are values, not strings.** The doctor-report round renders the same structs.
- **Every task ends with `cd HealthGraphCore && swift test` green.** Tasks whose tests live in the
  app target additionally run `xcodebuild test … -parallel-testing-enabled NO
  -only-testing:"Food IntolerancesTests/<Suite>"` — the package command does not compile that
  target, so those tests are otherwise never executed. (`SwiftDataMigratorTests` crashes the full
  app run; count `✔ Suite` lines and grep `✘` rather than trusting totals.)
- **Every test struct declares its own calendar helper(s).** Suites that exercise calendar
  behaviour build them from `DateComponents` in the suite's own named timezone — raw epoch
  arithmetic in fixtures is exactly how the DST bug hid.
- **Loops assert their collection is non-empty; string assertions assert non-emptiness.**
  Otherwise the test passes vacuously.
- Mutation discipline: apply the mutant, confirm the **named** test fails, restore, report both
  directions. **If a mutant does not kill its test, say so — that is the finding.**

## File Structure

**Package:** Create `Trends/WeeklyBucketing.swift`, `Trends/TrajectorySeries.swift`,
`Trends/TrajectorySnapshot.swift`, `Trends/TrajectoryService.swift`, `Trends/PersonProfile.swift`.
Modified: `Timeline/SleepSessionBuilder.swift`, `Ingestion/HealthKitSampleMapper.swift`.

**App:** Create `Views/HealthOS/Trends/{TrajectoryPresentation,TrajectoriesViewState,TrajectoriesView}.swift`,
`Views/HealthOS/Shared/NonDiagnosticFooter.swift`. Modified: `Models/UserProfile.swift`,
`Models/HealthKitIngestor.swift`, `Views/Profile/UserProfileView.swift`,
`Views/HealthOS/Timeline/BodyMetricValueFormatter.swift`, `Views/HealthOS/Health/HealthTabView.swift`,
plus the Insights and Experiments surfaces (non-diagnostic footer only).

`TrajectoryService` is the only file that knows about both the database and the bucketing.

---

### Task 1: Sleep sessions must union overlapping segments

A shipped bug, not a trajectory feature. `SleepSessionBuilder.session(from:)` does
`totals[subtype] += duration` and sums the stage totals, with no clamp anywhere.

Two independent ingest paths feed it, and the fix must cover both:

- **Same subtype, overlapping times.** `IngestPipeline` deliberately keeps both ("coverage is
  never truncated" — its overlap query is scoped by `subtype`), on the assumption a consumer will
  union them. Nothing does.
- **Different subtypes.** A watch writing `asleepCore`/`asleepDeep`/`asleepREM` and a ring writing
  `asleepUnspecified` over the same hours never even reach that overlap check — the subtype-scoped
  query finds nothing to compare, so both insert unconditionally. This is the more common
  real-world shape. Two sleep trackers produce roughly double the sleep, with no clamp anywhere —
  nothing prevents a 14-hour night. Functional-medicine and peptide patients are among the
  likeliest people to wear two, so this is the design partner's exact population.

**Files:** Modify `HealthGraphCore/Sources/HealthGraphCore/Timeline/SleepSessionBuilder.swift`;
extend `HealthGraphCore/Tests/HealthGraphCoreTests/SleepSessionBuilderTests.swift`.

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

Collect `(start, end)` for every asleep-stage segment, sort by start, merge overlapping intervals,
and derive `asleepMinutes` from the merged total, clamped to the session's own span. Keep the
per-stage totals for display but document that they are approximate when sources overlap — do not
silently present a doubled stage breakdown alongside a corrected total.

- [ ] **Step 3: Check the blast radius, and do not absorb it**

`asleepMinutes` feeds `ShortSleepExposureSource` in the evidence engine and the Timeline sleep
row. Run the full package suite and report any existing test whose expectations move. **Do not
edit an existing test to accommodate this change** — a shifted sleep total can change a mined
relationship, and that is the controller's call, not the implementer's.

Audited: no existing fixture in `SleepSessionBuilderTests`, `TimelineDayBuilderTests`,
`ExposureSourceTests` or `TimelineViewModelTests` contains two overlapping *asleep-stage*
segments — the one named `overlappingSegmentsChainByFurthestEnd` overlaps `inBed` with
`asleepCore`, and `inBed` is excluded from `asleepMinutes` by definition. So the expectation is
that nothing existing moves. If something does, that is a finding.

**The user-visible consequence is a product question this plan does not answer.** A two-tracker
user's nights were being doubled, so short-sleep nights looked long and `ShortSleepExposureSource`
never flagged them. After the fix they flag — and `InsightsRefreshCoordinator` recomputes silently
on the next app open, so new sleep-linked relationships can appear, and existing ones shift, with
no in-app signal. Whether that warrants a user-facing note is the controller's call; **record the
decision rather than letting it happen by default.**

- [ ] **Step 4: Mutants**

1. Sum durations without unioning → `twoTrackersRecordingTheSameNightDoNotDoubleIt` fails.
2. Drop the span clamp → `asleepTimeNeverExceedsTheSessionsOwnSpan` fails.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix(sleep): union overlapping segments before totalling asleep time"
```

---

### Task 2: Capture the HealthKit source at ingest

`HKSource`, `HKSourceRevision`, `HKDevice` and `bundleIdentifier` appear nowhere in the codebase;
`mapSample` keeps only value, timestamp, unit and timezone, and every HealthKit row collapses to
`EventSource.healthKit`. A new watch that shifts the HRV baseline, or a second scale reading
1.5 kg differently, is therefore **undetectable** — permanently, for data already ingested.

This round only **stores** it. Using it is a later round.

**Be precise about what that buys.** `HealthKitIngestor` reads through `HKAnchoredObjectQuery`
with the anchor persisted per sample type in `UserDefaults`. An anchored query only redelivers
samples added or changed *since* the anchor — so for any user who has already synced, historical
samples are **never** redelivered and will carry no source identifier **permanently**, not merely
"not yet". This captures source for new samples only.

That is still worth doing — it is the difference between a device-change detector being possible
in six months and being impossible forever — but a later round consuming this data must expect nil
across all pre-existing history. **Raise as a decision for the controller:** a one-time anchor
reset for the per-sample types (weight, HRV, resting HR, respiratory rate) would re-ingest history
*with* source, and `IngestPipeline` dedups by key so re-ingest updates in place rather than
duplicating. It costs a long re-read. Do not do it as part of this task; report the trade-off.

**Files:** Modify `Models/HealthKitIngestor.swift` and
`HealthGraphCore/Sources/HealthGraphCore/Ingestion/HealthKitSampleMapper.swift`; test
`HealthGraphCoreTests/HealthKitSampleMapperTests.swift`.

- [ ] **Step 1: Decide where it goes, and record the reasoning**

`HealthEvent.metadata` is an existing `Data?` blob with an encoder already used for routes and
cycle metadata. Prefer it: no migration risk, and nothing in this round queries by source. If you
conclude a column is genuinely required, **stop and report** rather than adding one — this repo's
SwiftData migration tests already crash the runner and schema changes are not free here.

- [ ] **Step 2: Write the failing test, implement, run**

Thread `HKSource.bundleIdentifier` (and `HKDevice.name` when present) through the sample-data
structs the mapper already accepts, so the mapper stays testable without HealthKit present.

**Keep it a flat `[String: String]`.** Every metadata consumer in the codebase decodes
`[String: String]` and reads its own key, so an added string key is invisible to all of them.
Nesting a sub-object instead would make that row's metadata fail to decode for *every* existing
consumer — all-or-nothing per row.

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

### Task 3: Calendar-week bucketing, counts and coverage

**Files:** Create `HealthGraphCore/Sources/HealthGraphCore/Trends/WeeklyBucketing.swift`; test
`HealthGraphCore/Tests/HealthGraphCoreTests/WeeklyBucketingTests.swift`.

**Interfaces:** `DailyPoint(day:value:)`, `WeeklyPoint(weekStart:value:dayCount:)`,
`SeriesCoverage(daysWithData:daysInWindow:weeksWithData:weeksInWindow:)`,
`WeeklyBucketing.bucket(_:weeksBack:asOf:calendar:) -> (weeks: [WeeklyPoint], coverage: SeriesCoverage)`.

**Semantics, pinned:**

- Buckets are **calendar weeks in the supplied calendar** (`dateInterval(of: .weekOfYear)`),
  respecting `firstWeekday`. This is what makes bucket membership stable: the same reading lands
  in the same week no matter which day the analysis runs. (The previous plan claimed this property
  for window-anchored buckets, which have the opposite behaviour — windowStart moves with the
  clock and every boundary shifts daily.)
- The window is the **last `weeksBack` calendar weeks ending with the week containing `asOf`**.
  The current week may be partial and is included as such — every *other* bucket holds exactly
  seven days, which retires the previous design's stub bucket (365 = 52×7+1 ended every year view
  on a one-day "weekly median").
- `daysInWindow` counts window start **through `asOf`**, not through the end of the partial week —
  otherwise coverage can never reach 100% mid-week.
- Two levels of median, both load-bearing: readings on one day collapse to that day's median
  first, then the week is the median of its day medians. `dayCount` counts DAYS, not readings.
- Empty weeks are **absent**, never zero.
- All arithmetic through the calendar; no `86_400` anywhere in the file.

- [ ] **Step 1: Write the failing tests**

Two calendars per suite, built from `DateComponents`, never raw epoch offsets: `utc` (Gregorian,
UTC) and `nyc` (Gregorian, `America/New_York`) — the DST test is the one the previous plan's
UTC-midnight fixtures could not express. Helpers `date(_:_:_:in:)` and `p(_:_:_:_:in:)` build
dates and points from components in the named calendar.

```swift
    @Test func aReadingLandsInTheSameWeekWhicheverDayTheAnalysisRuns() {
        // Calendar anchoring, the actual stability property. Analyse the same
        // corpus on Tuesday and again on Wednesday: every reading keeps its week.
        let reading = [DailyPoint(day: date(2026, 8, 12, in: utc), value: 70)]
        let tue = WeeklyBucketing.bucket(reading, weeksBack: 13, asOf: date(2026, 8, 18, in: utc), calendar: utc)
        let wed = WeeklyBucketing.bucket(reading, weeksBack: 13, asOf: date(2026, 8, 19, in: utc), calendar: utc)
        #expect(tue.weeks.map(\.weekStart) == wed.weeks.map(\.weekStart))
        #expect(tue.weeks.map(\.value) == wed.weeks.map(\.value))
    }

    @Test func weeksRespectTheUsersFirstWeekday() {
        // Monday-start calendar: Sunday and Monday readings are DIFFERENT weeks.
        var cal = utc; cal.firstWeekday = 2
        let pts = [DailyPoint(day: date(2026, 8, 16, in: cal), value: 1),   // Sunday
                   DailyPoint(day: date(2026, 8, 17, in: cal), value: 2)]   // Monday
        let out = WeeklyBucketing.bucket(pts, weeksBack: 13, asOf: date(2026, 8, 18, in: cal), calendar: cal)
        #expect(out.weeks.count == 2)
    }

    @Test func aWeeksValueIsItsMedianNotItsMean() {
        // One bad reading — a different scale, a suitcase — must not move the week.
        let pts = [p(2026, 8, 10, 70), p(2026, 8, 11, 70.5), p(2026, 8, 12, 71), p(2026, 8, 13, 200)]
        let out = WeeklyBucketing.bucket(pts, weeksBack: 13, asOf: date(2026, 8, 15, in: utc), calendar: utc)
        #expect(out.weeks.last!.value == 70.75)   // median, not the mean of 102.9
    }

    @Test func emptyWeeksAreAbsentNotZero() {
        // A week with no readings is missing data. Emitting 0 makes a gap look
        // like a crash to the floor — the worst rendering error available here.
        let pts = [p(2026, 6, 1, 70), p(2026, 8, 10, 71)]
        let out = WeeklyBucketing.bucket(pts, weeksBack: 13, asOf: date(2026, 8, 15, in: utc), calendar: utc)
        #expect(out.weeks.count == 2)
        #expect(!out.weeks.contains { $0.value == 0 })
    }

    @Test func multipleReadingsOnOneDayCollapseToThatDaysMedianFirst() {
        // Three weigh-ins on Monday must not out-vote the other six days.
        let pts = [p(2026, 8, 10, 70), p(2026, 8, 10, 72), p(2026, 8, 10, 74), p(2026, 8, 11, 80)]
        let out = WeeklyBucketing.bucket(pts, weeksBack: 13, asOf: date(2026, 8, 15, in: utc), calendar: utc)
        #expect(out.coverage.daysWithData == 2)    // two days, not four readings
        #expect(out.weeks.last!.value == 76.0)     // median of [72, 80]
        #expect(out.weeks.last!.dayCount == 2)
    }

    @Test func coverageDenominatorEndsAtToday() {
        // Mid-week, a perfect logger must be at 100% — the denominator stops at
        // asOf, not at the end of the partial week.
        var cal = utc; cal.firstWeekday = 2
        let pts = (0..<3).map { p(2026, 8, 17 + $0, 70) }                    // Mon–Wed
        let out = WeeklyBucketing.bucket(pts, weeksBack: 1, asOf: date(2026, 8, 19, in: cal), calendar: cal)
        #expect(out.coverage.daysInWindow == 3)
        #expect(out.coverage.daysWithData == 3)
    }

    @Test func dstSpringForwardDoesNotBendTheWindow() {
        // The bug the previous plan's convention shipped: 86 400-second math
        // across 2026-03-08 in America/New_York yields a window one day wrong.
        // expectedDays is computed independently via calendar day-counting.
        let pts = [p(2026, 3, 6, 70, in: nyc), p(2026, 3, 9, 71, in: nyc)]
        let out = WeeklyBucketing.bucket(pts, weeksBack: 13, asOf: date(2026, 3, 12, in: nyc), calendar: nyc)
        #expect(out.weeks.count == 2)                                   // different weeks
        #expect(out.coverage.daysInWindow == expectedDays(weeksBack: 13, asOf: date(2026, 3, 12, in: nyc), calendar: nyc))
    }
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement** — per the pinned semantics; one `median(_:)` helper
  (`precondition(!xs.isEmpty)`; even counts average the middle pair).

- [ ] **Step 4: Mutants**

1. Mean instead of median per week → `aWeeksValueIsItsMedianNotItsMean` fails.
2. Emit zero-valued weeks for gaps → `emptyWeeksAreAbsentNotZero` fails.
3. Skip the per-day median → `multipleReadingsOnOneDayCollapseToThatDaysMedianFirst` fails.
4. Compute week starts with `weekStart + 7 * 86_400` → `dstSpringForwardDoesNotBendTheWindow` fails.
5. Extend the denominator to the partial week's end → `coverageDenominatorEndsAtToday` fails.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(trends): calendar-week bucketing with counts and coverage"
```

---

### Task 4: Series catalog and extraction

**Files:** Create `Trends/TrajectorySeries.swift`; test `TrajectorySeriesTests.swift`.

Six series: `weight`, `sleepDuration`, `steps`, `restingHeartRate`, `hrv`, `respiratoryRate`.
**No blood pressure** (see the spec). Public `category`, `subtype`, `unit`, `displayName`,
`dailyPoints(from:calendar:)`.

Subtypes come from `HealthKitSampleMapper`'s existing tables — read that file rather than retyping
them. For the record (verified): weight → `.bodyMetric`, sleep → `.sleep`, steps → `.exercise`,
and exactly **three** series share `.vitals` (restingHeartRate, hrv, respiratoryRate) — four
categories total, which Task 5's read budget depends on.

- [ ] **Step 1: Write the failing tests** (declare the suite's own `utc`)

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
        // Protects the copy sweep in Task 8 from passing over an empty
        // collection, and pins blood pressure OUT.
        #expect(TrajectorySeries.allCases.count == 6)
        #expect(!TrajectorySeries.allCases.contains { $0.displayName.isEmpty || $0.unit.isEmpty })
        #expect(!TrajectorySeries.allCases.contains { "\($0)".localizedCaseInsensitiveContains("bloodPressure") })
    }
```

- [ ] **Step 2: Run, implement, run**

Weight, resting HR, HRV and respiratory rate are direct `(category, subtype)` reads. Steps are
already daily-aggregated on ingest — read, do not re-aggregate. Sleep goes through
`SleepSessionBuilder.sessions(from:timeZone:)` (with Task 1's union), filtered to
`kind == .night`, value `asleepMinutes / 60`, attributed to the start-of-day of the session
**end**.

- [ ] **Step 3: Mutants**

1. Attribute sleep to the session start → `sleepUsesNightSessionsAndIsAttributedToTheWakingDay` fails.
2. Match on category only → `aSeriesReadsOnlyItsOwnSubtype` fails.
3. Stop filtering `deletedAt` → `deletedEventsAreExcluded` fails.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(trends): series catalog and extraction"
```

---

### Task 5: `TrajectoryService` — snapshots, one read per category

**Files:** Create `Trends/TrajectorySnapshot.swift`, `Trends/TrajectoryService.swift`; test
`TrajectoryServiceTests.swift`.

**Interfaces:**

```swift
public enum TrendWindow: Int, CaseIterable, Sendable { case weeks13 = 13, weeks52 = 52 }

/// A charted series with its coverage. A VALUE, not a rendered string: the
/// doctor-report round renders these rather than recomputing them. Carries no
/// direction, no p-value, no verdict of any kind — see the decision record.
public struct TrajectorySnapshot: Sendable {
    public let series: TrajectorySeries
    public let window: TrendWindow
    public let weeks: [WeeklyPoint]          // calendar-week medians; gaps are absent entries
    public let coverage: SeriesCoverage
    public let rangeLow: Double              // min weekly median in the window
    public let rangeHigh: Double             // max weekly median in the window
}

public struct TrajectoryService: Sendable {
    public init(eventStore: any EventStore, calendar: Calendar)
    public func snapshots(window: TrendWindow, asOf: Date) async throws -> [TrajectorySnapshot]
}
```

- **The calendar is injected, not implied.** Production passes the user's current calendar; a
  23:30 weigh-in belongs to different days in UTC and local time, and this repo timezone-stamps
  events precisely because it cares.
- **One `events(in:category:)` call per category the catalog needs — exactly four** (bodyMetric,
  sleep, exercise, vitals). Not six (three series share `.vitals` — a per-series loop is the N+1
  shape this repo already paid ~6.9 s per ten Insights cards to fix), and not one nil-category
  fetch (that reads the entire corpus — symptoms, mood, environment, ~38k events — to chart six
  series).
- **The shared interval starts one day before the window** so a night session spanning the
  boundary keeps its earlier segments; the bucketing window filter drops the extra day for every
  other series. This is deliberate and the implementation must say so in a comment.
- **Any data ⇒ a snapshot.** There is no coverage gate: chartable was decoupled from
  verdict-eligible, and there is no verdict. A series with no data in the window is omitted.
- Output in catalog order.

- [ ] **Step 1: Write the tests**

```swift
    @Test func theCorpusIsReadOncePerCategoryRegardlessOfSeriesCount() {
        // Call-count guarded, following InsightsViewModelTests. Exactly four,
        // with distinct non-nil categories: six would be the N+1, one would be a
        // nil-category fetch of the whole corpus.
        let counting = CountingEventStore(wrapping: store)
        _ = try await TrajectoryService(eventStore: counting, calendar: utc)
            .snapshots(window: .weeks52, asOf: Self.now)
        #expect(counting.calls.value.count == 4)
        #expect(Set(counting.calls.value.map(\.category)).count == 4)
        #expect(!counting.calls.value.contains { $0.category == nil })
    }

    @Test func theFetchStartsOneDayEarlyForBoundarySpanningSleep() {
        // A night beginning 23:00 the day before the window starts must keep its
        // full duration on the first wake-day inside the window.
        let r = try await service(nightSpanningWindowStart)
            .snapshots(window: .weeks13, asOf: Self.now).first { $0.series == .sleepDuration }!
        #expect(abs(r.weeks.first!.value - 8.0) < 0.01)
    }

    @Test func thinDataStillGetsASnapshotAndItsCoverageSaysSo() {
        // Six weeks of weight in a 13-week window: charted, with honest coverage.
        // Co-seeded with a dense series so the assertion cannot pass over [].
        let rs = try await service(sixWeeksWeight + fullHRV)
            .snapshots(window: .weeks13, asOf: Self.now)
        let weight = rs.first { $0.series == .weight }!
        #expect(weight.coverage.weeksWithData == 6)
        #expect(rs.contains { $0.series == .hrv })
    }

    @Test func aSeriesWithNoDataIsAbsent() {
        let rs = try await service(fullHRV).snapshots(window: .weeks13, asOf: Self.now)
        #expect(!rs.isEmpty)
        #expect(!rs.contains { $0.series == .weight })
    }

    @Test func theRangeIsOverWeeklyMediansNotRawReadings() {
        // One 200 kg suitcase-on-the-scale day must not become the range.
        let r = try await service(steadyWeightWithOneOutlierDay)
            .snapshots(window: .weeks13, asOf: Self.now).first { $0.series == .weight }!
        #expect(r.rangeHigh < 100)
    }
```

- [ ] **Step 2: Run, implement, run**

For each series: extract daily points from its category's shared array, bucket via Task 3, compute
the range over weekly medians, package the snapshot. No further computation of any kind.

- [ ] **Step 3: Mutants**

1. One read per series → `theCorpusIsReadOncePerCategoryRegardlessOfSeriesCount` fails.
2. One nil-category read → same test fails on the distinct-categories assertion.
3. Fetch from the window start exactly → `theFetchStartsOneDayEarlyForBoundarySpanningSleep` fails.
4. Range over raw daily values → `theRangeIsOverWeeklyMediansNotRawReadings` fails.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(trends): trajectory snapshots, one read per category"
```

---

### Task 6: Profile — derived age with a safety fallback, and the ask

**The previous plan's first version would have disabled age-gated health screening.**
`profile.age` drives `HealthMonitoringService` (cholesterol at 40+, blood sugar at 45+), and
`dateOfBirth` is **never populated by any UI** — so deriving age purely from DOB returns nil for
every existing user and silently switches that surface off.

**Files:** Create `Trends/PersonProfile.swift`; modify `Models/UserProfile.swift`,
`Models/HealthKitIngestor.swift`, `Views/Profile/UserProfileView.swift`; test
`Food IntolerancesTests/PersonProfileTests.swift`.

- [ ] **Step 1: Write the failing tests**

Table-driven — a previous version's two fixtures were passed by *both* its named mutants
(`/365.25` disagrees with the correct answer on only 0.07% of birth dates and neither fixture was
among them).

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

Add DOB and biological sex to the existing `requestAuthorization(toShare:read:)` call as
characteristic types (`HKObjectType.characteristicType(forIdentifier:)`) and populate the profile
when granted.

**The ask, when HealthKit does not answer** (the spec's "asked otherwise", which the previous plan
dropped): add a date-of-birth field to `UserProfileView` alongside the existing age field, writing
`UserProfile.dateOfBirth`. The age field stays — it is the fallback's source. Height already has
UI; biological sex comes from the HealthKit characteristic only in this round (the existing
`gender` string is a different concept and is not conflated with it).

**No schema change.** `age` and `weightKg` remain columns; `weightKg` stops being *read* — weight
is a series. Find reads with `grep -rn "\.age\b\|weightKg" --include=*.swift Views Models` and
route them through `currentAge(asOf:)` and the event series respectively.

- [ ] **Step 3: Run the app-target tests explicitly**

```bash
xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO -only-testing:"Food IntolerancesTests/PersonProfileTests"
```

The package command does not compile this target; without this step the tests are written but
never run.

- [ ] **Step 4: Mutants**

1. Drop the stored-age fallback → `noDateOfBirthFallsBackToStoredAge` fails.
2. `component(.year, from: asOf) - component(.year, from: dob)` → the boundary table fails on two rows.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(profile): derive age from DOB with a stored-age fallback, and ask for DOB"
```

---

### Task 7: Weight formatting from a raw value

`BodyMetricValueFormatter.line(for:unit:)` takes a `HealthEvent` and guards on category, subtype
and unit; `poundsPerKilogram` is `private`. A snapshot carries bare `Double`s, so the previous
constraint — reuse it, no new conversion — was unsatisfiable: an implementer would have had to
fabricate a throwaway `HealthEvent` or write a second conversion.

**Files:** Modify `Views/HealthOS/Timeline/BodyMetricValueFormatter.swift`; extend its existing
tests.

Extract `static func line(kg: Double, unit: WeightUnit) -> String` and have `line(for:unit:)`
delegate to it. The existing event-based tests must pass **unedited** — that is the proof the
extraction changed nothing.

```bash
git commit -m "refactor(units): weight formatting from a raw value"
```

---

### Task 8: The surface — chart, descriptive copy, and the non-diagnostic line

**Files:** Create `Views/HealthOS/Trends/{TrajectoryPresentation,TrajectoriesViewState,TrajectoriesView}.swift`
and `Views/HealthOS/Shared/NonDiagnosticFooter.swift`; modify `HealthTabView.swift` and the
Insights and Experiments surfaces (footer only); test
`Food IntolerancesTests/TrajectoryPresentationTests.swift`.

**A chart is required, and it is the whole feature.** Weekly medians over the window; **gaps are
drawn as gaps** — missing weeks are absent from `weeks`, and the chart must not connect across
them. The partial current week renders with its actual `dayCount` visible. **No fitted line, no
smoothing, no slope band** — a slope band is a verdict in visual form.

**The copy is descriptive or it is nothing.** Per series: the range of weekly medians, the unit,
and the coverage — *"Weekly medians 68–74 kg · based on 284 of 364 days."* No direction words, no
comparison of endpoints, no numbers that imply a change.

`TrajectoriesViewState` follows the established pattern: `@MainActor`, a synchronous
double-invocation guard, its in-flight `Task` exposed read-only so tests await deterministically.
This repo has had three off-main-actor `@Published` cold-launch crashes; the pattern is not
optional.

- [ ] **Step 1: Write the failing copy tests**

`sample(_:)` builds a `TrajectorySnapshot` with fixed coverage (284 of 364 days) and weekly
medians spanning 68–74 kg, so every assertion is hand-checkable (68 kg = 149.9 lb, 74 kg =
163.1 lb — values chosen so no imperial string contains a metric digit-run).

```swift
    @Test func noTrajectoryEverClaimsACauseOrADirection() {
        #expect(TrajectorySeries.allCases.count == 6)          // else the sweep is vacuous
        let causal = ["because", "caused", "led to", "due to", "linked to", "resulted in"]
        let directional = ["trend", "rising", "falling", "increas", "decreas",
                           "improv", "worsen", "declin", "climb", "↑", "↓"]
        for system in [UnitSystem.metric, .imperial] {
            for series in TrajectorySeries.allCases {
                let text = TrajectoryPresentation.summary(for: sample(series), system: system)
                #expect(!text.isEmpty)                         // else a `default: ""` arm passes
                for banned in causal + directional {
                    #expect(!text.localizedCaseInsensitiveContains(banned), "\(series): \(text)")
                }
                // "up"/"down" only as whole words, so "supplement" stays legal.
                #expect(text.range(of: #"\b(up|down)\b"#,
                                   options: [.regularExpression, .caseInsensitive]) == nil, "\(series): \(text)")
            }
        }
    }

    @Test func weightIsConvertedNotRelabelled() {
        let imperial = TrajectoryPresentation.summary(for: sample(.weight), system: .imperial)
        let metric = TrajectoryPresentation.summary(for: sample(.weight), system: .metric)
        #expect(imperial.contains("149.9") && imperial.contains("163.1"))
        #expect(!imperial.contains("68") && !imperial.contains("74"))
        #expect(metric.contains("68") && metric.contains("74"))
    }

    @Test func coverageIsPartOfEveryLineNotAFootnote() {
        for series in TrajectorySeries.allCases {
            let text = TrajectoryPresentation.summary(for: sample(series), system: .metric)
            #expect(text.contains("284") && text.contains("364"), "\(series): \(text)")
        }
    }

    @Test func thinCoverageIsStatedNotHidden() {
        let text = TrajectoryPresentation.summary(for: sparseSample(.weight), system: .metric)
        #expect(text.contains("42") && text.contains("91"))    // 42 of 91 days, still charted
    }

    @Test func theNonDiagnosticLineIsPlainAndPresent() {
        let text = NonDiagnosticFooter.copy
        #expect(!text.isEmpty)
        #expect(text.localizedCaseInsensitiveContains("not") &&
                text.localizedCaseInsensitiveContains("diagnos"))
        #expect(text.localizedCaseInsensitiveContains("clinician") ||
                text.localizedCaseInsensitiveContains("doctor"))
    }
```

- [ ] **Step 2: Implement presentation, then state, then view**

Rows show the series name, the descriptive summary, and the chart. Window picker (13/52 weeks,
default 13) and one navigation row in `HealthTabView` following the existing `NavigationLink` +
`.hgCard()` pattern.

`NonDiagnosticFooter` is one shared component — persistent, plain, "informational, not a
diagnosis; discuss with your clinician" — placed on **Trends, Insights, and Experiments**. Today
the only such text is buried in `ProtocolPreviewView` and one Dashboard line; this closes that gap
app-wide, which App Store review and the clinic deployment both need.

- [ ] **Step 3: Mutants**

1. Add "falling" to any summary → `noTrajectoryEverClaimsACauseOrADirection` fails.
2. Append the unit without converting → `weightIsConvertedNotRelabelled` fails.
3. Drop coverage from the line → `coverageIsPartOfEveryLineNotAFootnote` fails.

- [ ] **Step 4: Run both suites**

```bash
cd HealthGraphCore && swift test
xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO
```

`SwiftDataMigratorTests` crashes the runner (pre-existing), so the trailing "Test run with N
tests" line under-counts. Count `✔ Suite` lines and grep `✘`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(trends): charted descriptive trajectories surface"
```

---

## Device verification

The gate before merge, on a device with real Apple Health history.

1. Health tab → **Trends**. Every series with any data renders; weight absent on a device with no
   connected scale; a thin series renders with its thin coverage stated.
2. Check one series' weekly medians against Apple Health. They will not match exactly — medians
   vs. Apple's averages — but every visible disagreement must be explainable, and gaps must match.
3. Switch 13 ↔ 52 weeks; the chart re-renders; the partial current week is visible as partial.
4. Toggle Imperial/Metric; weight re-renders with converted numbers, not relabelled ones.
5. Gaps render as gaps, never as lines through missing weeks; no fitted or smoothed line anywhere.
6. Read every visible string: nothing states or implies a direction, nothing implies a cause,
   nothing names a category.
7. The non-diagnostic line is visible on Trends, Insights, and Experiments.
8. Profile: enter a DOB in the profile UI, confirm derived age; remove it, confirm the stored-age
   fallback keeps `HealthMonitoringService` recommendations alive.
