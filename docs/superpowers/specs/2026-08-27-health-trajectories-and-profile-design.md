# Health trajectories and profile — design

**Date:** 2026-08-27 (rewritten same day after a five-lens audit)
**Status:** approved, pending implementation plan
**Scope:** Round 1b, sequenced first. Descriptive trends over device-recorded history, the
measurement-correctness fixes they depend on, and the profile that gives them context. No engine
changes, no symptom pairing, no causal claims.

Round 1a (daily check-in and recorded observability) follows this and is independent of it.

---

## What changed in this rewrite, and why

The first version of this spec justified itself with: *"It needs no observability assumption. The
device recorded these whether or not anyone opened the app."*

**That claim was false, and it was the load-bearing one.** The assumption was never about app
engagement. It is whether the decision to *measure* depends on the value being measured. For weight
and blood pressure the person decides each reading, and that decision is a function of how they
feel. That is informative missingness — the hardest case, not the absent one.

Simulated on the first spec's exact pipeline, over patients **whose true physiology never changed**:

| true value, flat all year | what changed | what the app would have said |
|---|---|---|
| weight 90.0 kg | weighed daily, then only when feeling light | **78% told "falling"** |
| systolic 138 mmHg | symptom-triggered → routine morning readings | **60% told "falling"** |
| sleep 7.0 h | bad nights unrecorded → nightly wear | **52% told "falling"** |

Constant selection bias moves the level, not the slope, and the pipeline survives it. What breaks
it is selection strength *changing across the window* — which is the normal case in a practice,
because starting a protocol changes measurement behaviour.

A second, independent flaw: **the statistical test used the wrong null.** Mann–Kendall assumes
independent observations. Weekly medians do not deliver that; they only shrink `z` by √(365/53).
Measured false-"trend" rates on series with no trend at all:

| daily dynamics | plain Mann–Kendall | with Hamed–Rao correction | power on a real 4 kg/yr change |
|---|---|---|---|
| mean-reverting (realistic weight) | 5.5% | **5.0%** | 100% → 100% |
| sticky | 23.0% | **7.5%** | 100% → 99% |
| near random-walk | 63.5% | **14.5%** | 73% → 30% |

Both flaws are fixed below. The rest of the first spec's method — weekly medians, Theil–Sen,
gaps-not-interpolated, absent-not-caveated, one shared multiplicity policy — survived the audit and
is unchanged.

**Product direction and the constraints this round inherits:** `docs/product-direction.md`.

## Why this round still goes first

Not "because it needs no assumptions" — that was wrong. The honest reasons:

**Its assumptions are about measurement, and measurement is observable.** When someone measured is
recorded in the data. That means the confound can be *detected and disclosed*, which is not true of
the symptom-observability problem Round 1a exists to solve.

**It gives the design partner's practice something on day one**, before any patient has rated a
symptom.

**It is independent of the evidence engine.** Nothing here reads or writes a `Relationship`.

## The three things a trajectory must survive

### 1. Measurement-density confounding

Every trajectory runs the same trend test on its own **weekly measurement count**. If the value
trends *and* the frequency of measurement trends, the two are confounded and **no direction may be
stated** — the surface shows the range and says the measurement pattern changed too much to read.

Validated on the scenarios above: it suppresses 97–100% of the artefacts while preserving 96% of a
genuine 6 kg loss.

This also settles how the series are treated. They divide into:

- **Passively recorded** — steps, sleep, resting heart rate, HRV, respiratory rate. Recorded by
  wearing a device, not by deciding to measure.
- **Self-initiated** — weight. The person chooses each reading.

The density guard applies to both, because a passively recorded series has the same problem when
someone starts or stops wearing a watch.

**Blood pressure is dropped from this round.** It is self-initiated, it is the case where the
failure was most dangerous in simulation (systolic "down 13 mmHg at p = 0.0008" from behaviour
alone, which a clinician could de-escalate on), and a daily median of arbitrary cuff readings is not
a clinical blood-pressure measure anyway — the standard is first-morning, seated, after five
minutes' rest, averaging the second and third readings. Doing it properly is its own design problem.

### 2. Serial dependence

