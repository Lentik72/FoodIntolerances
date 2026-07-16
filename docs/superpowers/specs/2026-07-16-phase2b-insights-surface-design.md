# Phase 2B — Insights Surface — Design

**Date:** 2026-07-16
**Status:** Approved (decisions made interactively with Leo)
**Depends on:** Phase 2A engine (merged `f917d59`) — `EvidenceEngine.recompute`/`evidence(for:)`, `RelationshipStore`, `Relationship` (type, status, confidence, evidenceCount/contradictionCount, strength, lagHours, firstSeen, fromObjectID/fromCategory, toSubtype)
**Relates to:** `2026-07-03-health-graph-design.md` §7 (Insights UI), `2026-07-04-ui-design.md` §2/§4/§6 (screen map, card anatomy, visual language)
**Scope:** The Insights reading surface over 2A's `relationships`, plus recompute scheduling. **No** red-flag interstitial (next cycle), **no** experiments/"Test it" (Phase 4), **no** missions/needs-more-data (Phase 3), **no** nightly `BGTask`/push (extension points).

---

## 1. Problem

Phase 2A mines the event graph into `relationships` (exposure→outcome edges with confidence, type, per-exposure counts) but nothing surfaces them: the Insights tab is a placeholder showing per-category event counts, and nothing ever calls `EvidenceEngine.recompute`. Phase 2B turns those edges into the cards, dots, and drill-down the user reads — the payoff of the whole engine — and decides when the engine runs.

## 2. Decisions (Leo, 2026-07-16)

| Decision | Choice |
|---|---|
| Scope shape | **Insights surface only** — one cohesive spec (read-mostly presentation over one data source). Red-flag safety is the committed **next** cycle (a distinct capture-time flow); "Test it" → Phase 4; missions → Phase 3 |
| Scheduling | **`InsightsRefreshCoordinator`** — a single owner that calls `recompute` on app-foreground + Insights-open + post-capture, **debounced**. Nightly `BGTask` is a documented extension point, not built |
| "3 new/week" cap | **Throttle the "New" highlight, never hide active edges.** All `active` edges are always listed; ≤3/week get the "New" treatment (firstSeen ≤ 7d, ranked confidence × novelty). With 2A's precision gates, actives are already sparse and real, so the cap limits *notification noise*, not visibility |
| Architecture | **Pure phrasing/feed/surfacing core in `HealthGraphCore`**; thin async ViewModel + SwiftUI views + one coordinator in the app |
| Drill-down navigation | Evidence row → the existing `EventDetailView` (reuse), not a cross-tab Timeline scroll |

