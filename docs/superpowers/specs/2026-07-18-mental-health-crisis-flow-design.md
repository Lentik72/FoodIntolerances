# Mental-Health Crisis Support Flow — Design

**Date:** 2026-07-18
**Status:** Approved (decisions made interactively with Leo)
**Extends:** `2026-07-17-red-flag-safety-interstitial-design.md` — this is the `.mentalHealthCrisis` branch the physical red-flag cycle deliberately deferred.
**Scope:** When a user *deliberately logs* a self-harm / suicide crisis symptom, show a warm, non-diagnostic **988 Suicide & Crisis Lifeline** support takeover — tonally the opposite of the physical red-flag's urgent 911 screen. Reuses the red-flag plumbing; adds a new category, one rule, one catalog entry, a crisis-resources constant, and a separate crisis view. **No** changes to the physical red-flag flow, evidence engine, or migrations.

This is the highest-stakes copy in the app. Getting the tone wrong (alarmist, dismissive, or clinical) is itself a harm, so the copy is specified verbatim.

---

## 1. Problem

The physical red-flag interstitial routes acute physical symptoms (chest pain, anaphylaxis) to 911. Its sibling case — someone logging thoughts of self-harm or suicide — needs a fundamentally different response: not alarm, but warmth and a one-tap path to a trained crisis counselor (988). The `RedFlagCategory` enum was built with `.mentalHealthCrisis` in mind for exactly this. Today the app has *no* way to surface crisis support and *no* catalog entry for the triggering symptom.

## 2. Decisions (Leo, 2026-07-18)

| # | Decision | Choice |
|---|---|---|
| 1 | Trigger | **Capture-time only** — a deliberate log of a specific crisis symptom. **No** text/voice scanning, **no** proactive detection (both carry false-negative danger, false-positive harm, and privacy cost; a clear deterministic trigger the user controls is safer and more honest). |
| 2 | The entry | **One combined catalog entry: "Thoughts of self-harm or suicide."** Self-injury urges and suicidal ideation both route to 988, so one clear entry beats a taxonomy decision in a hard moment. **Harm-to-others is excluded** (different response — 911/duty-to-warn — and clinically wrong to fold into a 988 flow). |
| 3 | Resources & tone | **Call 988 + Text 988**, a quiet "911 if in immediate danger" line, and a gentle close. **Warm, not red** — sage accent, calm, reassuring; the tonal opposite of the medical screen. |
| 4 | Mutable? | **No.** The crisis prompt always shows and is kept *out* of the "Safety reminders" mute list entirely. The "discourages honest logging" concern is answered by keeping the screen warm/brief with a one-tap gentle close — not by making a suicide-crisis prompt suppressible. |
| 5 | "Getting out" of the state | **There is no persistent crisis state.** The flow is event-driven: logging the symptom shows support *once*; later days with no such log do nothing (no flag, no nag, no residue). Actively *recording recovery/good days* is the **mood-tracking** feature (next round), not this one. |
| 6 | Recovery touch in-screen | The screen stays a moment-of-need surface; **hope lives in the copy** (one non-minimizing sentence), **not** in a functional element (no links, no "track this later") — cognitive load in an acute moment must be near-zero. |

## 3. Architecture & module layout

Reuses the red-flag system; adds a second, deliberately different branch.

```
HealthGraphCore/Sources/HealthGraphCore/Safety/
  RedFlagCatalog.swift        // + RedFlagCategory.mentalHealthCrisis; + one crisis rule;
                              //   + RedFlagCatalog.mutableSymptomKeys (excludes crisis)
  Capture/SymptomCatalog.swift// + one entry: "Thoughts of self-harm or suicide"

Views/HealthOS/Safety/
  CrisisSupportView.swift      // NEW — warm 988 support takeover (separate from RedFlagInterstitialView)
  CrisisContact.swift          // NEW — call988URL (tel:988), text988URL (sms:988)
  RedFlagRemindersView.swift   // Settings list now uses `mutableSymptomKeys` (crisis never appears)

FoodIntolerancesApp.swift      // the app-level .fullScreenCover switches on match.category:
                               //   .medicalEmergency → RedFlagInterstitialView (unchanged)
                               //   .mentalHealthCrisis → CrisisSupportView
```

