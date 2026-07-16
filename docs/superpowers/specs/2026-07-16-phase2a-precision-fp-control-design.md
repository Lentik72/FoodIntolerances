# Phase 2A — Engine-side False-Positive Control (Precision) — Design

**Date:** 2026-07-16
**Status:** Approved (decisions made interactively with Leo)
**Amends:** `2026-07-15-phase2a-evidence-engine-design.md` (adds a significance gate before activation)
**Depends on:** the merged-pending Phase 2A engine on branch `phase2a-evidence-engine` (all stages Tasks 1–17, commits d2f8856..742e1ab)
**Scope:** Add a statistical-significance + multiple-comparison gate so weak chance-correlations don't reach `active`. Engine + config + one analyzer field + acceptance-suite hardening. **No** change to extraction, lag windows, the confidence formula, or the confounder/decay/noEffect logic.

---

## 1. Problem

The strengthened precision acceptance test (FU-1) surfaced a real defect: at seed 42 the engine produces **~10 spurious `active` edges**, not the 8 planted ones. A dump of the mined corpus:

**Legitimately active (planted, 8):** `dairy→bloating` (P(Y\|X)=0.68), `shortSleep→fatigue` (0.68), `pressureDrop→headache` (0.71), `highStress→tension` (0.65), `luteal→cramps` (0.41), `magnesium→migraine` (improves), `espresso→jitters` + `croissant→jitters` (confounded but genuinely planted). Each has high consistency, or an outcome that only occurs via that exposure (huge ratio).

**False positives (should be internal, ~10):** `chicken→cramps` (P=0.14), `rice→cramps` (0.06), `espresso→cramps`, `croissant→cramps`, `menstrual→cramps`, `shortSleep→headache` (conf 0.68), `shortSleep→migraine` (0.66), `pressureDrop→cramps`, `pressureDrop→migraine`, `luteal→headache`.

**Root cause:** every false positive is a *frequent* exposure that **chance-correlates** with a *common or periodic* outcome (mostly `cramps`). The lift is weak (P(Y\|X) ≈ 0.12–0.29) but squeaks over `ratio ≥ 1.5` and `confidence ≥ 0.35`. The raw base-rate ratio has **no control for sampling noise or the ~78 implicit comparisons** run per recompute. Confidence doesn't separate them — noise `chicken→cramps` and real `luteal→cramps` both sit at 0.70. The confounder analyzer can't catch it because the noise exposure isn't *shadowed by another exposure*; it's just coincidentally correlated. This is exactly the "cry wolf" failure §7 exists to prevent, and §7 already names "false-positive control" as an engine responsibility ("humble statistics").

## 2. Decisions (Leo, 2026-07-16)

| Decision | Choice |
|---|---|
| Mechanism | **One-sided binomial significance test per pair + Benjamini-Hochberg FDR** across all pairs in a recompute |
| Significance test | **Binomial tail** of observed exposure-day follows vs the base-rate expectation, computed in **log-space via `lgamma`** (deterministic, exact for small n). Trigger = upper tail; improves = lower tail |
| Correction | **Benjamini-Hochberg** at conventional `fdrAlpha` (**0.05**) — less conservative than Bonferroni, keeps weak-but-real signals |
| **Effect-size floor** | Activation ALSO requires a meaningful lift: trigger `ratio ≥ activationRatioTrigger` (default **2.0**), protective `ratio ≤ activationRatioProtective` (default **0.55**) — higher bars than the direction gate (1.5 / 0.67). Significance alone can't separate here: with dense data, spurious day-level correlations (frequent foods × the *periodic* `cramps` outcome) are genuinely significant at any conventional α. Significance catches small-n noise; the effect floor catches large-n small-lift noise |
| Gate | A directional pair is `active` only if **significant (BH-FDR @ 0.05) AND past the effect-size floor** (and `confidence ≥ activationThreshold`); otherwise **`candidate`** (internal, may strengthen later). `noEffect`/`confirmedNoEffect` unchanged |
| Precision oracle | Strengthen the acceptance precision test to assert **active edges' (exposure, outcome) ⊆ the planted-pairs set** — a far stronger bar than "no noise-food outcome" |

**Amended (2026-07-16, after P5 validation):** significance+BH-FDR *alone* needed an unprincipled `fdrAlpha ≈ 5e-6` to separate on the harness (dense data makes tiny spurious day-level correlations genuinely significant — statistical significance ≠ meaningful effect). So we keep BH-FDR at conventional 0.05 and **add the effect-size floor above**. The floor is on the **ratio** (lift), not on P(Y\|X): `luteal→cramps` has a *huge* ratio (cramps occur only in the luteal window → base rate ≈ 0), so it clears the floor easily — the earlier objection to a raw P(Y\|X) threshold doesn't apply. Significance handles the small-sample-size dimension; the ratio floor handles the effect-magnitude dimension; together they are robust to data density (a ratio threshold means the same at n=20 or n=200).

