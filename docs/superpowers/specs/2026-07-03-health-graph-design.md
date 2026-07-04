# Personal Health OS — Health Graph Design

**Date:** 2026-07-03
**Status:** Approved direction, pre-implementation
**Supersedes:** `/Users/leo/Downloads/health-graph-execution-plan.md` (incorporated and revised here)
**Relates to:** `V1_SCOPE.md` (the pre-pivot v1 scope; still authoritative for safety/language rules)

---

## 1. Vision

Evolve the existing FoodIntolerances app into a Personal Health OS: a private, on-device
system that captures everything health-related (symptoms, foods, medications, supplements,
peptides, labs, sleep, exercise, environment), mines it for personal evidence about what
helps and what hurts, learns over time — including learning what has *no* effect — and
produces reports a user can hand to a practitioner.

Strategic context that shaped this design:

- **Quality over speed.** No release pressure; the owner is willing to rebuild the
  foundation before TestFlight. There are zero users today, so migration is free.
- **Design-partner clinic.** One functional-medicine practice wants to see whether the
  peptides and protocols they prescribe actually work for their patients. This is the
  business wedge: clinic-authored protocols, adherence + outcome tracking, and
  patient-generated outcome reports — all without a backend at first.
- **Business shape: decide later.** Build the indie-subscription path (it is a strict
  subset of the venture path); keep identity, export, and module boundaries clean so a
  practitioner dashboard, community aggregates, or Android/web can be added post-revenue.

## 2. Guiding decisions (unchanged from the original plan; binding)

1. **On-device first.** All storage and evidence computation happen locally. SQLite via
   **GRDB** (preferred over SwiftData for complex queries, migrations, and FTS). LLM calls
   are used only for parsing unstructured input and generating natural-language
   explanations — never as the source of truth for confidence numbers.
2. **The "graph" is three tables, not a graph database.** `health_events`,
   `health_objects`, `relationships`. No Neo4j, no vector DB, no CoreData relationship
   spaghetti in v1.
3. **One evidence pipeline, not six agents.** A deterministic `EvidenceEngine` Swift
   module (pure functions, fully unit-testable). Agent separation is a Phase 7+ concern,
   if ever.
4. **Humble statistics.** Confidence = a bounded score built from observation count,
   consistency, recency, and confounder penalties. No p-values, no "causes." All
   user-facing language: "associated with," "historically followed by," "we observed."
5. **Wellness, not medical device.** No diagnosis, no treatment recommendations, no dosing
   advice. Descriptive patterns only. Persistent disclaimer; prediction phrasing stays
   historical ("in your past data…"). This keeps the app outside FDA SaMD territory and
   inside App Store health-app rules. While the *patient* holds and shares their own data
   (Phases 1–6), the developer is also outside HIPAA; that changes only if a practitioner
   dashboard is built (Phase 7+), which is when legal review happens.
6. **Capture friction is the #1 product risk.** Every phase must reduce, never increase,
   the effort to log a day.
7. **Never paywall capture.** Logging and the timeline are free forever; the data corpus
   is the moat and the retention engine. Monetize insight, experiments, and reports.

## 3. Current codebase: what carries over

The app is SwiftUI + SwiftData, pre-TestFlight. Decision: **re-foundation** — keep the
project and the good UI, replace the data layer.

| Existing asset | Fate |
|---|---|
| `LogEntry`, `TrackedItem`, `AvoidedItem`, `OngoingSymptom`, `SymptomCheckIn`, `CabinetItem`, `TherapyProtocol` (SwiftData) | Replaced by the event graph; one-time migrator converts existing rows, old store kept read-only behind a flag until verified |
| `QuickSymptomLogger`, `BodyMapView`, onboarding, notifications (`NotificationManager`, `ProactiveAlertService`) | Ported onto the event model, UI largely unchanged |
| Medicine cabinet stock/refill logic (`CabinetItem.logUsage`, refill alerts) | Ported and extended for peptide vial inventory (§6 item 5) |
| Environmental services (`EnvironmentalDataService` weather/pressure, `GetMoonPhase`, `SeasonService`, mercury-retrograde tables) | Kept; each becomes an exposure-event emitter (§6 item 6) |
| `PersonalAIAssistant` + `AIMemory` (confidence/decay/cooldown) | Concepts absorbed into EvidenceEngine + Insights; the conversational surface is kept as the presentation layer over engine output |
| `CloudAIService` (BYOK OpenAI/Anthropic) | Kept as fallback parser; primary parsing moves to on-device Foundation Models (§6.2) |
| `HealthKitManager` (sleep-only read) | Replaced by full ingestion + backfill (§5) |
| Known stubs: `QuickNoteView` save, `ProtocolFetchService` fake data, `TreatmentAnalysis.calculateCorrelation` placeholder, duplicated container schema | Deleted or rebuilt during re-foundation; none are load-bearing |

