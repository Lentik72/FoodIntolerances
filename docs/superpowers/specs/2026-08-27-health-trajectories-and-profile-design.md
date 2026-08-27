# Health trajectories and profile — design

**Date:** 2026-08-27
**Status:** approved, pending implementation plan
**Scope:** Round 1b, sequenced **first**. Descriptive trajectories over device-recorded history, and
the profile that gives them context. No engine changes, no symptom pairing, no causal claims.

Round 1a (daily check-in and recorded observability) follows this and is independent of it.

---

## Why this round exists, and why it goes first

The app has years of device-recorded data and shows the user almost nothing from it. A real device
carries tens of thousands of HealthKit events reaching back to 2016 — weight, steps, resting heart
rate, HRV, respiratory rate, blood pressure, sleep — all already ingested and canonicalised by
`HealthKitSampleMapper`, and all sitting unused outside the evidence engine.

Three reasons this is the right thing to ship first:

**It needs no observability assumption.** The device recorded these whether or not anyone opened the
app. A day with a weight sample is a day we know the weight. That is the property the whole
denominator problem lacks, and it is why this round can be honest without waiting for anything.

**It gives the design partner's practice something on day one.** "Average sleep fell from 7.1 to 6.2
hours over the last year, based on 284 of 365 days" is clinically useful, immediately, before a
single symptom has been rated. A practice cannot adopt an app that has nothing to show until its
patients have logged for three months.

**It is independent.** No engine changes, no new statistical machinery in `HealthGraphCore`'s
evidence path, nothing that can regress an existing finding.

## What a trajectory is — and is not

**It is:** the direction and magnitude of one device-recorded series over a fixed window, stated in
the series' own units, with the data coverage it rests on.

**It is not** a relationship, a cause, or a claim about symptoms. Nothing here pairs a series with an
outcome; that is Round 2's job and it needs the check-in data from Round 1a. The word "because" must
not appear on this surface.

The distinction matters beyond wording. A trajectory needs no assumption about unobserved days, so
it can be stated plainly and confidently. The moment a surface implies "your sleep got worse *and
that is why* your psoriasis flared", it inherits every problem this project has spent a month
untangling.

## The series covered

Taken from what `HealthKitSampleMapper` already ingests, so this round adds no ingestion work:

| series | category / subtype | unit | notes |
|---|---|---|---|
| Weight | `.bodyMetric` / `weight` | kg | rendered per the user's Imperial/Metric preference |
| Sleep duration | sleep sessions | hours | nightly asleep total via the existing session builder |
| Steps | `.exercise` / `steps` | count | already daily-aggregated on ingest |
| Resting heart rate | `.vitals` / `restingHeartRate` | bpm | |
| HRV | `.vitals` / `hrv` | ms | |
| Respiratory rate | `.vitals` / `respiratoryRate` | breaths/min | |
| Blood pressure | `.vitals` / `bloodPressureSystolic`, `…Diastolic` | mmHg | shown as a pair, never averaged together |

Dietary macros are ingested too but are deliberately **out of scope** — they are only present for
people who log food into Apple Health, and a partial dietary record is more misleading than none.

A series with insufficient coverage is not shown at all, rather than shown with a caveat. An absent
row invites "connect this"; a present row with a warning invites reading the number anyway.

## How a trend is computed

This is the part that has to be right, because a trend that is really noise is the same class of
error as a relationship that is really noise — and this app has just spent a month on that.

**Aggregate before testing.** Daily values are strongly autocorrelated — today's weight is nearly
yesterday's — and every standard trend test assumes independence, so run on raw daily values they
report significance that is not there. Aggregate to **weekly medians** first: it breaks most of the
autocorrelation, resists outliers (one bad cuff reading, one day on a different scale), and matches
how people actually think about these numbers.

**Direction from Mann–Kendall, magnitude from Theil–Sen.** Mann–Kendall is a non-parametric test for
monotonic trend that assumes nothing about distribution; Theil–Sen is the median of pairwise slopes,
which tolerates outliers that would swing a least-squares fit. They are the standard pairing for
exactly this problem, and their non-parametric nature matters here because none of these series are
normally distributed.

**State no direction unless the test supports one.** If Mann–Kendall does not reach significance, the
surface says "no clear change" and shows the range. It does not show a slope with a shrug. Several
series are tested at once, so apply the same Benjamini–Hochberg correction the evidence engine
already uses (`SignificanceTester.benjaminiHochbergThreshold`) at the same `EvidenceConfig.fdrAlpha`,
rather than inventing a second multiplicity policy with a second threshold to keep in step.

**Fixed windows, never the best-looking one.** 30, 90 and 365 days, with 90 as the default. The app
must never scan windows and present whichever is most dramatic — that is p-hacking with a friendly
face, and it is exactly the failure mode that makes a health app untrustworthy.

**Coverage is part of the result, not a footnote.** Every trajectory states the days it rests on
("based on 284 of 365 days"). Coverage is *reported* in days, because that is how people think about
it, but the *floor* is defined in weeks, because weeks are the unit being tested: a window qualifies
only when at least **60% of its weeks carry at least one reading**, and at least **8 weeks** are
present at all. Below either, the series is not shown. Those two numbers are the round's only
invented constants and should be revisited against real devices; everything else here is either
derived from the data or reused from the engine.

