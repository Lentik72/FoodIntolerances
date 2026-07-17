# Red-Flag "Seek Care Now" Safety Interstitial — Design

**Date:** 2026-07-17
**Status:** Approved (decisions made interactively with Leo)
**Scope:** The capture-time safety net deferred from Phase 2B. When a user logs a symptom on a fixed red-flag list, the app interrupts with a full-screen "seek care now" takeover **instead of** the normal save-and-move-on flow. Deliberately a dumb, deterministic static table — no ML, no evidence engine. It is an **ethics requirement** (health-graph design §7) and an App Store review asset.

**This cycle covers physical medical emergencies only.** Self-harm / mental-health crisis is a distinct, higher-stakes flow (988 Suicide & Crisis Lifeline, different tone, no "log and move on" affordance) and gets its own dedicated design round next — see §7.

**Not touched:** the evidence engine, extraction, scoring, migrations, the Insights surface. This is a new, isolated capture-time unit.

---

## 1. Problem

The corpus and the Insights surface exist, but the app can silently accept a log of "Chest Pain" and do nothing — or worse, route it toward slow correlation analysis — when the right response is "consider urgent care now." A health app that surfaces patterns has an ethical duty not to let a genuine emergency pass unremarked. The design docs (health-graph §7, ui-design §2/§4) always scoped this as a small, mandatory, static-table safety interstitial that takes precedence over all UI. This is that.

## 2. Decisions (Leo, 2026-07-17)

| # | Decision | Choice |
|---|---|---|
| 1 | Trigger model | **Symptom identity alone, severity-independent.** A fixed set of red-flag symptoms fires the interstitial whenever logged, regardless of the 1–10 severity. A safety net must never miss a real emergency because the person under-rated it; over-firing is a safe failure, under-firing is not. |
| 2 | Scope of red-flags | **Physical emergencies this cycle.** The cardiac/respiratory cluster (already in the catalog) + a new "Severe Allergic Reaction" (anaphylaxis) entry. Self-harm / mental-health crisis → its own next round (§7). |
| 3 | Log handling + actions | **Save the symptom first, then take over.** The screen offers **Call 911** (primary), **Find nearest ER**, and **Dismiss**. Never gate the user's data behind the safety screen; never trap them. |
| 4 | Repeat handling | **Always show, with opt-in per-symptom muting** (reversible in Settings). No silent auto-throttle — a suppressed warning is the one failure mode a safety net can't have. |
| 5 | Firing scope | **Live, foreground, user-initiated new symptom logs only** — the capture sheet and voice capture. **Never** on import / backfill / HealthKit sync, or on edits of past events. |

**Rejected:** severity thresholds and symptom combinations (miss genuine single-symptom emergencies; wrong trade for a safety net); silent auto-throttling of repeats (suppresses a warning without the user knowing); gating the log behind the screen (risks losing deliberately-entered data).

## 3. Architecture & module layout

The "is this a red flag?" decision is pure and deterministic → **HealthGraphCore**. Everything user-facing is a thin app layer. Same split as 2A/2B.

```
HealthGraphCore/Sources/HealthGraphCore/
  Safety/
    RedFlagCatalog.swift      // NEW — static table: RedFlagCategory, RedFlagRule, rules[], rule(forSymptomKey:)
    RedFlagEvaluator.swift     // NEW — pure evaluate(symptomKey:mutedKeys:) -> RedFlagMatch?
  Capture/
    SymptomCatalog.swift       // + one entry: "Severe Allergic Reaction"

Views/HealthOS/Safety/
    RedFlagInterstitialView.swift  // NEW — full-screen takeover (copy + 3 actions + guarded mute)
    RedFlagRemindersView.swift     // NEW — Settings list: per-symptom reminder toggles
    RedFlagPresenter.swift         // NEW — @MainActor ObservableObject; holds pending: RedFlagMatch?
    RedFlagMuteStore.swift         // NEW — RedFlagMuteStoring (UserDefaults-backed) + protocol
    EmergencyContact.swift         // NEW — regionalizable tel:// number + Maps ER URL builder (pure, testable)

<capture save site>                // + evaluate + hand off to presenter (§6)
<root view>                        // + .fullScreenCover(item: presenter.pending)
<Profile/More settings>            // + "Safety reminders" row → RedFlagRemindersView
```

Each unit is independently testable: the evaluator and mute store have no view dependencies; the views have no decision logic.