**Rebrand before App Store:** "Food Intolerances" (`com.leo.symptomtracker`) is too narrow.
New name chosen before the store listing is created, not after.

## 4. Data model (Phase 0)

GRDB with `DatabaseMigrator`; migration v1 creates three core tables plus indexes on
`(category, timestamp)`, `(objectID, timestamp)`, and relationship endpoints.

```swift
// health_events — everything that happens is an event
struct HealthEvent {
    var id: UUID
    var timestamp: Date              // stored UTC
    var timezoneID: String           // IANA id at capture time — lag math must survive travel
    var endTimestamp: Date?          // durations (sleep, exercise)
    var category: EventCategory      // food, medication, supplement, peptide, symptom,
                                     // sleep, exercise, vitals, lab, mood, stress, stool,
                                     // bodyMetric, cycle, illness, environment, travel,
                                     // doctorVisit, protocolMarker, note
    var subtype: String?             // "headache", "run", "ferritin"
    var objectID: UUID?              // FK -> health_objects
    var value: Double?               // severity 1–10, dose, duration min, lab value…
    var unit: String?
    var source: EventSource          // manual, photo, voice, healthKit, healthExportFile,
                                     // labImport, weatherAPI, appIntent
    var confidence: Double           // 0–1 parse quality (not evidence confidence)
    var metadata: Data?              // JSON for category-specific fields
    var attachmentPath: String?
    var createdAt: Date
    var deletedAt: Date?             // soft delete only
}

// health_objects — persistent things events reference
struct HealthObject {
    var id: UUID
    var kind: ObjectKind             // medication, supplement, peptide, food, allergen,
                                     // doctor, labTest, condition, protocol, experiment,
                                     // location, device
    var name: String
    var normalizedName: String       // lowercased, brand-stripped, for dedup
    var metadata: Data?              // dose forms, ingredients, reference ranges,
                                     // peptide: route/cycle/vial (§6.4)
    var isArchived: Bool
    var createdAt: Date
}

// relationships — the moat
struct Relationship {
    var id: UUID
    var fromObjectID: UUID?          // one of from/fromCategory set
    var fromCategory: String?
    var toObjectID: UUID?
    var toCategory: String?
    var type: RelationshipType       // possibleTrigger, improves, worsens, noEffect, precedes
    var evidenceCount: Int
    var contradictionCount: Int
    var confidence: Double           // computed by EvidenceEngine, never by LLM
    var strength: Double?            // avg effect size
    var lagHours: Double?
    var firstSeen: Date
    var lastSeen: Date
    var lastRecomputed: Date
    var status: RelStatus            // candidate, active, decayed, confirmedNoEffect, userDismissed
    var aiExplanation: String?       // generated text, regenerated on demand
}
```

Changes from the original plan's schema: added `timezoneID`; added `peptide`, `cycle`,
and `illness` categories; added `healthExportFile` and `appIntent` sources.

Supporting tables (created in the phase that needs them): `insights`, `experiments`,
`data_quality_snapshots`.

Repositories: `EventStore`, `ObjectStore`, `RelationshipStore` — async CRUD + range
queries. Object dedup on `normalizedName` at insert. Soft-delete everywhere. ~20 unit
tests including migration tests, plus the migrator from the SwiftData store.

## 5. Data bootstrap — eliminating the cold start

The engine needs weeks of data before it can say anything; new users won't wait. Solution:
import history at onboarding so the first manually-logged symptom correlates against
months of existing exposure data within days.

1. **HealthKit backfill (primary, Phase 1).** On permission grant, batch-import
   historical samples — default 1 year, user-expandable to all: sleep analysis, workouts,
   steps, heart rate, resting HR, HRV, respiratory rate, body mass, blood pressure,
   **menstrual cycle**, mindfulness, dietary entries, and existing HealthKit symptom
   samples. Then live ingestion via `HKObserverQuery` background delivery. Everything
   that syncs *into* Apple Health — **Oura ring, Apple Watch, Whoop, Garmin, Withings,
   Eight Sleep, MyFitnessPal** — arrives through this single pipe with no per-vendor work.
