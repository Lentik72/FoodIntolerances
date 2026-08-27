# Daily check-in and recorded observability — design

**Date:** 2026-08-27
**Status:** approved, pending implementation plan
**Scope:** Round 1 of three. Ongoing conditions, a daily check-in that rates them, and the
engine change that makes a silent day mean "unknown" instead of "no symptom". The continuous
estimand (Round 2) and episode resolution follow-ups (Round 3) are deliberately out.

---

## Why this round exists

Two things arrived at the same conclusion.

**The engine is asserting things it cannot support.** `CooccurrenceAnalyzer` computes
`baseRate = spontaneousOutcomeDays / nonExposureDays`, where `nonExposureDays` counts every
calendar day between the oldest and newest event of *any* source (`EvidenceEngine.swift:84`).
Measured: adding a single HealthKit sleep sample dated 2016 to an otherwise identical 400-day
corpus took the graph from 12 relationships (1 trigger, 1 improves, 10 no-effect) to 16 — all
`possibleTrigger`, zero `improves`, zero `noEffect` — with the evidence counts unchanged. Only the
denominator moved.

Four replacement denominators were measured against realistic histories. Every one of them fails
in some direction:

| rule | fails how |
|---|---|
| calendar days (today) | false triggers — and **not only from imports**: a null pair at 50% logging engagement already reads `possibleTrigger`/`active` with no imported data at all |
| days with a manual log | false **protective** verdicts at `active`; a day joins the set *because a symptom was logged*, so the base rate climbs toward 1.0 as engagement falls |
| calendar days inside active logging periods | false triggers again, when symptoms are only logged by people already using the app |
| exposure ∩ outcome span | breaks on a returning user's gap |

The two survivors fail in opposite directions, and which one is right depends on a question the
data cannot answer: on a day with no symptom log, does "no symptom" apply, or "not watching"?
**This is unidentifiable from event data.** Case-crossover does not escape it either — it relocates
the same assumption into how referent windows are chosen.

**So the answer is not a better inference. It is to stop inferring.**

**And the product points the same way.** The users who need this most — and, on the design
partner's account, most of the users — have chronic or long-lasting conditions. Psoriasis,
endometriosis, long COVID. They are not asking "did I get a migraine on Tuesday". They are asking
what makes it better or worse: medications, supplements, peptides, weather. For them a daily
severity rating is the natural interaction *and* it records observability as a side effect. One
feature answers both problems.

## The core insight

**The model has two states where it needs three.** A symptom row exists or it does not, and
absence is read as "no symptom". Adding **unknown** as a representable state is the whole fix.

| state | today | after |
|---|---|---|
| symptom occurred | a row exists | a row exists |
| symptom did not occur | *inferred from absence* | **recorded** |
| we don't know | *not representable* | **the default** |

The daily rating is not a feature that happens to help the statistics. **The rating is the
observability record.** A day with a rating is observed; a day without one is unknown. There is no
heuristic, no threshold, no argument about what silence means.

## Product principles

**On-device is the default and stays the default.** No account, no backend, no sync in this round
or the ones that follow it. A patient may choose to share a report with their practice; nothing
leaves the device unless they take that action, and the app must never present sharing as the
expected path. This is a standing constraint on every later round, not a Round-1 detail.

**Reported history is not evidence.** "I've had this about three years" is valuable — it belongs in
a doctor's report — but it is not three years of observation, and the engine must never treat it as
such. There were no exposures logged then either, so those days could not support a finding
regardless.

**Silence is never a claim.** Dismissed, ignored, and never-opened all resolve to unknown.

## What ships

### 1. Ongoing conditions

A symptom can be marked **ongoing**: "I have this all the time." It records:

- the canonical symptom key (existing `SymptomCatalog`)
- when tracking started (the real, precise date tracking began)
- an optional **reported onset** — days / months / years, deliberately coarse, stored as reported
  history and never as observation
- whether it is still active, and when it stopped

An ongoing condition is a first-class record in its own table, following the `experiments`
precedent from the protocols round rather than being encoded in event metadata. It has a
lifecycle, it is queried directly, and it drives a Home surface.

Marking something ongoing means the person is not expected to log it daily as an occurrence. They
rate it instead.

### 2. The daily check-in

