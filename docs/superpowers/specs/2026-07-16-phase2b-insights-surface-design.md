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

- `InsightPresentation.swift` — value types: `InsightCardModel { relationshipID, claim, emoji, badge, dots(filled,hollow), subline, isNew, kind }`, `BadgeTier { earlySignal, moderate, strong }`, `InsightSection { active, noEffect, archive }`, `InsightsFeedModel`.
- `InsightPhrasing.swift` — deterministic functions from a **resolved** relationship (names already looked up) → claim, emoji, `BadgeTier`, and subline. Templated; **no causal language** ("associated with", "followed", "we observed" — never "causes/triggers-for-certain"). Handles trigger / `improves` (protective wording) / `noEffect` (even-tone win).
- `InsightsFeed.swift` — `build(inputs: [ResolvedRelationship], now: Date, config: InsightsConfig) -> InsightsFeedModel`: sections edges by status, ranks each section (active: confidence desc then recency; noEffect: recency), and computes the **"New" flags** (≤ `newPerWeek` edges with `firstSeen ≥ now − 7d`, ranked by `confidence × novelty` where novelty falls off with age-since-firstSeen). Pure and unit-testable.
- `ResolvedRelationship` — a `Relationship` plus its resolved exposure label (object name / derived-kind phrase) and outcome label; the app builds these after a DB name-resolution pass.
- `RecomputePolicy.swift` — the **pure** debounce decision `shouldRecompute(lastRunAt:, lastEventWatermark:, now:, currentWatermark:, minInterval:) -> Bool` (in core so it's package-testable; the app coordinator wraps it — §6).
- `InsightsConfig` — `newPerWeek = 3`, `newWindowDays = 7`, badge thresholds (Early 0.3–0.5 / Moderate 0.5–0.75 / Strong > 0.75).

### 3.2 App (`Views/HealthOS/Insights/`)

- `InsightsViewModel` (`@MainActor`, observable) — fetch `relationships(status:)` for active/noEffect/decayed/dismissed via `RelationshipStore`; resolve object names via `ObjectStore.object(id:)`; build `[ResolvedRelationship]` → call `InsightsFeed.build`; expose the model. Actions: **dismiss** (fetch → set `status = .userDismissed` → `save` → reload, with undo toast), **reload**. Refresh driven by the coordinator + `CaptureCoordinator.lastCaptureAt` (already used elsewhere).
- `InsightsView` — replaces `InsightsPlaceholderView`; renders the sections; empty state (§5).
- `InsightCardView`, `InsightBadgeView`, `EvidenceDotsView` — small views over `HealthTheme` tokens (`amber` hits, `dotMiss` misses, serif claim, card tokens).
- `InsightDetailView` — drill-down; on appear calls `EvidenceEngine.evidence(for:)`; renders the itemized list + confounders + raw numbers; rows push `EventDetailView`.
- `InsightsRefreshCoordinator` — the single `recompute` owner (§6).

### 3.3 Data flow

`foreground / Insights-open / post-capture → coordinator (debounced) → recompute → relationships updated → ViewModel reload → resolve names → InsightsFeed.build → InsightsView`. Dismiss and drill-down read/write the same stores.

## 4. Insight cards & drill-down

**Card** (UI-design §4):

```
[MODERATE]                              badge: tier from confidence
🥛 Dairy → bloating                     claim (serif), emoji by category
In your last 8 dairy days, bloating
followed in 6:   ● ● ○ ● ● ● ○ ●        filled = evidenceCount (amber),
usually within ~12h · avg severity +2.1   hollow = contradictionCount (dotMiss)
[All evidence →]              [Dismiss]  extensible action row
```

- The dot row renders from stored `evidenceCount`/`contradictionCount` — **no async** to draw a card, so the list scrolls instantly. (Exactly why 2A stored these counts.)
- `improves` cards phrase protectively ("magnesium → fewer migraines"); `noEffect` cards use the same anatomy, even tone, no dot alarm.
- Badge: Early 0.3–0.5 / Moderate 0.5–0.75 / Strong > 0.75. Strong is reachable only via Phase-4 experiments, so 2B tops out at Moderate — honest.

**`InsightPhrasing` (pure, tested):** claim = `<exposure label> → <outcome label>`; subline from `lagHours` (bucketed: "within ~Xh") + `strength` ("avg severity +N.N"); emoji from category. The **no-causal-language rule** is a spec invariant with a unit test asserting forbidden words never appear.

**`InsightDetailView` (drill-down)** — on appear, `evidence(for:)` yields the itemized pairs + confounders:
- Each exposure→outcome row (incl. **misses**): date, filled/hollow, outcome value → tap pushes `EventDetailView` for the event (`evidence(for:)` returns the event IDs).
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
- **Debounce:** skip if a recompute ran within `minRecomputeInterval` (default 15 min) OR no events changed since the last run (compare `EventStore.count` / latest event `createdAt` to a stored watermark). So repeated opens don't re-mine.
- Runs `recompute(asOf: Date())` off the main actor; on completion signals the ViewModel to reload.
- **`scheduleBackgroundRecompute()`** exists as an unimplemented, clearly-marked extension point so a nightly `BGTask` is a localized add later.
- The **decision logic lives in the core `RecomputePolicy.shouldRecompute(...)` (pure, package-tested)**; the app coordinator only owns the triggers, the stored watermark, and the off-main-actor `recompute` call.

`Date()` lives only in the coordinator (the trigger layer), never inside the engine — 2A's determinism invariant is preserved.

## 7. Non-functional requirements

- **Accessibility:** Dynamic Type throughout (older audience is core); VoiceOver labels on cards/dots/badges (a dot row reads "6 of 8 followed"); generous tap targets. Layouts survive XXL.
- **No causal language** anywhere in phrasing — spec invariant, unit-tested.
- **Performance:** the card list renders from stored counts (no per-card query); only drill-down does the on-demand `evidence(for:)`. Recompute debounced so opening Insights is instant when data is unchanged.
- **Light + dark** via existing `HealthTheme` tokens; both ship.
- **Determinism:** `now`/`Date()` only in the coordinator; core phrasing/feed are pure.

## 8. Testing

- Core unit tests: `InsightPhrasingTests` (claim/subline/badge for trigger, `improves`, `noEffect`; the no-causal-language invariant), `InsightsFeedTests` (sectioning; the ≤3 "New" throttle by firstSeen + confidence×novelty; ordering; archive), `RecomputePolicyTests` (the pure `shouldRecompute` decision: interval elapsed, watermark changed/unchanged).
- App-side: `InsightsViewModel` load / dismiss (+ undo) / refresh against an in-memory DB seeded by the synthetic harness (a mined corpus drives a realistic feed).
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
