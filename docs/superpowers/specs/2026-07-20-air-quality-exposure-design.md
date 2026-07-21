# Air Quality Exposure — Design

**Date:** 2026-07-20
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Ingest **air quality** (PM2.5 → US EPA AQI) as a NEW **established-tier** health exposure, correlate it with symptoms/mood through the existing evidence engine (like weather), surface it in Insights and the Environment Timeline row, and lead the collapsed Environment headline with the AQI on a poor-air day. First step of the "warn sensitive people" arc.

**Not touched:** the evidence gates, the tier framework, weather/moon/mercury exposures, the units picker. Air quality reuses the weather ingestion + the Environment summary row.

---

## 1. Problem

The app mines environmental exposures (weather, pressure, moon) but not **air quality** — the most established environmental health factor for sensitive people (PM2.5 fine particulates → respiratory/cardiac/migraine effects, well-documented). Adding it lets the engine surface "poor air days → your symptom" as a **credible** (established-tier) relationship, and lays the ingestion groundwork the later pollen and proactive-warning rounds reuse.

## 2. Decisions (Leo, 2026-07-20)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Signal | **US EPA AQI computed from PM2.5** (fine particulates — the dominant driver of bad-air days: wildfire smoke, traffic, inversions). Ozone/other gases deferred. |
| 2 | Threshold model | **Absolute health thresholds, NOT personal-percentile** — a deliberate reversal of the weather decision. AQI is physiologically universal ("unhealthy" means the same everywhere), and a typical user has mostly-good air with occasional spikes, so absolute thresholds give natural contrast (not the climate-degeneracy that forced percentiles for temperature). |
| 3 | Exposure | **One binary `poorAirDay` = AQI ≥ 101** ("Unhealthy for Sensitive Groups" or worse; ⟺ daily-mean PM2.5 ≥ ~35.5 µg/m³). |
| 4 | Tier | **Established** (automatic — `PlausibilityCatalog` defaults to `.established`; no catalog change). No "unproven mechanism" tag. |
| 5 | Aggregation | **Day's mean PM2.5** over the next-24h forecast slots → EPA AQI (not a single app-open snapshot — the same open-time-bias fix as the weather high/low). |
| 6 | Timeline | **Folds into the Environment summary row** — an "Air quality" detail line always; and on a **poor-air day (AQI ≥ 101)** it **leads the collapsed headline** (`AQI 132 · Unhealthy for sensitive groups`). Normal-air days: headline unchanged. |
| 7 | Provider | OpenWeather `/air_pollution/forecast` (free, hourly, **same API key** as the existing weather ingestion). |

## 3. Architecture

Mirrors the weather pipeline. **Core owns the AQI math + mining; the app owns ingestion + display** (consistent with the existing split).

### A. AQI computation (core — pure, testable)

- **`AirQualityIndex`** (new, `HealthGraphCore`):
  - `epaAQI(pm25: Double) -> Int` — the standard EPA piecewise-linear breakpoint table (24-hr PM2.5 µg/m³ → AQI), concentration truncated to 0.1 per EPA convention. Breakpoints: `0.0–12.0→0–50`, `12.1–35.4→51–100`, `35.5–55.4→101–150`, `55.5–150.4→151–200`, `150.5–250.4→201–300`, `250.5–350.4→301–400`, `350.5–500.4→401–500`; above 500.4 clamps to 500.
  - `AQICategory` enum (`good, moderate, unhealthySensitive, unhealthy, veryUnhealthy, hazardous`) + `category(aqi: Int) -> AQICategory` and a `name` ("Good", "Moderate", "Unhealthy for sensitive groups", …). Used at display; `poorAirDay` = `aqi >= 101`.

### B. Ingestion (app)

- `APIConfig.airPollutionURL(latitude:longitude:)` → `\(base)/air_pollution/forecast?lat=&lon=&appid=` (no `units`; PM2.5 is µg/m³).
- `EnvironmentalDataService` — a `fetchAirQuality()` that GETs the URL, decodes `{ list: [{ dt, components: { pm2_5 } }] }`, and a **pure static** `meanPM25(slots:now:) -> Double?` aggregating PM2.5 over `dt ∈ [now, now+24h]` (≥3 slots else nil), then `AirQualityIndex.epaAQI(pm25:)`; sets `@Published var forecastAQI: Int?` (nil on failure/<3 slots). Reuse the existing pressure/forecast location-resolution path; call from `fetchAllData()`.
- `EnvironmentalReading` gains `airQualityAQI: Int?` (defaulted nil). `EnvironmentalEventEmitter.emitIfNeeded` threads `service.forecastAQI`; `backfillDerived` leaves it nil (no AQI history).

### C. The event (core)

- `EnvironmentalEventFactory.events(for:)` — when `airQualityAQI` present, emit ONE daily `.environment` event: `subtype: "airQuality"`, `value: Double(aqi)`, `unit: nil`, daily dedupKey. (No metadata; the category is derived from the AQI at display.)
- `EventDisplay`: `titles["airQuality"] = "Air quality"`; `valueLine` for `airQuality` → `"\(Int(value)) · \(AirQualityIndex.category(aqi: Int(value)).name)"` (e.g. `"132 · Unhealthy for sensitive groups"`). `EventDisplay` stays pure (AQI display needs no user pref).

