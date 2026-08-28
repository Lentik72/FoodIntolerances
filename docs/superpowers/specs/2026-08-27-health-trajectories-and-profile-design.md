# Health trajectories and profile — design

**Date:** 2026-08-27 (rewritten same day after a five-lens audit; revised 2026-08-28 after the
trends-verdict decision)
**Status:** approved — Option A; pending implementation plan revision
**Scope:** Round 1b, sequenced first. Descriptive trajectories over device-recorded history —
a chart, coverage, and range, with **no stated direction** — the measurement-correctness fixes
they depend on, and the profile that gives them context. No engine changes, no symptom pairing,
no causal claims, no directional claims.

Round 1a (daily check-in and recorded observability) follows this and is independent of it.

---

## What changed in this revision, and why

The 2026-08-27 version of this spec shipped a **directional verdict** per series (Mann–Kendall
with a Hamed–Rao correction, Theil–Sen slope with a Sen interval, a measurement-density guard, an
effect-size floor, one Benjamini–Hochberg correction). A second adversarial audit round found
that design substantively wrong, and the decision recorded in
`docs/OPEN-QUESTION-trends-verdict.md` resolved it: **the verdict is cut from this round.**

The short form of the reasoning, so this document stands alone:

- Weight is self-initiated, and the decision to measure depends on the value being measured.
  Selection lives in *which* days a person steps on the scale; any frequency-based guard sees
  only *how many*. Each guard fix was defeated by the next persona — the last being a patient who
  starts a protocol, weighs more often, and skips the scale after bad days: recorded weight falls
  on flat physiology and the fixed guard certifies it clean. That is an identifiability failure,
  not a bug, and no amount of real user data supplies the counterfactual.
- Every audit finding across three passes attacked the verdict machinery. The chart, the weekly
  medians, and the coverage reporting were never touched, and a clinician review had already
  concluded the chart carries the clinical value.
- Apple Health already ships trend arrows — the verdict is the commodity feature. Gaps drawn as
  gaps, "based on 284 of 364 days", and later pairing with symptoms and protocols (Round 2) are
  the differentiated parts.

A restricted direction layer for **device-recorded** series (whose confounder — wear — is
observable in the data) remains a possible future round; its requirements are in Follow-ups.
Nothing in this round may state, imply, or visually assert a direction.

Everything else the audit left standing survives: weekly medians, per-day medians first, gaps
never interpolated, the prerequisite correctness fixes, and the profile with its safety fallback.

**Product direction and the constraints this round inherits:** `docs/product-direction.md`.

## Why this round still goes first

- **It gives the design partner's practice something on day one**, before any patient has rated a
  symptom.
- **It is independent of the evidence engine.** Nothing here reads or writes a `Relationship`.
- **It makes no inferential claim at all**, so the hardest open problems (observability,
  denominators, selection) do not gate it.

## What ships

**Series:** weight, sleep duration, steps, resting heart rate, HRV, respiratory rate. All already
ingested and canonicalised by `HealthKitSampleMapper`; this round adds no new sample types.

**Blood pressure stays out.** It is self-initiated, it was the most dangerous case in simulation,
and a daily median of arbitrary cuff readings is not a clinical blood-pressure measure — the
standard is first-morning, seated, after five minutes' rest, averaging the second and third
readings. Doing it properly is its own design problem.

**The chart is the feature.** Weekly medians drawn over the window, gaps drawn as gaps — never
interpolated, never zero — with the coverage denominator stated ("based on 284 of 364 days") and
the observed range of weekly medians. A step change at a protocol start and a steady decline are
visually distinct here; no sentence can carry that, which is exactly why the sentence was the
wrong product.

**Windows: the last 13 or 52 calendar weeks, default 13.** Whole calendar weeks in the user's
calendar (respecting `firstWeekday`), ending with the week containing today, which may be
partial and is rendered as such:

