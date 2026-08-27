# Observed-Days Denominator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the evidence engine counting a decade of days the person was not using the app as days their symptom did not occur — without introducing the opposite error, where sparse logging manufactures false "this helps you" verdicts.

**Architecture:** The base-rate denominator stops being "every calendar day between the oldest and newest event" and becomes a set of days on which the person's symptoms would actually have been recorded. **Which set is not yet decided** — see "STOP" below. The two candidates are days with a user-authored log, and calendar days inside active logging periods; they fail in opposite directions and Task 1 measures which failure applies to real users. Everything downstream of the set — the analyzer signature, the three call sites, the candidate gate — is identical either way, so only Task 2 changes with the answer.

**Tech Stack:** Swift 6, Swift Testing (`@Test`/`#expect`), GRDB, `HealthGraphCore` package.

**Spec:** `docs/superpowers/specs/2026-08-25-tracked-days-denominator-design.md` — **out of date; this plan governs.** The spec proposed filtering to days with a manual log. An audit showed that rule can manufacture false `improves`/`active` verdicts as logging thins; reproducing the proposed replacement showed it can manufacture false triggers instead. The spec should be rewritten only once Task 1 settles which applies.

## Why this plan changed

The first version of this plan filtered the statistics to **days with a manual log**. Two independent measurements killed it.

On a pair with **no effect whatsoever** (true ratio exactly 1.0), varying only how often the person logs:

| logging pattern | today | tracked-days rule |
|---|---|---|
| every day | correct | correct |
| every 2nd day | correct | **improves / ACTIVE** |
| every 7th day | correct | **improves / ACTIVE** |

The mechanism is closed-form: a day joins the tracked set *because a symptom was logged there*, so each symptom-only day adds one to both the spontaneous-outcome count and the denominator, pushing the base rate toward 1.0 as engagement falls. Every ratio deflates by `1/(f + b − fb)`. The rejected "days you logged a symptom" variant (base rate 60.0) is the limit of the same continuum.

Three further findings shaped this rewrite:

- **`.candidate` is rendered nowhere.** `InsightsViewModel.swift:54` filters `status == .active`. The ~15 false triggers on the device were never displayed. The bug's real harm is **suppression** — true findings drop to candidate and vanish, and `confirmedNoEffect` becomes unreachable — not false claims. This plan is calibrated against suppression.
- **`StabilityValidator` is an existing mitigation.** Its per-half windows come from each half's own exposure times, independent of corpus span, so it already catches ratio *inflation* — which is why the false triggers sit at candidate rather than active. Any change must not disarm it against *deflation*.
- **`source == .manual` is the wrong predicate.** `EventSource` has nine cases; the app's own manual family is `[.manual, .photo, .voice, .appIntent]` (`TimelineViewModel.swift:24`), and `SwiftDataMigrator` stamps the user's hand-logged history as `.legacyImport`. The literal rule would give a migrated user zero days from their entire pre-migration history.

## STOP: the rule is not decided yet

I rewrote this plan around active-logging-periods on the strength of an audit's measurements, then
reproduced them myself and got the opposite result. Both numbers are real; they disagree because
the two probes assume different things about **when a symptom gets logged**, and that assumption
is the whole ballgame.

Null pair — the exposure does nothing at all. Any verdict here is false:

| engagement | logged-days rule | active-periods rule |
|---|---|---|
| 1.0 | correct | correct |
| 0.5 | correct | **possibleTrigger / ACTIVE** (ratio 3.72) |
| 0.3 | correct | **possibleTrigger / ACTIVE** (ratio 5.97) |

My probe generates events only on engaged days — **capture is conditional**: you log a symptom
only if you were already using the app. Under that model, active-periods counts unlogged days
inside a period as symptom-free days they were not, deflates the base rate, and reproduces the
original bug at period scale. The audit's probe let symptoms be captured on otherwise-silent days
— **capture is unconditional** — and under that model logged-days over-counts symptom days,
inflates the base rate, and manufactures false protective verdicts.

Neither rule is safe under the other's model, and the failure modes point in opposite directions:

- **capture conditional** → logged-days is right; active-periods produces false **triggers**
- **capture unconditional** → active-periods is right; logged-days produces false **protective** verdicts

This is not a bug in either measurement. It is an unidentifiable choice: on a day with no symptom
log, "no symptom" and "not watching" are indistinguishable from the data alone. **The behaviour
has to be measured on real data before either rule is built.** Task 1 does that, and nothing after
it should start until its answer is in.

---

## Global Constraints