**Unchanged:** `RedFlagPresenter.consider` already produces a `RedFlagMatch` (carrying the rule's `category`) severity-independently from any rule, so the crisis symptom flows through the same capture hook and **save-first** ordering with no wiring change. Only the cover's presentation branches on category.

**Why a separate `CrisisSupportView`** (not a branch inside `RedFlagInterstitialView`): the two screens share almost nothing — red/urgent/911/mutable vs. warm/calm/988/never-mutable, different actions and copy. Separate single-purpose files stay focused and independently testable, matching the codebase's style.

## 4. The trigger & catalog entry

- **New `SymptomCatalog` entry:** `"Thoughts of self-harm or suicide"`, with the same `regionId` the existing mental-health symptoms use (Anxiety/Depression/Stress — resolve the exact string against the real catalog in the plan). The HealthOS capture UI is search-based, so the entry is reachable by typing regardless of region; `regionId` only matters to the legacy body-map. Its derived `canonicalKey` is pinned by a `SymptomCatalogTests` literal assertion.
- **New rule in `RedFlagCatalog.rules`:**
  ```swift
  RedFlagRule(symptomKeys: [key("Thoughts of self-harm or suicide")],
              category: .mentalHealthCrisis, extraGuidance: nil)
  ```
- Existing "Depression"/"Anxiety"/"Stress" catalog entries are **not** triggers — chronic mental-health tracking is not an acute crisis.
- The crisis symptom is saved as a normal `HealthEvent` (category `.symptom`) — valuable for the person's own record and their clinician, and deletable from the Timeline like any event. Whether the evidence engine should *mine* crisis symptoms in correlations is a deliberate later question (§9).

## 5. The crisis screen — `CrisisSupportView`

Full-screen cover, presented save-first, warm throughout. Presented from the app anchor (like the medical cover) so it sits above all UI.

### 5.1 Copy (verbatim)

> **You're not alone**
> Thank you for noticing this and writing it down — that takes real strength. If you're thinking about harming yourself, talking to someone can help, and hard moments can pass. The **988 Suicide & Crisis Lifeline** has trained counselors, free and confidential, any time.

Non-minimizing by design: validates the act of logging, affirms that support helps and hard moments *can* pass — never a dismissive "it gets better."

### 5.2 Actions (by prominence)

1. **Call 988** — primary, styled **warm** (`HealthTheme.accent`, NOT `HealthTheme.danger`). Opens `CrisisContact.call988URL` (`tel:988`). VoiceOver "Call nine eight eight."
2. **Text 988** — secondary (accent outline). Opens `CrisisContact.text988URL` (`sms:988`). Texting matters — many people can't safely speak.
3. *"If you're in immediate danger, call 911."* — a quiet line with **911** tappable (`EmergencyContact.callURL`), low prominence so it never competes with 988.
4. **"I'm okay for now"** — the gentle close (quiet text button); always present; clears `presenter.pending` and returns to the app. **No mute affordance.**

### 5.3 Tone, visuals, accessibility

- Calm and spacious: serif title, `HealthTheme.paper`, accent (never `danger`/red). Optional small non-clinical accent glyph, kept minimal (or none). No countdown, no alarm.
- On appear, a VoiceOver screen-changed announcement in warm phrasing ("You're not alone. Support is available — call or text 988.").
- Call 988 ≥44pt with an explicit label; content scrolls at XXL Dynamic Type; nothing signalled by color alone.

### 5.4 Behavior

The crisis symptom is saved first (their record), then this cover takes over instead of the quiet undo-toast — that is what "no log-and-move-on" means here. The gentle close dismisses; there is no lingering state to exit (decision 5).

## 6. Muting exclusion

`RedFlagCatalog` gains `mutableSymptomKeys` = keys of rules whose `category != .mentalHealthCrisis`. `RedFlagRemindersView` (Settings → Safety reminders) lists `mutableSymptomKeys` instead of `allSymptomKeys`, so a crisis symptom is **never** offered as a mute toggle and can never enter the muted set. The crisis screen has no "stop reminding me" affordance. A test asserts the crisis key is in `allSymptomKeys` but not in `mutableSymptomKeys`.

## 7. Testing

- **Core (`swift test`):**
  - `RedFlagCatalogTests` — crisis rule exists (`category: .mentalHealthCrisis`); its key resolves to a real catalog entry (drift guard); `mutableSymptomKeys` **excludes** the crisis key while `allSymptomKeys` includes it.
  - `RedFlagEvaluatorTests` — the crisis key → a `.mentalHealthCrisis` match; severity-independent.
  - `SymptomCatalogTests` — the new entry exists + literal canonical-key pin.
- **App (`-parallel-testing-enabled NO`):**
  - `RedFlagPresenterTests` — a crisis symptom sets `pending` with `.mentalHealthCrisis`.
  - `CrisisContactTests` — `call988URL == "tel:988"`, `text988URL == "sms:988"`.
- **Views:** `CrisisSupportView` build + preview (light/dark); the cover's category switch verified by build.
- **Device e2e:** log the crisis symptom → warm 988 screen (not red); Call/Text 988 open the dialer/Messages; gentle close returns; the symptom is saved (Timeline) and deletable; it does **not** appear in Health → Safety reminders; logging it again still shows it (not mutable, no lingering state); VoiceOver announces; light/dark + XXL hold.

## 8. Copy & factual guardrails

- **988** is the US Suicide & Crisis Lifeline — call **or** text 988, free, confidential, 24/7 (since July 2022). `sms:988` opens Messages to 988; `tel:988` dials it.
- No diagnostic or minimizing language anywhere. The screen never asserts the person "has" a condition, never says "it gets better," never uses alarm framing.

## 9. Out of scope (this cycle)

- **Mood / mental-state tracking (including improvements / good days)** → the committed **next design round**: positive-mood entries + evidence-engine "what lifts your mood" (sleep, exercise, sunlight, meds → better days). This is the recovery-recording counterpart to the crisis flow.
- **Harm-to-others** — different response (911/duty-to-warn); excluded.
- **Text/voice scanning** and **proactive mood nudges** — excluded (false-negative danger, false-positive harm, privacy).
- **Regionalization** beyond the single `CrisisContact` constants (988/911 are US) — later, like `EmergencyContact`.
- **Evidence-engine handling of crisis symptoms** (whether to mine them in correlations) — a deliberate later question.
- No changes to the physical red-flag flow, evidence engine, extraction, scoring, or migrations.
