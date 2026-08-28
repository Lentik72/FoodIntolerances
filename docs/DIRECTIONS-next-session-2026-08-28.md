# Directions for the next session — written 2026-08-28

This document was produced at the end of a session that (1) analyzed
`docs/OPEN-QUESTION-trends-verdict.md`, (2) audited the Round 1b implementation plan, and
(3) reviewed the whole project. It is self-contained: follow it top to bottom. Where it says
"verified", the fact was checked against the repo on 2026-08-28, not recalled from memory.

**The one-paragraph mission:** the built product (capture → timeline → evidence engine → insights
→ safety → experiments) is complete and green. The project is at the start of the Personal Health
OS re-foundation (`docs/product-direction.md`, round order 1b → 1a → 2 → report → protocols →
backend). Round 1b (health trajectories) is **blocked on one product decision Leo has not yet
made**, and its implementation plan needs revision before any task is executed. Nothing for 1b or
1a is implemented yet — no `Trends/` code, no check-in UI (verified by exhaustive search).

---

## Standing rules for working with Leo (from memory; they apply to you)

- **No shortcuts.** Design and code must be the best available option, not the pragmatic hedge.
  Long-term app, many users, a clinic design partner.
- **Confirm before pushing** to main/shared branches or any outward action broader than literally
  asked. Report-after is not confirm-before. Local commits are fine when asked for.
- **Present design options in plain language with a worked example; give a decisive
  recommendation, not a menu.**
- This repo has **no CI** (`.github/workflows` does not exist — do not claim a CI gate).
- The workflow is superpowers-style: brainstorm → spec (`docs/superpowers/specs/`) → plan
  (`docs/superpowers/plans/`) → subagent-driven execution with TDD and mutation checks → device
  verification gate → merge. Plan checkboxes are never ticked in this repo; completion is judged
  by git history and tests, not checkbox state.

---

## Verified project state (2026-08-28)

**Git:**
- Current branch `fence-legacy-ai`, clean, **2 commits ahead of local main**:
  `d5d8be1` (legacy cloud-AI path compiled out of Release — five files `#if DEBUG`, five call
  sites guarded, verified by a successful Release build) and `93fbb30` (the open-question doc).
- **Local `main` is ~14 commits ahead of `origin/main`** — the entire re-foundation record:
  `docs/product-direction.md`, both round specs, both plans, the five-lens-audit rewrite, plus two
  experiment fixes (`experiment-copy-and-demo` merge). **None of this is backed up anywhere.**
- No open PRs. PRs #1–#12 all MERGED (incl. #10 stress-demo-seed, merged 2026-08-25).
- Stale remote branches never deleted: `stress-exposure`, `stress-demo-seed`,
  `insights-batch-evidence`, `protocols-experiments-phase-a`.

**Tests:**
- Package: `cd HealthGraphCore && swift test` → **434/434 in 75 suites, green** (run 2026-08-28).
- App target: 64 suites; run with
  `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO`.
  **`SwiftDataMigratorTests` crashes the runner (pre-existing), so full-suite totals lie** — count
  `✔ Suite` lines and grep `✘`, or use `-only-testing:` per suite.

