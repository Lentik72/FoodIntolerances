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

## Design

### 1. Data source (reused, unchanged)

`EnvironmentalDataService.forecastAQI: Int?` (`@Published`) is the sole input. It is:
- populated in the foreground environmental pass from `/air_pollution/forecast` (next-24h mean PM2.5 → `AirQualityIndex.epaAQI`),
- `nil` whenever the fetch fails, the location is untrusted (denied/fabricated), or the key is absent — with the failure recorded against the `.forecastAirQuality` capability,
- display-and-warning-only; it is **never** ingested as a mined `airQuality` event (mining stays `observedCompletedDay` only). No change to this property or its fetch.

### 2. Tier ordering (small addition to `AirQualityIndex`)

`AirQualityIndex.category(aqi:)` already maps an AQI to an `AQICategory` (good / moderate / unhealthySensitive / unhealthy / veryUnhealthy / hazardous) via the single EPA-breakpoint table. Add a **severity ordering** to `AQICategory` (a `severityRank: Int` and/or `Comparable` conformance) so the warning core can compare bands ("is this forecast a higher band than the highest I dismissed today?") **without** re-stating any numeric ranges. This is the only change to `AirQualityIndex`.

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
- If several qualify, choose **deterministically** by `confidence` (desc), then `evidenceCount` (desc), then symptom name (`toSubtype`, asc).
- Return the chosen edge's `toSubtype`, humanized for display via the existing `InsightPhrasing` outcome-labelling so the copy reads naturally ("your cough", not "cough_v2").

### 5. Dismissed-state store (app, UserDefaults)

Persists, per **local calendar day**, the highest AQI band the user has dismissed:
- key namespace `hg.poorAir.*` (day key derived with the app's local `Calendar`);
- `highestDismissedBandToday(now:calendar:)` → `AQICategory?` (returns `nil` once the local day rolls over — a new day is fully eligible again);
- `recordDismissed(band:now:calendar:)` → stores `max(existing, band)` for today's local day.
Injecting `Calendar` makes day-rollover deterministic in tests.

### 6. Home surface + composition (app)

A small view-model assembles the inputs and drives a dismissible **banner at the top of Home**:
- reads `forecastAQI` (observes the service), the preference `hg.poorAirWarningsEnabled`, and the dismissed-state store;
- runs the personalization lookup and the decision core on foreground / when `forecastAQI` changes;
- on `.show`, renders the banner; on dismiss, calls `recordDismissed(band:)` and hides it.

**Banner content**, by band:
- Title: **"Air quality is forecast to be unhealthy"** (301+: **"Air quality is forecast to be hazardous"**).
- The AQI value + EPA category name (`AQICategory.name`).
- One **tier-specific, EPA-derived guidance** line:
  - **101–150 (unhealthySensitive):** sensitive groups (heart/lung conditions, older adults, children) should limit prolonged or heavy outdoor exertion.
  - **151–200 (unhealthy):** everyone should limit prolonged or heavy outdoor exertion; sensitive groups should avoid it.
  - **201–300 (veryUnhealthy):** everyone should avoid prolonged or heavy outdoor exertion; sensitive groups should stay indoors and keep activity light.
  - **301+ (hazardous):** everyone should avoid all outdoor exertion and stay indoors.
- When `personalizedSymptom != nil`: one tentative personal line, phrased like Insights ("Poor-air days have been linked to your \<symptom\>.").
- **Salience scales with band** (e.g. muted → more prominent color/weight as severity rises) but the banner is **always dismissible and never a takeover** — it stays outside the red-flag/crisis interstitial system, which is reserved for physical emergencies and self-harm.

### 7. Settings

A dedicated default-on `@AppStorage("hg.poorAirWarningsEnabled")` toggle, surfaced in the app's settings/Health area. When off, the Home VM never evaluates or shows the banner. The legacy `enableEnvironmentalAlerts` is untouched.

## Data flow

Foreground → env pass populates `forecastAQI` (or nil) → Home VM: if `hg.poorAirWarningsEnabled` and `forecastAQI != nil`, run personalization lookup + `PoorAirWarningDecision.decide(...)` with today's `highestDismissedBandToday` → `.show` renders the banner / `.none` hides it. Dismiss → `recordDismissed(band:)` → banner hides for that band and lower until the local day rolls over.

## Testing

**HealthGraphCore (pure)**
- `AQICategory` severity ordering: good < moderate < unhealthySensitive < unhealthy < veryUnhealthy < hazardous.
- Decision core: `aqi == 100` ⇒ none, `aqi == 101` ⇒ show(unhealthySensitive); nil ⇒ none; band mapping matches `category(aqi:)`; suppressed when `highestDismissedBandToday` equals the current band; **re-shown** when the current band is strictly higher than the dismissed band; personalized symptom passed through into the outcome.
- Personalization lookup: picks the active `poorAirDay→symptom possibleTrigger` edge; the deterministic tiebreak (confidence, then evidenceCount, then name); returns nil when no qualifying edge; ignores non-active / wrong-category / wrong-type edges.

**App**
- Dismissed-state store: `recordDismissed` stores the max band for the local day; `highestDismissedBandToday` returns nil after a day rollover (injected `Calendar`); survives a round-trip.
- Home VM: with the toggle off, never shows; with a nil forecast, never shows; band-specific guidance selected per tier; minimal banner render.

## Accepted limitations

- **Forecast, not live**: the warning is a next-24h forecast, so it can differ from the air outside at the exact moment of reading. Copy says "forecast" to set that expectation. A live-observation source is a future provider decision, out of scope here.
- **Foreground-only detection**: no background fetch, so the warning appears when the user opens/foregrounds the app, not proactively while it's closed. A background AQI check (the unimplemented nightly BGTask) is a separate future round.