- Calendar anchoring makes bucket membership stable: the same reading lands in the same week no
  matter which day the analysis runs — the property the previous version claimed and inverted.
- Whole weeks kill the previous version's stub bucket (365 = 52×7+1 left a one-day "weekly
  median" at the end of every year view).
- All date arithmetic uses calendar operations (`date(byAdding:)`, `dateInterval(of:)`), never
  86 400-second math — the previous convention silently produced a 91-day "90-day window" in any
  DST timezone.

**Chartable is not gated.** Any series with data in the window draws its chart with its coverage
stated. The previous coverage floors existed to gate a verdict; there is no verdict. A user with
six weeks of weight data sees six weeks of weight data.

**Values, not strings.** A trajectory snapshot (weekly points, coverage, range) is a structured
value that presentation renders — the doctor-report round consumes the same values rather than
recomputing them.

**The profile** supplies context: date of birth as the source of truth with age derived,
biological sex, height. Read from HealthKit characteristics where permitted; **asked otherwise** —
this round adds a date-of-birth field to the existing profile UI, which today never populates
`dateOfBirth` at all.

**Critically — `currentAge` must fall back to the stored `age` when date of birth is absent.**
`profile.age` today drives `HealthMonitoringService`'s age-thresholded screening recommendations
(cholesterol at 40+, blood sugar at 45+), and `dateOfBirth` is never populated by any UI. Deriving
age purely from DOB would return nil for every existing user and silently switch that safety
surface off.

**Demographics are for interpretation only.** They must not normalise symptom severity or
exposure thresholds — comparing someone to their own history beats any population norm.

**No category names.** Assigning a blood-pressure or BMI category is disease classification. Cut,
as before.

## Prerequisite correctness fixes

These are not trajectory features. They are defects in how the data is already handled, and a
chart built on top of them would be confidently wrong.

**Sleep is double-counted for multi-device users.** `SleepSessionBuilder.session(from:)` sums
stage durations without unioning overlapping intervals, and every HealthKit-sourced event carries
the same `.healthKit` rank, so `IngestPipeline` deliberately keeps both. An Oura ring, Whoop, or
Eight Sleep alongside an Apple Watch produces roughly double the true sleep, with no clamp
anywhere. Functional-medicine and peptide patients are among the likeliest people to wear two
sleep trackers. Overlapping intervals must be unioned before totalling, and `asleepMinutes`
clamped to the session's own wall-clock span.

**No HealthKit provenance is captured.** `HKSource`, `HKSourceRevision`, `HKDevice` and
`bundleIdentifier` appear nowhere; every HealthKit row collapses to `EventSource.healthKit`. A new
watch that shifts the HRV baseline, or a second scale reading 1.5 kg differently, is
*undetectable*, permanently, for data already ingested. This round captures the source identifier
at ingest. It is not used for anything yet; capturing it is what makes the problem solvable later
instead of never. (Anchored queries mean history already ingested stays nil forever — a later
round consuming this must expect that.)

*Boundary learned in implementation (2026-08-28):* HRV and respiratory rate ingest as day-level
statistics aggregates, which have no single source — so those two series carry **no** source
identifier at all, not merely nil history. The capture covers the per-sample paths (weight,
resting heart rate, workouts, category samples). Making the original HRV example detectable
requires switching those types to per-sample anchored queries — its own round, with its own
data-volume trade-offs.

## Language and framing

**No directions, stated or implied.** Beyond the standing causal-language ban ("because",
"caused", "led to", "due to", "linked to", "resulted in"), this round bans directional language in
every trajectory summary: no "trend", "rising", "falling", "increasing", "decreasing",
"improving", "worsening", "declining", no arrow glyphs. Say what was recorded, over what period,
from how many days, and stop: *"Weekly medians 72–78 kg · based on 284 of 364 days."*

