# What Lifts Your Mood — Design

**Date:** 2026-07-19
**Status:** Approved (decisions made interactively with Leo)
**Scope:** The mood **reading experience** — the committed follow-up to mood capture. Add a **good-mood outcome** so the evidence engine mines *what lifts your mood* (not just what lowers it), un-suppress mood edges from the Insights feed, and give mood insights **warm, tentative, directional phrasing** ("Exercise seems to lift your mood" / "Short sleep is linked to lower mood"). Both directions surface, positive-led.

**Not touched this round:** adding new exposures. Mood is mined against the exposures the engine **already** wires — food, medications, supplements, peptides, short sleep, high stress, **barometric pressure drops**, cycle phase. Moon phase / mercury retrograde / general weather as *new* exposures — and the honest **plausibility-tier** presentation that must accompany them — are the **committed next round** (§9).

---

## 1. Problem

Mood capture ships and banks `.mood` events. The engine already mines a **low-mood** outcome (a mood event `≤ lowMoodThreshold`), but two things block the reading experience:

1. **Only the negative half is mined.** There is a `low-mood` outcome but no **good-mood** outcome — so the engine can tell you what *lowers* your mood but never what *lifts* it. On the 1–3 scale these are genuinely distinct signals (an exposure can push you *up to Good* without changing how often you hit *Rough*, and vice-versa), so a good-mood outcome adds real information, not a mirror of the low-mood one.
2. **Mood edges are suppressed.** The mood-capture round added `InsightsFeed.build`'s `toCategory != "mood"` filter because mood edges rendered awkwardly ("Coffee → low"). `InsightPhrasing` was never designed for mood.

This round adds the good-mood outcome, removes the suppression, and gives mood its own phrasing.

## 2. Decisions (Leo, 2026-07-19)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Good-mood outcome | **Add `OutcomeKey.goodMood`** (a mood event `≥ goodMoodThreshold`). On the 1–3 scale: Rough(1) → low, Okay(2) → neither, Good(3) → good. `goodMoodThreshold = 3`. |
| 2 | Directions shown | **Both, positive-led.** Surface *what lifts* (good-mood) AND *what lowers* (low-mood, previously suppressed). Same evidence-gated pipeline; warm/positive framing leads. |
| 3 | Phrasing tone | **Tentative / honest** — "seems to lift", "is linked to lower". The engine finds correlation, not causation (it caps confidence at the observational ceiling 0.75), so no causal claims. |
| 4 | One-off causes | **No special handling — the gates already cover it.** A one-off (broke a toe → bad week) can't form an edge (needs recurrence: `minExposures`, `minOutcomeOccurrences`, and the **stability** gate requiring evidence in both temporal halves). Only *recurring* lifters/lowerers surface; one-offs stay invisible (correctly). |
| 5 | Astrology / outside factors | **Deferred to the next round.** Moon/mercury/weather are NOT exposures today and are NOT added here. When added, they get an honest **plausibility tier** so nothing unproven reads as established science — moon/mercury never mixed into the evidence feed as fact. (§9) |

## 3. Architecture & data model

The engine's structure is unchanged — this adds one outcome key and wires it through the identity + phrasing layers. Five small, well-bounded changes:

**A. The good-mood outcome (core).**
- `OutcomeKey` (`Evidence/ExposureModel.swift`) gains `case goodMood` (alongside `symptom(String)`, `lowMood`).
- `EvidenceConfig` gains `goodMoodThreshold: Double = 3`.
- `OutcomeSource.occurrences` (`Evidence/OutcomeSource.swift`) — the `.mood` case now emits **either** outcome: `value ≤ lowMoodThreshold` → `.lowMood`; `value ≥ goodMoodThreshold` → `.goodMood`; otherwise (Okay = 2) → `nil`. A single mood event maps to at most one outcome.

**B. Edge identity (core, `Evidence/EdgeIdentity.swift`).** Mirror `lowMood` for `goodMood`:
- `toToken`: `.goodMood → "mood:good"`.
- `columns`: `.goodMood → (…, toCategory: "mood", toSubtype: "good")`.
- `parseTo`: `"mood:good" → .goodMood`.
(`lowMood` stays `"mood:low"` / `("mood","low")`.)

**C. Un-suppress mood edges (core, `Insights/InsightsFeed.swift`).** Remove the `resolved.filter { $0.relationship.toCategory != "mood" }` line (added last round). Both low- and good-mood edges now flow into the feed.

**D. Mood-aware phrasing (core, `Insights/InsightPhrasing.swift`).** `claim(_:)` gains a mood branch (when `rr.relationship.toCategory == "mood"`) keyed on `toSubtype` ("low"/"good") × `relationship.type`. Tentative, directional, positive-led:

| toSubtype | type | Meaning | Phrase |
|-----------|------|---------|--------|
| good | `.possibleTrigger` | exposure → more good days | **"\(X) seems to lift your mood"** |
| low | `.improves` | exposure → fewer low days | **"\(X) seems to protect against low moods"** |
| low | `.possibleTrigger` | exposure → more low days | **"\(X) is linked to lower mood"** |
| good | `.improves` | exposure → fewer good days | **"\(X) seems to weigh on your mood"** |
| low or good | `.noEffect` | — | **"No clear link between \(X) and your mood"** |