- **A user-authored event is one whose source is in `[.manual, .photo, .voice, .appIntent, .legacyImport]`.** Not `.healthKit`, `.healthExportFile`, `.labImport`, or `.weatherAPI`. Photo and voice captures are user-authored; so is migrated history from the previous app.
- **The observed-day set is whatever Task 1's measurement selects** — do not assume. Tasks 3-8 take it as a `Set<Date>` and must not care how it was built. Both candidate rules are documented under "STOP"; the constraint that binds regardless is that a day counts only if a symptom occurring that day would have been recorded.
- **The acceptance suite must pass unedited.** `EvidenceEngineAcceptanceTests.recallAllPlantedPatterns` and `.precisionIsHonestForAnAssociationEngine` run on a dense all-manual corpus, where observed days equal calendar days and this change is a no-op. If a task needs to edit either test, the implementation is wrong — stop and report.
- **No changes to `activationThreshold`, `decayThreshold`, `candidateRatio*`, `activationRatio*`, `noEffectRatioBand`, the observational ceiling, lag windows, or the `ConfidenceScorer` formula.** New constants for period detection are additions, not edits.
- **UTC start-of-day throughout,** via the existing `Self.utc` calendars. A local-time calendar would make the day set drift with travel.
- **Every task ends with the package suite green:** `cd HealthGraphCore && swift test`.
- **Optional-comparison hygiene.** `Optional == Optional` is `true` when both sides are nil, so `a?.x == b?.x` passes when both runs found nothing. Every such assertion must be preceded by one that pins the non-nil side.
- **Fixtures anchor at exact UTC midnight** (`Date(timeIntervalSince1970: 1_749_945_600)`) and pass that as `asOf:`. `Date()` makes day bucketing depend on the wall clock, and these tests sit near thresholds.
- Mutation discipline: where a task names a mutant, apply it, confirm the **named** test fails, restore, and report both directions. If a named mutant does *not* kill its test, say so — that is a finding, not a formality.

---

### Task 1: Measure how symptoms actually get logged, on real data

Decides the rule. Do not skip it, and do not let its result be inferred from a synthetic corpus —
every synthetic corpus in this repo encodes one of the two capture models by construction, so it
can only return the assumption it was built with.

**Files:**
- Modify: `Views/HealthGraphDebugView.swift` — add one DEBUG diagnostic beside "Dump relationship report"

**Interfaces:**
- Produces: a printed report the human partner reads off the device and pastes back.

- [ ] **Step 1: Add the diagnostic**

A button "Dump logging-pattern report" that computes, over the real corpus, using
`source.isUserAuthored` (add the extension from Task 2 first, or inline the set here):

1. `userAuthoredDays` — count.
2. **`symptomOnlyDays` / `symptomDays`** — of the days carrying a symptom log, what fraction carry
   *nothing else* the person authored. **This is the number that decides the rule.** High means
   people open the app specifically to log a symptom, so a symptom on an otherwise-silent day is
   captured, so capture is closer to unconditional. Low means symptoms only ever ride along with
   other logging, so a silent day tells us nothing.
3. Gap histogram between consecutive user-authored days — buckets 1, 2-3, 4-7, 8-14, 15-30, 31+.
   The 1-14 buckets are where the two rules disagree; if there are almost none, the choice barely
   matters and either rule is safe.
4. Longest run of consecutive user-authored days, and the count of runs of length 1 and 2.
5. Same four numbers restricted to the last 180 days, since older history may reflect a different
   app and different habits.

Print to the on-screen report and to the console, same shape as `dumpRelationshipReport`.

- [ ] **Step 2: Report and stop**

Write the numbers into the task report and **stop**. Do not implement a denominator. The controller
picks the rule from this data and updates the Global Constraints and Task 2 before anything else
runs.

Decision rule, stated in advance so the result cannot be rationalised after the fact:

- **symptom-only days ≥ ~30% of symptom days** → capture is substantially unconditional →
  **active logging periods** (Task 2 as written).
- **symptom-only days ≤ ~10%** → capture is conditional → **logged days**, and Task 2 becomes the
  much smaller "days with a user-authored event" set, with the persona harness inverted to guard
  the false-protective direction instead.
- **In between** → neither rule is defensible on its own. Fall back to the conservative option:
  observed days = days inside periods whose logging density exceeds a floor, which mines nothing
  for sparse loggers rather than mining wrongly. Suppression is the safer failure for a health app,
  and it is the failure the app already has today.

- [ ] **Step 3: Commit**

```bash
git add Views/HealthGraphDebugView.swift
git commit -m "debug: logging-pattern report to settle the denominator rule"
```

---

### Task 1b: The persona harness (after the rule is chosen)

Build the harness against the CHOSEN rule. Both directions must be pinned, because the two
candidate rules fail in opposite directions and the harness is what stops the round from trading
one error for the other.

**Files:**
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/DenominatorPersonaTests.swift`

- [ ] **Step 1: Build corpora under BOTH capture models**

The persona builder takes a flag: `captureIsConditional`. When true, events are generated only on
engaged days (a symptom on a silent day is never recorded). When false, symptoms are recorded
whenever they occur and make their day user-authored. Every persona test runs under both, and the
report states which model each result assumes. A harness that only encodes the chosen model would
have caught neither of the two failures found so far.

- [ ] **Step 2: The two guards, at engagement 1.0 / 0.5 / 0.3**

```swift
    @Test func aPairWithNoEffectGetsNoVerdictHoweverSparselyYouLog() async throws {
        for conditional in [true, false] {
            for engagement in [1.0, 0.5, 0.3] {
                let edge = try await minedEdge(PersonaCorpus.build(
                    days: 730, engagement: engagement, effect: 1.0, captureIsConditional: conditional))
                #expect(edge?.type != .improves,
                        "conditional=\(conditional) engagement=\(engagement): false protective verdict")
                #expect(!(edge?.type == .possibleTrigger && edge?.status == .active),
                        "conditional=\(conditional) engagement=\(engagement): false trigger")
            }
        }
    }

    @Test func aRealTriggerSurvivesSparseLogging() async throws {
        for conditional in [true, false] {
            for engagement in [1.0, 0.5, 0.3] {
                let edge = try await minedEdge(PersonaCorpus.build(
                    days: 730, engagement: engagement, effect: 5.0, captureIsConditional: conditional))
                #expect(edge != nil, "conditional=\(conditional) engagement=\(engagement): mined nothing")
                #expect(edge?.type == .possibleTrigger)
            }
        }
    }
