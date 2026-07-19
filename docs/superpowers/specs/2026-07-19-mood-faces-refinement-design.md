# Mood Faces Refinement — Design

**Date:** 2026-07-19
**Status:** Approved (decisions made interactively with Leo)
**Scope:** A presentation-first refinement of the just-merged mood-capture feature (`docs/superpowers/specs/2026-07-18-mood-capture-design.md`). Reduce the mood scale from **five faces to three** (Rough · Okay · Good) and replace the system emoji with **custom-drawn, subtly-colored faces**. Recalibrates the low-mood threshold for the new scale and adds a display-robustness helper.

**Not touched:** the evidence engine's structure, extraction of other categories, migrations of stored data, the crisis/red-flag flow, the Insights suppression. The positive "what *lifts* your mood" mining remains the committed next round.

---

## 1. Problem

The shipped mood scale uses five system emoji (😖🙁😐🙂😄). Two issues, raised by Leo during the on-device pass:

1. **Emoji look unpolished** — system emoji render inconsistently across iOS versions, don't tint to the app's calm palette, and read as "not designed."
2. **Five levels is more granularity than the product needs.** The evidence engine **binarizes mood at a threshold** — it only ever asks "is this a low day / (next round) a good day / neither." Five levels and three levels give the engine the *identical* three buckets (negative / neutral / positive), so the finer resolution is data the engine discards at the threshold anyway. Meanwhile the design's own north star is low-friction, regular logging ("friction is the enemy"), and three bigger faces are faster to read and tap.

So this is a **pure-UX call** (the engine is indifferent to 3 vs 5): fewer, larger, better-drawn faces. Fewer faces also means ~110pt per face instead of ~65pt, which is exactly the room a custom graphic needs to look good.

## 2. Decisions (Leo, 2026-07-19)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Scale size | **Three levels** (odd, so there's a true neutral middle → the engine's three buckets). |
| 2 | Labels | 🙁 **Rough (1)** · 😐 **Okay (2)** · 🙂 **Good (3)**. "Rough" (not "Bad") for the negative pole — warm, non-self-judgmental, matches the app's gentle tone; covers everything from meh-minus to awful in one word. |
| 3 | Face graphics | **Custom-drawn SwiftUI faces** (not emoji, not SF Symbols). Consistent across devices, tintable to the palette, crisp at large size. The exact face proportions are dialed in live in SwiftUI previews on-device. |
| 4 | Color | **Subtle color** — Rough = muted rose, Okay = neutral, Good = sage/green. A quiet rose→neutral→sage gradient that reinforces meaning at a glance (health convention), not loud. |
| 5 | Existing data | **No migration.** The only mood logs anywhere are throwaway pre-launch test logs on Leo's device; the value-drift below is harmless. Test logs left as-is. |
| 6 | Threshold | `lowMoodThreshold` **2 → 1** — low mood is now just Rough (1). |

## 3. Architecture & data model

**Value semantics change (1–5 → 1–3).** The new scale reuses the low integers, so stored values from the old scale now *mean* something different:

| New value | Label | Old value that now reads as this |
|-----------|-------|----------------------------------|
| 1 | Rough | old 1 (Awful) — consistent |
| 2 | Okay  | old 2 (Low) — *was negative, now neutral* |
| 3 | Good  | old 3 (Okay) — *was neutral, now positive* |
| —         | —     | old 4 (Good) / 5 (Great) — no longer valid `rawValue`s |

Because the only affected data is disposable test logs, this drift is accepted (Decision 5). No migration, no remap.

**`MoodLevel` stays pure data in core** (`HealthGraphCore/Sources/HealthGraphCore/Capture/MoodScale.swift`):

```swift
public enum MoodLevel: Int, CaseIterable, Sendable {
    case rough = 1, okay = 2, good = 3
    public var label: String { ... }   // "Rough" / "Okay" / "Good"

    /// Nearest valid level for any Int — so display/mining never break on an
    /// out-of-range value (e.g. an orphaned old 4/5 test log, or future drift).
    public init(clamping raw: Int) {
        self = raw <= 1 ? .rough : (raw >= 3 ? .good : .okay)
    }
}
```

- **`emoji` is removed.** The face *drawing* moves to the app layer (SwiftUI); core carries only the label + value. This keeps `MoodScale` pure and unit-testable and keeps color/`HealthTheme` out of core.
- **`init(clamping:)`** is the display-robustness helper: any stored value maps to a valid level, so the Timeline never renders a bare "Mood" and no consumer traps on `Int(Double)`.

**Threshold calibration (the only engine touch).** `OutcomeSource` flags a `.mood` event as low when `value ≤ config.lowMoodThreshold`. On the 1–3 scale, low = Rough (1) only, so `EvidenceConfig.lowMoodThreshold = 1`. Okay (2) is **not** low; Rough (1) **is** low.

**No red-flag/crisis interaction** (unchanged): a mood event is `category: .mood`; the red-flag/crisis check fires only on `.symptom`. Logging Rough never triggers a takeover.

