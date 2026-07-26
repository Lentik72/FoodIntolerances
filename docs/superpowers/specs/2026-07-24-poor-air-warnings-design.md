# Proactive poor-air warnings — design

**Status:** approved for implementation planning
**Date:** 2026-07-24
**Queue position:** follow-up #4 (last) of the "harden before expanding" round, after demo-data hygiene (PR #7, `c0f3271`).

## Problem

The app already fetches a next-24h **forecast** AQI (`EnvironmentalDataService.forecastAQI`, OpenWeather `/air_pollution/forecast` → mean PM2.5 → EPA AQI) but does nothing user-facing with it — it's only surfaced indirectly through the Health "Environment" fetch-health screen. A user can open the app on a day forecast to be unhealthy and get no heads-up. This round turns that already-fetched signal into a calm, dismissible **Home warning** — and, when the evidence graph already links poor-air days to one of the user's symptoms, a personal line.

## Goals

1. **Proactive, forecast-based heads-up**: when the next-24h forecast AQI is unhealthy, warn on Home the moment the user foregrounds the app.
2. **Universal protection, personalized when possible**: everyone sees the base warning; a user with a demonstrated poor-air→symptom pattern also sees a personal line.
3. **Calm, not naggy, not alarmist**: once per local calendar day while air stays poor, re-showing only when the forecast worsens to a higher EPA band; tone scales with severity but never enters the emergency/red-flag interstitial system.

**Non-goals:** no new AQI provider/endpoint (reuse `forecastAQI`); no notifications and no background fetch (in-app only, detection on foreground); no change to event ingestion or mining (the warning is display-only).

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Reuse `EnvironmentalDataService.forecastAQI` — no new fetch | It already runs in the foreground environmental pass, reuses the trusted location resolution, tracks `.forecastAirQuality` failures independently, and stays outside ingestion/mining. A current-observation endpoint would be duplicate infrastructure. |
| 2 | Copy is **forecast-oriented** ("forecast to be unhealthy"), not "current" | `forecastAQI` is a next-24h forecast, not a live observation. |
| 3 | In-app Home banner; no notification, no background | Detection is foreground-only (the env pass runs on `.task` / scene-active / recovery). A calm in-app surface fits the moment of detection without new permissions or background work. |
| 4 | Universal base warning + optional personalized line | Poor air is a universal risk (the EPA threshold is itself the trigger); a personal line adds relevance when the graph supports it, without gating the base warning on weeks of data. |
| 5 | Personalization from the **evidence graph**, not legacy `AIMemory` | The graph is the current source of truth for mined relationships. |
| 6 | Trigger at AQI ≥ 101; bands from `AirQualityIndex.category(aqi:)` | Reuses the existing `poorAirThreshold` and the single EPA-breakpoint source; the warning core never duplicates numeric ranges. |
| 7 | Once per local calendar day; re-show on band **escalation** | Keeps a multi-day episode visible without nagging every foreground; a worsening forecast is worth re-surfacing. |
| 8 | Persist the **highest DISMISSED band for the local day**, not "last shown" | An undismissed warning must stay eligible after relaunch; dismissing a band suppresses that band and lower ones for the day, while a higher band can still reappear. |
| 9 | Fail-safe: `forecastAQI == nil` ⇒ no warning | Absence of data (fetch failure, denied/fabricated location, keyless build) is never a warning. The Health screen already explains *why* ("Air quality unavailable"). |
| 10 | Tier-specific, EPA-derived guidance + salience | One mild sentence across all four bands would understate a severe forecast; EPA distinguishes sensitive-groups (101–150) from general-population (151–300) from hazardous (301+). |
| 11 | Dedicated default-on preference `hg.poorAirWarningsEnabled` | The legacy `enableEnvironmentalAlerts` is notification-oriented; a fresh in-app toggle keeps concerns separate. |
| 12 | Decide only on a **settled, pass-scoped** forecast state (`.pending`/`.value`/`.unavailable`); fix the not-configured path to clear the stale value | `forecastAQI` persists across passes and the invalid-URL path leaves it uncleared, so Home could show/dismiss yesterday's tier before today's attempt settles. |
| 13 | Persist the dismissed band as a **stable raw token**, not `name` or `severityRank` | Localized copy or a renumbered ordering would corrupt stored dismissals. |
| 14 | Humanize the personal symptom via **`SymptomCatalog.displayName(for:)`**; sort the tiebreak on the raw subtype | `InsightPhrasing.outcomeLabel(for:)` returns non-mood subtypes unchanged, so it would surface raw identifiers. |
| 15 | Personalization failure **degrades to the base warning**, never suppresses it; guard against **async-staleness** | A symptom-lookup error must not hide a real hazard, and a late lookup must not clobber a newer forecast's decision. |

