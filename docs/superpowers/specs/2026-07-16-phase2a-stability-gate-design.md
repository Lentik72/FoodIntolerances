# Phase 2A Precision — Temporal Stability Gate — Design

**Date:** 2026-07-16
**Status:** Approved (decisions made interactively with Leo)
**Amends:** `2026-07-16-phase2a-precision-fp-control-design.md` (adds the third activation gate)
**Depends on:** the significance + effect-size gates already built (branch `phase2a-evidence-engine`, commits through `86137da`)
**Scope:** Add an out-of-sample replication (temporal stability) requirement for activation. One new pure stage, one classifier param, one config value, an allow-list correction to the precision oracle. No change to extraction, lag windows, the confidence formula, significance, the effect-size floors, decay, or edge identity.

---

## 1. Problem

Significance (BH-FDR @ 0.05) + the effect-size floor reduced false-positive `active` edges from ~10 to 2, but two survive that gating fundamentally cannot remove (measured, seed 42):

- **`chicken→cramps`** (ratio 2.0303) — a pure chance correlation whose ratio is essentially identical to a genuine planted edge, `espresso→jitters` (ratio 2.0321). A 0.0018 gap; no ratio or significance threshold separates them.
- **`cyclePhase.menstrual→cramps`** (ratio 6.20) — a *real* cycle correlation (cramps cluster around the menstrual cycle). Its ratio exceeds a genuine planted edge (`pressureDrop→headache`, 4.08), so any floor that drops it also kills real recall.

`chicken→cramps` is an **overfitting** problem: a spurious pattern in one snapshot. Overfitting has one correct cure — **held-out validation**. A genuine association holds up when you split the data; a chance one does not. Neither significance nor effect size can catch it *by construction*, because at a single point in time a chance correlation and a real one are indistinguishable. Only replication can. `menstrual→cramps` is not a false positive at all — the precision oracle's "exactly the 8 planted pairs" was simply too strict; the harness creates real cycle correlations beyond the one planted.

## 2. Decisions (Leo, 2026-07-16)

