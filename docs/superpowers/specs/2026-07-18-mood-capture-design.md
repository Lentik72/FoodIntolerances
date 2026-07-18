# Mood Capture — Design

**Date:** 2026-07-18
**Status:** Approved (decisions made interactively with Leo)
**Scope:** The **capture-first** slice of mood / mental-state tracking — a surface to log how you feel on a five-level scale, producing the `.mood` events the evidence engine already knows how to mine. This is the recovery-recording counterpart to the crisis flow. The positive "what *lifts* your mood" mining and the mood **Insights** presentation are the committed **next round** (§9).

**Not touched:** the evidence engine's structure, extraction of other categories, migrations, the crisis/red-flag flow. The only core changes are a new `MoodLevel` scale, a `CaptureService.logMood` method, and a one-line threshold calibration.

---

## 1. Problem

The engine is already half-built for mood — `EventCategory.mood`, `OutcomeKey.lowMood`, and `OutcomeSource` (a mood event with `value ≤ lowMoodThreshold` → a low-mood outcome) all exist and are unit-tested. But **nothing in the app creates a `.mood` event** — there is no way to log mood at all. So the engine can never mine mood, and a user with few symptoms to log has nothing to track. This feature adds the missing capture surface; the engine's existing low-mood mining then works from day one.

## 2. Decisions (Leo, 2026-07-18)

| # | Decision | Choice |
|---|---|---|
| 1 | Scale | **Five levels** — 😖 Awful · 🙁 Low · 😐 Okay · 🙂 Good · 😄 Great — stored `1–5`. Fast, honest for a fuzzy feeling; coarse is fine for the engine (it binarizes at a threshold). |
| 2 | Primary surface | A prominent, ambient **Home quick-check** ("How are you feeling?", one tap logs). For a mood tracker, mood is often the *main* thing logged, and the engine needs *regular* logs — friction is the enemy. A capture-sheet Mood tab is the secondary path (notes / back-dating). |
| 3 | Entry shape | Level + optional note. **No tags / "why" pickers** — the engine finds *what* affects mood by correlating the log against your *other* events (sleep, exercise, food), so the entry needn't carry the why. |
| 4 | No prediction | **Never predict / pre-fill mood** (e.g. from sleep). It's circular (the engine is supposed to *discover* sleep→mood from data, not assume it), presumptuous, and corrupts the data. The sleep↔mood link arrives the trustworthy way — as an evidence-based Insight next round. |
| 5 | "Don't know yet" | **No stored "don't know" value** (a fake data point would poison the engine). The check-in is ambient/optional, so waking-up-unsure = just log later; plus a UI-only **"not now"** dismiss (hides the card for the day, stores nothing). |
| 6 | Cadence | Log anytime, as often as you like, **never nagged** — no forced daily check-in. |

## 3. Architecture & data model

**`MoodLevel` — the single source of truth for the scale** (core, `HealthGraphCore/Sources/HealthGraphCore/Capture/MoodScale.swift`):

```swift
public enum MoodLevel: Int, CaseIterable, Sendable {
    case awful = 1, low = 2, okay = 3, good = 4, great = 5
    public var label: String { ... }   // "Awful"…"Great"
    public var emoji: String { ... }   // 😖🙁😐🙂😄
}
```

Every surface reads the scale from here — the emoji, labels, and stored values live in exactly one place.

**The mood event.** A mood log is a normal `HealthEvent`: `category: .mood`, `value: Double(level.rawValue)` (1–5), `subtype: "mood"` (matching the existing `OutcomeSource`/`ExposureSourceTests` convention — `.mood` events key off category + value, not subtype), `source: .manual`, optional note in metadata. The Timeline label ("Mood: Good") is derived from `value` via `MoodLevel` in `EventDisplay` (§6). A new method writes it, parallel to `logSymptom`:

```swift
// CaptureService
public func logMood(level: MoodLevel, at timestamp: Date, note: String?) async throws -> HealthEvent
```

**Threshold calibration (the only engine touch).** `OutcomeSource` maps a `.mood` event to a `low-mood` outcome when `value ≤ config.lowMoodThreshold`. That threshold is currently `3` (sized for an imagined 1–10 scale). On the 1–5 scale, "low mood" = **Awful/Low**, so set `EvidenceConfig.lowMoodThreshold = 2`. This is a one-line *calibration*, not an engine redesign: the existing `ExposureSourceTests` low sample is value `2` (still ≤ 2 → still low) and its high sample is `8` (still skipped), so it stays green. A new test pins the boundary (Okay=3 is *not* low; Low=2 *is*).

**No red-flag/crisis interaction.** A mood event is `category: .mood`; the red-flag/crisis check only fires on `.symptom`, so logging "Awful" mood never triggers a crisis takeover (correct — the crisis flow is only the explicit self-harm symptom, never a low mood).

## 4. The Home quick-check (primary surface)

A calm card near the top of Home (right under the greeting, above the sleep/steps stats) — the daily-habit driver.