The trend test uses the **Hamed–Rao variance correction**: inflate the Mann–Kendall variance by the
autocorrelation of the ranks. Where a series is well behaved this changes nothing and costs no
power; where it is persistent it prevents drift from being reported as direction.

Its residual limit is honest and must be stated in the plan rather than hidden: for a
near-random-walk series it still over-rejects (about 14%) *and* loses most of its power. For such a
series the truthful answer is that drift and trend cannot be separated, so the app says nothing.

### 3. Effect size

Significance is not enough — this project's own `EvidenceConfig` says so, in a comment explaining
why activation needs an effect floor as well as significance. With 52 weekly points, a 1 kg annual
change is statistically detectable and clinically meaningless; it is inside the disagreement between
two bathroom scales.

Every series therefore carries a **minimum meaningful change**, below which no direction is stated
regardless of p-value. And every stated change carries a **confidence interval** — the Sen interval,
derived from the Mann–Kendall variance already computed. A clinician shown "down 1.2 kg" with no
interval will discount the whole feature, correctly.

## Prerequisite correctness fixes

These are not trajectory features. They are defects in how the data is already handled, and a
trajectory built on top of them would be confidently wrong.

**Sleep is double-counted for multi-device users.** `SleepSessionBuilder.session(from:)` sums stage
durations (`totals[subtype] += duration`) without unioning overlapping intervals, and every
HealthKit-sourced event carries the same `.healthKit` rank, so `IngestPipeline` deliberately keeps
both. An Oura ring, Whoop, or Eight Sleep alongside an Apple Watch produces roughly double the true
sleep, with no clamp anywhere — nothing prevents a 14-hour night. Functional-medicine and peptide
patients are among the likeliest people to wear two sleep trackers, so this is the design partner's
exact population. Overlapping intervals must be unioned before totalling, and `asleepMinutes`
clamped to the session's own wall-clock span.

**No HealthKit provenance is captured.** `HKSource`, `HKSourceRevision`, `HKDevice` and
`bundleIdentifier` appear nowhere; `mapSample` keeps only value, timestamp, unit and timezone, and
every HealthKit row collapses to `EventSource.healthKit`. So a new watch that shifts the HRV
baseline, or a second scale reading 1.5 kg differently, is not merely unhandled — it is
*undetectable*, permanently, for data already ingested. This round captures the source identifier at
ingest. It is not used for anything yet; capturing it is what makes the problem solvable later
instead of never.

## What ships

**Series:** weight, sleep duration, steps, resting heart rate, HRV, respiratory rate. All already
ingested and canonicalised by `HealthKitSampleMapper`; this round adds no new sample types.

**Windows: 90 and 365 days, default 90.** The 30-day window is **dropped** — the first spec asked
for it while also requiring at least 8 weeks of data, and a 30-day window contains 5. It would have
been permanently empty. Fixed windows, never chosen by result.

**A chart, not only a sentence.** The first version specified a summary line and a coverage note.
That is not clinically usable: a step change at a protocol start and a steady decline render
identically, and no clinician will act on "down 1.2 kg over 365 days" without seeing the shape,
the gaps, and the outliers. `TrendMeasurement` already carries the weekly points, and the app
already uses Swift Charts in several places. Gaps are drawn as gaps — never interpolated, never
zero.

**Coverage** is stated with every trajectory and is part of the result, not a footnote.

**The profile** supplies context: date of birth as the source of truth with age derived, biological
sex, height. Read from HealthKit characteristics where permitted, asked otherwise.

**Critically — `currentAge` must fall back to the stored `age` when date of birth is absent.**
`profile.age` today drives `HealthMonitoringService`'s age-thresholded screening recommendations
(cholesterol at 40+, blood sugar at 45+), and `dateOfBirth` is *never populated by any UI*. Deriving
age purely from DOB would return nil for every existing user and silently switch that safety surface
off. The first version of this spec would have shipped that.

**Demographics are for interpretation only.** BMI needs height; a 5 kg change means something
different at 55 kg than at 120 kg. They must not normalise symptom severity or exposure thresholds —
comparing someone to their own history beats any population norm.

**No category names.** The first version proposed age-banded blood-pressure categories. Assigning a
blood-pressure category is hypertension staging — a disease classification, and the clearest
device-claim risk in either document. Cut. BMI categories are the same shape, milder; also cut.

