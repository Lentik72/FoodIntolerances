# Phase 2A — Evidence Engine (headless) — Design

**Date:** 2026-07-15
**Status:** Approved (decisions made interactively with Leo)
**Depends on:** Phase 0 graph (`HealthEvent`/`HealthObject`/`Relationship`, `EventStore`/`ObjectStore`/`RelationshipStore`, `AppDatabase` migrations v1–v4), Phase 0 synthetic harness (`SyntheticDataGenerator`, `PlantedPattern`, `SeededGenerator`), Phase 1A sleep ingestion + `Timeline/SleepSessionBuilder`
**Relates to:** `2026-07-03-health-graph-design.md` §7 (Evidence Engine), §16 (phase sequencing)
**Scope:** The deterministic, headless correlation-mining engine only. **No UI.** Validated entirely against the synthetic harness. One schema migration (v5).

---

## 1. Problem & framing

The corpus captured in Phase 1 is inert: symptoms, foods, meds, supplements, peptides, sleep, stress, environment, and cycle all land in the event graph, but nothing mines them for personal evidence about what helps and what hurts. Phase 2 (design doc §7) is the Evidence Engine that does the mining, plus the Insights surface and red-flag safety that present it.

**Phase 2 is split** the way Phase 1 was split into 1A/1B/1C:

- **Phase 2A (this spec):** the headless engine — a pure, deterministic function of the event graph that produces `relationships`. Zero UI. Proven correct against the synthetic harness before a single pixel exists.
- **Phase 2B (later cycle):** the Insights surface — cards, per-exposure dots, evidence drill-down, dismiss / "suggest an experiment" actions, the red-flag "seek care now" interstitial, template explanation copy, scheduling, and the 3-new-candidates/week surfacing cap.

This clean seam exists because the engine is a spec-mandated *pure function* (§2.3, §7): its correctness is a property of the math, testable with no device, no HealthKit, and no views. 2A gets to be brutally unit-tested in isolation.

## 2. Decisions (Leo, 2026-07-15)

| Decision | Choice |
|---|---|
| Phase 2 shape | **Split 2A engine / 2B surface** — two spec→plan→SDD cycles, mirroring 1A/1B/1C |
| Exposure set (2A) | **Full §7 set** — object exposures (food/med/supplement/peptide) **plus** derived predicates: short-sleep, high-stress, pressure-drop, cycle-phase |
| Evidence detail for the dots | **Recompute on demand** — persist only the `relationships` summary; re-derive per-exposure detail via a deterministic `evidence(for:)` function |
| Engine architecture | **Pipeline of small pure stages** (extract → generate → count → score → classify → upsert); **full recompute**, not incremental |
| Explanations | **Deferred to 2B** — no LLM infrastructure is wired into the new core (voice parsing was deferred out of Phase 1), so explanation copy is 2B's concern; fits §7's "numbers from the engine, never the model" |

**Rejected:**

- **One combined Phase 2 spec** — the engine and the surface are a clean seam; combining them makes a 3–4-week single surface and couples the math's proof to UI.
- **Persist an `evidence_pairs` table** — the engine is deterministic, so stored evidence pairs are pure redundancy (a cache), not a second source of truth. Editing history (§17) would stale it; sync (Phase 6) would have to reconcile it. The one genuine need for frozen numbers — the Doctor Report (§10) — is better served by snapshotting into the report's signed JSON at generation time. If drill-down ever profiles slow (it won't, for one card), a cache can be added *over* a clean source of truth later; removing a denormalized table other code depends on is far harder.
- **Monolithic `recompute()`** — can't unit-test the counting logic in isolation, and 2B's on-demand `evidence(for:)` couldn't reuse a stage without duplicating it.
- **Incremental / dirty-tracking recompute** — extra bookkeeping state, much harder to prove correct; a full recompute fits the <30s budget for v1. The pure-stages structure lets incremental be bolted on later if profiling ever demands it.
- **Objects-only exposure set** — sleep→fatigue is a flagship relationship (missions §8) and sleep already flows in via HealthKit; deferring all derived predicates was judged to under-deliver.

## 3. Architecture — a pipeline of pure stages

New module `Sources/HealthGraphCore/Evidence/`, alongside `Timeline/` and `Capture/`. It reads through `EventStore`/`ObjectStore` and writes through `RelationshipStore` — no direct SQL.