**Outstanding non-code items:**
- Protocols Phase A (PR #12) was never device-tested.
- The Timeline weather-unavailable marker overnight UX check (from PR #5) was never done.

**Two false alarms already investigated — do not re-flag them:**
- `Views/AI/FoodQueryView.swift` is unguarded but contains **no** `CloudAIService` /
  `PersonalAIAssistant` reference; it is a static legacy screen. The AI fencing is complete.
- `EvidenceEngine.swift:116` `nullRate = min(stats.baseRate * windowDays, 1 - 1e-9)` is a correct
  cap (a subagent once misread it as `min(x, 1e-9)`).

---

## Gate 0 — back up the decision record (do this first, with Leo's confirmation)

The riskiest thing in the repo is ~16 unpushed commits of irreplaceable decision documents.

1. Ask Leo to confirm, then: merge `fence-legacy-ai` into `main` (fast-forward-able content:
   docs + the fencing commit), push `main` to `origin`, delete the branch.
2. With the same confirmation, delete the four stale remote branches listed above.

Do not push anything without explicit confirmation in-session.

---

## Gate 1 — settle the trends-verdict decision with Leo

`docs/OPEN-QUESTION-trends-verdict.md` asks whether the trajectories feature should state a
direction ("Weight ↓ down 2.4 kg…", Option B with six fixes) or only show the chart (Option A).
**Leo has NOT yet decided.** The previous session's recommendation, delivered in full, was:

**Option A now; a restricted verdict layer as its own later round; never full B.** The complete
argument is in the session record, but the load-bearing points you must be able to reproduce:

1. **Sort the audit findings into two piles.** Implementation errors (variance floor, detrended
   ranks, rate-based floor, window honesty) are fixable engineering. The density-guard failures
   are **identifiability failures**: selection lives in *which* days a person measures, the guard
   can only see *how many*, so the space of selection behaviors always contains a counterexample.
2. **The sign-condition "fix" from round 2 is itself unsound.** Persona: a patient starts a
   protocol (the design partner's normal onboarding), weighs **more** often AND skips the scale
   after bad days (scale avoidance). Recorded weight steps down on flat physiology; frequency
   rises; the sign-fixed guard certifies it clean. And the rate-based floor fix lowers the bar to
   roughly where this selection step lives — the six fixes are individually sound and jointly
   reopen the hole. This is what a third audit round would find.
3. **The principled dividing line is observable missingness, not passive vs. self-initiated.**
   Device series (steps, sleep, RHR, HRV, resp rate): the confounder is wear, which is *in the
   data* — a direction can be defended if guarded on wear directly, with honest per-series
   figures, 365-day/≥26-week eligibility only. Self-initiated series (weight, BP): the confounder
   is how the person felt on unmeasured days — definitionally missing (MNAR); no seventh fix
   exists, and **real user data cannot fix it either** (you never observe the counterfactual), so
   "add the layer later, calibrated on real data" is a mirage for weight.
4. **Product**: Apple Health already ships trend arrows — the verdict is Apple's commodity
   feature. The differentiators are gaps-drawn-as-gaps, "based on 284 of 365 days", weekly
   medians, later pairing with symptoms/protocols (Round 2), and the doctor report. Plain
   language without inference is available and fits the "AI is for language, not evidence"
   commitment. A clinician audit already found the chart carries the clinical value.
5. **Reframe the density guard as an eligibility gate** in any future verdict layer: verdicts are
   *earned* by a dense, stable record (user-legible: "directions appear once there's enough
   steady history"), rather than policed by a confound detector that keeps losing.

Present that summary, get Leo's decision, and record it (update the OPEN-QUESTION doc with a
"Decision" section, or delete it and fold the decision into the spec).

---

## Work package A — revise the 1b spec and plan to match the decision

Files: spec `docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md`,
plan `docs/superpowers/plans/2026-08-27-health-trajectories-and-profile.md`.

### A.1 If Option A (recommended): cut the verdict stack

Delete from scope: Mann–Kendall, Hamed–Rao, Theil–Sen, the density guard, Benjamini–Hochberg,
effect floors, `TrendDirection` — plan Tasks 4, 5, 6, 7, 9 and the verdict half of Task 12.
Keep: Task 1 (sleep union — a shipped bug, solid as written), Task 2 (HealthKit source capture —
solid, including the anchored-query "historical samples stay nil forever" caveat), Task 3 (weekly
bucketing/coverage, with fixes below), Task 10 (profile/derived age — the stored-age fallback is
safety-critical for `HealthMonitoringService`), Task 11 (weight formatting extraction), and the
chart/coverage/profile surface from Task 12. Keep `TrendMeasurement`-style structured values (no
direction field) so the doctor-report round consumes values, not strings.

### A.2 Fixes required regardless of the decision (found by this session's plan audit)

- **DST bug in the pinned window convention** (plan line 26): `windowStart = windowEnd −
  (days−1) × 86_400` lands at 23:00 the previous day across spring-forward, making
  `daysInWindow` 91 and breaking the constraint's own invariant. Use
  `calendar.date(byAdding: .day, value: -(days-1), to: windowEnd)`. All fixtures are UTC-midnight
  so no test catches it — add a DST-timezone test.
- **Bucketing rationale is inverted** (plan line 189): window-anchored buckets shift every day
  *because* windowStart moves with the clock; calendar-anchored weeks are what deliver the
  stability the comment claims. Decide deliberately; fix the comment or the anchor.
- **Partial final bucket**: 90 = 12×7+6, 365 = 52×7+1 — the 365-day window ends in a **one-day
  "weekly median"** and a forced step-down in every `dayCount` series. Whole-week windows
  (91/364 days) dissolve this; requires updating the spec's window numbers.
- **Pin the production calendar/timezone** for day attribution (all tests are UTC; the service's
  calendar is unspecified; a 23:30 weigh-in belongs to different days in UTC vs local).
- **Decouple "chartable" from "verdict-eligible"**: plan Task 9 omits below-coverage series
  entirely, so 6 weeks of weight data would render nothing. The chart is descriptive and should
  render for any data; only statements need floors.
- Spec-to-plan gaps to close: per-series "typical range of normal variation" values are displayed
  (Task 12) but defined nowhere — they are clinical content and need sources + the
  unvalidated-constant treatment; the profile never *asks* for DOB/sex/height when HealthKit
  denies (spec says "asked otherwise"); the seasonality disclosure the spec demands appears in no
  copy; the non-diagnostic line must be app-level, not only on this surface.
- Test-quality fixes: `aRandomWalkIsStillOftenReportedAsATrend_knownLimit` (plan line 744)
  asserts only `r.count == 1` — vacuous; `everyStatedChangeCarriesItsInterval` (line 921) asserts
  `contains("to")` — satisfied by "today"; assert real content.

### A.3 If Option B is chosen anyway (or for a future verdict-layer round), also required

- All six round-2 fixes, located: variance floor `max(n/n*, tiny)` → `max(n/n*, 1.0)` (line 376);
  rank **detrended residuals**, not raw values (line 372); sign condition AND zero-filled absent
  weeks in the density guard (lines 466, and Task 3's weeks array which omits empty weeks);
  effect floor as a rate (line 522); honest 90-day figures or no verdicts at 90 days at all.
- **The MK test suite contradicts the MK implementation spec — provably.**
  `tiesReduceTheVarianceRatherThanBeingIgnored` (line 332) pins z = 3.7666 for
  `[1,1,1,2,2,2,3,3,3,4,4,4]` — the *uncorrected* z (S=54, Var=198). That fixture's rank lag-1
  autocorrelation is 0.75 > 1.96/√12 = 0.57, so Hamed–Rao as specified fires (inflation ≈ 2.1×,
  z ≈ 2.6) and the test fails. Same for `anIndependentSeriesIsBarelyTouchedByTheCorrection`
  (line 345): a rising series' raw ranks are trend-dominated. The tests pass only under
  detrended-ranks + floor-at-1.0 — i.e., **the tests already assume the round-2 fixes the
  implementation text lacks.** Make them consistent.
- `theBenjaminiHochbergThresholdIsActuallyApplied` (line 716) reads `service.lastThreshold`,
  which cannot exist on the declared `Sendable` struct — return the applied threshold in a
  `TrajectoryReport` value instead (the report round wants it anyway).
- **The "one read" constraint is mis-stated** (line 695): it claims "four of the six series share
  `.vitals`" — it's three (verified: steps → `.exercise`, `HealthKitSampleMapper.swift:77`; RHR,
  HRV, respiratoryRate → `.vitals`; weight → `.bodyMetric`; sleep → `.sleep`). A literal 1-call
  test forces a nil-category fetch of the entire corpus (~38k events incl. symptoms/mood). Assert
  ≤ 4 category-scoped calls. Sleep needs lookback to windowStart − 1; fetch the shared interval a
  day early and let bucketing filter it — say so in the plan.
- **Commit the simulation harness.** Every headline number (78 %, 5.5/23/63.5 %, 97–100 %/96 %)
  came from simulations that are not in the repo; that is why the plan is on its second
  generation of pasted constants that disagree with the code. Personas become executable
  regression tests or the numbers are not real.

Useful verified API facts for this work: `EventStore.events(in:category:)` takes
`EventCategory?` (`Database/EventStore.swift:19`);
`SignificanceTester.benjaminiHochbergThreshold(pValues:alpha:)` exists
(`Evidence/SignificanceTester.swift:32`); `EvidenceConfig.default.fdrAlpha = 0.05`
(`Evidence/EvidenceConfig.swift:50`).

---

## Work package B — execute revised 1b

Follow the repo's normal flow (subagent-driven, TDD, mutation checks with the "if a mutant does
not kill its test, say so" rule). Per-task package gate: `cd HealthGraphCore && swift test`.
App-target suites must be run explicitly with `-only-testing:` (the package command never
compiles them). Device verification before merge, per the checklist at the end of the plan —
including "check one series against Apple Health; disagreeing with Apple's chart is worse than
showing nothing".

Blast-radius rules already in the plan that matter: Task 1 changes `asleepMinutes`, which feeds
`ShortSleepExposureSource` — if any existing test moves, **report it, don't absorb it**; the
recompute-after-fix can silently change mined relationships for two-tracker users (a product
decision to surface, not bury). Task 10's `currentAge` must fall back to stored `age` or
age-gated screening silently dies.

---

## Work package C — write the Round 1a implementation plan

Spec (approved): `docs/superpowers/specs/2026-08-27-daily-check-in-and-recorded-observability-design.md`.
This round fixes the engine's one real shipping defect (corpus-span denominator — a single 2016
HealthKit sample measurably flipped a 12-relationship graph to 16 all-`possibleTrigger`). Key
constraints the plan must honor:

- Three states, not two: occurred / recorded-absent / **unknown (default)**. Only positive
  assertions are stored; dismissal = unknown, never a negative.
- Observability is **per outcome**, never a global day-set.
- **Three call sites must all receive the observed-day set**: `EvidenceEngine.recompute`,
  `EvidenceContext.makeContext` / `evidence(for:in:)` (drill-down parity), and
  `StabilityValidator.directional` (the easy one to miss — leave it behind and the stability gate
  passes/fails for reasons unrelated to stability with every test green).
- `nil` when no comparison days remain — never floor the denominator to 1.
- Two new tables (ongoing conditions; observed absences), following the `experiments` migration
  precedent. Severity events keep their existing shape (`unit: "severity"`, 1–10).
- Testing must include **personas under both capture models** (engaged-then-logs vs
  symptom-brings-them-to-the-app) — the two models that defeated every previous denominator; the
  spec lists five named mutants — use them.
- UX: Insights go quiet on upgrade **by design** — the app must say so and show progress toward
  re-qualification; fixing the archive's "dismissed" mislabel is in scope; redesigning the
  archive is not.

---

## Housekeeping queue (fit in when convenient)

1. Protocols Phase A device check (never run; do before real patients touch experiments).
2. Timeline weather-unavailable marker overnight UX check (pending since PR #5).
3. Eventually: delete the legacy Debug-only view tree (`MainTabView`, `MoreView`, Dashboard/
   Logging/Onboarding/Protocols views) — dead in Release, still compiled in Debug.
4. Memory hygiene: `stress-demo-seed` memory was corrected to MERGED on 2026-08-28; keep memory
   PR states in sync with `gh pr list`.