| Decision | Choice |
|---|---|
| Third gate | **Temporal stability** — the association must replicate in both time-halves of the evidence to activate |
| Split | **Temporal, at the median exposure time** (health associations should be temporally stable; a chance pattern clustered in one period won't replicate) |
| Criterion | Both halves **directional in the same direction** as the full data (each half's ratio past the direction gate, ≥`candidateRatioTrigger`/≤`candidateRatioProtective`), each half with ≥ `stabilityMinExposuresPerHalf` exposures. **Not** "fully significant in both halves" — splitting halves the data; only the *direction* need replicate, which is robust for real signals and fragile for chance blips |
| Insufficient data | A pair without enough exposures to split (< ~2× the per-half minimum) can't be validated → stays `candidate` until more data accrues (natural early-data conservatism) |
| `menstrual→cramps` | **Allow-listed** as a legitimate cycle correlation (it replicates); the precision oracle accepts `active ⊆ planted ∪ {menstrual→cramps}` |

**Rejected:**
- **Random / odd-even split:** less meaningful for time-series health data; a temporal split specifically catches non-stationary chance patterns.
- **Significant-in-both-halves:** too strict — halving the data halves the power, risking suppression of genuinely weak-but-real signals; the direction replicating is the right, robust bar.
- **Accepting `chicken→cramps` as a documented chance FP:** papers over one instance; replication retires the whole class and is robust across seeds and data densities.

## 3. Design

### 3.1 `StabilityValidator` (new pure stage, `Evidence/StabilityValidator.swift`)

```swift
public enum StabilityValidator {
    /// True iff the association replicates in BOTH temporal halves. Splits the
    /// exposures at their median timestamp; runs CooccurrenceAnalyzer on each half
    /// over that half's observation window; requires each half to be directional in
    /// `fullDirection` and to have >= config.stabilityMinExposuresPerHalf exposures.
    public static func isStable(exposure: [ExposureOccurrence], outcome: [OutcomeOccurrence],
                                window: ClosedRange<Double>, fullDirection: TailDirection,
                                config: EvidenceConfig) -> Bool
}
```

- Sort exposures by time; split at the median index into `early` / `late`. If either half has `< config.stabilityMinExposuresPerHalf` exposures → **not stable** (insufficient data to validate).
- For each half, build a sub-observation `DateInterval` bounding that half's exposures, run `CooccurrenceAnalyzer.analyze` on `(half, all outcomes, window, sub-observation)`, and check the resulting `ratio` is past the direction gate in `fullDirection`:
  - `fullDirection == .upper` → require `ratio >= config.candidateRatioTrigger` in **both** halves.
  - `fullDirection == .lower` → require `ratio <= config.candidateRatioProtective` in **both** halves.
- Deterministic (median split by timestamp; analyzer is pure). Reuses the existing analyzer — no new statistics.

Outcomes are NOT split — each exposure half is tested against the full outcome stream (an early-half exposure can only match outcomes in its own window anyway, so this is correct and simpler).

### 3.2 Classifier change

`RelationshipClassifier.classify` gains a `stable: Bool` parameter (symmetric with `significant`). Activation now requires **all three**: `significant`, the effect-size floor, and `stable`. When any fails, the status is capped at `candidate`. `.decayed` and `confirmedNoEffect` remain unaffected; the type is still recorded.

```swift
        if status == .active && (!significant || !meetsEffectFloor || !stable) { status = .candidate }
```

### 3.3 Engine change

In `recompute`'s pass-2 (or a small extension of pass-1), for each pair that already passes significance **and** the effect-size floor (the would-be-active set — checked via the classifier's existing logic / `tailDirection` + ratio), compute `stable = StabilityValidator.isStable(...)` using the pair's `tailDirection` as `fullDirection`, and pass it to `classify`. Pairs that aren't would-be-active don't need the stability computation (efficiency). Everything else — the two-pass structure, BH threshold, upsert/reconcile — is unchanged.

### 3.4 Config

`EvidenceConfig` gains `stabilityMinExposuresPerHalf: Int = 5` (= `minExposures`; a half must carry at least a full candidate's worth of evidence to count as a validation).

## 4. Validation — the acceptance suite is the oracle

- **Precision (updated):** `active` edges' (exposure, outcome) ⊆ **planted ∪ {`cyclePhase.menstrual|cramps`}**. `chicken→cramps` must now be `candidate` (fails stability). All ~9 original FPs remain suppressed.
- **Recall (unchanged):** all 8 planted pairs stay `active` — each is planted with constant probability across all 400 days, so it replicates in both halves.
- **FU-2, ceiling, noEffect, determinism, espresso/croissant confounder:** unchanged, still green.
- `stabilityMinExposuresPerHalf` is the only new tunable; adjusted only if a *real* planted edge is borderline-suppressed, documented.

**Honest risk:** if `chicken→cramps` happens to replicate across both halves at seed 42, stability won't catch it — and that would indicate it isn't pure chance. The implementer surfaces the measured per-half ratios rather than forcing the test; if it can't be separated, that is a real signal to reconsider, not a tuning gap.

## 5. Out of scope (unchanged)

No change to extraction, lag windows, the confidence formula, significance/BH-FDR, the effect-size floors, decay, edge identity, or migrations. The "3-new-candidates/week" surfacing cap remains Phase 2B.

## 6. Testing

- Unit `StabilityValidatorTests`: a pair with a consistent effect in both halves → stable; a pair whose effect appears in only one half → not stable; a pair with a half below `stabilityMinExposuresPerHalf` → not stable; protective (`.lower`) direction works.
- Unit `RelationshipClassifier`: a significant, past-floor, but `stable: false` pair → `candidate`; `stable: true` → `active`.
- Integration: the acceptance oracle (§4) — precision (⊆ planted ∪ menstrual→cramps), recall, FU-2, ceiling, noEffect, determinism — all green.
- Regression: full `HealthGraphCore` suite green; perf tripwire still under bound (stability adds two half-analyses only for would-be-active pairs — a handful per run).

## 7. Module layout (delta)

```
Evidence/
  StabilityValidator.swift     // NEW — temporal-split replication check (reuses CooccurrenceAnalyzer)
  RelationshipClassifier.swift // + stable: Bool param (active requires significant AND floor AND stable)
  EvidenceConfig.swift         // + stabilityMinExposuresPerHalf = 5
  EvidenceEngine.swift         // recompute: compute stability for would-be-active pairs, pass to classify
Tests/
  StabilityValidatorTests.swift          // NEW
  RelationshipClassifierTests.swift      // + stability-gating cases
  EvidenceEngineAcceptanceTests.swift    // precision ⊆ planted ∪ {menstrual→cramps}
```