| File | Responsibility |
|---|---|
| `ExposureSource.swift` | `ExposureOccurrence` type + `ExposureSource` protocol; one extractor per exposure kind |
| `OutcomeSource.swift` | Extracts symptom/low-mood `OutcomeOccurrence`s |
| `CandidateGenerator.swift` | Pairs exposures × outcomes worth testing |
| `CooccurrenceAnalyzer.swift` | Windowed counting + base-rate → `PairStats` |
| `ConfidenceScorer.swift` | The sigmoid formula, confounder penalty, decay |
| `RelationshipClassifier.swift` | Assigns `type` + `status` from the stats |
| `EvidenceConfig.swift` | Every tunable number in one place (lag windows, thresholds, weights) |
| `EvidenceEngine.swift` | Orchestrates the stages; the only public entry point |

Each stage is a pure function testable on hand-built fixtures. The whole chain is validated end-to-end by the synthetic harness (§7).

### Public API

```swift
public struct EvidenceEngine {
    public init(database: AppDatabase, config: EvidenceConfig = .default)

    /// Full recompute: mine every candidate pair, upsert relationships.
    /// `now` is injected (never Date() internally) so runs are deterministic.
    public func recompute(asOf now: Date) async throws -> RecomputeReport

    /// On-demand per-exposure detail for 2B's drill-down/dots (the recompute path).
    /// Reuses CooccurrenceAnalyzer for a single pair — no stored evidence table.
    public func evidence(for relationship: Relationship,
                         asOf now: Date) async throws -> RelationshipEvidence
}
```

- `RelationshipEvidence` is the itemized list 2B renders as dots: for each exposure, `{ exposureEventID, exposureTime, outcomeFollowed, outcomeEventID?, outcomeValue? }` plus the roll-up counts and the recorded confounders.
- `RecomputeReport` is a plain summary (pairs evaluated, relationships upserted / decayed, wall-clock). Used by harness tests and later telemetry; **not persisted**.

**Two commitments:** `now` is always injected (determinism is non-negotiable for a testable engine), and the engine's **only persistence side-effect is upserting `relationships`**.

## 4. Extraction — exposures & outcomes

Everything below is a **default in `EvidenceConfig`**, tuned against the harness (§7), not a constant buried in code.

Exposures normalize to one shape regardless of origin:

```swift
struct ExposureOccurrence {
    var key: ExposureKey      // object(UUID, category) | derived(DerivedKind)
    var timestamp: Date
    var timezoneID: String
    var sourceEventID: UUID   // for the drill-down
}
```

Five extractors (`ExposureSource` conformers):

| Extractor | Emits an exposure when… | Timestamped at | v1 default |
|---|---|---|---|
| **Object** (food/med/supplement/peptide) | an event references a `health_object` | event time | one per event, keyed by objectID |
| **Short-sleep** | a night's total asleep `< 6h` (reuses `SleepSessionBuilder` nightly totals) | wake time | threshold `6h` |
| **High-stress** | a `stress` event with `value ≥ 7` (1–10) | event time | threshold `7` |
| **Pressure-drop** | barometric pressure falls `≥ 6 hPa / 24h` (from `environment` events) | drop time | threshold `6 hPa` |
| **Cycle-phase** | a day falls in the **menstrual** or **luteal** window (derived from logged period starts) | phase-entry | needs ≥2 logged periods to bound a cycle |

**Outcomes** (`OutcomeSource`): `OutcomeOccurrence { key, timestamp, value? }` for every distinct **symptom subtype** (headache, bloating, fatigue — "energy" folds in as fatigue) plus **low mood** (a `mood` event below threshold). Symptom `value` (1–10 severity) feeds effect-size/strength.

**Two asymmetries from §7, made explicit:**

- **Cycle-phase is both an exposure and a permanent confounder.** It is mined as an exposure *and* is always in the confounder set for every *other* relationship.
- **Illness is confounder-only** — `illness` events define illness windows used to penalize other edges, but illness is never mined as an exposure.

**Scope note:** the derived extractors are the real work; **cycle-phase is the heaviest** (phase estimation from sparse period logs) and the extractor most likely to need a second iteration. v1 scopes it to the two symptomatic windows (menstrual, luteal), not a full four-phase model.

## 5. Counting — candidates & windowed co-occurrence