## 4. The red-flag table & evaluator

### 4.1 Types (core)

```swift
public enum RedFlagCategory: Sendable, Equatable {
    case medicalEmergency          // this cycle. Future: mentalHealthCrisis
}

public struct RedFlagRule: Sendable, Equatable {
    public let symptomKeys: [String]     // SymptomCatalog canonicalKeys
    public let category: RedFlagCategory
    public let extraGuidance: String?    // e.g. anaphylaxis epinephrine line; nil otherwise
}

public struct RedFlagMatch: Sendable, Equatable, Identifiable {
    public let symptomKey: String
    public let category: RedFlagCategory
    public let extraGuidance: String?
    public var id: String { symptomKey }
}
```

### 4.2 The set

- **Cardiac / respiratory (already in the catalog):** Chest Pain · Lower Chest Pain · Chest Tightness · Upper Chest Tightness · Breathing Difficulty · Shortness of Breath. `category: .medicalEmergency`, `extraGuidance: nil`.
- **Severe Allergic Reaction (new catalog entry):** `category: .medicalEmergency`, `extraGuidance: "If you have an epinephrine auto-injector (EpiPen), use it now, then call 911."`

The table **derives its canonical keys from `SymptomCatalog` by display name** (via `SymptomCatalog.canonicalKey(for:)`) rather than hardcoding key strings, so a future symptom rename can't silently drift a red-flag entry out of sync. A unit test asserts every referenced display name resolves to a real catalog entry.

### 4.3 The evaluator

```swift
public enum RedFlagEvaluator {
    /// Severity-independent, mute-aware, pure. Returns the match iff the key is a
    /// red flag AND not muted; nil otherwise.
    public static func evaluate(symptomKey: String, mutedKeys: Set<String>) -> RedFlagMatch?
}
```

No severity parameter (decision 1), no `Date()`, no I/O. The muted set is passed in — the store provides it, the evaluator stays pure.

### 4.4 Catalog-reachability caveat

`SymptomCatalog` is body-region organized (symptoms hang off a body-map picker); "Severe Allergic Reaction" is systemic and has no region. The plan must ensure it is **reachable in the capture UI** — a "General / Systemic" grouping or via symptom search — not merely present in the data. The exact mechanism is resolved in the plan against the real picker code.

## 5. The interstitial screen

A full-screen cover presented from the root (`.fullScreenCover(item:)`), so it sits above every tab and sheet — the "precedence over all UI" the ui-design doc requires. Visually **urgent but calm**: high-contrast, a red primary action, distinct from the app's usual serif/paper calm, while respecting Dynamic Type and light/dark and never relying on color alone.

### 5.1 Copy (symptom-aware, non-diagnostic)

> **This could be serious**
> You just logged **{symptom display name}**. Symptoms like this can be a medical emergency. If it's severe, came on suddenly, or is getting worse, call 911 or get emergency care now.
>
> *[when `extraGuidance != nil`, shown prominently]* **{extraGuidance}**
>
> This isn't medical advice or a diagnosis — when in doubt, get checked.

### 5.2 Actions (by prominence)

1. **Call 911** — large red primary (≥44pt), VoiceOver "Call nine one one". Dials via `EmergencyContact.emergencyNumberURL` (`tel://911`).
2. **Find nearest ER** — opens Apple Maps searching "emergency room near me" via `EmergencyContact.nearestERURL`.
3. **Dismiss** — quiet text ("I'm okay — dismiss"); clears `presenter.pending`; returns the user where they were. Always available.

### 5.3 Guarded mute affordance

Least-prominent element, bottom of screen: "Stop reminding me about {symptom}." Because muting a red flag is high-stakes, tapping it opens a **confirmation** (not an instant toggle):

> Turn off the seek-care reminder for **{symptom}**? You'll still be able to log it — you just won't see this screen. You can turn it back on anytime in **Settings → Safety reminders**.
> [Turn it off] · [Cancel]

Confirm → `muteStore.mute(key)` → dismiss.

### 5.4 Accessibility

Call 911 is a ≥44pt target with an explicit label; the takeover posts a VoiceOver screen-changed announcement; actions scroll rather than clip at XXL Dynamic Type; no color-only signalling.

## 6. Muting — storage & Settings

### 6.1 Store

```swift
protocol RedFlagMuteStoring {
    var mutedKeys: Set<String> { get }
    func mute(_ key: String)
    func unmute(_ key: String)
    func isMuted(_ key: String) -> Bool
}
```

