# Tracked days as the statistical denominator — design

**Date:** 2026-08-25
**Status:** approved, pending implementation plan
**Scope:** replace the calendar-day denominator in `CooccurrenceAnalyzer` with the set of days
the person actually logged something. Thresholds, weights, and the confidence formula are not
touched.

---

## Why this round exists

A device check of the experiments surface produced a verdict that would not appear. Chasing it
found a defect in the evidence engine that has nothing to do with experiments and is much
larger than the thing being tested.

On a real device — 38,069 HealthKit events reaching back to 2016, symptom logging only recent —
the relationship dump is almost entirely `possibleTrigger` at the observational ceiling (0.750),
including demo foods planted as pure noise with no relationship at all. The demo's *protective*
magnesium appears as a trigger:

```
obj:2678E305…:supplement|symptom:migraine|possibleTrigger | candidate | 0.750 | 50 | 157
```

The same corpus, mined in the package, classifies it correctly as `improves` / `active`.

### One event flips the whole graph

Identical 400-day synthetic corpus, mined end to end through `EvidenceEngine.recompute`, twice.
The only difference is a single HealthKit sleep event dated ten years back:

| | relationships | possibleTrigger | improves | noEffect | magnesium → migraine |
|---|---|---|---|---|---|
| corpus alone | 12 | 1 | 1 | 10 | `improves` / **active** |
| corpus + one 2016 event | 16 | **16** | **0** | **0** | `possibleTrigger` / candidate |

Evidence counts are identical in both runs (49 follows, 158 misses). Only the denominator moved.

## The defect

`EvidenceEngine.recompute` sets the observation window from the oldest event of *any* category to
the newest:

```swift
let observation = DateInterval(start: times.min()!, end: times.max()!)   // EvidenceEngine.swift:84
```

`CooccurrenceAnalyzer.analyze` then computes the base rate over every calendar day in that span:

```swift
let totalDays = max(1, Int(observation.duration / 86_400) + 1)
let nonExposureDays = max(1, totalDays - exposureDays.count)
let baseRate = Double(spontaneousOutcomeDays) / Double(nonExposureDays)
let ratio = pYgivenX / max(baseRate * windowDays, eps)
```

This treats every silent day as a day on which the outcome did not occur. That is only true on
days the person was watching. A day in 2019 when Apple Health recorded sleep and the app was not
in use is not evidence of no migraine — it is no evidence at all, and counting it as a clean day
drives the base rate toward zero and inflates every ratio until it clears the trigger threshold.

Two consequences follow, both visible in the measurements above:

- **`confirmedNoEffect` becomes unreachable.** Ten correctly classified no-effect edges became
  zero. The whole confirmed-no-effect path cannot fire on a device with imported history.
- **Protective effects invert into triggers.** The app can tell someone the supplement that helps
  them is causing their symptom. That is the wrong direction on a safety-relevant claim.

This is not a demo artifact. The first-run flow actively encourages connecting Apple Health, so
every user who accepts gets a decade-wide denominator against a few months of real logging.

## Alternatives considered

Each candidate denominator was run against the same magnesium → migraine pair under three
histories. `analyze` consumes `observation` only as a day count, so an interval of the right
length exercises a candidate denominator without changing the engine.

| denominator | clean corpus | + Apple Health to 2016 | + one migraine logged 8 yrs ago |
|---|---|---|---|
| A — all events (today) | improves | **trigger** | **trigger** |
| B — manual-only span | improves | improves | **trigger** |
| C — outcome-tracked span | improves | improves | **trigger** |
| D — exposure ∩ outcome span | improves | improves | improves |
| F — days you logged anything | improves | improves | improves |

The third column decides it. B and C look correct until one stray old log reopens the window: a
single migraine recorded eight years ago and forgotten drags the span to 2,920 days and flips the
verdict. D and F answer nearly identically (ratio 0.36 vs 0.38).

**D was rejected** in favour of F. D still counts calendar days *inside* its window, so a
three-month gap in the middle recreates the same dilution at smaller scale; and it bounds the
comparison to where both series overlap, discarding genuine baseline history for an exposure
started recently.

**A per-symptom "days you logged a symptom" variant was measured and rejected as degenerate:**
symptom days are a subset of outcome days, so the denominator collapses below the numerator and
the base rate came out as 60.0.

## Decision

**A day counts in the statistics only if the person logged something themselves that day.**
Everything else is unobserved, not negative.

### 1. The engine computes the tracked-day set

`EvidenceEngine.recompute` already walks every event once. It builds

