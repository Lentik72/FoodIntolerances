# Protocols & experiments — design

**Date:** 2026-08-25
**Status:** approved, pending implementation plan
**Scope:** declare an intervention, watch it for a window, and say what can honestly be said
about it afterwards. Medication-risk warnings and product identification are named
follow-up rounds, not part of this one.

---

## Why this exists

The evidence engine raises questions it cannot answer. A card reads "magnesium may reduce
your migraines — contested, thin evidence", and today that is a dead end: you read it and
move on. Nothing in the app lets you *test* it.

It is also the answer to a problem three rounds have now run into from different angles: the
engine is well built and starved. Outcomes come almost entirely from manual capture, a real
graph is ~20 manual events against ~38,000 imported ones, and nothing in the app yet makes
daily logging worth the effort. An experiment is a reason to log — a question the user
already cares about, with an end date and an answer at the end of it.

## What an experiment is

Four things fixed at creation:

- **the intervention** — an existing `HealthObject` (magnesium, ibuprofen, amoxicillin), the
  same object dose capture already writes against
- **the target outcome** — a symptom subtype, or mood
- **a window** — start and intended end
- **the shape** — *repeated* (as needed, or ongoing) or *course* (a fixed run)

**The shape is declared, never inferred.** Fourteen consecutive daily doses could be a
two-week antibiotic course or the start of a daily habit, and the events cannot distinguish
them. Guessing wrong is precisely how the antibiotic case ends up with a fabricated verdict.

**An experiment records nothing itself.** It is a lens over events logged through the normal
capture sheet. Adherence is computed by counting dose events for that object inside the
window — never a separate "did you take it" flag that could disagree with the Timeline.

**Storage:** its own GRDB table, not a `HealthObject` with `kind: .experiment`. An experiment
has state that changes over time (status, window, reminder settings, outcome), and putting
that in an object's `metadata` blob makes every query a JSON decode. `ObjectKind.experiment`
exists but was never wired up; leave it alone rather than half-use it.

## Lifecycle

**Starting.** Pick the intervention and outcome, set a window, optionally set a daily
reminder at a chosen time. **The notification permission request happens here** — at the
moment the user has asked to be reminded, one tap after stating the reason. The first-run
round removed the launch-time notification prompt precisely because asking before giving a
reason is the wrong pattern; asking at the point of value is the right one, and this is it.

**Running.** A card shows days elapsed, doses logged, outcome events so far. **Nothing is
claimed while it runs.**

**Slipping.** At the midpoint, if adherence is thin — say two logs by day ten of twenty-one
— the card asks directly: keep going, extend, or stop here. In-app, **not** a push
notification unless reminders were already opted into. An app that starts pushing alerts
nobody asked for because it is disappointed in the user is the wrong instinct.

**Ending.** At the window's end, or when stopped, the experiment freezes and produces its
output.

**Abandonment is the common case, not the edge case**, and it gets a real output rather than
silent expiry — see "Picture" below. Silent expiry teaches people the feature does not
matter.

**Reminders** are per-experiment, at a user-set time, cancelled when the experiment ends or
is abandoned. The experiment **records whether reminders were on**, because a reminded
regimen and an unreminded one are different evidence and the record should say which.

## What an experiment may claim

**The gate — and it must not be a second statistics implementation.** A verdict requires two
things: the *repeated* shape, and **the evidence engine having produced a result for that
exact pair that cleared its own gates**. The experiment asks the engine about
`intervention → outcome` and reports what comes back; it does not compute its own
significance, effect size or stability.

That matters beyond saving work. The engine's split-half stability gate is already what
rejects clumped exposures — a run of consecutive doses fails it — so "enough, and spread
rather than clumped" needs no new rule and no new threshold to drift out of sync with
`EvidenceConfig`. A parallel statistics path inside the experiments feature would be a
second opinion the app could contradict itself with.

A *course* never produces a verdict regardless of dose count: fourteen consecutive days
during one illness cannot be separated from recovering anyway. Thin adherence on a repeated
experiment likewise drops to a picture, because the engine will not have produced a result
to report.

**Why an experiment may speak more plainly than a mined card.** Not more data —
**pre-registration**. The engine mines every exposure against every outcome and needs strict
gates to control the fishing that implies. An experiment tests one pair, named before the
answer was visible. That is a genuine inferential improvement. It does not escape the
observational ceiling, but it earns plainer language.

**The four outputs:**

| Output | Example |
|---|---|
| **Helps** | "Magnesium appears to help. Migraines followed 4 of your last 22 magnesium days, against 11 of 22 without. This is your own observation, not a trial — it can't rule out that something else changed." |
| **No detectable effect** | "No detectable effect on your migraines across 24 doses over 11 weeks." |
| **Worsens** | The direction people forget. Analgesic overuse genuinely causes rebound headaches, so a pain-med experiment surfacing *worsens* may be the most valuable result this feature ever produces. |
| **Picture, no verdict** | "You took amoxicillin for 12 days. Here's what you logged before, during and after. A single course can't be evaluated — there's nothing to compare it against." |

**"No detectable effect" must never render as "it doesn't work."** Absence of a detectable
effect in one person's logs is not proof of absence, and the wording carries that or the
feature is lying.

