# Weight Units (Timeline Display) — Design

**Date:** 2026-07-21
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Show **Timeline weight events** (body-mass samples) in the user's chosen unit — **pounds** or **kilograms** — instead of the current hardcoded `kg`. Display-only; HealthKit and the database stay canonically in kilograms. **Reuses the existing profile `unitPreference` (Imperial/Metric)** — no new competing setting. Follow-up #1 after the merged air-quality/ingestion work.

**Not touched:** the profile's own height/weight entry (already unit-aware via `unitPreference`); temperature units (shipped, its own `hg.temperatureUnit`); the evidence engine / storage / HealthKit values.

---

## 1. Problem

Weight events render a hardcoded `"%.1f kg"` in `EventDisplay` (HealthGraphCore, pref-unaware), so a US user who set **Imperial** in their profile still sees **kg** in the Timeline. The app already has a weight-unit preference — `UserProfile.unitPreference` ("imperial"/"metric", governing profile height/weight entry with a `kg ↔ lbs` conversion) — it just doesn't reach the Timeline. We reuse that single preference rather than adding a third units system (temperature has `hg.temperatureUnit`, the profile has `unitPreference`).

## 2. Decisions (Leo, 2026-07-21)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Source of truth | **Reuse `UserProfile.unitPreference`** (Imperial → lb, Metric → kg). NO new `hg.weightUnit`. |
| 2 | No-profile fallback | **Locale:** US → pounds, otherwise kilograms. |
| 3 | Canonical storage | **Kilograms** in HealthKit + DB; convert ONLY for display. |
| 4 | Lookup | **Single parent-level profile lookup** near `TimelineView`, resolved to a `WeightUnit` and passed down to rows/detail — NOT a `UserProfile` query per Timeline row. |
| 5 | Precision | One decimal: `81.4 kg` / `179.5 lb`. |
| 6 | Core independence | `EventDisplay`'s canonical `kg` rendering stays as the FALLBACK; **HealthGraphCore must NOT depend on the SwiftData `UserProfile`.** |
| 7 | Setting UI | The preference already lives in `UserProfileView` (Imperial/Metric picker). **No new Health-tab weight picker** (unlike temperature — this reuses an existing control). |

## 3. Architecture

Mirrors the shipped temperature-unit split (`WeatherValueFormatter` app-side, `EventDisplay` pure/fallback), adapted to read the profile once at the parent.

### A. `WeightUnit` + `BodyMetricValueFormatter` (app-side, new)

- **`WeightUnit`** — `enum { case kilograms, pounds }`.
  - `static func resolved(from profile: UserProfile?, locale: Locale = .current) -> WeightUnit` — `profile?.unitPreference == "imperial"` → `.pounds`; `"metric"` → `.kilograms`; **no profile** → `locale.measurementSystem == .us ? .pounds : .kilograms`. (Locale injectable for testability, mirroring `TemperatureUnit.localeDefault`.)
- **`BodyMetricValueFormatter`** — peer to `WeatherValueFormatter`, app-side, pure:
  - `static func line(for event: HealthEvent, unit: WeightUnit) -> String?` — for a weight event (`category == .bodyMetric`, `subtype == "weight"`, `unit == "kg"`, `value` in kg): convert (`.pounds` → `kg * 2.20462`, else kg), format `String(format: "%.1f %@", shown, unit.abbrev)` → `"179.5 lb"` / `"81.4 kg"`. Returns **nil** for any non-weight event, so the caller falls back to `EventDisplay.valueLine`.

### B. Single parent-level resolution (`TimelineView`)

- `TimelineView` gains `@Query private var userProfiles: [UserProfile]` (the pattern already used by `MainTabView`/`LogSymptomView`) and computes `weightUnit = WeightUnit.resolved(from: userProfiles.first)` ONCE.
- It passes the resolved `weightUnit` into `TimelineEventRow` (a new `weightUnit: WeightUnit` prop) and into `EventDetailView` via the `navigationDestination` closure (which already has `TimelineView` scope) — so neither the row nor the detail queries `UserProfile` itself.

### C. Display wiring (`TimelineEventRow`, `EventDetailView`)

- Both render a weight event's value via `BodyMetricValueFormatter.line(for: event, unit: weightUnit) ?? EventDisplay.valueLine(for: event)` — exactly the `WeatherValueFormatter ?? EventDisplay` chain already used for temperature/humidity. The a11y/VoiceOver value uses the same resolved string.
- `EventDisplay` (core) is unchanged — its `"%.1f kg"` stays as the pure fallback (also what any surface we don't touch keeps showing).

## 4. Reused / unchanged

- The `WeatherValueFormatter ?? EventDisplay.valueLine` display pattern in `TimelineEventRow`/`EventDetailView` (weight rides the same seam).
- `UserProfile.unitPreference` + its `UserProfileView` Imperial/Metric picker (the setting UI — no duplication).
- **`EventDisplay` stays pure/pref-unaware; HealthGraphCore gains no `UserProfile` dependency.**

## 5. Testing

- **App (`-parallel-testing-enabled NO`):**
  - `BodyMetricValueFormatter` — a weight event 81.4 kg → `"81.4 kg"` (kilograms) and `"179.5 lb"` (pounds: 81.4 × 2.20462 = 179.46 → 179.5); a non-weight event → nil (falls back to `EventDisplay`); rounding lands on the .05 boundary sensibly.
  - `WeightUnit.resolved` — profile `unitPreference == "imperial"` → `.pounds`; `"metric"` → `.kilograms`; **no profile + US locale → `.pounds`**, **no profile + non-US locale → `.kilograms`** (inject the locale).
- **Device:** a weight event in the **Timeline row** and the **detail screen** shows the profile's unit (set Imperial in the profile → `lb`; Metric → `kg`); with no profile, a US device shows `lb`; VoiceOver reads the same value.

## 6. Out of scope

- A separate `hg.weightUnit` setting or a Health-tab weight picker (rejected — reuse `unitPreference`).
- The profile's own height/weight entry (already unit-aware).
- Temperature units (shipped) and height display on the Timeline (no height events).
- Any dashboard/analytics weight rendering that doesn't go through `EventDisplay` (none identified; a later pass if one surfaces).
- Fixing `UserProfile.unitPreference`'s hardcoded `"imperial"` default (a pre-existing profile quirk — note only: a metric-locale user with an untouched profile sees imperial until they set it; the no-profile path correctly uses locale).

## 7. Next / future

- If a dashboard weight chart or logging screen surfaces that bypasses `EventDisplay`, route it through `BodyMetricValueFormatter` too.
- (Independent follow-ups already queued: accessible AQI badges, hide the display-only season, moon-phase SF Symbols.)
