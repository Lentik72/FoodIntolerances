# Weather Exposures (Temperature + Humidity) — Design

**Date:** 2026-07-19
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Capture **temperature** and **humidity** (already present in the weather API payload, just not decoded), emit them as daily `.environment` events, and mine them as **personal-percentile** exposures — **Hot days / Cold days / Humid days** — presented as **contested** under the existing plausibility-tier framework. The committed final piece of the outside-factors arc.

**Not this round:** absolute thresholds (rejected — climate-degenerate, see §1), a low-humidity / "dry" exposure (weak mechanism), historical weather backfill (the current-conditions API has no history), and any change to the evidence gates, phrasing, or the tier UI (reused from [the outside-factors round]).

---

## 1. Problem

Barometric **pressure** is already mined from the OpenWeatherMap current-conditions call (`WeatherResponse.main.pressure`, fetched daily on app foreground, emitted as a `.environment` event). That same `main` object — fetched with `units=metric` (`APIConfig.swift:45`) — **also carries `temp` (°C) and `humidity` (%)**, which the app never decodes. People plausibly react to heat, cold, and humidity (migraine, joint pain, fatigue, mood), so these belong in the graph — honestly tiered, not asserted.

**Why percentile, not absolute, thresholds.** Temperature/humidity are *continuous*, so they must be bucketed into binary "days" for the engine (which correlates presence vs absence). A fixed threshold (e.g. "hot ≥ 27 °C") **breaks for most climates**: the engine needs *contrast* — both hot and not-hot days — to correlate, but a Phoenix user is ≥27 °C nearly every day (exposure fires ~100% → no contrast → unminable), while a London user rarely hits it (too few → never clears the gates). **Personal-percentile bucketing** ("hot = your top quartile") always yields ~25% exposure days with real contrast, *regardless of climate*, and is more semantically apt (the body responds to one's *relative* range and acclimatization). It is the robust foundation for a diverse future user base.

## 2. Decisions (Leo, 2026-07-19)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Factors | **Temperature + humidity**, captured going-forward from the existing OpenWeather call (no new integration; no historical backfill). |
| 2 | Bucketing | **Personal-percentile (quartile)** — per-user, computed over their own series. NOT absolute thresholds (climate-degenerate). |
| 3 | Exposures | **Three:** Hot day (temp ≥ p75), Cold day (temp ≤ p25), Humid day (humidity ≥ p75). Temperature has two mechanism-distinct poles (heat vs cold); humidity is one-directional (high). |
| 4 | Tier | **Contested** — plausible mechanism, mixed evidence. Renders in the evidence feed with the existing "unproven mechanism · your pattern" tag. |
| 5 | Cold-start | A **min-readings guard** (~20) before computing percentiles; aligns with the engine's own weeks-of-data cold-start. |

## 3. Architecture

### A. Ingestion — capture temp + humidity (going-forward)

- **`EnvironmentalDataService`** (app): `WeatherResponse.Main` decodes `temp: Double` + `humidity: Int` (the response is `units=metric`, so `temp` is already °C and `humidity` is %). Expose `@Published currentTemperatureC` / `currentHumidityPct`, set in `fetchAtmosphericPressure`'s success branch alongside pressure.
- **`EnvironmentalReading`** (core, `EnvironmentalEventFactory.swift`): add `temperatureC: Double? = nil` and `humidityPct: Double? = nil` (defaulted, so the two existing construction sites and any tests compile unchanged).
- **`EnvironmentalEventEmitter.emitIfNeeded`** (app): thread `service.currentTemperatureC` / `currentHumidityPct` into the reading. `backfillDerived` leaves them nil (no weather history — same as pressure).
- **`EnvironmentalEventFactory.events(for:)`** (core): emit a daily `temperature` `.environment` event (`value: temperatureC`, `unit: "°C"`) and a `humidity` event (`value: humidityPct`, `unit: "%"`) when present, `source: .weatherAPI`, `dedupKey: DedupKey.daily(.environment, subtype, dayStart:)` — exactly parallel to the existing `pressure` event.

### B. Percentile exposures — the new stateful source shape

Existing exposure sources are *stateless per-event* (a day either is/isn't a pressure-drop). Temperature/humidity buckets are **relative to the user's whole series**, so the source must see all readings:

- **`DerivedExposureKind`** gains `.hotDay, .coldDay, .humidDay`.
- **`TemperatureExposureSource`** (`occurrences(from:)`): collect all `.environment` `subtype == "temperature"` events' values; if `count >= config.minWeatherReadings`, compute p25/p75; emit `.derived(.hotDay)` for each event `value >= p75` and `.derived(.coldDay)` for each `value <= p25`. Below the min-readings guard → emit nothing.
- **`HumidityExposureSource`**: same shape on `subtype == "humidity"`; emit `.derived(.humidDay)` for each `value >= p75`.
- Register both in `EvidenceEngine`'s `sources` array.
- **`EvidenceConfig`** knobs: `weatherHighPercentile = 0.75`, `weatherLowPercentile = 0.25`, `minWeatherReadings = 20`, and a same-day lag window for the three kinds (reuse `outsideFactorLagHours = 0...24`).
- **`EdgeIdentity`**: `fromToken`/`parseFrom` gain `"derived:hotDay"` / `"derived:coldDay"` / `"derived:humidDay"` (and `columns` derives `fromCategory` `"hotDay"`/`"coldDay"`/`"humidDay"` by the existing prefix-strip).
- **`InsightPhrasing.derivedExposureLabel`**: `"hotDay" → "Hot days"`, `"coldDay" → "Cold days"`, `"humidDay" → "Humid days"`.

**Percentile definition:** a simple nearest-rank / linear-interpolation percentile over the sorted values; ties at the cutoff count as in-bucket (`>= p75` / `<= p25`). Deterministic (no randomness). Documented so tests can pin exact boundaries.

### C. Tiering — reuse the framework

- **`PlausibilityCatalog.tier(forExposureCategory:)`**: `"hotDay"`, `"coldDay"`, `"humidDay"` → `.contested`. No other change — contested edges already render in the evidence feed with the "unproven mechanism · your pattern" tag (visible + VoiceOver) and the `.environment` icon path picks these up (they're `.environment`-sourced; confirm `InsightsViewModel.exposure(for:)` maps the three tokens to `.environment`, mirroring pressureDrop/moon/mercury).

## 4. Reused / unchanged

- The **evidence gates** (significance + effect-size + stability) + the 0.75 observational ceiling — a weather correlation still must clear them; percentile bucketing just makes the exposure *minable*, it doesn't lower the bar.
- The **tier presentation** (contested tag, "Just for fun" for novelty) — no UI change; weather is contested, so it uses the existing tag.
- **Phrasing** — the existing tentative, non-causal templates render "Hot days → migraine" etc.
- Pressure/moon/mercury/season mining, capture, crisis flow — untouched.

## 5. Copy / honesty guardrails

- Weather cards carry the **contested** tag ("unproven mechanism · your pattern") — honest about weak/mixed evidence, never asserted as fact.
- No causal language (existing rule + tests).
- The percentile framing means a "Hot day" is *one of your warmer days* (relative), which the tag's "your pattern" wording already fits.

## 6. Testing

- **Core (`swift test`):**
  - `TemperatureExposureSource` — a series with a clear spread yields `.hotDay` for top-quartile days and `.coldDay` for bottom-quartile days, and nothing for the middle; a series **below** `minWeatherReadings` yields **no** exposures (cold-start guard); a degenerate all-equal series yields no spurious buckets. Pin exact p25/p75 boundaries on a known input.
  - `HumidityExposureSource` — top-quartile → `.humidDay`; below-min → none.
  - `EdgeIdentityTests` — round-trip `.hotDay` / `.coldDay` / `.humidDay`.
  - `InsightPhrasingTests` — the three labels.
  - `PlausibilityCatalogTests` — all three → `.contested`.
  - `EvidenceConfigTests` — the percentile + min-readings + lag knobs are defined.
  - `EnvironmentalEventFactoryTests` — a reading with `temperatureC`/`humidityPct` emits `temperature`/`humidity` events with the right value/unit/dedupKey; a reading with them nil emits neither (parity with pressure).
- **App (`-parallel-testing-enabled NO`):** `InsightsViewModelTests` — a seeded `hotDay` edge surfaces in `.active` with `tier == .contested` (mirrors the fullMoon test).
- **Device e2e:** a debug **"Load WEATHER demo"** seed (a spread of `temperature`/`humidity` events over ~200 days + a symptom correlated with the hot/humid days + recompute) → "Hot days → …" / "Humid days → …" appear in the evidence feed with the contested tag and the environment icon; established factors unlabeled; phrasing tentative; light + dark.

## 7. Out of scope (this round)

- **Absolute thresholds** (rejected, §1) and a **user-facing threshold setting** (percentile is automatic).
- **Low-humidity / "dry"** exposure (weak mechanism), **temperature-swing** day-over-day exposure (a possible future add, like pressureDrop), and **season** as an exposure (still emitted-only).
- **Historical weather backfill** (no API history) — insights accrue going-forward.
- No changes to the gates, phrasing rule, tier UI, capture, or crisis flow.

## 8. Next / future refinements

- **Temperature-swing** exposure (a large day-over-day change, mirroring `pressureDrop`) if the flat hot/cold buckets prove too coarse.
- Revisiting the quartile split or the min-readings guard once real weather data accrues.
- This round completes the outside-factors arc (pressure [done] · moon/mercury [done] · weather [this]); no further environmental factors are committed.