**Prescriptions get harder framing.** When the intervention's kind is `.medication`, every
output carries the line that this is not a reason to change anything without talking to the
prescriber. A self-chosen supplement does not need it; a prescription does, because "no
detectable effect" on an antidepressant or a blood-pressure drug plus a quiet decision to
stop is a genuinely dangerous path.

**Side effects, surfaced as observations.** The engine already mines the intervention
against *every* outcome, so "what else followed this" is mostly presentation: *"On days you
took ibuprofen, stomach ache followed more often than usual."* Never *"ibuprofen is causing
your stomach aches"* — the same line the plausibility tiers already hold elsewhere.

**The refusal is printed, not implied.** Every medication result states that the app cannot
see kidney, liver or other organ-level effects, because they do not appear in symptom logs.
If the app stays quiet, a clean-looking result reads as a clean bill of health. Silence is
the dangerous option.

**Overlapping long-running intake is noted, not adjusted for.** If a background regimen
spans the window — three months of daily vitamin A while a magnesium experiment runs — the
result says so. Adjusting for it would be a statistical claim this data cannot support;
noting it is honest.

## Where it lives

No new tab. The bar is Home, Timeline, +, Insights, Health; a fifth alongside the capture
button is past what an iOS tab bar carries, and it would give permanent prime placement to
something used occasionally.

An experiment is three things depending on when you meet it:

- **Running → Home.** One compact card, only while something is running, carrying the
  midpoint nudge. It **yields to the poor-air banner**: a safety warning outranks a progress
  tracker. At most one experiment card, because Home already carries a greeting, mood
  check-in, passive strip, backfill card and banner.
- **Creating and browsing → Health tab**, replacing the "Protocols & experiments — Soon" row
  with the real thing.
- **Finished result → Insights**, beside the mined cards — but **visually and verbally
  distinct from them**. "We noticed this in your data" and "you tested this and here's what
  happened" are different epistemic acts, and the second is exactly what pre-registration
  earned. If they render identically, that distinction dies at the last step.

**Entry point that matters most:** a *Test this* action on an insight card, opening creation
with intervention and outcome pre-filled. That is the loop the whole feature exists to
close.

Not in v1: a prompt from dose capture ("you've logged this 12 times, want to track it?").
Good idea, distraction from getting the core right.

## Testing

Follows this codebase's established shapes rather than inventing one.

- **The claim ladder is pure presentation over a result type** (the `DataSourcesPresentation`
  / `InsightPhrasing` pattern), so every branch is unit-testable without a view:
  course-never-gets-a-verdict, thin-adherence-gets-a-picture, "no detectable effect" never
  rendering as "doesn't work", prescriptions always carrying the prescriber line, and the
  organ-harm limitation present on every medication result.
- **The lifecycle gets a workflow + view-state split**, like Connect and Backfill: an
  `ExperimentWorkflow` owning transitions with ordering pinned by recording doubles, and an
  `ExperimentViewState` owning screen state with a synchronous guard — starting an
  experiment twice from a double tap must create one.
- **Adherence and the verdict gate are pure functions over events**, testable against a
  seeded corpus. `StressDemoSeed` is the template for building one.

**Mutants to demonstrate:** a course producing a verdict; "no detectable effect" softened to
"doesn't work"; the prescriber line dropped from a medication result; reminders surviving an
abandoned experiment; the midpoint nudge firing on a healthy experiment.

## Out of scope, named so they do not drift in

- **Medication-risk warnings** — the curated catalog of known risks triggered by usage
  patterns (daily NSAIDs → kidney and GI risk; cumulative preformed vitamin A →
  accumulation). **The next round.** It is deliberately separate because that warning must
  fire for anyone logging daily ibuprofen, experiment or not — the person most at risk is
  the one quietly taking painkillers and tracking nothing, who would never see a warning
  that lived inside this feature.
- **Product identification** (RxNorm, photo of the label). The round after. It is safety
  infrastructure, not convenience: from a log reading "Vitamin A" the app cannot tell
  preformed retinol from beta-carotene, and warning someone off carrots is exactly the noise
  that trains people to ignore warnings.
- **Drug–drug interactions.** Clinically the biggest risk of all, and out of reach: it needs
  a maintained pharmacological database, not a hand-curated list, and a half-complete
  interaction checker is worse than none because absence reads as safety.
- **Comparing alternatives** ("should I try exercise instead?"). Requires either sequential
  trials or observational comparison across interventions, and edges into recommending
  treatment changes.
- Notification prompting outside an explicit per-experiment reminder opt-in.
- Any change to `EvidenceConfig`, the gates, or the observational ceiling.

## Follow-ups this round generates

- The two catalogs for the medication-risk round: **general** (substance → known risk +
  triggering usage pattern) and **personal modifiers** (recorded health conditions —
  especially kidney and liver — then age 65+, pregnancy, alcohol, body weight). Modifiers
  change *salience and framing*; they must **never** produce a computed personal dose limit.
  Height earns almost nothing and should not be leaned on.
- Two honesty limits for that round: logged totals **understate** reality, because
  acetaminophen and vitamin A hide inside combination products — so warnings say "at least
  this much", never an all-clear.
- Whether a dose-capture prompt should offer to start an experiment.