## Design

### 1. Data source + forecast freshness

`EnvironmentalDataService.forecastAQI: Int?` (`@Published`) is the AQI value. It is:
- populated in the foreground environmental pass from `/air_pollution/forecast` (next-24h mean PM2.5 → `AirQualityIndex.epaAQI`),
- `nil` on most failures (no location / untrusted-denied-fabricated location / HTTP error / insufficient data), with the failure recorded against the `.forecastAirQuality` capability,
- display-and-warning-only; **never** ingested as a mined `airQuality` event (mining stays `observedCompletedDay` only).

**Freshness is load-bearing and NOT safe today.** `forecastAQI` retains the *previous* pass's value while a new foreground pass is in flight, and — a real bug — the not-configured/invalid-URL path (`EnvironmentalDataService.swift:589`) records a failure **without** clearing the old value. So Home could evaluate (and let the user dismiss) yesterday's tier before today's attempt settles, and a stale dismissal could then suppress today's real forecast. The design therefore requires a **pass-scoped freshness state** on the service, e.g.:

```
enum ForecastAQIState { case pending, value(Int), unavailable }
@Published var forecastAQIState: ForecastAQIState = .pending
```

- Set `.pending` at the START of each `fetchAirQuality()` pass; set `.value(aqi)` / `.unavailable` on **every** settle path — including fixing the not-configured branch to `.unavailable` (and clearing the stale `forecastAQI`).
- The cancellation bail (`Task.isCancelled` → return) must not leave a permanently `.pending` state that a superseding pass won't resolve — the superseding pass re-enters `.pending` then settles, which is the intended "newer refresh wins" behaviour; the state must reflect the LATEST pass only.
- **Home decides only on a settled state** (`.value` / `.unavailable`); while `.pending` it holds its current decision (no flicker, no premature show/dismiss). `.unavailable` ⇒ `.none` (fail-safe).

Regression tests (§Testing) must cover: an old AQI value present → a new pass goes `.pending` → settles to healthy / failure / cancellation, and prove Home never decides on the stale value nor lets a stale dismissal suppress the newer settled result.

### 2. Tier ordering (small addition to `AirQualityIndex`)

`AirQualityIndex.category(aqi:)` already maps an AQI to an `AQICategory` (good / moderate / unhealthySensitive / unhealthy / veryUnhealthy / hazardous) via the single EPA-breakpoint table. Add two things to `AQICategory` (the only changes to `AirQualityIndex`):
- a **severity ordering** (`severityRank: Int` and/or `Comparable`) so the warning core can compare bands ("higher than the highest I dismissed today?") **without** re-stating any numeric ranges;
- a **stable persistence token** — a fixed `String` per case (e.g. `"unhealthy"`), with a matching `init?(persistedToken:)`, used only by the dismissed-state store. This is deliberately distinct from `name` (localized display text) and from `severityRank` (an ordering that could be renumbered): persisting either would make stored dismissals fragile across copy or ordering changes. The token strings are frozen and covered by a round-trip test.

### 3. Decision core (pure, `HealthGraphCore`)

A pure function/struct — `PoorAirWarningDecision` — with **no** I/O, date math, `@AppStorage`, or SwiftUI:

```
decide(
  forecastAQI: Int?,           // the reused service value
  highestDismissedBandToday: AQICategory?,   // nil if nothing dismissed for today's local day
  personalizedSymptom: String?  // humanized symptom label, or nil
) -> Outcome
```