## 4. The custom face (`MoodFace`)

A small app-layer SwiftUI view (`Views/HealthOS/…`), the single place mood is drawn:

- **Draws** a rounded face: circle outline/fill + two eyes + a **mouth curve whose curvature is driven by the level** (frown for Rough → flat for Okay → smile for Good).
- **Subtle color** from `HealthTheme` (Decision 4): Rough = muted rose, Okay = neutral, Good = sage. Core stays color-free; `MoodFace` maps `MoodLevel → Color`.
- **No selection binding.** Both surfaces log on a single tap — there is no "select then confirm" step — so the face renders statically with ordinary button press-feedback (a brief scale/opacity on press). The confirmed state on Home is already conveyed by the "Felt Good … — tap to update" text, not by a persistently highlighted face. (YAGNI: no selected/highlighted variant.)
- **Legible at size + accessible:** crisp at ~110pt (3-across); the tap target keeps the existing `≥44pt` minimum and its VoiceOver label ("Rough"/"Okay"/"Good") comes from the enclosing button, unchanged.
- **The exact proportions/curve/colors are iterated in `#Preview` (light + dark, all three faces) on-device** — the spec commits to the approach, the previews settle the pixels.

## 5. The two capture surfaces

Both already lay faces out in an `HStack` with each face `maxWidth: .infinity`, so **going 5→3 auto-enlarges** them with no layout math.

- **`MoodCheckInView` (Home quick-check):** replace `Text(level.emoji).font(.largeTitle)` with `MoodFace(level: level)` inside the existing `ForEach(MoodLevel.allCases)`. One tap still logs (`model.log(level)` → `saveCompleted()`); accessibility label unchanged.
- **`MoodCaptureView` (capture-sheet tab):** replace `Text(level.emoji).font(.largeTitle)` with `MoodFace(level: level)`; keep the `Text(level.label)` caption underneath and the optional note field. Back-dating via the shared "When" picker is unchanged.

No change to `MoodCheckInModel` / `CaptureService.logMood` / the event shape (`category: .mood`, `subtype: "mood"`, `value: 1–3`).

## 6. Timeline & engine integration

- **`EventDisplay.title`** switches from `MoodLevel(rawValue: Int(v))` (which returned nil for orphaned 4/5) to **`MoodLevel(clamping: Int(v))`**, so every mood row renders "Mood: Rough/Okay/Good". `valueLine` still returns nil for `.mood` (level is in the title).
- **Engine** mines low mood at the new threshold (Rough=1) from day one. Mood-outcome edges remain **suppressed** from the Insights feed (unchanged from the last cycle) and stored (history banks).

## 7. Testing

- **Core (`swift test`):**
  - `MoodScaleTests` — the three `MoodLevel` cases' rawValue/label; `allCases` count == 3 and order (rough, okay, good); **`init(clamping:)`** boundaries: `0→rough`, `1→rough`, `2→okay`, `3→good`, `4→good`, `99→good`, negative→rough.
  - `EventDisplayTests` — mood value `1/2/3` → "Mood: Rough/Okay/Good"; **out-of-range** `4`/`5`/`0` → clamped ("Mood: Good"/"Mood: Good"/"Mood: Rough") — the bare-"Mood" regression is gone.
  - `ExposureSourceTests` — with `lowMoodThreshold = 1`: the low-mood sample value becomes **1**; a boundary case pins **Okay (2) is NOT low, Rough (1) IS low**. (Any existing high sample stays skipped.)
- **App (`-parallel-testing-enabled NO`):**
  - `MoodCheckInModelTests` stays green on 1–3 values (fixtures must not hardcode old 4/5).
  - `MoodFace` builds + `#Preview` renders (light + dark, all three faces).
- **Device e2e:** Home + sheet show three custom faces; one tap logs; Timeline shows "Mood: Rough/Okay/Good"; logging **Rough** shows **no** crisis takeover; faces read well light + dark and at XXL Dynamic Type.

## 8. Copy / UX guardrails (carried from the mood-capture design)

- The check-in stays a gentle question ("How are you feeling?"), never a demand; no streaks, no nagging.
- "Okay" (2) means *neutral*, never *"I don't know"* — unknown = don't log (no stored "don't know").
- Faces are the primary read; labels/accessibility labels keep it language-legible.

## 9. Out of scope (unchanged commitments)

- **The positive "what lifts your mood" mining + mood Insights presentation** — a `good-mood` outcome keyed off Good (3) + mood-edge phrasing. Still the committed next round; not built here.
- **The Timeline swipe-to-delete/edit gap** Leo noticed on device — pre-existing, unrelated to mood; its own small fix later.
- **No data migration / remap** of old mood values.
- **No prediction/pre-fill, no forced check-ins/streaks, no stored "don't know"** (all still true).
- No changes to the engine's structure, the crisis/red-flag flow, other extractors, or the Insights suppression.
