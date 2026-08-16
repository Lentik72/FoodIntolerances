# Stress as an exposure — design

**Date:** 2026-08-13
**Status:** approved, pending implementation plan
**Scope:** wake the dormant `highStress` exposure by mining the stress logs the app can
already record. Stress as an *outcome* family is explicitly deferred.

---

## Why this round exists

The first-run round (`2026-07-26-first-run-and-health-connect`) hardened
`HighStressExposureSource` into a positive allowlist: `.stress` category, subtype
`stressRating`, unit `score`, value 1–10, threshold ≥ 7. That fixed a live defect — the
previous rule accepted *any* `.stress` event, and the only producer was HealthKit Mindful
Sessions carrying duration in **minutes**, so every meditation of 7+ minutes was mined as a
high-stress exposure with inverted semantics.

The fix removed the only producer. Nothing in the app writes a `stressRating`, so
**`highStress` has been dormant by design ever since** — a tested exposure family with no
input. That is the debt this round pays.

## The discovery that shapes the design

Stress is *already loggable*, and already mined — as something else.

`SymptomCatalog` contains a **"Stress"** entry (canonical key `stress`), and `OutcomeSource`
maps **every distinct symptom subtype** to an outcome. So today:

| | Category | Subtype | Unit | Written by | Role in the engine |
|---|---|---|---|---|---|
| Symptom "Stress" | `.symptom` | `stress` | `severity` | symptom capture — **works today** | outcome |
| Stress rating | `.stress` | `stressRating` | `score` | **nothing** | exposure |

A user who wants to record stress will search the symptom field, find "Stress", and log it
at 8. That is the obvious path, it works, and it is invisible to the exposure miner.

Adding a separate stress capture surface would therefore create *two* ways to log stress
that mean different things, with nothing on screen indicating which one counts. The
discoverable one would be the one that doesn't.

## Decision

**Teach the consumer to read what already exists, rather than adding a producer.**

Rejected alternatives:

- **A dedicated stress capture surface** writing `.stress`/`stressRating`. Conceptually
  clean, but leaves symptom-"Stress" in place as a decoy that silently doesn't count.
- **A dedicated surface plus retiring "Stress" from the symptom catalog.** One entry point,
  but it *removes an existing outcome* — "does poor air worsen my stress?" stops being
  answerable — and needs `retiredSubtypes` handling for historical rows.

## What changes

### 1. `HighStressExposureSource` accepts a second shape

| | Category | Subtype | Unit | Value |
|---|---|---|---|---|
| Existing (kept, dormant) | `.stress` | `stressRating` | `score` | 1–10, ≥ threshold |
| **New** | `.symptom` | `stress` | `severity` | 1–10, ≥ threshold |

Both remain **positive allowlists with a unit guard**. This is what keeps the Mindful
Sessions defect closed: that event is `.stress` with unit `min`, and it fails both shapes.
The guards are load-bearing and their existing tests must keep passing unchanged.

**Only *rated* stress logs become exposures.** `CaptureService.logSymptom` writes
`unit: "severity"` when a severity is given and `nil` otherwise, so a "Stress" log with no
rating has a `nil` value and is rejected by the range check. A log that says "I was
stressed" without a number cannot be thresholded at 7, and must not be guessed at.

**The dormant `.stress` branch stays.** It costs nothing, is already tested, and documents
the exact shape any future writer must produce — a dedicated capture surface, or an Apple
*State of Mind* import. Deleting it would mean rediscovering the contract later.

**The threshold does not change.** `highStressThreshold = 7` applies to the severity scale
unchanged: both scales are 1–10 and mean the same thing.

### 2. `CandidateGenerator` skips shadowed pairs

One stress log now yields two things from the **same event**: an exposure
(`derived:highStress`) and an outcome (`symptom("stress")`). `CandidateGenerator` pairs
every qualifying exposure with every qualifying outcome, so it would generate
`highStress → stress` and mine it. The co-occurrence is perfect *by construction* — same
event, same timestamp — so it passes every gate and surfaces as a high-confidence insight
reading "High stress → Stress".

That is the worst failure mode available here: not a crash, but a statistically immaculate
tautology sitting beside real findings and devaluing all of them.

**An exposure key may declare that it *shadows* an outcome key** — "I am derived from that
outcome's events, so testing me against it is meaningless." `CandidateGenerator` skips any
candidate whose exposure shadows its outcome. Today there is exactly one entry:

```
derived(.highStress)  shadows  symptom("stress")
```

Expressed as a declaration rather than an `if` so the *reason* lives in the code: the next
exposure derived from an outcome event declares itself and is correct automatically,
instead of reproducing this bug and waiting for someone to notice a suspiciously perfect
result.