`Outcome` is either `.none` or `.show(aqi: Int, band: AQICategory, personalizedSymptom: String?)`. Rules:
- `forecastAQI == nil` OR `aqi < poorAirThreshold` ⇒ `.none` (fail-safe + below threshold).
- Otherwise `band = AirQualityIndex.category(aqi:)`; show iff `highestDismissedBandToday == nil` **or** `band` is strictly higher severity than `highestDismissedBandToday`.

All day-scoping lives in the state store (§5): the caller resolves `highestDismissedBandToday` for the current local day before calling `decide`, so the core itself needs no `Date`/`Calendar` and is trivially deterministic. The core is enable-toggle-agnostic: the caller skips it entirely when the preference is off.

### 4. Personalization lookup (`HealthGraphCore`)

A query over the relationship store returning the best matching symptom label, or `nil`:
- Match relationships with `status == .active` AND `fromCategory == "poorAirDay"` AND `toCategory == "symptom"` AND `type == .possibleTrigger`.
- If several qualify, choose **deterministically** by `confidence` (desc), then `evidenceCount` (desc), then the **raw** `toSubtype` (asc) — the tiebreak sorts on the stable identifier, not on display text.
- Humanize the chosen edge's `toSubtype` for display via **`SymptomCatalog.displayName(for:)`** (HealthGraphCore, `Capture/SymptomCatalog.swift:209`). Note: `InsightPhrasing.outcomeLabel(for:)` returns a non-mood `toSubtype` **unchanged**, so it would surface the raw identifier — do not use it here. If `SymptomCatalog` has no entry for the key, fall back to the raw subtype (never crash).

### 5. Dismissed-state store (app, UserDefaults)