```

If the chosen rule cannot pass both tests under both models — and on the evidence so far, neither
candidate can — then report which cells fail and stop. A rule that is only correct under the
model we happened to measure is worth shipping only if the report says so explicitly and the
controller accepts it.

- [ ] **Step 3: Record the before-picture, then commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/DenominatorPersonaTests.swift
git commit -m "test: persona harness across both capture models"
```

---

### Task 2: `ActiveLoggingPeriods` — the observed-day set

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ActiveLoggingPeriods.swift`
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/ActiveLoggingPeriodsTests.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift`

**Interfaces:**
- Produces: `ActiveLoggingPeriods.observedDays(userAuthoredDays:config:calendar:) -> Set<Date>`
- Produces: `EvidenceConfig.maxLoggingGapDays: Int = 14`, `EvidenceConfig.minPeriodDays: Int = 3`
- Produces: `EventSource.isUserAuthored: Bool`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct ActiveLoggingPeriodsTests {
    private static let t0 = Date(timeIntervalSince1970: 1_749_945_600)
    private func day(_ n: Int) -> Date { Self.t0.addingTimeInterval(Double(n) * 86_400) }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func observed(_ days: Set<Date>) -> Set<Date> {
        ActiveLoggingPeriods.observedDays(userAuthoredDays: days, config: .default, calendar: utc)
    }

    @Test func gapsInsideAPeriodStillCount() {
        // THE point of this design. Someone logging every other day is ACTIVE;
        // the days between are real negatives, not unobserved. Counting only
        // logged days is what manufactured false protective verdicts.
        let everyOtherDay = Set((0..<40).filter { $0 % 2 == 0 }.map { day($0) })
        #expect(observed(everyOtherDay).count == 39)     // days 0...38 inclusive
    }

    @Test func aLongSilenceSplitsThePeriodAndIsExcluded() {
        // The returning user: 20 days on, 550 days gone, 20 days on.
        let early = (0..<20).map { day($0) }
        let late  = (570..<590).map { day($0) }
        let out = observed(Set(early + late))
        #expect(out.count == 40)
        #expect(!out.contains(day(300)))            // the silence is not evidence
    }

    @Test func aStrayForgottenDayIsNotAPeriod() {
        // One symptom logged years ago and never followed up. Under a
        // logged-days rule this day counts; under a span rule it reopens the
        // whole window. It is neither: it is not an active period.
        let stray = Set([day(-2920)])
        let real  = Set((0..<40).map { day($0) })
        let out = observed(stray.union(real))
        #expect(!out.contains(day(-2920)))
        #expect(out.count == 40)
    }

    @Test func importedHistoryContributesNothing() {
        // Verified through the predicate, not the day set: HealthKit days never
        // become user-authored days in the first place.
        #expect(EventSource.healthKit.isUserAuthored == false)
        #expect(EventSource.weatherAPI.isUserAuthored == false)
        #expect(EventSource.healthExportFile.isUserAuthored == false)
        #expect(EventSource.labImport.isUserAuthored == false)
        // The app's own manual family, plus migrated hand-logged history.
        for s in [EventSource.manual, .photo, .voice, .appIntent, .legacyImport] {
            #expect(s.isUserAuthored, "\(s) must count: it is the person's own log")
        }
    }

    @Test func anEmptyHistoryHasNoObservedDays() {
        #expect(observed([]).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd HealthGraphCore && swift test --filter ActiveLoggingPeriodsTests`
Expected: compile failure — `ActiveLoggingPeriods` and `isUserAuthored` do not exist.

- [ ] **Step 3: Implement**

Add to `Enums.swift` beside `EventSource`:

```swift
public extension EventSource {
    /// Did the person write this themselves? Drives the observed-day denominator:
    /// only a user-authored day is evidence they were watching. `.legacyImport` is
    /// the user's OWN hand-logged history from the previous app (SwiftDataMigrator),
    /// not a device import — excluding it would give migrated users no history at all.
    var isUserAuthored: Bool {
        switch self {
        case .manual, .photo, .voice, .appIntent, .legacyImport: return true
        case .healthKit, .healthExportFile, .labImport, .weatherAPI: return false
        }
    }
}
```

Add to `EvidenceConfig`:

```swift
    /// A silence longer than this ends an active logging period. Days inside a
    /// period count even when nothing was logged; days in the gap do not.
    public var maxLoggingGapDays: Int = 14
    /// A run of user-authored days shorter than this is not a period at all —
    /// it is a stray day, and it must not reopen the denominator around itself.
    public var minPeriodDays: Int = 3
```

Create `ActiveLoggingPeriods.swift`:

```swift
import Foundation

/// The days a person was actually using the app, as calendar days.
///
/// The denominator of the engine's base rate answers "on how many days would we
/// have known about the symptom?". Two wrong answers were measured before this:
/// every calendar day between the oldest and newest event (a decade of imported
/// Apple Health history collapses the base rate and suppresses true findings),
/// and only the days with a log (engagement is caused by both exposures and
/// outcomes, so conditioning on it manufactures false protective verdicts).
///
/// This is the middle: gaps INSIDE an active period are real negatives, gaps
/// BETWEEN periods are unobserved.
public enum ActiveLoggingPeriods {
    public static func observedDays(userAuthoredDays: Set<Date>,
                                    config: EvidenceConfig,
                                    calendar: Calendar) -> Set<Date> {
        guard !userAuthoredDays.isEmpty else { return [] }
        let sorted = userAuthoredDays.sorted()
        var runs: [[Date]] = []
        var current: [Date] = [sorted[0]]
        for day in sorted.dropFirst() {
            let gap = calendar.dateComponents([.day], from: current.last!, to: day).day ?? 0
            if gap <= config.maxLoggingGapDays { current.append(day) }
            else { runs.append(current); current = [day] }
        }
        runs.append(current)

        var out: Set<Date> = []
        for run in runs where run.count >= config.minPeriodDays {
            guard let first = run.first, let last = run.last else { continue }
            var d = first
            while d <= last {
                out.insert(d)
                guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
        }
        return out
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd HealthGraphCore && swift test --filter ActiveLoggingPeriodsTests`
Expected: all pass.

- [ ] **Step 5: Demonstrate the mutants**

1. Emit only the days in `run` rather than every day from `first` to `last` → `gapsInsideAPeriodStillCount` must fail (39 → 20). This is the mutant that reintroduces the engagement bias.
2. Drop the `run.count >= config.minPeriodDays` filter → `aStrayForgottenDayIsNotAPeriod` must fail.
3. Make `.healthKit` return `true` from `isUserAuthored` → `importedHistoryContributesNothing` must fail.

Restore after each; report both directions for all three.

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ActiveLoggingPeriods.swift \
        HealthGraphCore/Sources/HealthGraphCore/Models/Enums.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ActiveLoggingPeriodsTests.swift
git commit -m "feat(evidence): active logging periods as the observed-day set"
```

---

### Task 3: `CooccurrenceAnalyzer` takes observed days

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/CooccurrenceAnalyzer.swift:37-100`
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/CooccurrenceAnalyzerTests.swift:27,38,62`

**Interfaces:**
- Produces: `CooccurrenceAnalyzer.analyze(exposure:outcome:window:observedDays:) -> PairStats?`, replacing `observation: DateInterval`. Returns `nil` when the filtered exposure list is empty or no non-exposure observed days remain.

- [ ] **Step 1: Write the failing tests**

Append to `CooccurrenceAnalyzerTests.swift`:

```swift
    private static let d0 = Date(timeIntervalSince1970: 1_749_945_600)   // exact UTC midnight
    private func obsDay(_ n: Int) -> Date { Self.d0.addingTimeInterval(Double(n) * 86_400) }
    private func obsAt(_ n: Int, hour: Int) -> Date { obsDay(n).addingTimeInterval(Double(hour) * 3600) }

    @Test func daysOutsideTheObservedSetChangeNothing() {
        // The whole fix, at unit scale: occurrences outside the observed window
        // must not enter EITHER side of the rate. PairStats is Equatable, so one
        // assertion pins every field rather than a hand-picked few.
        let observed = Set((0..<10).map { obsDay($0) })
        let inside = (0..<5).map { ExposureOccurrence(key: .derived(.shortSleep),
                                                      timestamp: obsAt($0, hour: 8),
                                                      timezoneID: "UTC", sourceEventID: UUID()) }
        let plusOutside = inside + (500..<530).map {
            ExposureOccurrence(key: .derived(.shortSleep), timestamp: obsAt($0, hour: 8),
                               timezoneID: "UTC", sourceEventID: UUID()) }
        let outcomes = [OutcomeOccurrence(key: .symptom("fatigue"), timestamp: obsAt(7, hour: 12),
                                          value: 5, sourceEventID: UUID())]
        let analyzer = CooccurrenceAnalyzer(config: .default)
        let a = analyzer.analyze(exposure: inside, outcome: outcomes, window: 0...18, observedDays: observed)
        let b = analyzer.analyze(exposure: plusOutside, outcome: outcomes, window: 0...18, observedDays: observed)
        #expect(a != nil)                       // pin the non-nil side: nil == nil would pass
        #expect(a == b)
        #expect(a?.exposureDayCount == 5)
        #expect(a?.baseRate == 1.0 / 5.0)       // outcome day 7 is one of the 5 non-exposure days
    }

    @Test func theDenominatorIsTheObservedSetNotTheSpan() {
        // Same occurrences, two observed sets: one contiguous, one with far-apart
        // days. A span-based implementation cannot tell these apart.
        let exposures = (0..<3).map { ExposureOccurrence(key: .derived(.shortSleep),
                                                         timestamp: obsAt($0, hour: 8),
                                                         timezoneID: "UTC", sourceEventID: UUID()) }
        let outcomes = [OutcomeOccurrence(key: .symptom("fatigue"), timestamp: obsAt(5, hour: 12),
                                          value: 5, sourceEventID: UUID())]
        let analyzer = CooccurrenceAnalyzer(config: .default)
        let contiguous = Set((0..<10).map { obsDay($0) })          // 7 non-exposure days
        let sparse = Set((0..<3).map { obsDay($0) }).union([obsDay(5), obsDay(400)])  // 2
        #expect(analyzer.analyze(exposure: exposures, outcome: outcomes,
                                 window: 0...18, observedDays: contiguous)?.baseRate == 1.0 / 7.0)
        #expect(analyzer.analyze(exposure: exposures, outcome: outcomes,
                                 window: 0...18, observedDays: sparse)?.baseRate == 1.0 / 2.0)
    }

    @Test func noComparisonDaysMeansNoAnswer() {
        // Every observed day carries the exposure. A max(1, …) floor here would
        // report "every outcome happened on the single comparison day" and make
        // this look wildly protective.
        let observed = Set((0..<3).map { obsDay($0) })
        let exposures = (0..<3).map { ExposureOccurrence(key: .derived(.shortSleep),
                                                         timestamp: obsAt($0, hour: 8),
                                                         timezoneID: "UTC", sourceEventID: UUID()) }
        let outcomes = [OutcomeOccurrence(key: .symptom("fatigue"), timestamp: obsAt(0, hour: 12),
                                          value: 5, sourceEventID: UUID())]
        #expect(CooccurrenceAnalyzer(config: .default)
            .analyze(exposure: exposures, outcome: outcomes, window: 0...18, observedDays: observed) == nil)
    }

    @Test func exposuresEntirelyOutsideTheObservedSetYieldNothing() {
        // Not the same as an empty observed set: there IS a denominator, the
        // exposure just never happened while anyone was watching.
        let observed = Set([obsDay(100), obsDay(101), obsDay(102)])
        let exposures = [ExposureOccurrence(key: .derived(.shortSleep), timestamp: obsAt(0, hour: 8),
                                            timezoneID: "UTC", sourceEventID: UUID())]
        #expect(CooccurrenceAnalyzer(config: .default)
            .analyze(exposure: exposures, outcome: [], window: 0...18, observedDays: observed) == nil)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd HealthGraphCore && swift test --filter CooccurrenceAnalyzerTests`
Expected: compile failure — `extra argument 'observedDays'`.

- [ ] **Step 3: Implement**

Replace the parameter and add the filter at the top of `analyze`:

```swift
    /// - Parameter observedDays: calendar days inside the person's active logging
    ///   periods (`ActiveLoggingPeriods`). A day outside this set is UNOBSERVED,
    ///   not negative — an Apple Health sleep sample from 2019 is not evidence
    ///   that no migraine occurred. Days INSIDE a period count even with nothing
    ///   logged; that is deliberate, and it is what stops a sparse-but-active
    ///   logger's ratios from deflating into false protective verdicts.
    public func analyze(exposure: [ExposureOccurrence], outcome: [OutcomeOccurrence],
                        window: ClosedRange<Double>, observedDays: Set<Date>) -> PairStats? {
        guard !exposure.isEmpty else { return nil }
        let cal = Self.utc
        // Both sides, one rule: a statistic computed over one universe must not
        // be compared against a count taken over another.
        let exposure = exposure.filter { observedDays.contains(cal.startOfDay(for: $0.timestamp)) }
        let outcome = outcome.filter { observedDays.contains(cal.startOfDay(for: $0.timestamp)) }
        guard !exposure.isEmpty else { return nil }
```

In the "Per-day base rate & ratio" block, replace the `totalDays`/`nonExposureDays`/`baseRate` lines:

```swift
        let nonExposureDays = observedDays.subtracting(exposureDays).count
        // No comparison days means no comparison — not a floor of 1.
        guard nonExposureDays > 0 else { return nil }
        let spontaneousOutcomeDays = outcomeDays.subtracting(exposureDays).count
        let baseRate = Double(spontaneousOutcomeDays) / Double(nonExposureDays)
```

Leave `pYgivenX`, `windowDays`, `eps` and the `ratio` expression untouched. `windowDays` scaling stays coherent here **because observed days are contiguous within a period** — the numerator's lag window lands on days that are in the denominator's universe. This is only true for the period-based set; it was *not* true of the rejected logged-days rule, and that is a reason the earlier design failed.

- [ ] **Step 4: Fix the three existing analyzer tests**

`countsFollowsAndMissesWithinWindow` (:11-33) and `surfacesPerDayContingency` (:46-64) place exposures on **every** day their fixtures use. Passing exactly those days as `observedDays` gives `nonExposureDays == 0` and the new guard returns `nil`, failing every assertion. Add at least one further observed day carrying no exposure. Do **not** weaken what those tests assert.

- [ ] **Step 5: Run**

Run: `cd HealthGraphCore && swift test --filter CooccurrenceAnalyzerTests`
Expected: all pass. The package will not build yet — three call sites still pass `observation:`. That is Task 4.

- [ ] **Step 6: Demonstrate the mutants**

1. Remove the `exposure`/`outcome` filters, keeping only the denominator change → `daysOutsideTheObservedSetChangeNothing` must fail.
2. Replace `observedDays.subtracting(exposureDays).count` with a span-derived day count → `theDenominatorIsTheObservedSetNotTheSpan` must fail on the sparse case.
3. Replace the `guard nonExposureDays > 0` with `max(1, nonExposureDays)` → `noComparisonDaysMeansNoAnswer` must fail.

- [ ] **Step 7: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/CooccurrenceAnalyzer.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/CooccurrenceAnalyzerTests.swift
git commit -m "fix(evidence): base rate over observed days, not calendar days"
```

---

### Task 4: Wire all three call sites

Leaving any one behind splits the semantics: a statistic on one universe compared against a threshold calibrated on another.

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift:84,104-105,137`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceContext.swift:15,31-34,53-56`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/StabilityValidator.swift:7-9,19-26`
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/StabilityValidatorTests.swift:26,33,46` — **three `isStable` call sites break without this; omitting the file guarantees a compile failure.**

**Interfaces:**
- Produces: `StabilityValidator.isStable(exposure:outcome:window:fullDirection:observedDays:config:) -> Bool`
- Produces: `EvidenceContext.observedDays: Set<Date>` replacing `observation: DateInterval?`

- [ ] **Step 1: `EvidenceEngine.recompute`**

Replace the `observation` binding at :84:

```swift
        // Observed days, not calendar days: see ActiveLoggingPeriods.
        let userAuthoredDays = Set(events.filter { $0.source.isUserAuthored }
                                         .map { cal.startOfDay(for: $0.timestamp) })
        let observedDays = ActiveLoggingPeriods.observedDays(userAuthoredDays: userAuthoredDays,
                                                            config: config, calendar: cal)
```

Pass `observedDays: observedDays` at :105 and :137. Delete `observation` if unused.

- [ ] **Step 2: `EvidenceContext`**

Replace the stored property with `let observedDays: Set<Date>`, build it in `makeContext` exactly as above (same two lines — a second, subtly different derivation is how the drill-down and the card come to disagree), and replace the guard in `evidence(for:in:)` with `guard !ctx.observedDays.isEmpty else { return empty() }`.

- [ ] **Step 3: `StabilityValidator`**

Add `observedDays: Set<Date>` before `config:`. Inside `directional(_:)`, narrow to the half's window:

```swift
            let halfObserved = observedDays.filter { $0 >= cal.startOfDay(for: lo) && $0 <= obsEnd }
            guard let stats = analyzer.analyze(exposure: half, outcome: halfOutcomes,
                                               window: window, observedDays: halfObserved) else { return false }
```

`cal` is not in scope — add a UTC calendar as `CooccurrenceAnalyzer` does.

**Note the direction, because the first draft of this plan had it backwards:** widening a half's day set *shrinks* its base rate and *raises* its ratio. A protective edge then fails the `≤ candidateRatioProtective` gate by rising above it. Do not describe this as deflation.

- [ ] **Step 4: Decide `daySets` explicitly, and say which you chose**

`EvidenceEngine.swift:87-88` and `EvidenceContext.swift:28-29` build `daySets` for confounder analysis from **unfiltered** occurrences, and `ConfounderAnalyzer.penalty` computes `overlap = |target ∩ other| / |target|`. Left alone, `|target|` is inflated by unobserved days, every overlap is deflated, and the `0.6` threshold gets harder to cross — under-applying `w4`.

Filter `daySets` to `observedDays` at both sites, so the confounder universe matches the rate universe. Then measure: run the acceptance suite and report whether any planted relationship changed status. If any did, stop and report rather than adjusting anything — that is the controller's call.

Do the same for `illnessDays` (`EvidenceEngine.swift:60-74`), which today has **no source filter at all**, so imported symptoms contribute illness days.

- [ ] **Step 5: Run the package suite**

Run: `cd HealthGraphCore && swift test`
Expected: green, with `EvidenceEngineAcceptanceTests` **unedited**.

- [ ] **Step 6: Demonstrate the mutant**

Pass the full `observedDays` instead of `halfObserved` in `StabilityValidator.directional`. Report which tests fail. If none do, say so plainly — it means nothing in the suite pins the half-window narrowing, and the controller needs to know.

- [ ] **Step 7: Commit**

```bash
git add HealthGraphCore/Sources HealthGraphCore/Tests
git commit -m "fix(evidence): observed days at all three analyze call sites"
```

---

### Task 5: Re-gate candidate admission on observed occurrences

`CandidateGenerator.candidates` is called with the pre-filter maps, so `minExposures: 5` / `minOutcomeOccurrences: 3` count occurrences the analyzer will then discard. A pair can be admitted on 40 occurrences and scored on 2 observed days — and that pair's p-value still joins the Benjamini-Hochberg pool, loosening the correction for every other pair. This is the same bug class the round exists to fix: a count over one universe gating a computation over another.

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift:91-93`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/DenominatorPersonaTests.swift`

- [ ] **Step 1: Write the failing test**

Build a corpus where an exposure has well over `minExposures` occurrences but nearly all fall outside any active logging period, and assert no relationship is produced for it. Anchor the precondition first:

```swift
        let (exp, _) = engine.extract(events)
        #expect((exp[key]?.count ?? 0) >= EvidenceConfig.default.minExposures)  // it WOULD be admitted
        #expect(try await GRDBRelationshipStore(database: db).all().isEmpty)    // but is not mined
```

Without the first line the test cannot distinguish "correctly refused" from "nothing to refuse" — the failure mode that made an earlier version of this plan's HealthKit-only test vacuous.

- [ ] **Step 2: Implement**

Filter the exposure and outcome maps to `observedDays` before `CandidateGenerator.candidates`, so admission and scoring count the same days.

- [ ] **Step 3: Run, then demonstrate the mutant**

Revert to passing unfiltered maps → the new test must fail.

- [ ] **Step 4: Commit**

```bash
git commit -m "fix(evidence): admit candidates on observed occurrences"
```

---

### Task 6: The persona harness must now pass, and the regressions must hold

**Files:**
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/DenominatorPersonaTests.swift`
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/ObservedDaysRegressionTests.swift`

- [ ] **Step 1: Re-run Task 1's harness**

Run: `cd HealthGraphCore && swift test --filter DenominatorPersonaTests`
Expected: both tests pass at every engagement level. Report the after-picture beside Task 1's before-picture.

- [ ] **Step 2: Add the graph-level regressions**

Per-edge assertions let a fix repair one edge and leave four fabricated ones standing. Assert the whole graph:

```swift
    @Test func importedHistoryDoesNotChangeTheGraphAtAll() async throws {
        // The defect, named, at the level the evidence was actually observed:
        // one 2016 event took a 12-edge graph to 16, all possibleTrigger,
        // 0 improves, 0 noEffect — with the evidence counts unchanged.
        let events = PersonaCorpus.build(days: 400, engagement: 1.0, effect: 3.0)
        let clean = try await minedGraph(events)
        let withImport = try await minedGraph(events + PersonaCorpus.importedHistory(days: 3650))
        #expect(!clean.isEmpty)                     // pin the non-empty side
        #expect(clean == withImport)                // Set<String> of edgeKey|type|status
    }

    @Test func aStrayForgottenSymptomDoesNotChangeTheGraphAtAll() async throws {
        let events = PersonaCorpus.build(days: 400, engagement: 1.0, effect: 3.0)
        let stray = HealthEvent(timestamp: PersonaCorpus.t0.addingTimeInterval(-2920 * 86_400),
                                category: .symptom, subtype: "bloating", value: 6,
                                unit: "severity", source: .manual)
        let clean = try await minedGraph(events)
        #expect(!clean.isEmpty)
        #expect(clean == (try await minedGraph(events + [stray])))
    }

    @Test func aReturningUsersSilenceIsNotEvidence() async throws {
        // 90 days of logging, 550 days away, 90 days back. The silence must not
        // become 550 symptom-free days. This is the case that eliminated the
        // exposure-outcome-intersection alternative.
        …
    }
```

`minedGraph` returns `Set<String>` of `"\(edgeKey)|\(type)|\(status)"` — one comparison pins every edge, its classification, and its status.

- [ ] **Step 3: Demonstrate the mutant**

Revert `EvidenceEngine`'s `observedDays` binding to the old `DateInterval` day count → `importedHistoryDoesNotChangeTheGraphAtAll` must fail with a set difference.

- [ ] **Step 4: Commit**

```bash
git commit -m "test: graph-level regressions for imported history and silences"
```

---

### Task 7: The drill-down must agree with the card — on a fixture that can actually disagree

An earlier version of this test passed against the **unfixed** engine: `followCount`/`missCount` come from the pair loop, which never touches the denominator, so the assertion was structurally immune to the change it policed. The fixture must put occurrences on unobserved days so the two paths can diverge.

**Files:**
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceContextObservedDaysTests.swift`

- [ ] **Step 1: Write the test**

Corpus: a normal active period, plus — dated years earlier, outside any period — imported `category: .symptom` and `category: .food` events carrying the same subtypes and `objectID` as the mined pair. Then:

```swift
        var compared = 0
        for r in stored where r.status != .userDismissed {
            let ev = engine.evidence(for: r, in: ctx)
            compared += 1
            #expect(ev.followCount == r.evidenceCount, "follow mismatch on \(r.edgeKey ?? "?")")
            #expect(ev.missCount == r.contradictionCount, "miss mismatch on \(r.edgeKey ?? "?")")
            #expect(ev.exposures.allSatisfy { observedDays.contains(utc.startOfDay(for: $0.exposureTime)) })
        }
        #expect(compared >= 5)      // a skip-guard that silently compares nothing is not a pass
```

Do not add a `guard followCount != 0 || missCount != 0 else { continue }` — that skips exactly the divergence being hunted.

- [ ] **Step 2: Run, then demonstrate the mutant**

Drop the `isUserAuthored` filter in `makeContext` → the imported days join the context's observed set, its filtered arrays diverge from `recompute`'s, and the counts mismatch. If the mutant does not kill the test, the fixture is still inert — report that.

- [ ] **Step 3: Commit**

```bash
git commit -m "test: drill-down counts match the stored relationship"
```

---

### Task 8: Say what changed, in the two places a user will notice

**Files:**
- Modify: `Views/HealthOS/Insights/InsightDetailView.swift:156-174` (`rawNumbersCard`)
- Create: `Food IntolerancesTests/InsightDetailPresentationTests.swift`

There is no ViewInspector in this project, so a test asserting a literal contains a substring of itself proves nothing. Follow the precedent already here — `Food IntolerancesTests/EmptyStateCopyTests.swift` tests `TimelineView.emptyStateMessage(...)`, a pure static function the body calls.

- [ ] **Step 1: Write the failing test**

```swift
    @Test func theEvidenceCaptionSaysWhatTheCountCovers() {
        let caption = InsightDetailView.evidenceCaption(for: rel(evidence: 12, contradictions: 8))
        #expect(caption.contains("12"))
        #expect(caption.localizedCaseInsensitiveContains("logging"))
    }

    @Test func theCaptionReflectsItsInput() {
        // Guards against a constant string that happens to contain the words.
        #expect(InsightDetailView.evidenceCaption(for: rel(evidence: 12, contradictions: 8))
             != InsightDetailView.evidenceCaption(for: rel(evidence: 30, contradictions: 8)))
    }