Concretely: a static mapping co-located with the exposure model (where `ExposureKey` and
`OutcomeKey` both live), consulted by `CandidateGenerator` — not a field on the key type,
and not a scattering of checks at the call sites.

**Deliberately per-key, not per-event.** Both occurrence types carry a `sourceEventID`, so
the exclusion could be narrowed to the same log. That was rejected: it would still permit
"your 9am stress predicts your 3pm stress", which is autocorrelation dressed as insight.
Any stress→stress edge is uninformative.

**The exclusion must stay surgical.** `highStress → headache` from the same log must still
be generated. "Stress exposures don't pair with symptoms" would be a regression, not a fix.

### 3. Discoverability

Add `"Stress"` to `SeedSymptomGrid.offeredNames`, so it can be chosen during first run and
become a one-tap quick-log chip. `SeedCatalogTests` already enforces that every offered
name exists in the catalog and is not a red-flag key, so the addition is validated for
free.

### Not touched

No new screens, no new `CaptureService` method, no schema change, no migration. The lag
window (`stressLagHours = 0...24`) and the Insights label ("High stress", via
`InsightPhrasing`) already exist and are correct.

## Consequence: this change is retroactive, and it reaches further than new edges

Any historical `.symptom`/`stress` log with a severity ≥ 7 becomes a high-stress exposure on
**the next recompute**. This is intended — the signal arrives immediately rather than after
weeks of new logging — but the relationship set can change without the user logging
anything new.

**It is not only additive.** `EvidenceEngine` builds its confounder pool from *every
exposure key that has occurrences* (`EvidenceEngine.swift:86-87`: "Day-sets for confounder
analysis: every exposure key + illness (always)"). `highStress` has always been in that
loop and has always contributed nothing, because it had no occurrences. The moment it has
some, **high-stress days join the confounder pool for every other candidate**, and existing
relationships whose exposure days overlap stressful days can be penalized and lose
confidence.

That is the correct behaviour — stress is a genuine confounder, and the engine was built to
account for it — but it means this round can *demote* findings a user has already seen. It
is not an out-of-scope item to be avoided; it is a consequence to expect and to look for
when verifying.

**A second-order interaction, accepted:** for a candidate whose *outcome* is
`symptom("stress")` — say `poorAirDay → stress` — the confounder pool still contains
`highStress` days, which are by construction the days that outcome is severe. Such a
candidate is therefore penalized by something close to its own outcome. The effect is
suppression, never fabrication, and stress-as-an-outcome is deferred anyway, so this round
accepts it rather than special-casing the confounder pool. Revisit it in the outcome round.

## Testing

Package-level, in `HealthGraphCoreTests`. The existing `HighStressExposureSourceTests` must
pass **unchanged** — the new shape is additive and must not weaken a single guard.

New coverage:

- a `.symptom`/`stress`/`severity` log at or above threshold yields a `highStress` exposure
- the same log below threshold does not
- a `.symptom`/`stress` log with `nil` value and `nil` unit (no severity given) does not
- a `.symptom` log with the right unit but a different subtype (`headache`) does not
- a `.symptom`/`stress` log with a wrong unit (`score`, `min`) does not — the unit guard is
  per-shape, not global
- `CandidateGenerator` does not emit `highStress → symptom("stress")`
- `CandidateGenerator` still emits `highStress → symptom("headache")` from the same corpus

**Mutants to demonstrate** (mutate, run, restore, report both directions — the convention
established in the previous round):

1. Drop the unit guard on the new shape → a nil-severity or wrongly-united stress log is
   mined.
2. Drop the subtype guard on the new shape → every rated symptom at ≥ 7 becomes a
   high-stress exposure.
3. Remove the shadow rule → `highStress → stress` is generated, and a corpus containing
   only stress logs mines a perfect tautology.
4. Over-broaden the shadow rule to all symptoms → `highStress → headache` disappears,
   which is the entire point of the feature.

## Out of scope

Named so they do not drift in:

- **Stress as an outcome family** — "what makes me stressed?", its own Insights phrasing,
  and what the app is allowed to claim about rising stress. Deferred by decision; stress
  remains an outcome only in its existing form, as the symptom subtype.
- A dedicated stress capture surface, and any Home quick-check for stress.
- HRV-derived or otherwise inferred stress. Inferring stress from physiology is exactly the
  class of mistake the Mindful Sessions defect was.
- Mindfulness as a protective exposure family (a separate spec follow-up).
- Any change to `highStressThreshold`, the lag window, or the evidence gates.

## Follow-ups this round generates

- Stress as an outcome family, with phrasing that does not alarm.
- Revisit whether "Stress" belongs in a body-region symptom catalog at all, or wants its own
  concept — worth asking once the outcome round has a view on it.