(First two are the "positive-led" lifters/protectors; the middle two are the honest cautions.) Non-mood edges keep the existing generic templates unchanged.

**E. Readable outcome noun (app, `Views/HealthOS/Insights/InsightsViewModel.swift`).** The resolver currently sets `outcomeLabel: r.toSubtype ?? "outcome"`, so a mood edge's label is the bare "low"/"good". Map mood subtypes to a natural noun for the *supporting* lines (`countLine`, etc.): `"low" → "a low mood"`, `"good" → "a good mood"` (symptom subtypes unchanged). So `countLine` reads "In 3 of your last 8 Exercise logs, a good mood followed".

**Subline (core).** `subline` appends lag + "avg severity" for triggers. Severity is a symptom concept; for mood outcomes **omit the severity clause** (keep the lag, e.g. "usually within ~18h"). Guard on `rr.relationship.toCategory == "mood"`.

## 4. What the engine already handles (no work)

- **One-offs (Decision 4):** the recurrence + stability gates mean a single injury week can neither form its own edge nor sustain a spurious one. Nothing to build; stated so the plan's reviewers don't "add" one-off handling.
- **Barometric pressure:** already an exposure (`PressureDropExposureSource`), so "pressure drop → lower mood" can surface *this round* with the new phrasing — the one "outside factor" that is established science and already wired.
- **Confidence honesty:** the existing three-gate precision (significance + effect-size + stability) and the 0.75 observational ceiling already keep weak/coincidental mood correlations out; the tentative phrasing matches that.

## 5. Presentation & ordering

- Mood edges render as cards in the existing Insights feed alongside symptom edges, using the same badge tiers, dots, and drill-down — only the **claim/supporting copy** differs (§3D).
- **Positive-led** is expressed through *framing* (the warm "lift"/"protect" templates), **not** a special re-sort — the feed keeps its existing confidence/status ordering (YAGNI; a mood-priority sort is not added).
- Drill-down (`InsightDetailView`) works unchanged — it reads the same relationship + evidence.

## 6. Testing

- **Core (`swift test`):**
  - `OutcomeSourceTests` — a mood event value 3 (Good) → `.goodMood`; value 1 (Rough) → `.lowMood`; value 2 (Okay) → **no** outcome. (Extends the existing threshold tests.)
  - `EdgeIdentityTests` — `goodMood` round-trips: `toToken` → `"mood:good"`, `columns` → `("mood","good")`, `parseTo("mood:good")` → `.goodMood`; and `edgeKey` parses back.
  - `EvidenceConfig` — `goodMoodThreshold == 3`.
  - `InsightPhrasingTests` — each mood template (the 5 rows in §3D) renders exactly; a non-mood edge is unchanged; `subline` omits severity for a mood trigger but keeps lag.
  - `InsightsFeedTests` — the suppression test from last round is **inverted**: a mood-outcome edge now **appears** in the built feed (delete/replace `moodOutcomeEdgesAreSuppressed`).
- **App (`-parallel-testing-enabled NO`):**
  - `InsightsViewModelTests` — a resolved mood edge's `outcomeLabel` is the natural noun ("a good mood" / "a low mood"), not "good"/"low".
- **Device e2e:** with seeded data + recompute, a good-mood edge surfaces as "… seems to lift your mood" and a low-mood edge as "… is linked to lower mood"; both appear in Insights with dots + drill-down; "pressure drop → lower mood" can appear; no moon/mercury factor appears.

## 7. Copy / honesty guardrails

- **No causal language** — "seems to", "is linked to", "may"; never "causes"/"lifts" as bare assertion (Decision 3, and `InsightPhrasing`'s existing "NO causal language" rule).
- Mood is presented as *your personal pattern*, correlation-only, consistent with the observational ceiling.
- The tentative tone is the template that the **next round's plausibility tiers** build on (established → contested → novelty).

## 8. Out of scope (this round)

- **New exposures:** moon phase, mercury retrograde, general weather/temperature/humidity. (Next round.)
- **The plausibility-tier presentation** (labeling factors established / contested / novelty) — designed with the outside-factors round, since it only matters once contested/novelty factors are mined.
- **Any re-sort** to prioritize mood or positive insights (framing carries "positive-led").
- No change to the mood **capture** surfaces, the crisis/red-flag flow, or the engine's gate structure.

## 9. The committed next round — Outside factors + honest tiering

Add moon phase / mercury retrograde / weather as **trackable exposures**, and a **plausibility tier** in the Insights presentation so each factor is labeled by causal plausibility:

- **Established mechanism** (pressure, sleep, food, meds, stress, cycle) — normal evidence framing.
- **Plausible / contested** (weather, climate, moon) — "some people are sensitive; here's *your* pattern; mechanism unproven."
- **No known mechanism / novelty** (mercury retrograde) — "curious coincidence; correlation isn't causation" — never presented as actionable fact, kept out of the evidence feed proper (a separate for-fun surface if surfaced at all).

Principle (agreed with Leo): **track & correlate everything the user wants, but present each factor with an honest plausibility tier so nothing unproven masquerades as established science** — protecting credibility with the clinic design partner while honoring that people may genuinely be sensitive to weather/pressure/moon.