**Rejected:**
- **Bundling the red-flag interstitial** — it's a safety-critical *capture-time* takeover coupled to the Capture flow with a different trigger and owner; mixing it with the reading surface tangles two unrelated units. Separate cycle, sequenced next (mandatory, small).
- **Gating visibility to top-3-new (literal §7)** — with sparse high-precision actives it would *hide* genuine findings the user has data for ("why isn't X here?") and needs per-week promotion bookkeeping.
- **Splitting the surface finer** (list / drill-down / explanations as separate cycles) — they are mutually dependent parts of one read-mostly surface (same shape as Phase 1B's Timeline, which was one spec); fragmenting adds round-trips for no isolation benefit.
- **A disabled "Test it" placeholder button** — YAGNI; omit the action, design the action row to be extensible so Phase 4 slots it in without reworking the card.

## 3. Architecture

Clean seam, mirroring 2A: **pure logic in the package, thin shell in the app.**

### 3.1 Core (`HealthGraphCore/Sources/HealthGraphCore/Insights/`, pure — no UI, no DB)

- `InsightPresentation.swift` — value types (all with **`public init`s** — the app module constructs them across the package boundary): `InsightCardModel { id, claim, exposureCategory, badge, countLine?, recentDots: [Bool], subline?, isNew, kind }`, `BadgeTier { earlySignal, moderate, strong }`, `InsightSection { active, noEffect, archive }`, `InsightsFeedModel`.
  - **`recentDots`** is the chronological hit/miss sequence of the **last ~8 exposures** (`true` = outcome followed), NOT the lifetime total — matching UI §4 ("your last 8 dairy days"). `countLine` is the natural-language preamble ("In 6 of your last 8 Dairy logs, bloating followed"). For `noEffect`/archive cards `recentDots` is empty and `countLine`/`subline` are nil (no dot alarm, even tone).
  - The card carries the **exposure's `EventCategory`** so the view draws the app's **`CategoryStyle` icon (SF Symbol)** — a deliberate substitution for §4's emoji, chosen for consistency with the rest of the app's icon system (recorded as an approved deviation).
- `InsightPhrasing.swift` — deterministic functions from a **resolved** relationship → claim, `BadgeTier`, `subline` (trigger: lag + severity; **`improves`: protective, no "+severity"; `noEffect`: nil**), and `countLine` (from the recent window). Templated; **no causal language** ("associated with", "followed", "we observed" — never "causes/triggers-for-certain"). `noEffect` claim is null-tone ("No measurable effect of Vitamin D on your tracked outcomes"), NOT a directional "X → Y".
- `InsightsFeed.swift` — `build(inputs: [ResolvedRelationship], now: Date, config: InsightsConfig) -> InsightsFeedModel`: sections edges by status, ranks each section (active: confidence desc then recency; noEffect: recency; **all sorts carry a stable `id` tiebreak** so output is deterministic on ties), and computes the **"New" flags** (≤ `newPerWeek` edges with `firstSeen ≥ now − 7d`, ranked by `confidence × novelty`). Pure and unit-testable.
- `ResolvedRelationship` — a `Relationship` plus its resolved exposure label (object name / derived-kind phrase), outcome label, exposure `EventCategory`, and — for **active** edges — `recentOutcomes: [Bool]` (last-~8 chronological followed flags, filled by the app from `evidence(for:)`; empty for others). The app builds these after a DB name-resolution + per-active-card evidence pass.
- `RecomputePolicy.swift` — the **pure** debounce decision `shouldRecompute(lastRunAt:, lastEventWatermark:, now:, currentWatermark:, minInterval:) -> Bool` (in core so it's package-testable; the app coordinator wraps it — §6).
- `InsightsConfig` — `newPerWeek = 3`, `newWindowDays = 7`, `recentDotCount = 8`, badge thresholds (Early 0.3–0.5 / Moderate 0.5–0.75 / Strong > 0.75).

### 3.2 App (`Views/HealthOS/Insights/`)

- `InsightsViewModel` (`@MainActor`, observable) — fetch relationships via `RelationshipStore.all()`; resolve object names via `ObjectStore.object(id:)`; for each **active** edge, load its recent window via `EvidenceEngine.evidence(for:)` and take `pairs.suffix(recentDotCount)` → `recentOutcomes` (this is the per-active-card query the dots need; sparse actives make it cheap); build `[ResolvedRelationship]` → `InsightsFeed.build`; expose the model. Actions: **dismiss** (capture prior status into a `pendingUndo`, set `.userDismissed`, `save`, reload) and **undoDismiss** (restore the captured prior status, `save`, reload) — surfaced with an undo toast (no confirm dialog, the app convention). Refresh driven by the coordinator + `CaptureCoordinator.lastCaptureAt`.
- `InsightsView` — replaces `InsightsPlaceholderView`; renders the sections; empty state (§5).
- `InsightCardView`, `InsightBadgeView`, `EvidenceDotsView` — small views over `HealthTheme` tokens (`amber` hits, `dotMiss` misses, serif claim, card tokens).
- `InsightDetailView` — drill-down; on appear calls `EvidenceEngine.evidence(for:)`; renders the itemized list + confounders + raw numbers; rows push `EventDetailView(event:viewModel:)` (the existing detail is coupled to a `TimelineViewModel`, so the push site constructs one over the shared DB; the detail falls back to the passed event when its id isn't in that VM's slice).
- `InsightsRefreshCoordinator` — the single `recompute` owner (§6).

### 3.3 Data flow

`foreground / Insights-open / post-capture → coordinator (debounced) → recompute → relationships updated → ViewModel reload → resolve names → InsightsFeed.build → InsightsView`. Dismiss and drill-down read/write the same stores.

## 4. Insight cards & drill-down

**Card** (UI-design §4):

```
[MODERATE]                              badge: tier from confidence
🩺 Dairy → bloating                     claim (serif) + CategoryStyle icon (SF Symbol)
In 6 of your last 8 Dairy logs,
bloating followed:   ● ● ○ ● ● ● ○ ●    countLine + recentDots: the last ~8 exposures in
usually within ~12h · avg severity +2.1   CHRONOLOGICAL order; filled = followed (amber),
[All evidence →]              [Dismiss]   hollow = not (dotMiss). Extensible action row.
```

- The dot row is the **last ~8 exposures in chronological hit/miss order** (`recentDots`), NOT the lifetime total — a lifetime `dairy→bloating` has 100+ exposures. The ViewModel fills `recentOutcomes` from `evidence(for:).pairs.suffix(recentDotCount)` per **active** card at load (a per-card query; cheap because precision-gated actives are sparse — this supersedes the earlier "no query" idea). `noEffect`/archive cards render **no dots** (empty `recentDots`).
- `improves` cards phrase protectively ("Magnesium → fewer migraines"), no "+severity" subline. **`noEffect` cards use a null-tone claim** ("No measurable effect of Vitamin D on your tracked outcomes"), no dots, no severity — an even-tone win, never a directional "X → Y".
- Icon is the **`CategoryStyle` SF Symbol** for the exposure's category (approved substitution for §4's emoji — consistency with the app).
- Badge: Early 0.3–0.5 / Moderate 0.5–0.75 / Strong > 0.75. Strong is reachable only via Phase-4 experiments, so 2B tops out at Moderate — honest.

**`InsightPhrasing` (pure, tested):** claim = `<exposure> → <outcome>` (trigger) / `<exposure> → fewer <outcome>` (improves) / null-tone (noEffect); `subline` = `lagHours` ("within ~Xh") + `strength` ("avg severity +N.N") for triggers only (nil for improves/noEffect); `countLine` = "In K of your last N `<exposure>` logs, `<outcome>` followed" from the recent window. Unit tests cover trigger / improves / noEffect wording and the **no-causal-language invariant** (forbidden words never appear).

**`InsightDetailView` (drill-down)** — on appear, `evidence(for:)` yields the itemized pairs + confounders:
- Each exposure→outcome row (incl. **misses**): date, filled/hollow, outcome value → tap pushes `EventDetailView(event:viewModel:)` for the event (`evidence(for:)` returns the event IDs; the push site builds a `TimelineViewModel` over the shared DB).
- **Confounder warnings** from `evidence.confounders` ("coffee was present on most of these days — can't tell these apart yet; try one without the other").
- **Raw numbers** at the bottom (confidence %, evidence/contradiction counts, median lag, avg effect) for power users and the clinic.

## 5. Insights screen structure

Top to bottom:

1. **Active patterns** — all `active` edges (confidence desc, then recency). The ≤3 "New"-flagged ones sort to the top with a badge.
2. **No effect** — all `confirmedNoEffect` edges, presented as *wins* with an even tone (headline honest-null feature, §7).
3. **Archive** (collapsed) — `decayed` + `userDismissed`; nothing lost, dismissed insights recoverable.

**Empty state** (no active or no-effect yet): show **"what the engine is watching"** — the per-category event-coverage strip `InsightsPlaceholderView` shows today, plus one honest line ("Keep logging — patterns appear here once there's enough signal"). The placeholder's content is *demoted to the empty state*, not deleted, so pre-insight weeks feel alive (UI §8).

**Deferred (rationale in-spec):** the **Needs-more-data** section is the Phase-3 missions engine; showing `candidate` edges without the one-tap mission fix is a half-feature, so 2B omits it — candidates stay internal (as 2A designed).

## 6. Recompute scheduling — `InsightsRefreshCoordinator`

The single owner of when the engine runs (nothing else calls `recompute`):

- **Triggers:** app foreground, Insights-tab appear, and post-capture (reusing `CaptureCoordinator.lastCaptureAt`).
- **Debounce:** skip if a recompute ran within `minRecomputeInterval` (default 15 min) OR the event watermark is unchanged. Watermark = `EventStore.count` (adds/deletes trip it immediately). An in-place edit/correction keeps the same count and is caught by the 15-min interval fallback — an accepted v1 limitation; a content watermark (max `createdAt` / a change token) is a cheap later add.
- **The `isRunning` guard is set synchronously (no `await` between the guard-check and the set), with a `defer` reset**, so concurrent triggers (appear + foreground + post-capture all firing at once) cannot start overlapping recomputes.
- Runs `recompute(asOf: Date())` off the main actor; on completion signals the ViewModel to reload. Feed reload is decoupled from whether recompute ran (a skipped recompute still reloads existing relationships).
- **`scheduleBackgroundRecompute()`** exists as an unimplemented, clearly-marked extension point so a nightly `BGTask` is a localized add later.
- The **decision logic lives in the core `RecomputePolicy.shouldRecompute(...)` (pure, package-tested)**; the app coordinator only owns the triggers, the stored watermark, and the off-main-actor `recompute` call.

`Date()` lives only in the coordinator (the trigger layer), never inside the engine — 2A's determinism invariant is preserved.

## 7. Non-functional requirements

- **Accessibility:** Dynamic Type throughout (older audience is core); VoiceOver labels on cards/dots/badges (a dot row reads "6 of 8 followed"); generous tap targets. Layouts survive XXL.
- **No causal language** anywhere in phrasing — spec invariant, unit-tested.
- **Performance:** the feed build loads each **active** card's recent window via `evidence(for:)` once at load (sparse, precision-gated actives → a handful of calls, off the main actor); no-effect/archive cards need none. Cards then render from that cached window (no per-scroll query). Recompute is debounced so opening Insights is instant when data is unchanged.
- **Light + dark** via existing `HealthTheme` tokens; both ship.
- **Determinism:** `now`/`Date()` only in the coordinator; core phrasing/feed are pure.

## 8. Testing

- Core unit tests: `InsightPhrasingTests` (claim/subline/badge/countLine for trigger, `improves`, **`noEffect` null-tone**; the no-causal-language invariant), `InsightsFeedTests` (sectioning; the ≤3 "New" throttle by firstSeen + confidence×novelty; ordering with the stable tiebreak; archive), `RecomputePolicyTests` (interval elapsed, watermark changed/unchanged).
- App-side: `InsightsViewModel` load / **dismiss + undoDismiss (restore)** / refresh against an in-memory DB seeded by the synthetic harness (a mined corpus drives a realistic feed, incl. an active card's `recentDots`).
- A `/verify` pass driving the real Insights tab (synthetic-seeded store) before completion.

## 9. Out of scope (each has a home)

- **Red-flag "seek care now" interstitial** → the committed next cycle (capture-time safety flow).
- **"Test it" / experiments** → Phase 4 (action row extensible).
- **Needs-more-data / missions** → Phase 3.
- **Nightly `BGTask`, push notifications** → post-2B extension points; the "New" signal is in-app.
- **Home "newest insight teaser"** → the surfacing selection is built + exposed; Home consumes it in a thin follow-on.
- No change to the engine, extraction, scoring, or migrations — 2B is read-only over `relationships` (plus the dismiss status write, which recompute already preserves).

## 10. Module layout (delta)

```
HealthGraphCore/Sources/HealthGraphCore/Insights/     // NEW (pure)
  InsightPresentation.swift   // value types (InsightCardModel, BadgeTier, InsightsFeedModel, ResolvedRelationship, InsightsConfig)
  InsightPhrasing.swift       // claim / emoji / badge tier / subline; no-causal-language rule
  InsightsFeed.swift          // sectioning + ranking + ≤3/week "New" selection
  RecomputePolicy.swift       // pure shouldRecompute(...) debounce decision
HealthGraphCore/Tests/HealthGraphCoreTests/
  InsightPhrasingTests.swift  InsightsFeedTests.swift  RecomputePolicyTests.swift

Views/HealthOS/Insights/                              // app
  InsightsView.swift          // replaces InsightsPlaceholderView
  InsightsViewModel.swift
  InsightCardView.swift  InsightBadgeView.swift  EvidenceDotsView.swift
  InsightDetailView.swift     // drill-down
  InsightsRefreshCoordinator.swift
```