### D. Mining (core)

- `DerivedExposureKind` gains `.poorAirDay`.
- **`AirQualityExposureSource`** (new, `ExposureSource`): for each `.environment`/`subtype == "airQuality"` event with `value >= 101`, emit `.derived(.poorAirDay)` keyed on that event. **Absolute threshold — no percentile, no min-readings guard** (each poor-air day is independently valid; the evidence gates handle significance).
- `EdgeIdentity`: `.poorAirDay ↔ "derived:poorAirDay"`. `EvidenceConfig.lagWindow(.poorAirDay)` = `outsideFactorLagHours` (same-day/next-day). `InsightPhrasing`: `"poorAirDay" → "Poor air quality"`. `PlausibilityCatalog`: **no change** — `"poorAirDay"` falls through to `.established`.

### E. Display (app)

- **Canonical order** — add `"airQuality"` to `EnvironmentDaySummaryBuilder.subtypeOrder` (core) after `"humidity"`: `temperature, humidity, airQuality, pressure, pressureDrop, moonPhase, season, mercuryRetrograde`. The summary's events sort by this, and the formatter renders them in that order.
- `EnvironmentSummaryFormatter`:
  - **detailLines** — because the events are pre-sorted, `airQuality` lands after Humidity automatically; rendered via `EventDisplay` → `"Air quality  132 · Unhealthy for sensitive groups"` (always shown when present, good or bad day). It is NOT folded like pressureDrop.
  - **headline** — new FIRST branch: if an `airQuality` event has `value >= 101`, return `"AQI \(aqi) · \(category.name)"` (leads with the bad-air signal). Otherwise the existing chain (temp·humidity → moon·season → degenerate) is unchanged.
- `InsightsViewModel` — add `"poorAirDay"` to the derived-token → `.environment` icon list (so the card gets the environment icon). Established tier ⇒ `InsightCardView` shows **no** "unproven mechanism" tag (that's contested/novelty only) — no card change needed.

## 4. Reused / unchanged

- The **weather ingestion pattern** (location resolution, 24h forecast aggregation, `@Published` → reading → factory), the **Environment summary row** (just shipped — air quality is one more detail line + a headline lead), `EventDisplay`/`EdgeIdentity`/`EvidenceConfig`/`InsightPhrasing`, and the **evidence gates + tier framework**.
- **No** percentile machinery (absolute threshold), **no** `PlausibilityCatalog` change (established is the default).

## 5. Testing

- **Core (`swift test`):**
  - `AirQualityIndexTests` — `epaAQI` at the category boundaries (PM2.5 `12.0→50`, `12.1→51`, `35.4→100`, `35.5→101`, `55.4→150`, `55.5→151`; a mid-bin value interpolates; `>500.4` clamps to 500); `category(aqi:)` names each band; `poorAirDay` boundary (`100` false / `101` true).
  - `EnvironmentalEventFactoryTests` — an `airQualityAQI` reading emits one `airQuality` event, `value == aqi`, daily dedupKey; nil AQI → no event.
  - `AirQualityExposureSource` — days with AQI ≥ 101 emit `.poorAirDay` (one per such day); AQI ≤ 100 emit nothing; non-airQuality subtypes ignored.
  - `EdgeIdentityTests` — `.poorAirDay` round-trips. `InsightPhrasingTests` — "Poor air quality". `PlausibilityCatalogTests` — `"poorAirDay" → .established`. `EvidenceConfigTests` — `lagWindow(.poorAirDay) == 0...24`.
- **App (`-parallel-testing-enabled NO`):**
  - `meanPM25(slots:now:)` — mean over in-window slots; excludes out-of-window; `< 3` → nil.
  - `EnvironmentSummaryFormatter` — a poor-air day (AQI 132) → headline `"AQI 132 · Unhealthy for sensitive groups"`; a good-air day (AQI 42) → headline still temp·humidity, and `"Air quality"` appears in detailLines in canonical position (after Humidity) with value `"42 · Good"`.
  - `InsightsViewModelTests` — a seeded `poorAirDay` edge surfaces as **established** (no unproven tag) with the environment icon.
- **Device:** the debug WEATHER seed (extended with poor-air days correlated to a symptom) → the Environment row shows an "Air quality" line; poor-air days lead the headline `AQI 132 · …`; Insights shows an **established** "Poor air quality → …" card (no unproven tag); light + dark.

## 6. Out of scope

- Ozone, NO₂, SO₂, CO, PM10 (PM2.5 covers most bad-air days; a max-of-sub-indices AQI is a later option).
- **Pollen** (the next round — different provider, its own threshold/seasonal modeling; reuses this template).
- **Proactive "poor air today" warnings / notifications** (the round after — this only ingests + correlates retrospectively).
- Personal-percentile fallback for chronically-polluted locations (add only if real data shows the absolute threshold saturating).
- AQI color coding in the UI, and a One Call / AirNow provider swap.

## 7. Next / future

- **Pollen** as the immediate next round (established, absolute thresholds, same Environment-row fold).
- **Proactive warnings** built on this ingestion (forecast AQI is already fetched) — a forward-looking alert surface, credibility-tiered per exposure.
- Ozone as a second pollutant (hot-sunny-day bad-air that PM2.5 misses), via the standard max-of-sub-indices AQI.