## Safety and framing

Descriptive trends over a person's own recorded data, user-pulled, no alerts, no interpretation, sit
within FDA General Wellness guidance — Apple's own Health app does exactly this. Two things are
needed to stay there:

**An app-level non-diagnostic line.** Today the only "informational purposes only" text is buried in
`ProtocolPreviewView` and one Dashboard line. There is nothing global. For App Store review and for
a clinic deployment, this needs to be persistent and plain.

**Language discipline.** No "abnormal", "high", "low", "risk", "should". No category names. No
notifications. Say what the number did, over what period, from how many readings, and stop.

**Patient alarm is a real risk this round must address.** Rising resting heart rate and falling HRV
are precisely the two metrics people have been trained to read as impending doom. The banning of
causal words stops the *app* asserting a cause; it does nothing about the patient supplying one. The
minimum treatment: state the typical range of normal variation alongside the change, enforce the
effect-size floor so trivial changes never surface at all, and — for the practice — an explicit
"discuss this with your clinician" rather than silence.

## Not touched

- The evidence engine, relationships, Insights, and the denominator work.
- Any pairing of a trajectory with a symptom, mood, exposure or protocol.
- The doctor report, labs, and anything transmitted off device. The one forward-looking constraint:
  a trajectory is a **structured value** that a renderer consumes, never a formatted string, so the
  report round renders the same values rather than recomputing them.
- Dietary macro trends — present only for people who log food into Apple Health, and a partial
  dietary record misleads more than none.
- Goals and targets.
- Blood pressure (above).
- *Using* the captured HealthKit source. This round stores it; acting on it is later.

## Correction to the first version's motivation

The first spec claimed "years of device-recorded data reaching back to 2016". `HealthKitIngestor`
backfills `years: Int = 1`. Older data exists only if the user imported an Apple Health export file.

This matters beyond accuracy: the first spec's stated seasonality mitigation was that *"the 365-day
window exists precisely so a season-length change can be read against a longer one."* With one year
of history, 365 days **is** the longest window, so that mitigation is unavailable. Seasonality
remains a live confounder for weight and steps — the two series most affected — and must be
disclosed rather than mitigated.

## Testing

- **A flat series is never given a direction**, at every persistence level from mean-reverting to
  near-random-walk, and under measurement patterns that change across the window. This is the
  primary guard and the one the first version failed.
- **A real change is still detected** — the mirror guard, so the fixes do not over-correct into
  uselessness.
- **The density guard suppresses the behaviour-driven artefacts** and preserves a genuine change.
- **Hamed–Rao is load-bearing**: pinned by a persistent series where the plain variance would report
  a trend and the corrected one does not.
- **Weekly bucketing is load-bearing** — but note the first version's test for this asserted
  something false. A random walk *is* reported as a trend by weekly-bucketed Mann–Kendall about 79%
  of the time; the honest test pins the per-week versus per-day rate, not an absence of trend.
- **The effect-size floor** blocks a statistically significant but clinically trivial change.
- **Sleep sessions union overlapping segments** and never exceed their own wall-clock span.
- **Coverage below the floor yields no trajectory**, asserted alongside a series that survives, so
  the test cannot pass over an empty result.
- **One database read** regardless of series count — guarded by call count, following the precedent
  set when the Insights N+1 was fixed.
- **No causal language**, swept across every series, direction and unit system, with a non-empty
  assertion so an empty string cannot pass.

## Follow-ups this round generates

- **Round 1a** — the daily check-in and recorded observability.
- **Round 2** — the continuous estimand, which lets a trajectory be *paired* with a condition.
- **Blood pressure**, done properly: a guided measurement protocol rather than a median of whatever
  was recorded.
- **Using the captured source identifier** — flagging a baseline shift when the recording device
  changes, rather than reporting it as a trend.
- **Sleep quality beyond duration** — efficiency, timing regularity, overnight HRV. A clinician
  would rate duration the least interesting of these, and timing variability is derivable from data
  already held.
- **Seasonal decomposition**, once more than a year of history exists.
- **The doctor report**, rendering these same structured values.