**Rejected:**
- **Effect-size floor ALONE** (no significance): a high ratio can arise by chance at small n (e.g. `menstrual→cramps`, n≈15) — significance is needed to catch that. Hence the two gates in combination, not either alone.
- **Effect-size confidence interval:** comparable to the chosen approach but more knobs (margin + CI width + correction) and still needs multiple-comparison control.
- **Fisher's exact test:** heavier (hypergeometric) for no real gain here; the binomial test directly asks the trigger question against a well-estimated base rate.
- **Bonferroni:** too conservative — risks dropping the weak real `luteal→cramps`.

## 3. Design

### 3.1 Contingency (already computed, now surfaced)

The analyzer's per-day counts are the test's inputs. Surface two existing intermediates on `PairStats`:
- `exposureDayCount: Int` — distinct exposure days `n` (`exposureDays.count`).
- `exposureDaysWithOutcome: Int` — `a` (already computed).

The null rate `p₀` is the **window-scaled** base rate — `min(baseRate × windowDays, 1−ε)` where `windowDays = (window.upperBound − window.lowerBound)/24` — **the same null the ratio divides by** (`ratio = pYgivenX / (baseRate × windowDays)`). This matters: a 48h-window intervention (e.g. `magnesium→migraine`) observes the outcome over ~2 days, so testing `a` follows against the raw per-day `baseRate` would understate the expected count and make a real ~50% reduction look insignificant. `baseRate` and the window both already exist at the call site; no new counting.

### 3.2 `SignificanceTester` (new pure stage, `Evidence/SignificanceTester.swift`)

```swift
public enum SignificanceTester {
    /// One-sided binomial p-value that `a` successes in `n` trials is more extreme
    /// than the base rate `p0` predicts, in the given direction. Log-space (lgamma),
    /// deterministic, exact for small n. Clamped p0 to (0,1) to avoid log(0).
    public static func pValue(successes a: Int, trials n: Int, baseRate p0: Double,
                              direction: TailDirection) -> Double
}
public enum TailDirection { case upper, lower }   // upper = trigger, lower = improves
```

- `upper`: `p = Σ_{k=a..n} C(n,k) p0^k (1-p0)^(n-k)`.
- `lower`: `p = Σ_{k=0..a} C(n,k) p0^k (1-p0)^(n-k)`.
- Binomial log-pmf: `lgamma(n+1) - lgamma(k+1) - lgamma(n-k+1) + k·ln(p0) + (n-k)·ln(1-p0)`; sum via `exp`. `p0` clamped to `[ε, 1-ε]`. `n == 0` → `p = 1`.

### 3.3 Benjamini-Hochberg FDR (in `EvidenceEngine.recompute`)

The engine already loops candidates producing a `Relationship` per surviving pair. Restructure into two passes:

1. **Score pass:** for each candidate, compute `PairStats`, confounder penalty, and confidence. Determine the pair's **tail direction** via a small `RelationshipClassifier.tailDirection(stats:)` helper — `upper` when `ratio ≥ candidateRatioTrigger`, `lower` when `ratio ≤ candidateRatioProtective` and `followCount ≥ 1`, else `nil`. This reuses the classifier's exact direction thresholds (DRY, one source of truth), and returns `nil` for both `noEffect`-band and weak-undirected pairs — since a directional ratio (≥1.5 or ≤0.67) is by construction outside the `noEffect` band `[0.83, 1.2]`, directional and noEffect are mutually exclusive. Compute a p-value only for pairs with a non-nil direction (`SignificanceTester.pValue(successes: a, trials: n, baseRate: min(stats.baseRate × windowDays, 1−ε), direction:)` — the **window-scaled** null per §3.1); those are the `m` tested hypotheses. Collect `(candidate, stats, confidence, pValue)` for them, and carry the nil-direction pairs straight to the classify pass unchanged.
2. **BH pass:** sort the collected p-values ascending; the BH threshold is the largest `p_(i)` with `p_(i) ≤ (i/m)·fdrAlpha` (m = number of tested directional pairs). Each pair is **significant** iff its `pValue ≤ threshold`.
3. **Classify pass:** the classifier's direction/status logic is unchanged EXCEPT a directional pair that is **not significant** is capped at `candidate` (never `active`), regardless of confidence. Significant pairs follow the existing confidence ladder (`active`/`candidate`/`decayed`). Upsert/reconcile unchanged.