```
trackedDays: Set<Date>   // distinct UTC start-of-day of every event with source == .manual
```

and passes it to the analyzer in place of `observation: DateInterval`. One set, computed once,
shared by every pair. HealthKit-sourced events never contribute a tracked day — that is the
mechanism of the fix. On the device that took 3,650 calendar days to roughly 400 tracked days.

`source == .manual` is the definition: any manual capture — a meal, a mood, a dose, a symptom.
The reasoning is that someone engaged enough to log lunch would have logged a migraine. A
narrower rule was measured and is degenerate (above).

**Imported symptoms do not make a day tracked.** `HealthKitSampleMapper` emits
`category: .symptom` (line 345), so an outcome can arrive from Apple Health on a day with no
manual capture. Those days are excluded from both sides. The alternative — treating an imported
symptom as evidence the outcome was observable that day — was rejected because the inference does
not hold in reverse: the *absence* of an imported symptom on such a day proves nothing about
whether the person had one, since they may not use that other app daily. Counting the days the
symptom appears while ignoring the days it would not have been recorded is precisely the
selection bias this round exists to remove.

The cost is real and worth naming: for a *derived* exposure (weather, air quality, sleep) the
exposure is known on every calendar day, so a day with an imported symptom and no manual log is
genuinely informative for that pair, and this rule discards it. That is a per-pair refinement —
"informative" means something different for a manual exposure than a derived one — and it is
deliberately out of scope here. See follow-ups.

### 2. One rule, applied to both sides

The restriction applies to the whole rate computation, not only the denominator:

- `exposureDays` — intersected with `trackedDays`
- `nonExposureDays` = `trackedDays.subtracting(exposureDays)`
- outcome days — intersected with `trackedDays` before subtracting exposure days
- `pYgivenX` = exposure days with outcome ÷ exposure days **on tracked days**

Fixing only the denominator leaves the mirror-image bug in place. Derived exposures (poor air,
short sleep, hot day, moon phase) land on days regardless of whether the person was logging, so a
poor-air day in a month the app was never opened enters the numerator as an exposure that
produced no symptom. Denominator-only would systematically deflate exactly the environmental
factors four previous rounds built.

**Evidence status:** the denominator finding is measured end to end. The both-sides argument is
reasoning from the code — an attempt to measure it was inert, because `ShortSleepExposureSource`
requires a parsed night session with `asleepMinutes` and ignored the raw sleep events planted for
the test. Test 3 below must construct the case properly; until it is green this part is unproven.

### 3. The same set filters the per-occurrence pairs

`pairs` drives the Insights dots, `evidenceCount` (= `followCount`) and `contradictionCount`
(= `missCount`), and `ConfidenceScorer` weights `log(exposureCount)`. Leaving those unfiltered
would inflate confidence with days that taught us nothing, and split the semantics: rates about
tracked days, counts about calendar days. One rule everywhere.

### 4. Three call sites, not one

`analyze` is called from three places, and all three must receive the same tracked-day set or the
engine contradicts itself:

- **`EvidenceEngine.recompute`** — the main pass. Replaces `observation` with `trackedDays`.
- **`EvidenceContext` / `evidence(for:in:)`** — the Insights drill-down. It carries its own
  `observation: DateInterval?` built in `makeContext`, and that function's doc comment already
  warns that a narrowed read makes "the batch numbers stop matching the stored evidenceCount".
  Left alone, the drill-down explains a card using different follow/miss counts than the card
  itself displays.
- **`StabilityValidator`** — the subtle one. It builds a *per-half* window from each half's
  exposure times (`DateInterval(start: lo, end: obsEnd)`) and compares each half's ratio against
  the same `candidateRatioTrigger` / `candidateRatioProtective` thresholds the full pass uses. If
  the halves keep a calendar-day denominator while the full pass moves to tracked days, the two
  ratios are computed on different scales and the stability gate becomes incoherent — passing and
  failing edges for reasons unrelated to stability, with every test still green. Each half must
  use `trackedDays` intersected with that half's window.

### 5. No denominator means no answer

`trackedDays.subtracting(exposureDays)` can be empty — a user who imported Apple Health and never
logged. Today's `max(1, …)` would floor that to one day and report "every outcome happened on the
single comparison day", making everything look wildly protective. `analyze` returns `nil`
instead. This is not a tuning threshold; it is the absence of a comparison. Whether a stricter
minimum tracked-day count is wanted is deliberately left open.

## Consequences

**This round is retroactive and not only additive.** Every relationship is recomputed, so
findings the user has already seen can change type or drop to candidate. Correct, but not
invisible.