2. **Apple Health export file (`export.zip`) import (Phase 1).** Streaming parse of
   `export.xml` for users migrating devices or wanting history beyond granted scopes.
   Same event mapping and dedup keys as live HealthKit, so the two compose.
3. **Universal lab-document import (Phase 4).** PDF / photo / CSV → LLM extraction to
   `(analyte, value, unit, referenceRange, collectedAt)` → user-confirm screen → `lab`
   events + trend charts. One pipeline covers **Ornament exports**, Labcorp/Quest PDFs,
   and clinic printouts — no per-vendor parsers. Opportunistic add: HealthKit Clinical
   Records (FHIR) for users whose providers are in Apple's network.
4. **Oura direct API (Phase 7+, optional).** OAuth integration only for data HealthKit
   doesn't carry: readiness score, sleep score, **temperature deviation** (illness and
   cycle signal). v1 explicitly gets Oura via HealthKit instead.
5. **Dedup and provenance.** Dedup key: `(category, subtype, timestamp)` — timestamps
   rounded to the minute for point events, overlapping intervals merged for duration
   events (sleep, workouts) — with source priority live-HealthKit > export-file >
   manual re-entry. Every imported event
   keeps its `source` so the engine and UI can show provenance.

## 6. Capture (Phase 1)

Target: a full day logged in under 60 seconds; a repeat log in ≤3 taps.

1. **Quick-log sheet:** one screen, most-frequent items as one-tap chips learned from
   history, severity slider for symptoms. Port of `QuickSymptomLogger` + body map.
2. **Voice capture (flagship):** "had eggs and coffee at 8, headache started around 11,
   took 400mg ibuprofen" → structured draft events → confirm screen. Parsing runs
   **on-device via Apple Foundation Models (`@Generable` guided generation, iOS 26)** —
   free, offline, private. BYOK cloud LLM (existing `CloudAIService`) is the fallback for
   long or ambiguous parses. Parsing contract (both engines): JSON only —
   `{"events":[{"category":"food","subtype":"eggs","timestamp_hint":"08:00","value":null,"objectName":"eggs","confidence":0.9}]}` —
   parser survives missing fields and rejects hallucinated categories.
3. **Photo capture:** meal photo → vision LLM (cloud, opt-in) → `[FoodItem]` draft →
   confirm → events with per-event parse confidence.
4. **App Intents:** one framework yields Siri ("log a headache, severity 6"), Shortcuts,
   interactive home/lock-screen widgets, and Action-button logging. In Phase 1, not
   deferred — capture friction is risk #1, and these are the lowest-friction surfaces.
5. **Peptide & medication tracking:** peptide objects carry route (subQ/IM/oral/
   nasal), injection-site rotation, on/off cycle schedule; vial inventory = reconstitution
   volume ÷ dose = doses remaining → reorder alert (extends existing `CabinetItem` logic).
   Tracking user-entered doses is fine; the app never *suggests* doses.
6. **Environmental auto-capture:** daily weather/pressure (existing OpenWeatherMap
   service), pressure-drop detection, moon phase, season, mercury retrograde — each emits
   `environment` events. These are ordinary exposures to the engine; if the data shows no
   association ("no association found between Mercury retrograde and your symptoms"),
   the app says so. Honest null results are a feature. Not marketed as science.
7. **Unified timeline:** reverse-chronological, category color-coding, day grouping,
   filter chips, tap-to-edit, inline severity sparklines per day.

## 7. Evidence Engine (Phase 2)

Deterministic module mining relationships nightly and on-demand; all math on-device.

For each candidate pair (exposure X → outcome Y), X ∈ {foods, meds, supplements, peptides,
sleep <6h, high stress, weather pressure drops, cycle phase, …}, Y ∈ {symptoms, mood, energy}:

1. **Windowed co-occurrence:** count outcomes within a per-category lag window after
   exposure (0–24h food→GI, 0–48h supplement→energy; config-driven). Lag math is
   timezone-aware via `timezoneID`.
2. **Base-rate comparison:** P(Y | X in window) vs P(Y | no X). Require ≥5 exposures and
   ratio ≥1.5 to create a candidate.