Gaps are gaps: a stretch when the watch was not worn is missing data, never a flat line, and never
interpolated across.

**Seasonality is named, not modelled.** Weight and activity have annual cycles, so a 90-day window
can show a real seasonal swing as a trend. Modelling that properly needs years of data per person
and is out of scope; the honest treatment is that the 365-day window exists precisely so a
season-length change can be read against a longer one.

## Profile

Everything needed already exists on `UserProfile` — `dateOfBirth`, `age`, `gender`, `heightCm`,
`weightKg`, `activityLevel`, `smokingStatus`, `alcoholConsumption`, `targetSleepHours` — but the
HealthOS first run never collects any of it, and the model has two defects worth fixing while it is
being brought into use.

**Date of birth is the source of truth; age is derived.** Both are stored today, which guarantees
drift: a stored `age` is correct the day it is entered and wrong every day after. Age becomes
computed.

**The profile stops holding a current weight.** Weight is a time series and already arrives as
`.bodyMetric` events with a working unit formatter. A `weightKg` field plus a
`bodyMeasurementsUpdated` stamp is a snapshot that will disagree with the series, and two answers to
"what do I weigh" is worse than one. The field is retired for reads; the series is the answer.

**Read from Apple Health before asking.** HealthKit supplies date of birth and biological sex as
characteristics, and height as a sample. Ask only for what it cannot supply or the person declines
to share.

**Reachable from `HealthGraphCore`.** The profile is SwiftData while the graph is GRDB, so the
package cannot see it. Personalised medication risk — the vitamin A accumulation and daily-ibuprofen
cases — needs age, weight and sex inside the package. Settle that boundary in this round rather than
after two more rounds build across the split.

**What demographics may and may not do.** They belong in *interpretation*: BMI needs height, blood
pressure categories are age-banded, five kilograms means something different at 55 kg than at 120 kg.
They must **not** normalise symptom severity or exposure thresholds. The app's personal-percentile
approach — comparing someone to their own history — is stronger than any population norm, and
replacing it with age-banded cutoffs would be a downgrade dressed as sophistication.

## Where it appears

A trajectories surface in the Health tab, where "Health confidence" and "Doctor report" already sit
as coming-soon rows. This is also, not incidentally, the content the doctor report will carry — so
the structured result must be a value that a renderer consumes, never a string assembled for display.
When the report round arrives, it renders the same values rather than recomputing them.

Units and locale reuse the existing `UnitSystem` / `TemperatureUnit` machinery and the global
measurement-system preference. No new unit handling.

## Privacy

On-device by default, as everywhere else. Trajectories are computed locally from data already on the
device; nothing is transmitted. Sharing with a practice is a later round, is always an action the
patient takes, and will require explicit consent because HealthKit-derived data carries
redistribution restrictions under Apple's rules.

## Not touched

- The evidence engine, relationships, Insights, and the denominator work. Nothing in this round
  reads or writes a `Relationship`.
- Any pairing of a trajectory with a symptom, mood, exposure or protocol.
- The doctor report itself, labs, and anything transmitted off device.
- Dietary macro trends.
- Goal-setting — "I want to lose 5 kg". A target changes a trajectory into a progress bar and brings
  its own design questions.

## Testing

Package-level for the statistics, app-level for the surface.

- **A flat series with noise reports "no clear change."** The primary guard. Generate a series with
  no true trend at several noise levels and assert no direction is claimed. This is the trajectory
  equivalent of the null-pair test that caught two bad denominator designs.
- **A known slope is recovered** within tolerance by Theil–Sen, including with 10% outliers injected
  — the case that would break least squares.
- **Autocorrelation does not manufacture significance.** Generate a random walk, which has no
  monotonic trend but is strongly autocorrelated, and assert the weekly-median path does not report
  one. Run the same series without weekly aggregation to show the aggregation is load-bearing.
- **Gaps are gaps.** A series with a two-month hole reports reduced coverage and does not interpolate
  across it.
- **Coverage below the floor yields no trajectory**, not a low-confidence one.
- **Unit rendering** follows the measurement-system preference, reusing the existing formatter tests
  as precedent.

**Mutants to demonstrate** (mutate, run, confirm the *named* test fails, restore, report both
directions):

1. Test daily values instead of weekly medians → the random-walk test fails.
2. Drop the Mann–Kendall gate and always report the Theil–Sen slope → the flat-series test fails.
3. Skip the Benjamini–Hochberg correction across series → the flat-series test fails when several
   flat series are tested together.
4. Interpolate across gaps → the gap test fails.
5. Pick the window with the largest slope instead of a fixed one → a fixture with a real short-window
   swing inside a flat year must fail.

## Follow-ups this round generates

- **Round 1a** — the daily check-in and recorded observability, which this round does not depend on.
- **Round 2** — the continuous estimand, which is what lets a trajectory be paired with a condition
  ("your flares track your short-sleep weeks") instead of merely displayed.
- **The doctor report**, rendering these same structured values, plus the reported history a patient
  gives ("about three years").
- **Goals and targets**, which turn a trajectory into progress and need their own design.
- **Seasonal decomposition**, once enough per-person history exists to estimate it.
- **Whether a trajectory should ever be surfaced proactively** — a decline worth noticing is useful,
  and also the kind of thing that alarms people. Nothing in this round pushes; everything is pulled.
