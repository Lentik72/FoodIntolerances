# First run, Apple Health connect, and evidence-input correctness — design

**Status:** in review — six reconciliation items applied 2026-07-26, awaiting sign-off
**Date:** 2026-07-26
**Queue position:** first round after the "harden before expanding" round closed (PR #8, merge `8b1ab8d`).
**Supersedes:** `2026-07-04-ui-design.md` §5 promise copy (see §13).
**Amends:** `2026-07-03-health-graph-design.md` §7.3 confounder claim (see §13).

## Problem

The app works well in Xcode and cannot be used by anyone else.

`HealthKitIngestor.requestAuthorization()` and `backfill()` have exactly one call site
each, both inside `Views/HealthGraphDebugView.swift`, whose line 1 is `#if DEBUG`;
`SwiftDataMigrator.run` is reached only from that same file and from tests. So a Release
install can never acquire health data. It is
worse than a missing button: `startObserving()` (called at `FoodIntolerancesApp.swift:139`)
guards on `UserDefaults.bool(forKey: backfillCompletedKey)` (`HealthKitIngestor.swift:195-196`),
and only `backfill()` ever sets that flag. Live observation therefore early-returns on
every Release launch, permanently. There is no onboarding of any kind — no first-run gate
exists anywhere in `Views/HealthOS/`.

Three shipped strings actively contradict reality:

- `HomeView.swift:146-156` — "Capture and insights arrive in the next updates."
- `InsightsPlaceholderView.swift:18,36` — "The engine isn't watching yet" / "When the
  evidence engine arrives…", used as the live Insights empty state.
- `TimelineView.swift:213-215` — tells the user to "Connect Apple Health from the Health
  tab", a control that does not exist in Release.

Separately, three verified defects mean the evidence engine mines the wrong inputs:

1. **Meditation is mined as stress.** `HighStressExposureSource` gates on
   `category == .stress && value >= config.highStressThreshold` with no subtype or unit
   guard (`DerivedEventExposureSources.swift:9`), and `highStressThreshold = 7` is
   documented as "on 1–10" (`EvidenceConfig.swift:18`). The only real-data producer of
   `.stress` is HealthKit Mindful Sessions, written with `value` = duration in minutes
   (`HealthKitSampleMapper.swift:266-281`). Every mindful session of 7+ minutes is mined
   as a high-stress exposure, with inverted semantics.
2. **Cycle phase never fires on real data.** `CyclePhaseExposureSource.swift:17` filters
   `subtype == "periodStart"`; real ingestion writes `subtype: "menstrualFlow"`
   (`HealthKitSampleMapper.swift:284-308`). Only `SyntheticDataGenerator` writes
   `"periodStart"`, so every cycle insight ever shown came from synthetic data.
3. **The illness confounder is permanently empty.** `EvidenceEngine` treats illness days
   as an always-on confounder (`:55-58,74,92,204-205`), and nothing outside
   `EvidenceEngineAcceptanceTests.swift:90` ever writes an `.illness` event. `SymptomCatalog`
   cannot express being sick either — it contains only "Cough".

`2026-07-03-health-graph-design.md` §7.3 states that cycle phase and illness are *always*
in the confounder set. On real data neither is.

## Goals

1. A Release build can connect Apple Health, import a year of history, and keep ingesting.
2. First run explains what the app does and what it shares, honestly, before asking for
   anything.
3. Nothing in the shipped UI claims a capability that does not exist.
4. The three evidence-input defects are fixed with positive, testable semantics.
5. Existing installs with a populated graph are never onboarded and never re-backfilled.

## Decisions (binding)

1. **The first-run gate is a structural root switch, not a cover.** `FirstRunFlowView`
   *or* `HealthOSRootView`, chosen before either mounts.
2. **All launch side effects live inside the completed branch.** `startObserving()`,
   initial emission, scene-active emission and location-recovery emission are attached to
   the `HealthOSRootView` branch, never as common modifiers on the switch. The UI switch
   alone does not guarantee ordering.
3. **Onboarding writes no health events.** Symptom seeding persists a validated key list;
   it never fabricates data.
4. **HealthKit read authorization is not reliably knowable.** Apple deliberately obscures
   read denial. No Connected/Denied vocabulary anywhere.
5. **Exposure sources use positive semantic contracts, not absence.** A subtype allowlist
   with a value-range check, never a denylist.
6. **Authoritative metadata beats inference.** HealthKit's cycle-start marker is primary;
   run detection is a fallback for records that lack it.
7. **The round ships honest dormancy where a producer is missing.** If nothing produces a
   real stress rating, `highStress` is dormant and the spec says so out loud.

## Design

### 1. Root switch and launch ordering

`FoodIntolerancesApp.swift:109` currently mounts `HealthOSRootView()` unconditionally.
That view keeps all four tabs mounted simultaneously by design
(`HealthOSRootView.swift:36-44`), so a `fullScreenCover` would mount the whole shell
underneath onboarding: `HomeView` would subscribe to `EnvironmentalDataService` and load a
`HomeViewModel` against an empty graph, and `.task { emitCoordinator.emit }` would begin
fetching weather and requesting location.

The root becomes a switch on resolved first-run state. One structural rebuild when
onboarding completes; nothing mounts early. This buys three things:

- The graph is populated before `HomeView` first renders, so the existing first-week
  backfill summary card (`HomeViewModel.swift:57-77`) is correct on the first frame.
- Permission prompts gain context. `NotificationManager.shared.requestNotificationPermission()`
  (`FoodIntolerancesApp.swift:32`) is **removed** — `Views/HealthOS/` and `HealthGraphCore/`
  schedule zero notifications, so it asks for something the app never uses. Location moves
  behind an explaining screen (§3.5).
- `startObserving()` runs after backfill, which is what its own `backfillCompletedKey`
  guard already assumes. It has **three** call sites by design — the onboarding flow after
  backfill (§3.3), the shell branch's `.task` (covering later launches), and the
  `DataSourcesView` import action (§5). This is safe: the method is documented idempotent
  per process, re-calling replaces the query list (`HealthKitIngestor.swift:193-198`).

### 2. First-run state, reconciliation, and DEBUG resets

Four UserDefaults keys, no new table:

| Key | Meaning |
|---|---|
| `hg.firstRun.startedVersion` (Int) | 0 = never begun. Set **before** onboarding performs any work. |
| `hg.firstRun.completedVersion` (Int) | 0 = never finished. Versioned so a later round can add a step. |
| `hg.firstRun.symptomSeeds` ([String]) | Validated canonical keys from §3.4. Never written to the graph. |
| `hg.firstRun.forceShow` (Bool, DEBUG only) | Bypasses reconciliation until the flow finishes. |

**Why `startedVersion` exists — an interrupted onboarding must not skip itself forever.**
Backfill inserts events *during* the flow, before completion. Without an in-progress
marker, a termination after the first insert leaves `completedVersion == 0` **and** a graph
containing events — which is exactly the legacy-reconciliation predicate. The next launch
would mark onboarding complete and mount the shell, permanently skipping symptom selection
and location. The user would never see them again, and nothing would look wrong.

State transitions:

- `startedVersion` is written before authorization or backfill begins.
- `startedVersion > 0 && completedVersion == 0` → resume or restart the flow. Never
  reconcile.
- Completion writes `completedVersion`, then clears the in-progress marker.
- DEBUG *reset first run* clears the marker along with the other keys.

`completedVersion` enables version-aware **routing** only. It does not by itself confer
step-skipping: the flow carries an explicit prior-version → required-screens map, and any
future round that adds a screen must extend that map.

**Legacy reconciliation** runs only when `completedVersion == 0`, **`startedVersion == 0`**,
and `forceShow` is false. Graph and backfill presence may be consulted *only* under that
`startedVersion == 0` condition — otherwise onboarding's own writes satisfy the predicate
that decides whether onboarding is needed. It marks first run complete without showing it
when the install is already populated or backfilled:

- Condition: `hg.hk.backfillCompleted` is set **or** the graph contains any event.
- The graph check is a new synchronous package primitive,
  `anyEventExists(includingDeleted: true)`, following the `purgeSyntheticDataSync`
  precedent (`DemoDataMaintenance.swift:23-28`, "synchronous variant for bootstrap … where
  no `await` is available"). It is a `SELECT EXISTS`-style query, not a count of 136k rows,
  and it includes soft-deleted rows — a user who deleted everything is not a fresh install.
- **Fail-closed:** a query failure is a bootstrap failure, never "show onboarding". A
  transient read error must not onboard over a populated graph.
- It **never advances a nonzero version.** Otherwise every future onboarding addition
  would be silently skipped on any device with events.
- Resolved before the first frame (same flash-free pattern as `UnitPreferenceBootstrap`).

Scope, stated precisely: this protects **populated or backfilled** installs. An existing
*empty* install is indistinguishable from a fresh one and will be onboarded. That is the
correct outcome.

**DEBUG resets are two separate, explicitly labelled actions:**

- *Reset first run* — clears `startedVersion`, `completedVersion` and `symptomSeeds`, and
  sets `forceShow = true`. Without `forceShow`, reconciliation would immediately mark a
  populated graph complete again and the flow would never appear.
- *Reset HealthKit backfill* — clears `hg.hk.backfillCompleted` only. Separate because
  clearing it invites a year-long re-backfill and silently disables observers if the test
  flow is abandoned.

Neither can reset the system HealthKit grant; that lives in Settings → Privacy.

### 3. The six screens

#### 3.1 Promise

The approved UI spec's copy is factually wrong for this codebase and is superseded (§13).
Coordinates are sent to OpenWeather, and `CloudAIService` is a BYOK client for
OpenAI/Anthropic. The framing also must not imply causation — the engine finds
associations (`2026-07-03-health-graph-design.md` §2.4, §17 "navigator, not advisor").

> **Notice patterns in what may help — or make symptoms worse.**
> Your Health Graph is stored on this device. Environment features share your location
> with the weather provider only when enabled. Cloud AI is optional and off by default.

#### 3.2 Connect Apple Health

Framed as import, not permission. Lists what will be imported: sleep, workouts, heart
rate, HRV, cycle, weight. `[Connect Apple Health]` `[Not now]`.

Branching is exhaustive:

| Outcome | Next |
|---|---|
| `Not now` | **Skips Backfill entirely**, straight to symptom selection (§3.4). |
| `requestAuthorization()` throws | Stays on Connect. `[Retry]` `[Not now]`. |
| Authorization returns | Advances to Backfill (§3.3) — including when reads were silently denied, since that is indistinguishable from "no data". |

#### 3.3 Backfill

Live: `currentStep` and `eventsIngested` from `BackfillProgress`.

**The completion summary must be source-scoped, and it must distinguish two different
things.** `countsByCategory()` (`EventStore.swift:109`) describes the *entire* graph — on a
DEBUG first-run reset that includes 136k pre-existing events, manual captures, prior
export.zip imports and any synthetic demo rows. Reporting it as what onboarding just
achieved would be false, and "the graph we just filled" is wrong wording on any re-import.

Two separate figures:

| Figure | Source |
|---|---|
| **This attempt** | `inserted` / `updated` from the returned `IngestSummary` (`IngestPipeline.swift:5-16`). |
| **Apple Health history now available** | Counts per category and earliest event date, from the scoped query below. |

`EventStore` has no source-filtered or earliest-date query today — `countsByCategory()` and
`countsBySource()` are both whole-graph and cannot be combined. This round adds a scoped
summary API returning per-category count plus earliest timestamp.

**The scoped predicate is three conditions, all required:**

```
source == .healthKit  AND  syntheticBatch IS NULL  AND  deletedAt IS NULL
```

`source == .healthKit` alone is **not** sufficient. `SyntheticDataGenerator.swift:207`
emits demo sleep events as `source: .healthKit`, so a DEBUG graph with demo data loaded
would report fabricated rows as imported Apple Health history — precisely the confusion the
demo-data-hygiene round exists to prevent. `syntheticBatch` is an indexed column
(`AppDatabase.swift:276-288`). Release purges synthetic rows at bootstrap
(`HealthGraphProvider.swift:18-29`), so this matters in DEBUG — which is exactly where the
first-run flow will be exercised most.

`BackfillProgress` carries no per-type counts (`HealthKitIngestor.swift:5-10`), so the UI
spec's "✓ 14 months of sleep ✓ 212 workouts" would require ingestion plumbing to invent.
The "sleep back to …" date comes from the **earliest HealthKit-sourced sleep event**, never
inferred from the requested one-year window — export.zip can reach further back and a
partial grant can yield less.

Three distinct outcomes, all non-blocking, each offering `[Retry]` `[Continue]`:

| Outcome | Copy |
|---|---|
| 0 events, no failures | "Nothing came through yet." |
| events + failures | "Your history was imported, but some data couldn't be read." |
| 0 events + failures | "Apple Health couldn't be fully imported." |

Denied reads surface as Code 5 "not determined" by Apple's privacy design (observed on
Leo's device during Phase 1A, blood pressure). Zero events is therefore a normal outcome,
never an error state. `lastBackfillFailures` detail lives in Data sources (§5), but their
*existence* is not hidden during onboarding.

#### 3.4 What brings you here?

A curated common-symptom grid: an explicit ordered list defined alongside the flow, **not**
the full 131-entry catalog and not derived from catalog order. **Every
`RedFlagCatalog.allSymptomKeys` entry is excluded** (`RedFlagCatalog.swift:61`) —
`SymptomCatalog` contains "Thoughts of self-harm or suicide" (`SymptomCatalog.swift:28`),
which must never appear in a first-run grid. Every entry must resolve to a current catalog
key, asserted by test. Skippable.

Writes `hg.firstRun.symptomSeeds` only.

#### 3.5 Location

Placed last so it can name what the user just chose:

> You picked Migraine and Bloating. If you share location, we'll also watch pressure
> drops, temperature swings and air quality against them.

"Watch", never "find" — every weather exposure is `.contested` in `PlausibilityCatalog`.

State-aware, via the injectable location seam (`Models/EnvironmentStatus.swift:42`), which
reads status without prompting:

- `.notDetermined` → explain, then request explicitly.
- `.denied` / `.restricted` → no prompt; explain and offer **Open Settings**; Continue
  stays enabled.
- authorized → no prompt; Continue enabled.

Completion **never** waits on a first coordinate.

#### 3.6 Home

The shell mounts, with launch side effects attached to this branch (§1, Decision 2).

### 4. Symptom seeds

Validated on **both write and read** (a stale store must not resurrect a removed or
red-flag key):

1. Must resolve to a current `SymptomCatalog` entry; unknown keys are dropped.
2. Excludes `Set(RedFlagCatalog.allSymptomKeys)`.
3. Deduplicated, preserving selection order.
4. Capped at 8, matching the `limit: 8` used at all three `ChipRanker` call sites
   (`SymptomCaptureView.swift:29-30`, `MealCaptureView.swift:16`, `DoseCaptureView.swift:22`).
   Eight selected seeds may fill all eight chip slots — that is the correct outcome for a
   user who has just told us exactly what they care about, and the catalog search field
   remains available for anything else.

`ChipRanker.rank` gains `seeds: [String] = []` — defaulted so no existing call site churns.
Seeds fill **only the slots left over** after history-ranked items, deduped against them,
in the user's order. No expiry logic: as real history accumulates it outranks and displaces
seeds naturally.

This closes a verified hole. Chips are filtered to `sources: [.manual]`
(`SymptomCaptureView.swift:28`, `MealCaptureView.swift:15`, `DoseCaptureView.swift:21`), so
a fresh HealthKit-only graph yields zero chips today and every log requires the full search
form.

### 5. `DataSourcesView` — one view, two presentations

A `NavigationLink` destination in the Health tab, and a sheet from the Timeline empty
state, so the "connect Apple Health" instruction finally points at something real without
cross-tab routing machinery.

**A persisted `HealthImportStatus` is required.** `lastBackfillFailures` and `progress` are
in-memory `@Published` properties on `HealthKitIngestor` (`:16-18`), so after a relaunch
Data sources could not truthfully say "Last imported …" or "Imported with issues" — it
would show a blank slate on a device that has imported successfully many times.

**The outcome must be a full state machine, not three terminal results.** *No data /
imported / imported with issues* cannot express an authorization failure, an import that
began and was killed, or an import attempted but never finished:

| State | Meaning |
|---|---|
| `notStarted` | No import has ever been attempted. |
| `inProgress` | Persisted **before** authorization or backfill begins. |
| `attemptFailed` | Authorization or backfill threw. |
| `completedNoData` | Finished, zero events, no failures. |
| `completed` | Finished with events, no failures. |
| `completedWithIssues` | Finished with per-type failures. |

`inProgress` surviving a relaunch is exactly how a killed import is detected, and it gives
onboarding the signal it needs to resume intelligently rather than restart from scratch.
Every terminal path must transition out of it.

Persisted alongside the state:

- last attempt date
- last completed date, if any
- imported event and category summary (source-scoped per §3.3)
- sanitized failure identifiers (type identifiers only, no sample payloads)

**The Timeline empty state reads this same state** (§6), rather than independently
inferring anything from `hg.hk.backfillCompleted` — one source of truth, so the two
surfaces can never disagree.

Contents:

- **Apple Health** — state vocabulary is *Not imported* / *Import attempted* /
  *Last imported …* / *Imported with issues*, derived from `HealthImportStatus`. No
  Connected/Denied (Decision 4).
- Import / re-import action, last summary, and failure detail.
- **export.zip / export.xml import**, keeping the existing long-running warning.
- **Location & environment** status via the existing `EnvironmentStatusStore`.
- `#if DEBUG`: the two reset actions (§2) and the relationship dump (§10).

**Lifecycle requirement:** the import action must call `healthKitIngestor.startObserving()`
after backfill completes. The root `.task` has already run by then and will not retry until
a later launch, so a user who skips onboarding and imports later would otherwise get no
live ingestion for the rest of the session. `HealthGraphDebugView.swift:104` already does
this; the new surface must too.

### 6. Copy retirement

| Where | Fate |
|---|---|
| `HomeView.swift:146-156` (`whatsNext`) | Deleted. Home already carries the backfill card, mood check-in, poor-air banner and passive strip. |
| `InsightsPlaceholderView.swift:18,36` | File and per-family coverage strip kept — both are honest and useful. Only the two claims that the engine hasn't arrived are replaced, with a description of what the engine needs to activate a pattern. |
| `TimelineView.swift:213-215` | Two branches, both driven by the persisted `HealthImportStatus` (§5), never by `hg.hk.backfillCompleted`: not imported → "Connect Apple Health", opening the `DataSourcesView` sheet; imported but empty → "Nothing logged yet. Tap + to log your first thing." |

### 7. Engine fix 1 — stress uses a positive semantic subtype

Introduce canonical subtype **`stressRating`**, unit `score`:

- `SyntheticDataGenerator` and tests emit `subtype: "stressRating"`, unit `score`.
- `HighStressExposureSource` requires **all three**: `subtype == "stressRating"`,
  `unit == "score"`, and `value` within `1...10`. Only then does `highStressThreshold`
  apply. The unit check is not redundant — it is what makes a future source that reuses the
  subtype with different units fail closed rather than silently mis-scale, which is exactly
  how mindfulness minutes got mined as stress.

Absence (`subtype == nil`) is not a durable allowlist — the next unit-mismatched ingestion
source would walk straight through it, exactly as mindfulness does today.

**Accepted consequence:** nothing currently produces `stressRating`, so `highStress`
becomes dormant on real data. That is the honest state; it was never measuring stress.
Mindfulness stays available for a later protective-exposure round.

### 8. Engine fix 2 — cycle start ownership

HealthKit menstrual-flow samples carry `HKMetadataKeyMenstrualCycleStart`, which
identifies the first sample of a period. `CategorySampleData` carries only
`identifier/start/end/value/timezoneID` (`HealthKitSampleMapper.swift:20-30`), and
`HealthKitIngestor.swift:302` reads only `HKMetadataKeyTimeZone`, so that marker is
currently discarded at the adapter boundary.

- Thread `menstrualCycleStart: Bool?` through `CategorySampleData`, **defaulted to `nil`**
  so existing fixtures and the export parser stay source-compatible.
- Keep the event as `subtype: "menstrualFlow"` and retain the marker in event metadata.
  Do **not** rewrite it to `periodStart` — that would discard the flow measurement.

`CyclePhaseExposureSource` resolves starts with explicit ownership:

| Marker | Treatment |
|---|---|
| `true` | Authoritative start. |
| `false` | **Definitely not** a fallback candidate. A live `false` must never be inferred as a start merely because it begins the loaded slice. |
| `nil` | Eligible for run inference (legacy and export records only). |

Two `EvidenceConfig` knobs govern inference:

- `maxFlowGapDays = 2` — a gap this small keeps the same period, so one missing middle day
  doesn't split a run.
- `minInferredStartGapDays = 10` — the suppression window for *inferred* candidates only.
  It does not suppress mid-cycle spotting two weeks later; only authoritative metadata does
  that.

**Resolution algorithm, ordered — inference must yield to authority in both directions**,
because live and legacy/export records coexist in one corpus:

1. Collect **authoritative** starts: manual `periodStart` events, plus flow events with
   `menstrualCycleStart == true`.
2. Build **inferred** candidates by run detection over flow events with
   `menstrualCycleStart == nil` only. Events with `false` never participate — a live
   `false` must not become a start merely because it begins the loaded slice.
3. Drop any inferred candidate within `minInferredStartGapDays` of **any authoritative
   start, before or after**.
4. Apply the same gap among the surviving inferred candidates.
5. Union authoritative and surviving inferred starts; dedupe by day.

Authoritative starts are never suppressed by steps 3 or 4.

The global `guard starts.count >= 2` is **removed**. One start yields its menstrual-day
exposure; two are required only to derive a luteal window.

### 9. Engine fix 3 — illness markers and classification

`SymptomCatalog` gains, as searchable symptoms: **Fever, Chills, Night Sweats, Sore
Throat, Congestion, Runny Nose, Generalized Body Ache**. "Cough" already exists. The list
is explicitly append-safe — additions are fine, renames change derived keys. Being sick
becomes loggable through the existing symptom capture path: no sixth capture type, no new
screen, no added friction.

**Normalization table** (HealthKit identifier subtype → catalog canonical key). HK
subtypes are derived by stripping `HKCategoryTypeIdentifier` and lowercasing the first
character (`HealthKitSampleMapper.swift:312-320`); catalog keys come from `canonicalize`
(`SymptomCatalog.swift:232-238`). These agree for most names and diverge for two:

| HK subtype | Catalog key |
|---|---|
| `coughing` | `cough` |
| `sinusCongestion` | `congestion` |
| `fever`, `chills`, `nightSweats`, `soreThroat`, `runnyNose`, `generalizedBodyAche` | identity |

*Considered and rejected:* naming the entry "Sinus Congestion" would make that row an
identity too, eliminating one alias. Rejected in favour of the friendlier user-facing
label "Congestion"; the alias is cheap and covered by test.

**Two distinct sets, and the tests must not conflate them:**

- *Normalization coverage* — all eight HK illness identifiers resolve to a catalog key.
- *Classification markers* — a strict subset. A day is an illness day when it has:
  - any explicit `.illness` event, **or**
  - `fever` alone, **or**
  - ≥2 distinct markers from {`chills`, `nightSweats`, `soreThroat`, `congestion`,
    `cough`, `generalizedBodyAche`}.

`runnyNose` is searchable and normalized but is **not** a classification marker — it is too
common and nonspecific (allergies) to justify penalizing every exposure that day. Chills or
night sweats alone are likewise insufficient.

Day-of semantics are preserved exactly as now. Forward-extension across a multi-day illness
is more realistic but is a behaviour change beyond this fix (§14).

### 10. DEBUG relationship dump

A `(edgeKey, status, confidence)` dump shows *that* a relationship changed, not *why*. The
dump therefore covers **active and decayed** relationships, and for each emits:

- edge key, status, confidence
- recomputed confounder keys
- evidence and contradiction counts

Decayed relationships are hidden from Insights but can still be passed through
`EvidenceEngine.evidence(for:asOf:)`, which never reads `relationship.status` — it re-parses
the edge and recomputes confounders from the corpus (`EvidenceEngine.swift:182-207`).
`RelationshipStore.all()` reaches them.

The reserved illness key is printed as **`illness`**, not its sentinel UUID
(`EvidenceEngine.swift:25-26`).

**N full corpus scans are not acceptable, even for a diagnostic.** `evidence(for:)` loads
the whole event table and re-extracts on every call, so dumping every relationship on a
136k-event graph would scan it once per edge. This round adds a **batch evidence-report
API** that loads and extracts the corpus **once**, then evaluates every requested
relationship against that shared context. It stays DEBUG-facing and does **not** rewire the
general Insights N+1 (§12) — but the reusable batch shape is what that later fix will build
on.

## Data flow

```
launch
  └─ resolve first-run state (sync, pre-frame, fail-closed)
       ├─ completedVersion > 0 ───────────────┐
       ├─ startedVersion > 0 && completed == 0 │  → HealthOSRootView branch
       │      → resume/restart the flow        │     + startObserving()
       ├─ started == 0 && completed == 0 &&    │     + initial / scene-active /
       │   (backfilled || anyEventExists)      │       location-recovery emission
       │      → mark complete ─────────────────┤
       │                                       │
       └─ otherwise → FirstRunFlowView         │
              │  (writes startedVersion FIRST) │
              ├─ 1 promise                     │
              ├─ 2 connect  → status .inProgress → requestAuthorization()
              ├─ 3 backfill → backfill() → startObserving()
              │      summary = healthKit-scoped query
              │      (source == .healthKit && syntheticBatch IS NULL
              │       && deletedAt IS NULL) → counts + earliest per category
              │      status → completed / completedNoData / completedWithIssues
              ├─ 4 seeding  → validated hg.firstRun.symptomSeeds → ChipRanker(seeds:)
              ├─ 5 location → request only when .notDetermined
              └─ complete   → set completedVersion, clear startedVersion
                                and forceShow ────────────────────────┘
```

## Testing

**Package (`HealthGraphCore`)**

- Seed validation and ranking: history-first ordering; remaining-slot fill; duplicate
  seeds; red-flag rejection; unknown/stale keys ignored; overall limit respected.
- `anyEventExists(includingDeleted:)`: true for a soft-deleted-only graph; false for empty.
- Source-scoped summary: counts and earliest dates exclude manual and export-file rows,
  soft-deleted rows, **and synthetic rows carrying `source: .healthKit`** — seed a graph
  with a `syntheticBatch` sleep event and assert it is not counted as imported history.
- Batch evidence report: loads the corpus once for N relationships; results match
  per-relationship `evidence(for:)` output exactly; includes decayed relationships.
- Stress source: accepts `stressRating` + `score` within `1...10`; rejects mindfulness
  minutes; rejects right subtype with wrong unit; rejects out-of-range values; rejects
  subtype-nil.
- Cycle: authoritative `true` wins; `false` is never inferred as a start even when first in
  the slice; `nil` runs fall back to inference; an inferred candidate within
  `minInferredStartGapDays` of an authoritative start is dropped **on both sides**;
  surviving inferred candidates are then gapped against each other; authoritative starts
  are never suppressed; union with manual `periodStart` dedupes by day; a single start
  yields menstrual days and no luteal window.
- Illness: normalization coverage over **all eight** HK identifiers; fever alone qualifies;
  two composite markers qualify; one composite marker does not; `runnyNose` alone does not;
  explicit `.illness` events still qualify.
- The existing `illnessRecordedAsConfounderForOverlappingExposure` acceptance test keeps
  passing.

**App**

- First-run routing through the prior-version → screens map.
- **Interrupted onboarding (required):** begin the flow, ingest one event, simulate
  termination before completion, relaunch — must return to the flow, **not** the shell.
  This is the test that would have caught the self-skipping defect.
- Reconciliation invariants: runs only when `startedVersion == 0` *and*
  `completedVersion == 0`; never advances a nonzero version; never re-onboards a populated
  graph; no flash; fail-closed on query error.
- `HealthImportStatus` transitions: every terminal path leaves `inProgress`; a persisted
  `inProgress` surviving relaunch is detected as a killed import.
- Connect branching: `Not now` skips Backfill and lands on symptom selection; an
  `requestAuthorization()` throw stays on Connect with Retry; success advances.
- Backfill outcome branching across the three states.
- `HealthImportStatus` survives relaunch and drives both the Data sources vocabulary and
  the Timeline empty state from the same value.
- `DataSourcesView` import calls `startObserving()` after backfill.
- Timeline empty-state branching reads `HealthImportStatus`, not `hg.hk.backfillCompleted`.

Suites run per the standing constraints: `swift test --package-path HealthGraphCore`;
app tests on iPhone 17 Pro with `-parallel-testing-enabled NO`; the known
`SwiftDataMigratorTests` teardown crash is unrelated.

## Device gate

The obvious procedure — "capture the same dump on `main`" — is **impossible**: `main` does
not contain the dump action. The baseline needs a build that has the diagnostic but not the
fixes, which constrains task order:

1. **Build the diagnostic first, as an isolated task** (§10), containing the batch report
   API and the DEBUG action and *nothing else*.
2. **Install that commit and capture the baseline report** — before any of §7–§9 lands.
3. Build final branch HEAD, recompute, capture the post-change report.
4. Diff as text, not screenshots.

This ordering is a hard requirement on the plan, not a suggestion. If it is dropped, the
fallback is a strictly weaker gate: a pre-change screenshot plus list of visible Insights
cards, compared against a detailed post-change report — good enough to notice a change,
not good enough to attribute one.

Three outcomes, classified explicitly — the stress fix produces disappearances with **no**
confounder explanation, and a cycle/illness-only rule would misclassify them as regressions:

| Observation | Verdict |
|---|---|
| A `highStress` relationship decays or vanishes, with no new confounder | **Expected.** Its exposures were mindfulness minutes and no longer exist (§7). |
| Any other relationship demotes, with cycle phase or illness listed as a new confounder | **Expected.** That is fixes §8/§9 doing their job. |
| Any other disappearance, unexplained by either | **Regression.** Investigate before merge. |

Also verified on device: fresh-install flow end to end; reset-first-run reproduces it;
skip-then-import-later starts live ingestion within the same session; denied-location path
shows Open Settings and never blocks completion.

## Accepted limitations

- An existing *empty* install is indistinguishable from a fresh one and will be onboarded.
- `highStress` is dormant until a `stressRating` producer exists (§14).
- Illness classification depends on the user logging markers; a user who never logs them
  has an empty illness confounder, now for an honest reason rather than a wiring gap.
- Export.zip records carry no cycle-start metadata, so they rely on run inference (§14).
- HealthKit read denial remains unknowable; the UI never claims otherwise.

## Out of scope

Named here so they don't drift in: **rewiring `InsightsViewModel.load()`** onto the new
batch evidence API — the batch API itself ships (§10) because the diagnostic needs it, but
the live Insights path keeps its current per-card `evidence(for:)` calls this round,
deferred by decision unless profiling shows it blocks backfill; legacy SwiftData migration
in Release; the clinic-QR
branch; UI spec §5's meds/supplement quick-add screen; mindfulness as a protective
exposure; illness forward-extension; voice, photo, App Intents, body map; backup, export,
paywall, rebrand; missions and Health Confidence.

## Spec divergences recorded

1. **Supersedes `2026-07-04-ui-design.md` §5 promise copy** on both counts — the privacy
   claim ("your data never leaves this device") is false given OpenWeather coordinates and
   BYOK Cloud AI, and "find what actually helps you" implies causation the engine does not
   establish.
2. **Amends `2026-07-03-health-graph-design.md` §7.3.** Its claim that cycle phase and
   illness are always in the confounder set was aspirational. This round makes it true for
   cycle, and conditionally true for illness.
3. **Adds a sixth onboarding step** (location) that UI spec §5 does not have, and **drops**
   §5's step 5 (meds/supplements quick add) from this round.

## Follow-ups this round generates

- Manual stress-rating capture producing `stressRating` — until then `highStress` is
  dormant by design.
- Mindfulness as a protective exposure family ("meditated ≥10 min → fewer headaches").
- Illness forward-extension across multi-day episodes.
- Insights N+1 fix: move `InsightsViewModel.load()` onto the batch evidence API this round
  introduces, replacing its per-card `evidence(for:)` calls.
- Cycle-start metadata on the export.zip parser path.