One card on Home, following `MoodCheckInView`, which already proves the pattern works here
(per-day dismissal key, loads today's state, survives relaunch within the day).

It covers two things in one pass:

- **Ongoing conditions** — each rated **1–10**, with the person's recent ratings shown alongside so
  they anchor against their own history rather than a drifting idea of what "7" means.
- **Tracked episodic symptoms** — a single "none today" confirmation, or tap the ones that
  happened.

**What makes a symptom "tracked" must be explicit, because the check-in is unbuildable without
it.** It is the set the person chose during first run (`SeedSymptomGrid` already captures this and
turns them into quick-log chips), plus any symptom they have logged recently, minus anything they
turn off. It is *not* every symptom in the catalog — a list of 90 is not answerable daily — and it
is not silently inferred, because a symptom quietly added to the list would start generating
negatives the person never asserted. The person must be able to see and edit the list.

The second half is what makes the strict reading survivable. Without it, "no migraine logged" stays
ambiguous forever and every occurrence finding has to go quiet permanently. With it, a person who
answers has genuine negatives and the engine may say what it is entitled to say.

**Why 1–10 and not 1–5.** The app already stores severity as 1–10 (`unit: "severity"`), and the
stress exposure thresholds at ≥7 on that scale — changing it forks existing data and invalidates a
shipped threshold. Clinically, 0–10 numeric rating scales are the standard for exactly this. Their
real resolution is closer to five levels, but the analysis is within-person: what matters is
self-consistency, not that a 6 means the same thing to two different people. Scale drift is a UI
problem, addressed by showing recent ratings, and by analysing in personal percentiles — the
machinery the weather exposures already use.

### 3. Observability, recorded

The engine derives, **per outcome**, the set of days on which that outcome was observed:

- a severity rating for an ongoing condition on day D → D is observed for that condition
- a symptom logged on day D → D is observed for that symptom
- a "none today" confirmation covering symptom S on day D → D is observed for S, and negative
- anything else → **unknown**, and the day does not exist as far as that outcome's statistics go

Only positive assertions are stored. Absence of a record means unknown; nothing needs to be written
to say "we don't know", which is also what makes the default safe.

Observability is **per outcome, not global**. A day when someone rated their psoriasis but said
nothing about migraine is observed for one and unknown for the other. A single global day-set would
re-introduce exactly the guessing this round removes.

Mood already satisfies this by construction — the mood check-in records a daily value, so mood
outcomes have observability today.

### 4. The engine reads observed days

`CooccurrenceAnalyzer.analyze` takes the observed-day set for the outcome under test in place of
today's `observation: DateInterval`, and:

- restricts **both** sides to it — exposure occurrences, outcome occurrences, and the day counts,
  so a statistic computed over one universe is never compared against a count taken over another
- computes `nonExposureDays` as the observed days minus the exposure days
- returns `nil` when no comparison days remain, rather than flooring the denominator to 1. A floor
  would report "every outcome happened on the single comparison day" and make everything look
  wildly protective.

There are **three** call sites and all three must receive the same set:

- `EvidenceEngine.recompute` — the main pass
- `EvidenceContext.makeContext` / `evidence(for:in:)` — the Insights drill-down, which builds its
  own window today and would otherwise explain a card using different numbers than the card shows
- `StabilityValidator.directional` — the easy one to miss. It builds a *per-half* window from each
  half's own exposure times and compares those ratios against the same thresholds the full pass
  uses. Leave it behind and the two ratios sit on different scales, so the stability gate starts
  passing and failing edges for reasons unrelated to stability, with every test still green.

Note the direction when reasoning about it: **widening a half's day set shrinks its base rate and
raises its ratio.** A protective edge fails its gate by rising above the threshold, not by falling.

## Consequences

### Insights go quiet, and the app must say so

This is the largest user-visible effect and it is intended. Existing history has no recorded
observability, so on upgrade almost nothing qualifies and most current findings disappear until
check-ins accumulate. For an existing user — including the author — that is a hard reset.

The app must explain it rather than appear broken: say that findings now wait for enough recorded
days, and show progress toward that ("14 days recorded"). An empty Insights tab with no explanation
reads as a bug, and a user who thinks it is a bug is right to distrust everything it says later.

The alternative — keep asserting findings built on guessed days — is what this round exists to
stop.

### Decayed edges are visible, and mislabelled

Superseded relationships do not vanish. `EvidenceEngine.recompute` reconciles edges it no longer
finds to `.decayed`, preserving their stored confidence, evidence counts and lag verbatim, and
`InsightsFeed.build` collects `.decayed` and `.userDismissed` into an **archive** section that
`InsightsView` renders under a disclosure labelled *"N dismissed insights"*. So this round will
produce a batch of archive rows the user never dismissed, still carrying their old claims and old
confidence numbers.

`.candidate`, by contrast, is rendered nowhere (`InsightsViewModel.swift:54` filters `.active`) —
which is why today's false triggers were never displayed, and why the current bug's real harm is
suppression rather than false claims on screen.

The archive labelling is a pre-existing defect this round triggers at scale. Correcting the label so
it does not claim the person dismissed these is **in scope**. Re-designing the archive, and deciding
whether stale confidence numbers should be shown there at all, is not.

### Reclassified findings will look new

`EdgeIdentity.edgeKey` embeds the relationship *type*, so an edge that changes classification is a
different key: the old row decays and a new one is inserted with `firstSeen = now`, which
`InsightsFeed` badges as **new**. Corrected findings can therefore arrive looking like fresh
discoveries. Recorded here so it is expected rather than alarming; a fix is a follow-up.

### Chronic users still get nothing from the engine this round

A condition present every day has no symptom-free days to compare against, so the occurrence
machinery can say nothing about it — correctly. Round 2's continuous estimand is what turns their
ratings into findings. Round 1 gives them tracking, a record, and the input Round 2 needs; it must
not imply more.

## Data model

- **A new table for ongoing conditions**, following the `experiments` precedent (schema migration,
  UUID key, uppercase-string UUID encoding to match the existing convention).
- **A new table for observed absences** — the "none today" assertions, keyed by day and outcome.
  Positive observations need no new storage: a rating or a symptom log already implies them.
- **Nothing further is stored for observability.** Positive observation is implied by data that
  already exists — the rating *is* the record — so the only new storage is the absence assertions
  above.
- `HealthEvent` already carries `endTimestamp`, unused by symptoms today; ongoing conditions do not
  need it in this round, because the condition record owns the lifecycle.
- Existing severity events are unchanged in shape: `.symptom`, subtype, `value` 1–10,
  `unit: "severity"` — so `OutcomeSource` continues to work untouched.

## Not touched

Named so they do not drift in:

- **The continuous estimand.** Severity differences, their thresholds, phrasing, and confidence
  treatment are Round 2. This round produces the data and says nothing new about it.
- **Episode resolution.** "Is it still going", next-day follow-ups, onset ranges for episodic
  symptoms, and the permanent-versus-resolved distinction for non-ongoing symptoms are Round 3.
- **Notifications.** The check-in is in-app on next open. A push follow-up needs a permission ask
  and belongs with Round 3, using the soft-ask-first pattern: describe the benefit in the app's own
  UI and only fire the system prompt on acceptance, because iOS grants exactly one.
- **The doctor report**, labs, weight, cholesterol, and any slow-moving outcome.
- **Accounts, sync, and practice integration.** On-device stays the default. The one forward-looking
  decision, taken when the report is built, is that it must be a structured document that is then
  rendered — never a PDF generated straight from the database — so the same extraction serves a
  later integration instead of being written twice.
- Thresholds, weights, the observational ceiling, lag windows, and the `ConfidenceScorer` formula.

## Known limitation, stated rather than hidden

This round records **outcome** observability. Exposure observability is not addressed: on a day
someone rated their psoriasis but logged no food, a food exposure is genuinely unknown, and this
round will treat it as absent. The bias is one-directional — unlogged exposures make exposure days
look rarer than they were — and it is smaller than the defect being fixed, because it applies only
within observed days rather than across a decade of them. Round 3 addresses it. It must not be
described as solved.

## Testing

Package-level for the engine, app-level for the check-in.

- The existing acceptance suite (`EvidenceEngineAcceptanceTests`) must pass **unedited** where its
  corpus is densely and manually logged, or be updated once with a recorded-observability fixture if
  the strict reading legitimately changes what it should assert. Which of those applies must be
  decided explicitly, not discovered.
- **Personas, under both capture models.** Every denominator test must run against a corpus where
  symptoms are only logged when the person was already engaged, *and* one where a symptom brings
  them to the app. The two models are what defeated every previous design, and a harness encoding
  only one of them would have caught neither failure.
- A pair with **no true effect** must never produce a verdict at any engagement level, in either
  capture model. This is the guard the previous design failed.
- A **real** effect must survive sparse logging — the mirror guard, against over-correcting into
  suppression.
- One imported HealthKit event dated years back must not change the graph **at all** — asserted at
  graph level (edge keys, types and statuses as a set), not on one hand-picked edge.
- Dismissing the check-in must leave the day unknown: no observed-absence row, no negative, no
  effect on any statistic.
- The drill-down's counts must equal the stored relationship's, on a fixture where the two paths
  *can* diverge — occurrences on unobserved days. A fixture without them passes against an unfixed
  engine.

**Mutants to demonstrate** (mutate, run, confirm the *named* test fails, restore, report both
directions):

1. Treat a dismissed check-in as "none today" → the dismissal test fails.
2. Use a global observed-day set instead of per-outcome → a fixture where one outcome is rated and
   another is not must fail.
3. Leave `StabilityValidator` on its old window → the stability test fails.
4. Leave `EvidenceContext` on the old window → the drill-down test fails.
5. Floor the denominator to 1 instead of returning `nil` → the no-comparison-days test fails.

## Follow-ups this round generates

- **Round 2:** the continuous estimand — within-person severity differences, their thresholds,
  phrasing that expresses "about a point and a half better" rather than a ratio, and wiring it to
  protocols so "did this peptide help" has an answer.
- **Round 3:** episodes and resolution — next-day follow-up, onset ranges, exposure-side
  observability, and push with the soft-ask-first permission flow.
- **Reclassified edges are badged new**, because `edgeKey` embeds the type. Pre-existing, becomes
  visible at scale here, and not fixed in this round. (The archive *label* is fixed here; what the
  archive shows is not.)
- **Chronic conditions need a flare concept.** Inside a permanently-open condition, every non-flare
  day is an observed negative, which makes chronic users the *best* case for the engine rather than
  the worst — but only once "worse than my normal" is derivable. The personal-percentile machinery
  from the weather round is the natural basis, and it should be derived from the daily rating rather
  than asked as a separate judgement call.
- **How many ongoing conditions one person can track** before the daily check-in becomes a chore.
  Unbounded is wrong; the right cap is unknown and should be set from real use.