**Candidate generation** (`CandidateGenerator`) bounds the combinatorial space cheaply. Form an exposure×outcome pair only if:

1. the exposure occurred **≥5 times** total (the evaluation gate — below that there is not enough data to compare), **and**
2. the outcome occurs in the corpus **≥3 times overall** (there must be *something* to associate; prunes symptoms logged once).

Note the gate is deliberately **direction-agnostic** — it admits pairs so the analyzer can measure the ratio in either direction. It does **not** pre-require `ratio ≥ 1.5`; that threshold is a *direction/activation* decision in §6, because a low ratio is exactly what `improves` (protective) and `confirmedNoEffect` need to observe. This generalizes §7's trigger-centric "ratio ≥1.5 to create a candidate," which §7's own `improves` type and negative-learning require.

**Windowed co-occurrence** (`CooccurrenceAnalyzer`), per pair, timezone-aware via `timezoneID`:

- For each exposure occurrence, does the outcome appear within the pair's **lag window**?

  | Exposure → outcome | Lag window |
  |---|---|
  | food → symptom | `0–24h` |
  | supplement / med / peptide → outcome | `0–48h` |
  | short-sleep → daytime outcome | `0–18h` |
  | high-stress → symptom | `0–24h` |
  | pressure-drop → symptom | `0–24h` |
  | cycle-phase → symptom | symptom occurring **within the phase window** |

- **Base rate:** `ratio` = P(outcome \| exposure in window) / P(outcome \| no exposure).

Output is a `PairStats` — exposure count, follow count, miss count, base rate, `ratio`, avg effect size, observed lag — that flows into scoring, where the ratio's magnitude *and direction* select the type and status.

## 6. Scoring, confounders, decay, negative-learning