- **Appearance:** titled **"How are you feeling?"**, a row of the five faces, each a ≥44pt tap target with a VoiceOver label ("Awful"…"Great"). No number, no slider.
- **One tap logs it:** tapping a face calls `logMood(level, at: now, note: nil)` and shows the existing non-blocking **undo toast** ("Logged Good · Undo"). One tap, done.
- **Ambient, never nagging:** it just sits there; if you don't know yet, ignore it and tap later.
- **"Not now":** a small dismiss (×) tucks the card away for the rest of the **day** (a per-day local UI flag — not a data point); it returns tomorrow.
- **Already logged today:** after a log, the card shows a gentle confirmed state ("Felt **Good** at 9:14 AM — tap to update"); tapping again logs another reading (mood shifts through a day; multiple logs are welcome).
- Styled in the calm `HealthTheme` palette — prominent but not shouting.

Reuses the existing capture plumbing (`logMood` + the coordinator's save-completed refresh), so Home logging behaves like sheet logging.

## 5. The capture-sheet Mood tab (secondary surface)

`CaptureType` gains a fifth case — `case mood` (label "Mood", icon `face.smiling`) — so the sheet tabs read Symptom · Meal · Dose · Note · Mood.

**`MoodCaptureView`** (parallel to `SymptomCaptureView`, simpler — the scale is a fixed five, no search/chips):
- The five faces + labels, each tappable.
- An optional **note** field.
- Tapping a level saves via `logMood(level:, at:, note:)` using the sheet's shared **"When" date picker** (back-dating "I felt rough this morning" just works), then fires the existing `onLogged` undo toast.

The Home quick-check is the fast path; this tab is the "with note / earlier time" path. Both write the identical `.mood` event.

## 6. Engine integration & the Insights deferral

**Immediate.** Once `.mood` events exist, `OutcomeSource` mines the low ones → `recompute` builds "X → low mood" edges (and protective "X *reduces* low-mood days" edges). Real mood history accumulates from day one; no engine work beyond the calibration.

**Deferred — the mood Insights *surface* (next round).** Those mined mood edges would render awkwardly today ("Coffee → low"): `InsightPhrasing` was never designed for mood, and the positive "what *lifts* your mood" framing (a good-mood outcome + proper copy) is the next round's job. So **this cycle suppresses `low-mood` relationships from the Insights feed** (a small filter in `InsightsViewModel`/`InsightsFeed` — exclude relationships whose outcome is the low-mood edge, i.e. `toCategory == "mood"`). The engine still mines and **stores** them (history banks); they don't surface until the next round presents them well. Correlations need weeks of data regardless, so nothing meaningful is hidden meanwhile.

**Timeline** renders mood events like any other event ("Mood: Good"), so they're visible and deletable (`EventDisplay` handles `.mood`).

## 7. Testing

- **Core (`swift test`):**
  - `MoodScaleTests` — each `MoodLevel`'s rawValue/label/emoji; `allCases` order.
  - `CaptureServiceTests` (or the existing capture test) — `logMood` writes `category: .mood`, `value == level.rawValue`, `subtype == level.label`, `source: .manual`, note in metadata.
  - `ExposureSourceTests` — stays green with `lowMoodThreshold = 2`; add a boundary case: mood value 3 (Okay) → **not** a low-mood outcome; value 2 (Low) → low-mood outcome.
- **App (`-parallel-testing-enabled NO`):**
  - The Home quick-check "not now" per-day dismiss flag persists/clears correctly (unit-tested at the view-model/store level).
  - An Insights test asserting `low-mood` (mood-outcome) relationships are **excluded** from the built feed.
  - `MoodCaptureView` + the Home card build + preview (light/dark).
- **Device e2e:** log mood from Home (one tap → undo toast) and from the sheet (with note + back-dated time) → both appear in the Timeline as "Mood: …" and are deletable; "not now" hides the Home card for the day (returns next day); logging **Awful** shows **no** crisis takeover; mood edges do **not** appear in Insights this cycle.

## 8. Copy / UX guardrails

- The check-in is a gentle question ("How are you feeling?"), never a demand. No streaks, no guilt, no "you missed a day."
- "Okay" (level 3) means *neutral*, never *"I don't know"* — the two are kept distinct (unknown = don't log).
- Emoji-forward so the scale reads at a glance and is largely language-neutral.

## 9. Out of scope (this cycle — the committed next round)

- **The positive "what lifts your mood" mining + mood Insights presentation:** a `good-mood` outcome (high end of the scale), and mood-edge phrasing so Insights reads "Exercise seems to lift your mood" / "Short sleep is linked to lower mood," with the dots behind it. This is the reading experience for mood and gets its own design.
- **No prediction / pre-fill** of mood (ever).
- **No forced check-ins / streaks / nagging.**
- **No Home quick-log for other event types** (mood only).
- No changes to the evidence engine's structure, the crisis/red-flag flow, other extractors, or migrations.