`RedFlagMuteStore` is an `@MainActor ObservableObject` with `@Published private(set) var mutedKeys: Set<String>`, persisted to `UserDefaults` on every change; behind the protocol so tests inject an isolated store (no global `UserDefaults` pollution). It is **app preference state, not health-graph data** — never in the event graph, never synced, never in a doctor report.

### 6.2 Settings surface — "Safety reminders"

A new row in the existing Profile/More settings area → `RedFlagRemindersView`:
- Header: *"When you log one of these symptoms, {App} reminds you to consider urgent care. These aren't diagnoses. Turn any off if the reminder isn't useful for you — you can turn it back on here anytime."*
- Lists **every** red-flag symptom with a per-symptom toggle. ON = reminder active (default); OFF = muted. Showing the full list keeps the feature discoverable when nothing is muted, and re-enabling is one tap.
- Toggling here is direct (no confirmation) — being in this screen is already deliberate; the in-the-moment interstitial mute is the one that confirms.

The loop: interstitial "Stop reminding me…" → confirm → `mute`; Settings toggle ↔ `mute`/`unmute`; next log of that symptom → `evaluate(...)` returns `nil` → no takeover. One source of truth, observable in both places.

## 7. Capture hook, data, and firing scope

### 7.1 Hook placement — UI capture layer, never the data layer

The evaluation call goes at the **symptom-capture save site** (`SymptomCaptureView`'s `log(...)` completion, and the equivalent point in the voice-save path), **not** in `EventStore.save`, which import/backfill/sync also flow through. This physically enforces decision 5: bulk and historical writes can't reach the trigger.

```
symptom saves (HealthEvent returned)
  → RedFlagEvaluator.evaluate(symptomKey:, mutedKeys: muteStore.mutedKeys)
  → if match: presenter.pending = match
  → root's .fullScreenCover(item:) presents RedFlagInterstitialView
```

Voice can parse several symptoms at once; the presenter holds **one** pending match, so co-occurring red-flags show the first and every log still captures. **No hook in the edit path.**

*Integration note:* presenting a full-screen cover exactly as the capture sheet dismisses can race in SwiftUI. Drive the cover from the root off `presenter.pending` so sheet-dismiss and cover-present sequence cleanly; verify on device.

### 7.2 Data / telemetry

None added. The symptom log is already the record; mute state is local preference. No "interstitial shown" event, no analytics — consistent with the on-device, minimal-footprint ethos. Easy to add later if a doctor report wants it.

## 8. Testing

- **Pure core (`swift test`):**
  - `RedFlagEvaluatorTests` — red-flag key → match; non-red-flag key → nil; muted key → nil; anaphylaxis `extraGuidance` present, cardiac/respiratory nil; evaluator takes no severity input.
  - `RedFlagCatalogTests` — **drift guard**: every referenced display name resolves to a real `SymptomCatalog` entry; "Severe Allergic Reaction" exists; `rule(forSymptomKey:)` lookups.
  - `EmergencyContactTests` — correct `tel://` and Maps URLs (one regionalization point).
  - `SymptomCatalogTests` — the new entry exists and its canonical key is stable.
- **App target (`-parallel-testing-enabled NO`):**
  - `RedFlagMuteStoreTests` — mute/unmute/persist/isMuted, isolated `UserDefaults` suite.
  - `RedFlagPresenterTests` — red-flag + not muted → `pending` set; muted → nil; non-red-flag → nil (the hook logic, without the view).
- **Views:** `RedFlagInterstitialView` + `RedFlagRemindersView` are build + preview verified (no snapshot infra, same as 2B).
- **End-to-end (on device):** log a red-flag symptom → takeover; mute → silent next time; backfill/import → silent; Settings toggle round-trips. On device, given simulator gesture-automation limits.

## 9. Out of scope (this cycle)

- **Self-harm / mental-health crisis** red-flags and the 988 flow — dedicated next round (distinct resource, tone, and no "log and move on"; higher stakes for wrong copy).
- **Regionalization** beyond a single `EmergencyContact` constant — 911 ships now; the constant is the one place to localize later.
- **Telemetry / doctor-report integration** of interstitial events.
- **Combinations, severity gates, auto-throttling** (rejected, §2).
- No changes to the evidence engine, extraction, scoring, migrations, or the Insights surface.