Confidence formula — a **direction-symmetric** adaptation of §7. (§7's literal form — `w1·log(evidenceCount) + w2·consistency − w3·baseRate − …` where `evidenceCount`/`consistency` are *follows* — is trigger-biased: a protective `improves` edge has *few* follows and *low* P(Y\|X), so §7 would score it near zero and `improves` could never activate. Plan-writing surfaced this; the formula below scores both directions by **effect magnitude** instead.)

```
signalStrength = min(1, |ln(ratio)| / ln(3))     // a 3× or ⅓× shift = full signal
confidence = min(0.75, sigmoid( w1·log(exposureCount)
                              + w2·signalStrength
                              − w4·confounderPenalty
                              − w5·staleness
                              + bias ))
```

| Term | Definition (v1) | Stored as |
|---|---|---|
| `exposureCount` | how much data — total exposure occurrences (direction-agnostic) | derivable from dots |
| (follows) | exposures where the outcome appeared in-window | `relationships.evidenceCount` → filled dots |
| (misses) | exposures with **no** outcome in-window | `relationships.contradictionCount` → hollow dots |
| `ratio` | P(Y \| X) / P(Y \| **no** X) — the base-rate comparison; drives both `signalStrength` and the type/direction | — (recomputed) |
| `signalStrength` | `min(1, |ln(ratio)|/ln(3))` — symmetric effect magnitude, so `improves` (ratio<1) and `possibleTrigger` (ratio>1) score alike | — |
| `confounderPenalty` | rises when another exposure co-occurs with X on **>60%** of X's occurrences. **Cycle-phase + illness always in the confounder set** | — |
| `staleness` | (now − lastSeen) / 60d, clamped 0–1 — drives decay | — |

The stored `evidenceCount`/`contradictionCount` (follows/misses) still power the UI dots — they are just no longer the *scoring* inputs. `strength` = mean outcome severity among follows; `lagHours` = median observed lag among follows.

**Two hard rules baked into the scorer:**

- **Observational ceiling:** confidence is clamped **≤ 0.75**. Exceeding it requires experiment/rechallenge confirmation (Phase 4). Observational evidence alone plateaus (§7).
- **`now` drives staleness**, so decay is deterministic and testable.

**Type** — selected by the ratio's **direction**; v1 assigns three of the five (`worsens` / `precedes` reserved):

| `ratio` | Type |
|---|---|
| `≥ 1.5` | `possibleTrigger` — positive association with a symptom/low-mood outcome |
| `≤ 0.67` | `improves` — protective / negative association (e.g. magnesium → *fewer* headaches) |
| within `[0.83, 1.2]` **and** ≥20 exposures over ≥90 days | `noEffect` — see negative-learning row below |
| in the weak bands (`1.2–1.5`, `0.67–0.83`) or too little data | no type assigned → stays `candidate` |

**Status transitions** (`RelationshipClassifier`), evaluated on a pair that cleared the §5 evaluation gate:

| Condition | → status |
|---|---|
| A type was assigned (ratio ≥1.5 or ≤0.67) **and** confidence ≥ 0.35 | `active` |
| Ratio in a weak/undirected band, or confidence < 0.35 | `candidate` (internal, not surfaced) |
| confidence < 0.3 from staleness | `decayed` |
| **≥20 exposures over ≥90 days**, ratio within `[0.83, 1.2]` | `confirmedNoEffect` (type `noEffect`) |
| User dismissed it in 2B | `userDismissed` — **recompute must never overwrite this** |

**Boundaries:**

- The **3-new-candidates/week cap** is a 2B concern. The engine produces *all* active relationships plus the raw signals (confidence, `firstSeen` for novelty); *which* to surface as "new this week" is a presentation choice. Keeping it out of the engine keeps 2A a pure function of the data.
- **Preserving user intent** is the engine's job: a `userDismissed` edge stays dismissed, and `firstSeen` is never bumped forward on re-runs.

## 7. Persistence — edge identity & idempotent upsert

An edge (e.g. **dairy → bloating**) must be *found again* on the next run (to update, not duplicate) and *rendered* by 2B. But `relationships` has no subtype field: symptom outcomes are identified purely by subtype, and derived exposures have no object to point at. A composite unique index fails here — SQLite treats NULLs as distinct, and every derived edge has a NULL `fromObjectID`. The schema comment anticipated this: *"edge identity/uniqueness is defined by the Phase 2 engine — deliberately not constrained here."*

**Migration v5** (append-only; never touches v1–v4; the table is empty in the field — zero users — so no backfill):

- `edgeKey TEXT` + a **UNIQUE index** — a deterministic identity string the engine computes, e.g. `obj:<uuid>|symptom:bloating|possibleTrigger` or `derived:shortSleep|symptom:fatigue|possibleTrigger`. This is the upsert key **and** the DB-level dedup guarantee.
- `toSubtype TEXT` — so 2B can label the outcome ("bloating") without parsing `edgeKey`.

Existing structured columns are still populated for indexed queries and name resolution: `fromObjectID` for object edges; `fromCategory` doing double duty as the object's category *or* the derived-exposure kind ("shortSleep"); `toCategory` = "symptom"/"mood". `edgeKey` is the single non-null identity that ties it together.

**Idempotent upsert** (final pipeline stage), one transaction:

1. Load existing edges into a map by `edgeKey` (hundreds, not 100k — cheap).
2. For each freshly-computed edge:
   - **exists** → keep `id` and `firstSeen`; update counts/confidence/strength/lag/status/`lastRecomputed`/`lastSeen`. **If it was `userDismissed`, leave it dismissed.**
   - **new** → insert with `firstSeen = now` (the novelty signal; never bumped afterward).
3. **Reconcile disappeared edges** — one that existed last run but isn't produced this run (e.g. its supporting events were deleted) is **downgraded to `decayed`**, not deleted (soft-delete philosophy). `userDismissed` preserved.

**Store additions** (`RelationshipStore`): `all()` (for the reconcile step) and a batch `save(_ relationships: [Relationship])` (one transaction, not N writes).

**On-demand `evidence(for:)`** reverses the identity: parse the stored edge back into its exposure key + outcome subtype, re-extract just those occurrences, run `CooccurrenceAnalyzer` on that single pair, return the itemized `RelationshipEvidence`. Same analyzer the full run uses, so the dots can never disagree with the summary.

## 8. Validation — extended harness & weight tuning

The existing harness plants only object→symptom patterns. The full exposure set demands the harness grow to plant the derived patterns too, or those code paths ship on hope. Extensions to `SyntheticDataGenerator` / `PlantedPattern`:

- Emit **sleep events** with durations → plant *short-sleep → fatigue*.
- Emit an **environment pressure series** with drops → plant *pressure-drop → headache*.
- Emit **stress events** ≥7 → plant *high-stress → symptom*.
- Emit **cycle events** (period starts) forming cycles → plant *luteal → symptom*.
- Plant a **protective scenario** (e.g. magnesium → *reduced* headache base rate) → validates the `improves` direction.
- Plant a **confounder scenario** (e.g. coffee always taken with dairy, >60% co-occurrence).
- Plant a **null-effect scenario** (≥20 exposures over ≥90 days, no association).
- Keep the existing **noise** streams.

**The acceptance bar for 2A** — the validation suite that defines "done":

| # | Test | Asserts |
|---|---|---|
| 1 | **Recall** | every planted pattern (object + each derived kind, both `possibleTrigger` and `improves` directions) surfaces as `active`, correct type, ~correct lag |
| 2 | **Precision** | noise pairs produce **no** `active` relationship |
| 3 | **Confounder** | the co-occurring pair gets suppressed confidence + a recorded confounder |
| 4 | **noEffect** | the long null-effect exposure → `confirmedNoEffect` |
| 5 | **Decay** | old-only evidence (lastSeen ≪ now) → `decayed` |
| 6 | **Ceiling** | no observational edge exceeds **0.75** |
| 7 | **Determinism / idempotence** | same seed + same `now` → stable edges; a second recompute makes no duplicates and does not drift |
| 8 | **`evidence(for:)` parity** | itemized follows/misses equal the stored `evidenceCount`/`contradictionCount` |

**Weight tuning is a checked-in artifact, not runtime learning.** `w1…w5` and thresholds live in `EvidenceConfig.default`, chosen by a small offline search so tests 1–2 pass *with margin* (planted signals comfortably above activation, noise comfortably below). If a test fails, tune the config, never the algorithm. This is §7's "without it the numbers are hope, not evidence" made concrete.

## 9. Testing, NFRs, and out-of-scope

**Testing:** unit tests per stage (extractors, analyzer, scorer, classifier) on hand-built fixtures; the harness suite (§8) as integration (in-memory `AppDatabase`); a v5 migration test (edgeKey uniqueness). Meets design-doc §16's "all EvidenceEngine math unit-tested" mandate.

**NFRs** (design-doc §17):

- **Performance:** full recompute **< 30s at 100k events** on a mid device — held by candidate-bounding (≥5 exposures + must-co-occur keeps the pair space small) and indexed single-pair queries. A loose perf test guards the bound.
- **Determinism:** `now` injected; no `Date()`/random inside the engine (seeded RNG lives only in the harness).
- **Timezone-aware lag** via `timezoneID`.
- **Concurrency:** the engine is a struct; `recompute` is async and safe to run off the main actor.
- **No user-facing causal language:** 2A is headless (no copy); `type` names are internal. 2B owns wording (§2.5, §17).

**Explicitly out of scope for 2A** (each has a home):

- All UI — Insights cards, dots, drill-down, **red-flag interstitial** → **2B**.
- **Scheduling** (nightly `BGTask` vs on-foreground) → 2B integration; 2A only exposes `recompute()`.
- Explanation copy (template or LLM) → **2B**.
- The **3-new-candidates/week surfacing cap** → **2B**.
- Experiment weighting (3× observational), rechallenge suggestions → **Phase 4**.
- **"What worked before?"** (§10) → **Phase 5** — a backward, symptom-anchored query, not a forward miner; it will **reuse** `CooccurrenceAnalyzer` + `EvidenceConfig`, which is why they are factored as standalone stages.
- `worsens` / `precedes` types, incremental recompute, mood/energy beyond low-mood + fatigue → reserved / future.

## 10. Module layout (delta)

```
HealthGraphCore/Sources/HealthGraphCore/
  Evidence/                      // NEW
    ExposureSource.swift
    OutcomeSource.swift
    CandidateGenerator.swift
    CooccurrenceAnalyzer.swift
    ConfidenceScorer.swift
    RelationshipClassifier.swift
    EvidenceConfig.swift
    EvidenceEngine.swift
  Database/
    AppDatabase.swift            // + migration v5 (edgeKey unique, toSubtype)
    RelationshipStore.swift      // + all(), batch save([])
  Synthetic/
    SyntheticDataGenerator.swift // + derived-pattern planting (sleep/pressure/stress/cycle),
                                 //   confounder + null-effect scenarios
HealthGraphCore/Tests/HealthGraphCoreTests/
  EvidenceEngineTests.swift      // NEW — the §8 acceptance suite + per-stage unit tests
```