**An app-level non-diagnostic line, finally global.** Today the only "informational purposes
only" text is buried in `ProtocolPreviewView` and one Dashboard line. This round introduces one
shared component and places it on the three surfaces that present health readings or findings —
Trends, Insights, Experiments — persistent and plain, with "discuss this with your clinician"
framing for the practice deployment.

**Patient alarm.** Rising resting heart rate and falling HRV are the two charts people have been
trained to read as impending doom. This round's mitigation is structural: the app asserts nothing,
so there is no claim to over-read — plus the non-diagnostic line and clinician framing. The
"typical range of normal variation" copy from the previous version existed to contextualise a
*stated change*; with no stated change it is cut rather than shipped as unsourced clinical
content. If the future verdict layer states changes, it must solve that properly, with sourced
per-series figures.

**Seasonality** likewise attached to directional claims (a season-length drift read as a trend).
With no direction stated, the chart shows what happened and the disclosure moves to the verdict
layer's requirements.

## Not touched

- The evidence engine, relationships, Insights, and the denominator work.
- Any pairing of a trajectory with a symptom, mood, exposure or protocol.
- **Any trend statistic**: no Mann–Kendall, no Hamed–Rao, no Theil–Sen, no density guard, no
  effect floors, no multiplicity correction, no fitted or smoothed line on the chart — a slope
  band is a verdict in visual form.
- The doctor report, labs, and anything transmitted off device (the snapshot-as-value constraint
  is the one forward-looking commitment).
- Dietary macro trends, goals and targets, blood pressure (above).
- *Using* the captured HealthKit source. This round stores it; acting on it is later.

## Correction retained from the first rewrite

The original spec claimed "years of device-recorded data reaching back to 2016".
`HealthKitIngestor` backfills one year. Older data exists only if the user imported an Apple
Health export file. The 52-week window is therefore the longest honest view.

## Testing

- **Weekly bucketing is calendar-anchored and DST-safe**: the same reading lands in the same week
  when analysed on different days, and a spring-forward week in a DST timezone buckets correctly.
  Fixtures must include a non-UTC, DST-observing timezone — the previous version's UTC-midnight
  fixtures could not catch its own window bug.
- **A week's value is its median, and per-day medians come first** — three weigh-ins on Monday do
  not out-vote the other six days.
- **Empty weeks are absent, never zero** — a gap must not render as a crash to the floor.
- **Coverage counts days, not readings**, and its denominator ends at today, not the end of a
  partial week.
- **Sleep sessions union overlapping segments** and never exceed their own wall-clock span; sleep
  is attributed to the waking day; a night spanning the window boundary is not truncated.
- **A series reads only its own subtype** — resting heart rate must not average exercise peaks.
- **The corpus is read once per category** regardless of series count — call-count guarded,
  following the Insights N+1 precedent.
- **No causal and no directional language**, swept across every series and unit system, with
  non-empty assertions so an empty string cannot pass.
- **Profile age derivation** across boundary birthdays, with the stored-age fallback proven by a
  test that would fail if age-gated screening silently switched off.

## Follow-ups this round generates

- **Round 1a** — the daily check-in and recorded observability.
- **Round 2** — the continuous estimand, which lets a trajectory be *paired* with a condition.
- **The direction layer for device-recorded series**, if it earns its way in: guarded on wear
  directly (the observable confounder), 52-week windows only, eligibility earned by a dense and
  stable record, honest per-series false-trend figures, and a **committed simulation harness** —
  the personas that falsified two designs become executable regression tests before any verdict
  ships. Weight states a direction only ever under a near-daily stable-record gate, possibly
  never.
- **Blood pressure, done properly**: a guided measurement protocol rather than a median of
  whatever was recorded.
- **Using the captured source identifier** — annotating a baseline shift when the recording
  device changes, rather than leaving it to be misread.
- **Sleep quality beyond duration** — efficiency, timing regularity, overnight HRV.
- **The doctor report**, rendering these same structured values.