Persists, per **local calendar day**, the highest AQI band the user has dismissed:
- key namespace `hg.poorAir.*` (day key derived with the app's local `Calendar`);
- the band is stored as its **stable persistence token** (§2), never `name` or `severityRank`;
- `highestDismissedBandToday(now:calendar:)` → `AQICategory?` (returns `nil` once the local day rolls over — a new day is fully eligible again; an unrecognized/legacy token also reads as `nil` rather than crashing);
- `recordDismissed(band:now:calendar:)` → stores `max(existing, band)` for today's local day.
Injecting `Calendar` makes day-rollover deterministic in tests.

### 6. Home surface + composition (app)

A small view-model assembles the inputs and drives a dismissible **banner at the top of Home**:
- reads `forecastAQIState` (observes the service — §1), the preference `hg.poorAirWarningsEnabled`, and the dismissed-state store;
- **maps the settled state to the core's `Int?`**: `.value(x) → x`, `.unavailable → nil`, `.pending → do not re-decide` (hold the current banner);
- runs the personalization lookup + `decide(...)` on foreground / when `forecastAQIState` settles;
- guards against **async staleness** (below): a personalization lookup that returns after the AQI has changed must not overwrite the newer decision;
- on `.show`, renders the banner; on dismiss, calls `recordDismissed(band:)` and hides it.

**Async staleness guard:** the personalization lookup is `async`. Capture the AQI (and/or a monotonically increasing request token) when the lookup starts; when it returns, apply its result only if the current settled AQI still matches — otherwise discard it (a newer settle already re-decided). This prevents an older symptom lookup from clobbering a newer forecast's decision.

**Personalization is non-suppressing:** a personalization-query *failure* (or empty result) degrades to `personalizedSymptom = nil` — the universal base warning still shows. A lookup problem must NEVER suppress the warning.

**Banner content**, by band:
- Title: **"Air quality is forecast to be unhealthy"** (301+: **"Air quality is forecast to be hazardous"**).
- The AQI value + EPA category name (`AQICategory.name`).
- One **tier-specific guidance** line, matching the current AirNow particle-pollution (PM2.5) activity table in meaning. These are the **finalized strings**, pinned in tests:
  - **101–150 (unhealthySensitive):** "Sensitive groups should reduce prolonged or heavy outdoor exertion."
  - **151–200 (unhealthy):** "Sensitive groups should avoid prolonged or heavy outdoor exertion; everyone else should reduce it."
  - **201–300 (veryUnhealthy):** "Sensitive groups should avoid all outdoor physical activity; everyone else should avoid prolonged or intense outdoor activity."
  - **301+ (hazardous):** "Everyone should avoid all outdoor physical activity; sensitive groups should stay indoors and keep activity low."
- When `personalizedSymptom != nil`: one tentative personal line, phrased like Insights ("Poor-air days have been linked to your \<symptom\>.").
- **Salience scales with band** (e.g. muted → more prominent color/weight as severity rises) but the banner is **always dismissible and never a takeover** — it stays outside the red-flag/crisis interstitial system, which is reserved for physical emergencies and self-harm.

**Root previews:** `HealthOSRootView` mounts Home eagerly; once Home observes `EnvironmentalDataService`, its two `#Preview` blocks (and any other root preview) must inject an `EnvironmentalDataService` instance, or they crash at render (the same lesson as the demo-hygiene `GraphMutationCoordinator` preview fix).

### 7. Settings

A dedicated default-on `@AppStorage("hg.poorAirWarningsEnabled")` toggle, surfaced in the app's settings/Health area. When off, the Home VM never evaluates or shows the banner. The legacy `enableEnvironmentalAlerts` is untouched.

## Data flow

Foreground → env pass runs `fetchAirQuality()`, driving `forecastAQIState` `.pending → .value(aqi) | .unavailable` → Home VM (only when settled): if `hg.poorAirWarningsEnabled`, map the state to `Int?`, run the (staleness-guarded) personalization lookup + `PoorAirWarningDecision.decide(...)` with today's `highestDismissedBandToday` → `.show` renders the banner / `.none` hides it. While `.pending`, the VM holds its current banner. Dismiss → `recordDismissed(band:)` → banner hides for that band and lower until the local day rolls over.

## Testing

**HealthGraphCore (pure)**
- `AQICategory` severity ordering: good < moderate < unhealthySensitive < unhealthy < veryUnhealthy < hazardous; and a **persistence-token round-trip** (`token → init?(persistedToken:) → same case`; unknown token → nil).
- Decision core: `aqi == 100` ⇒ none, `aqi == 101` ⇒ show(unhealthySensitive); nil ⇒ none; band mapping matches `category(aqi:)`; suppressed when `highestDismissedBandToday` equals the current band; **re-shown** when the current band is strictly higher than the dismissed band; personalized symptom passed through into the outcome.
- Personalization lookup: picks the active `poorAirDay→symptom possibleTrigger` edge; the deterministic tiebreak (confidence, then evidenceCount, then **raw** subtype); humanizes via `SymptomCatalog.displayName(for:)`; returns nil when no qualifying edge; ignores non-active / wrong-category / wrong-type edges.

**App**
- **Forecast freshness (regressions for the P1):** an old `forecastAQI` present → a new pass goes `.pending` → settles to `.value` (healthy) / `.unavailable` (failure incl. the fixed not-configured path) / cancellation — proving Home (a) never decides on the stale value while `.pending`, and (b) never lets a stale dismissal suppress the newer settled result.
- **Async-staleness:** a personalization lookup returning after the AQI changed does not overwrite the newer decision.
- **Personalization non-suppression:** a failing/empty lookup still shows the base warning (`personalizedSymptom == nil`).
- Dismissed-state store: `recordDismissed` stores the max band for the local day, persisted as the stable token; `highestDismissedBandToday` returns nil after a day rollover (injected `Calendar`) and on an unrecognized token; survives a round-trip.
- Home VM: with the toggle off, never shows; band-specific guidance selected per tier — **the four finalized strings pinned verbatim**; minimal banner render.
- Copy: the four tier strings match §6 exactly (guards against silent edits).

## Accepted limitations

- **Forecast, not live**: the warning is a next-24h forecast, so it can differ from the air outside at the exact moment of reading. Copy says "forecast" to set that expectation. A live-observation source is a future provider decision, out of scope here.
- **Foreground-only detection**: no background fetch, so the warning appears when the user opens/foregrounds the app, not proactively while it's closed. A background AQI check (the unimplemented nightly BGTask) is a separate future round.