`noEffect` (`confirmedNoEffect`) is decided before direction and is **not** significance-gated (it's a null claim guarded by the ≥20-exposures/≥90-days rule; it is not a cry-wolf risk).

### 3.4 Classifier change

`RelationshipClassifier.classify` gains a `significant: Bool` parameter. A directional edge is `active` only if **both** hold: `significant == true` **and** it clears the **effect-size floor** — `type == .possibleTrigger && ratio ≥ activationRatioTrigger`, or `type == .improves && ratio ≤ activationRatioProtective`. When either fails, the status is capped at `candidate` (the type is still recorded, for transparency/drill-down). The effect-floor check reads `stats.ratio` + config, which the classifier already has — no new parameter beyond `significant`. Everything else — noEffect-first, the *direction* thresholds (still 1.5 / 0.67, which assign the type / create the candidate), the `improves` `followCount ≥ 1` guard, the confidence ladder, and the rule that significance/floor never resurrect a `.decayed` edge — is unchanged.

### 3.5 Config

`EvidenceConfig` gains `fdrAlpha: Double = 0.05` (conventional), `activationRatioTrigger: Double = 2.0`, and `activationRatioProtective: Double = 0.55`. The two ratio floors are tuned against the acceptance suite (§4): raised/lowered only if a *real* planted edge is borderline-suppressed or a noise edge survives — never to force a specific test past, and the change is documented. `fdrAlpha` stays at the conventional 0.05.

## 4. Validation — the acceptance suite is the oracle

- **Recall (unchanged assertion, must still pass):** all 8 planted pairs are `active` after the gate. The real edges have astronomically small p-values (outcome occurs only via the exposure, or large n with a large lift) → survive BH comfortably.
- **Precision (strengthened — FU-1 done right):** every `active` edge's `(fromExposure, toOutcome)` is in the planted-pairs set. Resolve object edges via `ObjectStore`; derived edges via `fromCategory`/`toSubtype`. This replaces the outcome-vocabulary-only check.
- **FU-2 (unchanged):** illness recorded as a confounder for an overlapping exposure.
- **Determinism / ceiling / noEffect / confounder:** unchanged and must still pass.

What P5 actually found (why the effect-floor was needed): with 400 days of dense data the ~9 spurious edges are *genuinely significant* — noise `chicken→cramps` (a=21 over n≈153, base ≈ 0.09) reaches p ≈ 1e-5, well under any conventional BH threshold. Significance alone therefore could not separate them (it needed `fdrAlpha ≈ 5e-6`, an unprincipled effect-size proxy). The **effect-size floor** separates them cleanly at conventional α: the ~9 FPs are weak-lift (`chicken→cramps` ratio ≈ 1.5 < 2.0; `rice→cramps` ratio ≈ 0.64 > 0.55) → capped at `candidate`, while all 8 planted have either a huge ratio or a strong protective ratio and clear the floor. The two ratio floors (2.0 / 0.55) are what §4 tunes; `fdrAlpha` stays 0.05. If tuning reveals a genuinely borderline *real* edge (e.g. the harness's weak protective `magnesium→migraine` at ratio ≈ 0.50), that is surfaced for a decision, not silently accommodated.

## 5. Out of scope (unchanged from 2A)

- The "3 new candidates/week" **surfacing** cap and any UI — still Phase 2B. (This design gates *activation*, a distinct, engine-level concern; 2B still decides which active edges to surface.)
- Experiment weighting, rechallenge, "what worked before," scheduling, explanations.
- No change to extraction, lag windows, the confidence formula, decay, or edge identity.

## 6. Testing

- Unit: `SignificanceTesterTests` — a strong lift over background yields a tiny p-value; `a` at the base-rate expectation yields p ≈ 0.5–1; `n = 0` → p = 1; upper vs lower direction symmetry; a hand-checked small table (e.g. `n=10, a=8, p0=0.2` upper tail).
- Unit: a BH-FDR helper test — a known p-value vector yields the expected significance threshold/verdicts.
- Unit: `RelationshipClassifier` — a directional, high-confidence pair with `significant: false` → `candidate`; with `significant: true` AND a ratio past the effect-size floor → `active`; with `significant: true` but a ratio BELOW the floor (e.g. trigger ratio 1.6 < 2.0) → `candidate`.
- Integration: the strengthened acceptance suite (§4) — recall + planted-pairs precision + FU-2, all green with `fdrAlpha` default.
- Regression: full `HealthGraphCore` suite green; perf tripwire still comfortably under bound (BH adds an O(m log m) sort over a few dozen pairs — negligible).

## 7. Module layout (delta)

```
Evidence/
  SignificanceTester.swift     // NEW — binomial tail (log-space) + TailDirection
  CooccurrenceAnalyzer.swift   // + exposureDayCount, exposureDaysWithOutcome on PairStats
  RelationshipClassifier.swift // + tailDirection(stats:) helper; + significant: Bool param → caps non-significant to candidate
  EvidenceConfig.swift         // + fdrAlpha = 0.05, activationRatioTrigger = 2.0, activationRatioProtective = 0.55
  EvidenceEngine.swift         // recompute: score → BH-FDR → classify; helper for BH threshold
Tests/
  SignificanceTesterTests.swift          // NEW
  EvidenceEngineAcceptanceTests.swift    // strengthened precision (planted-pairs) + FU-2
  RelationshipClassifierTests.swift      // + significance-gating cases
```