```

- [ ] **Step 2: Implement**

Extract `static func evidenceCaption(for:) -> String` and call it from `rawNumbersCard`. One short line in the existing secondary style, saying the count covers days you were logging. No jargon — not "observed days", not "active logging period".

- [ ] **Step 3: Name the mutant**

Return a constant string ignoring the relationship → `theCaptionReflectsItsInput` must fail.

- [ ] **Step 4: Run the full app suite**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO`
`SwiftDataMigratorTests` crashes the runner (pre-existing), so the trailing "Test run with N tests" line under-counts. Verify by counting `✔ Suite` lines and grepping for `✘`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(insights): say the evidence count covers days you were logging"
```

---

## Device verification

The gate before merge, run by the human partner. **Corrected from the previous version, which asked for something the code contradicts.**

1. Health → Health Graph Debug → **Load synthetic dataset (400 days)**.
2. **Dump relationship report.** Before this round the dump was almost entirely `possibleTrigger | candidate | 0.750`, including pure-noise demo foods. Expect a smaller set, `improves` present for the DEMO magnesium → migraine edge, and `confirmedNoEffect` rows appearing at all.
3. Protocols & experiments → **+** → the **DEMO**-tagged magnesium → Migraine → Repeated → backdate 90 days → Start → End → tap in. Expect an actual verdict — the Phase A check that has never been completable on a real device.
4. **Open Insights and look at the Archive section.** Decayed edges are *not* invisible: `InsightsFeed.build` collects `.decayed` and `.userDismissed` into an archive section that `InsightsView` renders under a disclosure labelled "Archive, N dismissed insights". The superseded false triggers will land there — never dismissed by anyone, and still carrying their old claim text and old confidence, because `recompute` preserves those fields when decaying a row. Confirm whether that is acceptable; it is a pre-existing behaviour this round triggers at scale for the first time.
5. **Check for a wave of NEW badges.** `EdgeIdentity.edgeKey` embeds the relationship type, so a reclassified edge is a different key: the old row decays and the new one is inserted with `firstSeen = now`, which the feed badges as new. Corrected findings may arrive looking like fresh discoveries.

## Follow-ups this round generates

- **Archive labelling and the NEW wave** (device steps 4-5). Both are pre-existing; this round is the first event that triggers them at scale.
- **`ConfidenceScorer`'s inputs move even though its formula does not.** `exposureCount` shrinks and `lastExposure` can only move earlier, and `w1 = 0.4` / `w5 = 1.5` act on an activation/decay band only 0.228 wide in logit terms. Defensible — "we have not observed this recently" is true — but unquantified. Worth a lapsed-logger measurement before tuning anything.
- **`SignificanceTester` takes `baseRate` as a known `p0`** with no variance accounting. Over a small observed set that point estimate is itself noisy, which weakens the BH-FDR guarantee.
- **Environment events are stamped at local noon** (`EnvironmentalEventEmitter`) while observed days are UTC. For non-UTC users a local-day environment event and that day's manual logs can fall on different UTC days — today that blurs pairing, and under this change it can drop the exposure.
- **`maxLoggingGapDays = 14` and `minPeriodDays = 3` are unvalidated defaults.** Pick them properly once the corrected graph can be inspected on real data.
- Whether "informative" should differ per exposure family — a derived exposure is known on every calendar day, so its pairs only need the *outcome* to have been observable.
