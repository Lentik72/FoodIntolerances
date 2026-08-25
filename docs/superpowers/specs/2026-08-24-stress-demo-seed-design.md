# STRESS demo seed — design

**Date:** 2026-08-24
**Status:** approved, pending implementation plan
**Scope:** a deterministic synthetic corpus that exercises the stress exposure end to end,
usable both as a DEBUG device affordance and as a package acceptance test.

---

## Why this exists

The stress-exposure round (PR #9) shipped with its device check unrun, and the attempt
failed for a structural reason rather than an oversight: **the device's graph cannot
demonstrate the feature.** Mining needs exposure→outcome pairs; outcomes come almost
entirely from manual capture; the device has ~20 manual events against ~38,000 imported
ones, and the relationship report is empty. The previous round hit the same wall and had to
formally declare its relationship-diff gate vacuous.

Seeding by hand was tried and is the wrong instrument: it takes a dozen taps per run, it is
easy to get subtly wrong (a severity below 7 silently does not count), and it writes stress
and headache logs that never happened into a real health history.

The existing demo loaders — MOOD, OUTSIDE-FACTORS, WEATHER — already solve exactly this, and
the demo-data-hygiene round made their output **marked and purgeable**. A stress one is the
missing member of that set.

## What it plants

`StressDemoSeed` produces a deterministic `[HealthEvent]` over 120 days:

- **Stress days** — roughly half of all days carry a rated Stress symptom:
  `.symptom` / `stress` / unit `severity`, value 7–9. That is exactly the shape
  `HighStressExposureSource` accepts, and the values sit above `highStressThreshold` (7).
- **Followed headaches** — on ~75% of stress days, a headache roughly 3 hours later, inside
  the `stressLagHours` window of `0...24`.
- **Baseline headaches** — on ~15% of non-stress days, so the engine has a genuine contrast.
  Without it the unexposed rate is zero, the ratio is degenerate, and the demo would prove
  less than it appears to.

Determinism comes from index arithmetic, matching the WEATHER loader's style rather than a
seeded RNG, so the same corpus is produced every run and the acceptance test cannot flake.

Target margins against `EvidenceConfig`: ~60 exposures (vs `minExposures` 5), ratio ≈ 5
(vs `candidateRatioTrigger` 1.5). Tuned against the real engine, not guessed — **if the
relationship cannot clear the significance, effect-size and stability gates at a realistic
effect size, the numbers do not get inflated until it passes; that outcome gets reported.**

## What it proves

Because a rated Stress log is simultaneously an exposure and an outcome, this corpus creates
the tautology opportunity automatically. One seed therefore demonstrates both halves of the
stress round:

- `highStress → headache` **present** — the second accepted shape mines.
- `highStress → stress` **absent** — the derivation rule holds, despite that pair having
  perfect co-occurrence available to it and therefore being the edge most likely to clear
  the gates if the rule were broken.

## Where the code lives

`StressDemoSeed` goes in the **package** (`HealthGraphCore/Synthetic/`), not inline in the
debug view as the other three loaders do. That is the whole point: a seed in the package is
testable, which converts this from a button into an automated end-to-end check.

- Package: `HealthGraphCore/Sources/HealthGraphCore/Synthetic/StressDemoSeed.swift`
- One new `DemoBatch.stress` case, so the batch is purgeable and namespaced like its siblings.
- App: a `Load STRESS demo` button in `HealthGraphDebugView`, following `loadMoodDemo`
  exactly — `resetForSeedReload(batch:)`, save `DemoBatch.stamp(events, batch:)`, recompute,
  refresh.

## Testing

Shape assertions on the generated events (every stress event matches the accepted shape;
values in range; headaches fall inside the lag window; baseline noise exists), plus the test
this round exists for:

**An acceptance test over the real engine** — generate, insert into an in-memory database,
run `EvidenceEngine.recompute`, and assert `highStress → headache` is active while
`highStress → stress` is absent. That is stronger than the stress round's existing
integration test, which stops at candidate generation because a hand-built corpus could not
clear the statistical gates. This corpus can.

## Out of scope

- Any change to `EvidenceConfig`, the gates, or the exposure/derivation logic. If the seed
  cannot produce a relationship, that is a finding about the seed, not licence to move a
  threshold.
- Replacing the hand-built inline style of the other three loaders. They work; this is not a
  refactoring round.
- Shipping demo data in Release. The button stays `#if DEBUG`, like its siblings.