`recompute` does not delete: it upserts what it finds and reconciles edges that no longer appear
to `.decayed`, preserving `.userDismissed` throughout (`EvidenceEngine.swift:163,175`). So the
false triggers do not vanish — they become decayed rows. Worth confirming during the round that a
decayed edge is invisible on every surface, because a device carrying fifteen wrong triggers will
be carrying fifteen decayed rows afterwards.

**Stored relationships do not fix themselves.** There is no schema change, but the rewrite only
happens on a recompute. The round must force one after the update, or users keep the wrong edges
until some unrelated event triggers a pass.

**`PoorAirPersonalization` filters on `.active`**, so the Home banner's personalization shifts
with the corrected graph.

**The Insights drill-down count changes.** Filtering pairs means days the person was not logging
stop appearing — "12 times" where they previously saw "20". Defensible, because those days
carried no information, but it is a number a user may already have seen, so the drill-down likely
needs a line saying it counts days you were logging. Copy is in scope; a migration notice is not.

**On an all-manual corpus the fix is a no-op.** Tracked days and calendar days are the same set.
Measured: the clean-corpus row is identical under A and F.

## Testing

Package-level, in `HealthGraphCoreTests`. In the order they should be written:

1. **The bug, named.** Same corpus with and without one 2016 event → magnesium → migraine
   classifies identically. Fails today (`improves`/`active` vs `possibleTrigger`/`candidate`).
   This is the regression test the round exists for.
2. **Gappy logger.** One migraine logged 8 years ago, then silence → still `improves`. This is
   the case that killed the two plausible-looking alternatives.
3. **Derived exposure on untracked days.** Needs a real night-session shape, not raw sleep
   events. Until this is green, §2's both-sides claim is unproven.
4. **HealthKit-only history** yields no tracked days → `nil`, not a fabricated ratio.
5. **The acceptance suite unchanged.** `recallAllPlantedPatterns` and
   `precisionIsHonestForAnAssociationEngine` must pass without edits — they run on an all-manual
   corpus, where the fix is a no-op. If they need editing, the implementation is wrong.
6. **Drill-down agrees with the card.** On a corpus with imported history, the follow/miss counts
   from `evidence(for:in:)` equal the `evidenceCount`/`contradictionCount` stored on the
   relationship by `recompute`. This is the test that catches a missed `EvidenceContext`.
7. **Stability stays coherent.** An edge that is genuinely stable across both halves still passes
   the gate once the full pass uses tracked days. Without this, `StabilityValidator` silently
   compares half-ratios on a calendar-day scale against thresholds calibrated on a tracked-day
   scale, and nothing else in the suite notices.

**Mutants to demonstrate** (mutate, run, restore, report both directions):

1. Swap tracked days back to calendar days → test 1 fails.
2. Let HealthKit events count as tracked days → test 1 fails.
3. Fix the denominator but leave exposure days unfiltered → test 3 fails.
4. Drop the empty-set guard → test 4 fails.
5. Update `EvidenceEngine` but leave `EvidenceContext` on the calendar denominator → test 6 fails.
6. Update `EvidenceEngine` but leave `StabilityValidator`'s per-half windows alone → test 7 fails.

## Not touched

Named so they do not drift in:

- Thresholds, weights, the observational ceiling, lag windows, and the confidence formula.
- Any "we corrected an earlier finding" UI. Findings will change silently.
- The experiments surface. Verdicts change because the engine changes; nothing in
  `ExperimentResult` needs editing.
- The experiments-vs-demo-purge hygiene gap (experiments have no `syntheticBatch` column, so
  clearing demo data strands experiments pointing at deleted objects). Its own round.
- A stricter minimum tracked-day count, beyond "non-empty".

## Follow-ups this round generates

- **Per-pair definitions of "informative".** For a derived exposure the exposure is known on every
  calendar day, so the day only needs the OUTCOME to have been observable; for a manual exposure,
  absence of a log does not establish absence of the exposure, so the day needs manual engagement
  too. This round applies the manual-exposure rule to both, which is conservative and costs
  environment→symptom pairs the days carrying an imported symptom and no manual log. Worth
  revisiting once the corrected graph can be inspected on a real device.
- Whether a minimum tracked-day count should gate mining, once the corrected graph can be seen on
  real data.
- Whether the Insights drill-down should say what its count means, and in what words.
- Whether `exposureCount` in the confidence formula should be tracked-day exposures or occurrences
  — this round makes them the same by filtering pairs, but the question is worth revisiting if
  filtering pairs turns out to hurt the evidence trail.
