# Second opinion request: should a health-trends feature state a direction, or just show the data?

I want an independent view on a scope decision. Please argue it on the merits — I have a leaning and
I've deliberately kept it out of this brief.

## Context

An iOS health app, on-device only (no backend, no accounts). It ingests Apple Health data — weight,
sleep, steps, resting heart rate, HRV, respiratory rate — and separately lets people log symptoms.
A statistical engine already exists that finds within-person relationships between things they log
(e.g. "dairy → bloating") and is deliberately conservative: an observational confidence ceiling,
confounder penalties, stability checks across time halves, false-discovery-rate correction, and
phrasing that never claims causation.

Audience: patients, plus a functional-medicine and peptide clinic acting as design partner. Their
patients are mostly chronic, multi-symptom, protocol-driven. The app is heading to the App Store.

## The feature in question

A "trajectories" screen showing trends over device-recorded history, with **no** symptom pairing and
no causal claims. It is deliberately the first thing to ship because it needs no symptom logging.

The intended output per series, e.g.:

> **Weight ↓ down 2.4 kg over the last 365 days** (interval −4.1 to −0.8), based on 284 of 365 days

The design to produce that direction:

1. Aggregate daily values to **weekly medians** (daily values are autocorrelated).
2. **Mann–Kendall** test for monotonic trend, with a **Hamed–Rao** variance correction for serial
   dependence.
3. **Theil–Sen** slope for magnitude, with a Sen confidence interval.
4. A **measurement-density guard**: run the same trend test on the weekly *count* of measurements;
   if both the value and the measurement frequency trend, call it confounded and state no direction.
5. An **effect-size floor** per series (e.g. 2 kg for weight) below which no direction is stated.
6. One **Benjamini–Hochberg** correction across the ~6 series.
7. Windows of 90 (default) and 365 days; a coverage floor of 8 weeks and 60% of weeks.

## What two rounds of adversarial audit found

Each round found the design substantively wrong, not just its details. Everything below was
**measured by simulation**, and I independently reproduced the key results.

**Round 1 — the original design**

- The original justification was "this needs no missing-data assumption, because the device records
  regardless of app use". False: weight and blood pressure are *self-initiated* — people measure
  based on how they feel. Simulated on patients whose physiology never changed, **78% were told
  their weight was falling** when only their weighing habits changed across the window.
- Mann–Kendall assumes independence. Weekly medians don't deliver it. False-trend rates on series
  with **no** trend: 5.5% / 23% / 63.5% as serial dependence rises.
- Blood pressure dropped from scope as a result. The density guard and Hamed–Rao were added.

**Round 2 — after those fixes**

- **The density guard destroys real findings.** It is direction-blind: a patient who genuinely loses
  6 kg *and* becomes more motivated (weighing 2×/week → 7×/week) is suppressed **100% of the time**,
  identically to the artefact it exists to catch — even though rising measurement with falling weight
  is the opposite of the confound mechanism. A sign condition fixes this (verified: 100% → 0% false
  suppression, artefact still caught 100%).
- **The guard is blind to the dropout it was built for.** Empty weeks are omitted rather than zero,
  so someone who stops measuring entirely produces a constant count series and the guard is silent —
  0% caught against a 51% artefact rate for stop-then-resume.
- **The 90-day default window has none of the advertised properties.** All published figures were for
  365 days. At 90 days there are 13 weekly points, the correction's significance filter admits almost
  nothing, and it is effectively inert — 24% false trends where 14.5% was claimed.
- **The effect floor is absolute while the change scales with the window.** A real 4 kg/year change —
  the design's own power benchmark — is 0.99 kg over 90 days and is therefore **suppressed with
  certainty in the default view**.
- Two genuine algorithm errors: the variance correction was floored at ~0 instead of 1.0, which on
  anti-persistent series *collapses* the variance and yields p ≈ 0 on pure noise (38% false trends);
  and it ranked raw values rather than trend-removed residuals, inflating the variance of exactly the
  real trends it should leave alone (by up to 11×).
- Several tests in the plan would have failed against a correct implementation, and several
  "mutants" used to validate the tests were inert.

All of the above have known, verified fixes. The question is not whether they *can* be fixed.

## The decision

**Option A — ship the chart, drop the verdict.** Show the weekly-median chart, the range, the
number of days it rests on, and gaps drawn as gaps. Make no directional claim at all. No
Mann–Kendall, no Hamed–Rao, no multiplicity correction, no effect floor, no density guard. Add the
statistical layer later, calibrated against real user data rather than simulated personas.

**Option B — keep the verdict, apply the six fixes.** Sign condition on the density guard, zero-fill
absent weeks, floor the variance correction at 1.0, rank detrended residuals, express the effect
floor as a rate, and publish honest figures for the default window.

## Considerations on both sides

For A: every finding across both audits attacked the *directional claim*; none attacked the chart,
the coverage reporting or the weekly medians. An earlier audit also concluded no clinician would act
on "down 1.2 kg over 365 days" without seeing shape, gaps and outliers — implying the chart carries
the clinical value. The underlying data is self-selected and autocorrelated, which may simply not
support confident directional claims. Shipping sooner gets real data to calibrate with.

For B: a chart alone may be little more than a worse version of Apple Health, which patients already
have. Many users do not read charts well, and a plain-language answer may be the actual product. A
clinical report may want a summary line. The fixes are known and verified, so stopping now might be
over-reacting to an audit process that is working as intended.

## What I'd like your opinion on

1. Which option, and why?
2. If B: is there a defensible way to state a direction on self-selected, autocorrelated personal
   health data — or is the honest conclusion that this class of data supports description but not
   inference?
3. Is there a third option neither of us has considered? (For example: stating a direction only for
   passively recorded series like steps and sleep, and never for self-initiated ones like weight.)
4. Am I over-engineering? Two audit rounds have each found the design wrong. Is that evidence the
   process is working, or evidence the goal is unreachable and I should stop pursuing it?

Assume no constraint on effort — the priority is being right, not being quick.

---

## Decision — 2026-08-28

**Option A. Ship the chart, coverage, range and gaps; state no direction.** Decided by Leo after
two independent analyses reached the same recommendation.

The reasoning that carried it:

- The audit findings split into two piles. Implementation errors (variance floor, detrended
  ranks, effect floor as a rate, honest window figures) are ordinary bugs. The density-guard
  failures are **identifiability failures**: selection lives in *which* days a person measures,
  the guard can only see *how many*, and that gap always contains another counterexample.
- The counterexample that settled it: a patient starts a protocol — the design partner's normal
  onboarding — weighs **more** often (motivation) and skips the scale after bad days (scale
  avoidance). Recorded weight steps down on flat physiology, frequency rises, and the round-2
  sign-condition fix certifies it clean. The verified fix is defeated by the fourth persona.
- The principled dividing line is **observable missingness**, not passive vs. self-initiated.
  Device-recorded series carry their confounder (wear) in the data; weight's confounder is how
  the person felt on the mornings they skipped — definitionally missing, and real user data can
  never supply the counterfactual.
- Apple Health already ships trend arrows; the verdict is the commodity feature. Gaps drawn as
  gaps, "based on 284 of 365 days", and later pairing with symptoms and protocols are the
  differentiated parts.

**What becomes of the verdict:** a restricted direction layer for device-recorded series is a
possible **future round** — guarded on wear directly, 52-week windows only, eligibility earned
by a dense stable record rather than policed by a confound detector, shipped only with honest
per-series false-trend figures backed by a committed simulation harness. Weight earns a
direction only ever under a near-daily stable-record gate, possibly never.

The Round 1b spec and plan (2026-08-27 documents) are revised to match.