3. **Confidence (0–1):**
   `sigmoid(w1·log(evidenceCount) + w2·consistency − w3·contradictionRate − w4·confounderPenalty − w5·staleness)`
   — confounder penalty rises when another exposure co-occurs >60% (surfaced as "can't
   tell these apart yet — try one without the other"). **Cycle phase and illness events
   are always in the confounder set.** Staleness drives decay; below 0.3 → `decayed`
   (hidden from Insights, kept in history).
4. **Negative learning:** an intervention with ≥20 exposures over ≥90 days and effect
   ratio <1.2 both directions → `noEffect`: "No measurable effect of Vitamin D on your
   tracked outcomes after 120 days." This is a headline feature, and it is exactly what
   the design-partner clinic wants to know about its protocols.
5. **False-positive control:** cap new surfaced candidates at 3/week ranked by
   confidence × novelty; everything else stays internal. High confidence (>0.75) is
   reachable only via experiment/rechallenge confirmation (Phase 4) — observational
   evidence alone plateaus below it.

**Insights UI:** card per active relationship — plain-language claim, confidence %,
evidence count, avg effect, last seen, and a non-negotiable **Evidence drill-down**
listing the actual event pairs, each tappable. Actions: "Dismiss," "Not convinced —
suggest an experiment." The LLM's only role: turning computed stats into one friendly
paragraph. Numbers come from the engine, never the model.

**Safety red-flags (Phase 2, cheap, mandatory):** a static table of red-flag patterns
(e.g., chest pain, anaphylaxis-pattern reactions, self-harm ideation) triggers a
"seek care now" interstitial instead of correlation analysis. Ethics requirement and an
App Store review asset.

**Synthetic-data harness (built in Phase 0, used forever):** generator producing fake
histories with *planted* correlations (e.g., dairy→bloating, 12h lag, 70% consistency)
plus noise; tests assert the engine finds planted signals and rejects noise. Scoring
weights are tuned against this harness. Without it the engine's numbers are hope, not
evidence.

## 8. Data quality & missions (Phase 3)

- Nightly `data_quality_snapshot`: per-category coverage over trailing 30 days, gap
  detection, lab staleness.
- **Health Confidence screen:** overall data-quality % + per-category bars.
- **Missing-data prompts** wired into Insights: when a candidate is blocked by coverage,
  say exactly that, with a one-tap fix ("Enable a 9am meal reminder?").
- **Health Missions:** template missions from quality gaps + candidates ("Log sleep,
  fatigue, and exercise for 14 days to resolve Sleep → Fatigue"). Progress ring, no
  streak punishment; completion recomputes the target immediately and shows before/after
  confidence.

## 9. Experiments & clinic protocols (Phase 4)

- `Experiment` model: question, target relationship (optional), phases
  (baseline / intervention / washout / rechallenge) with durations and adherence
  (`protocolMarker` events).
- Guided wizard, sane defaults (14/21/7/3 days), templates: elimination (gluten, dairy),
  addition (magnesium, creatine), behavior (sleep schedule).
- Daily one-tap adherence check-in + auto-pull of outcome events.
- `EvidenceEngine.analyzeExperiment()` compares outcome rates/severity across phases;
  experiment evidence weighted ~3× observational.
- **Suggested rechallenges** when an observational relationship plateaus at 0.5–0.75.
- **Clinic protocols = imported experiments.** A clinic-authored protocol (peptide,
  schedule, duration, target outcomes) is shared as a QR/share code; importing it
  pre-configures an experiment. The app tracks adherence + outcomes and generates a
  structured per-protocol outcome report. No backend: the artifact is a signed JSON file.
- **Lab-document import pipeline** lands here (§5.3) — clinics order labs; results feed
  protocol outcome reports.

## 10. Hero features (Phase 5)

1. **"What worked before?" (homepage hero).** Tap a current symptom → engine finds past
   episodes (subtype match, severity-weighted) → ranks interventions taken during those
   episodes by subsequent improvement vs. episodes without them. "In 8 past migraine
   episodes: magnesium + dark room preceded improvement within 4h in 6 of them."
   Fully evidence-linked, historical phrasing only.
2. **Doctor / Practitioner Report (PDF).** Date-range picker → PDF: symptom timeline
   chart, med/supplement/peptide list with adherence, top insights with confidence +
   evidence counts, lab trend tables, experiment and clinic-protocol outcome summaries.
   Boring, clinical layout — that's a feature. This closes the clinic loop with zero
   backend: the patient taps "Share report with Dr. X."
   Every report embeds a **versioned, signed, machine-readable JSON payload** alongside
   the human-readable PDF, so a clinic can aggregate outcomes across patients today by
   importing report files locally, and a future practitioner portal can ingest the same
   files unchanged (§12).

## 11. Launch readiness (Phase 6)

- **Encrypted CloudKit backup** (private database or encrypted file backup). Ships
  *before* public release — data loss on a health app is unrecoverable churn. Full
  multi-device sync stays deferred.
- **Full data export** (JSON + CSV): trust feature and the escape hatch that keeps
  Android/web viable later.
- Rebrand, App Store listing (wellness language per `V1_SCOPE.md` rules), privacy
  nutrition labels (on-device storage, opt-in cloud AI, no tracking), TestFlight with the
  clinic's patients as the first cohort, then App Store.

## 12. Platform strategy & practitioner access

Decision (2026-07-04): **the phone stays the hub.** Apple Health has no web API —
sensor data (Apple Watch, Oura-via-HealthKit, sleep, cycle) is readable only by an app
on the device, so the iOS app is the mandatory gateway regardless of where viewing
happens. Analysis stays on-device, where the data is.

**Audiences and how each is served:**

| Audience | v1 | Later |
|---|---|---|
| iPhone users | Full app | — |
| Older users / big-screen readers (Apple devices) | Doctor Report PDF (print, email), Dynamic Type support | iPad + Mac apps via SwiftUI multiplatform; the encrypted CloudKit backup upgrades to sync (fast-follow after launch) |
| Windows-desktop users | PDF reports + CSV/JSON export | Read-only web viewer, post-revenue, riding the practitioner-portal backend |
| Android users | Not served in v1 | Android app as a client of the practitioner-portal backend; Health Connect as its sensor gateway; EvidenceEngine port validated by the synthetic-data harness used as a cross-platform conformance suite |
| Practitioners | Level 1 below | Levels 2–3 below |

Action item: ask the design-partner clinic for their patients' iOS/Android split before
fixing Phase 7+ ordering — a large Android share pulls the backend forward.

Note on capture for older users: voice logging on the phone ("had eggs at 8, headache
at 11") is lower-friction than desktop typing. Desktop matters mostly for *reading*,
which PDF and iPad/Mac cover.

**Practitioner access — three levels, consent-first at every level:**

1. **Level 1 (Phases 4–5, no backend).** Patient-initiated sharing of outcome reports:
   PDF for humans + the embedded signed JSON for machines (§10). The clinic aggregates
   across patients by importing report files locally. The developer never touches
   patient data — no HIPAA exposure.
2. **Level 2 (optional bridge).** End-to-end-encrypted share links / report inbox for
   derived reports only, retention-limited. First point of compliance exposure; build
   only if the clinic finds file-sharing too clunky during the pilot.
3. **Level 3 (Phase 7+, the paid clinic product).** Practitioner web dashboard: patient
   roster, longitudinal views, cross-patient protocol outcomes ("peptide X: 12 patients,
   8 logged improvement"). Web is the right platform here — clinic staff live in
   browsers. Requires backend, BAA + HIPAA security review, audit logs, and consent
   revocation.

Consent principles at all levels: sharing is patient-initiated, explicitly scoped
(date range + categories), visible in the report itself, and logged on device.

## 13. Explicitly deferred (Phase 7+, post-revenue)

- Practitioner portal Levels 2–3 and the backend that carries them (§12).
- Android app and read-only web viewer (§12).
- Community aggregates ("340 users tried this protocol; 62% logged improvement") —
  needs backend, accounts, moderation, k-anonymity thresholds. The clinic is the
  near-term community.
- Prediction engine (historical phrasing only, built on a mature Phase 2 engine).
- Oura/Whoop direct APIs, CGM, air quality, FHIR import — each is just a new
  `EventSource` adapter; no schema change.
- Apple Watch app (App Intents already cover quick capture in Phase 1).

## 14. Business model

- **Free forever:** all capture, timeline, medicine cabinet, reminders.
- **Pro (~$7.99/mo or ~$59.99/yr):** Evidence Engine insights, experiments, "what worked
  before," reports, data-quality missions. Comparable apps (Bearable, Visible, Guava,
  mySymptoms) sit at $30–70/yr; none has an explainable evidence engine, honest null
  results, or a practitioner loop.
- **Clinic (design partner now, paid later):** free clinic features for the
  functional-medicine practice in exchange for protocol/report design input, pilot
  patients, and testimonials. Practitioner-driven installs ("install this so I can see
  if the protocol works") are zero-CAC distribution. Post-validation: per-patient/month
  practitioner dashboard ($15–30 range).
- **Success gates:** median time-to-first-insight <7 days (backfill makes this
  possible); day-30 logging retention; one clinic pilot that renews.

## 15. Module layout

```
Core/
  Database/        // GRDB setup, migrations, repositories, SwiftData migrator
  Models/          // HealthEvent, HealthObject, Relationship, Experiment
  EvidenceEngine/  // pure functions: mining, scoring, decay, experiment analysis
  Capture/         // HealthKitIngestor, ExportFileImporter, PhotoParser,
                   // VoiceParser (FoundationModels + cloud fallback), QuickLog, AppIntents
  LLM/             // parsing contracts, explanation generation, CloudAIService
  Import/          // lab-document pipeline (Phase 4)
Features/
  Timeline/  Insights/  Missions/  Experiments/  ClinicProtocols/
  WhatWorked/  DoctorReport/  DataQuality/  Cabinet/
Shared/UI/
```

## 16. Phase summary & sequencing

| Phase | Deliverable | Est. |
|---|---|---|
| 0 | GRDB event graph, repositories, SwiftData migrator, synthetic-data harness | 2–3 wks |
| 1 | Capture: quick-log, voice (on-device LLM), photo, App Intents, HealthKit backfill + export.zip import, unified timeline, peptide/cabinet port | 3–4 wks |
| 2 | Evidence Engine v1 + Insights + red-flag safety | 3–4 wks |
| 3 | Data quality + missions | 2 wks |
| 4 | Experiments + clinic protocol codes + lab import | 3–4 wks |
| 5 | "What worked before?" + Doctor Report PDF | 2–3 wks |
| 6 | Encrypted backup, export, rebrand, TestFlight → App Store | 2–3 wks |

Post-launch fast-follow: iPad + Mac big-screen apps riding the CloudKit sync upgrade
(§12) — before any backend work.

## 17. Non-functional requirements & open items

**Binding NFRs:**

- **Positioning boundary:** the app is a *navigator*, not an *advisor*. It describes
  patterns, reports what historically worked for this user, proposes experiments, and
  prepares doctor-visit material. It never diagnoses, recommends treatments, or suggests
  doses (§2.5). All "advisory"-flavored features must pass this test.
- **Accessibility:** Dynamic Type throughout, VoiceOver labels on all interactive
  elements, generous tap targets — older users are a core audience, not an edge case.
- **Performance budgets:** 1-year HealthKit backfill completes in ~2 min on a mid-range
  device with visible progress; nightly mining < 30 s; cold launch < 1.5 s; DB remains
  responsive at 100k+ events.
- **Notification hygiene:** per-category toggles, quiet hours, adaptive frequency (no
  prompts while the user is actively logging), privacy-mode lock-screen text (exists
  today — keep).
- **Data hygiene:** user-facing duplicate-object merge tool (normalizedName dedup won't
  catch everything), full edit of history, soft delete only.
- **Units & locale:** metric/imperial per user setting; English-only v1.

**Open decisions (resolve before the phase that needs them):**

| Decision | Recommendation | Needed by |
|---|---|---|
| Telemetry vs. "no analytics" promise | Privacy-safe crash reporting only; no usage analytics | TestFlight (Phase 6) |
| Cloud LLM funding model | On-device parsing free for all; developer-funded meal-photo vision as Pro perk with monthly quota + no-retention API terms | Phase 5–6 |
| Caregiver/household logging (family logs for an older user) | Out of v1; ask the clinic whether their patients need it | Post-launch |
| App name + visual identity | Naming exercise alongside the UI design pass | Phase 6 listing |
| Legal docs (privacy policy, terms, disclaimer copy, hosting site) | Draft during Phase 5 | TestFlight (Phase 6) |
| Clinic patients' iOS/Android split (§12) | Ask the practice now | Phase 7 ordering |

Each phase ships something usable and is scoped to hand to a coding agent as a
self-contained work order (guiding decisions + schema + the phase section). Per phase,
require: compiling code, unit tests for all EvidenceEngine math, schema changes only via
numbered GRDB migrations, no user-facing causal language. Hand-review the migrator and
the scoring function — the two places an agent most likely goes wrong.
