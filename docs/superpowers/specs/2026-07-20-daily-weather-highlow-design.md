# Daily High/Low Weather — Design

**Date:** 2026-07-20
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Replace the weather feature's once-a-day *snapshot* (biased by when the user opens the app) with a **daily high/low** derived from the free OpenWeather **forecast** endpoint over the next 24 hours. Emit temperature as **one combined range event** (`12–24°C`) carrying both poles, and mine **three** temperature exposures — **Hot** (top-quartile high), **Cold** (bottom-quartile low), **Big swing** (top-quartile daily range) — plus **Humid**. All personal-percentile, all contested.

**Not touched:** the percentile/tier framework, pressure (still current-conditions), moon/mercury, the units feature. This is a data-quality refinement of the shipped weather exposures.

---

## 1. Problem

The weather feature logs **one current-conditions snapshot per day**, taken at the first app-foreground (`EnvironmentalEventEmitter.emitIfNeeded` → `/data/2.5/weather`). Temperature swings 10–15°C across a day, so a point snapshot (a) is a weak proxy for the day's temperature and (b) is **biased by *when* the user opens the app** — a confound: if open-time correlates with both temperature and symptoms, the engine can mistake "afternoon-opener" for "heat." Contested tier + per-user percentiles + the stability gate soften but don't remove it.

**Fix rationale.** A **24-hour window's high/low is open-time-independent** — any 24h span covers a full diurnal cycle, so its extremes are ~the daily min/max regardless of when the window starts. The free `/data/2.5/forecast` endpoint (3-hourly, 5 days, same key — `APIConfig.forecastURL` already exists) gives the slots to compute this. The forward-looking window is a slight imperfection (it characterizes "the day around/ahead of now," not strictly the past calendar day), acceptable for a contested factor and far better than a point.

## 2. Decisions (Leo, 2026-07-20)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Source | **Free `/forecast` + next-24h window** (no billing change). Aggregate the ~8 three-hourly slots covering the next 24h. |
| 2 | Values | **Daily high** (max temp), **daily low** (min temp), **daily humidity** (mean over the window). |
| 3 | Event shape | **One combined `temperature` event** — value = daily high, `metadata["low"]` = daily low — rendered as a range `12–24°C`. One `humidity` event (mean). |
| 4 | Exposures | **Three from temperature** — Hot (high ≥ p75), Cold (low ≤ p25), **Big swing (range = high−low ≥ p75)** — plus **Humid** (humidity ≥ p75). All personal-percentile. |
| 5 | Swing | **Personal-percentile, NOT an absolute "≥10°"** — an absolute swing cutoff hits the same climate-degeneracy trap (desert swings big daily → no contrast; coast never → never fires). Top-quartile of *your* daily ranges. |
| 6 | Tier | All contested (reuse the framework). |
| 7 | Old snapshot data | Not migrated — old `temperature` snapshot events (no `low` metadata) are **not mined** (skipped) and render as a single value (legacy). Pre-launch; negligible. |

## 3. Architecture

### A. Ingestion — daily forecast aggregate (app)

- `APIConfig.forecastURL` — add `&units=metric` (currently missing) so slot temps are °C.
- `EnvironmentalDataService` — add a forecast fetch: GET `forecastURL`, decode `ForecastResponse { list: [Slot { dt: TimeInterval, main: Main { temp: Double, humidity: Int } }] }`, keep slots with `dt ∈ [now, now + 24h]`, and compute `dailyHighC = max(temp)`, `dailyLowC = min(temp)`, `dailyHumidityPct = mean(humidity)`. Guard: need ≥ 3 slots in-window (else leave nil). Expose `@Published var forecastHighC / forecastLowC / forecastHumidity: Double?`.
- `EnvironmentalEventEmitter.emitIfNeeded` — fetch the forecast (alongside the existing current-conditions call that still feeds **pressure**), and build the reading with `temperatureHighC` / `temperatureLowC` / `humidityPct` from the forecast aggregate. `backfillDerived` leaves them nil (no weather history).

### B. The combined event (core)

- `EnvironmentalReading` — replace `temperatureC` with `temperatureHighC: Double?` + `temperatureLowC: Double?` (defaulted nil); `humidityPct: Double?` stays (now the daily mean). Update the two construction sites.
- `EnvironmentalEventFactory.events(for:)` — when **both** high and low are present, emit ONE `temperature` `.environment` event: `value: temperatureHighC, unit: "°C", metadata: ["low": String(temperatureLowC)]`, daily dedupKey. Humidity event unchanged (`value: humidityPct, unit: "%"`).

### C. Mining — Hot / Cold / Swing (core)

- `DerivedExposureKind` gains `.swingDay` (alongside `.hotDay/.coldDay/.humidDay`).
- `TemperatureExposureSource` (rewritten to read the combined event): for each `.environment`/`subtype == "temperature"` event, require `value` (high) **and** a decodable `metadata["low"]` (low) — events lacking `low` (old snapshots) are **skipped**. Build `highs`, `lows`, `ranges = high − low`. Guard `count >= minWeatherReadings`. Compute p75/p25 per series with the existing `Percentile` + spread guard (`hi > lo`), then emit per day:
  - `.hotDay` if `high >= p75(highs)`
  - `.coldDay` if `low <= p25(lows)`
  - `.swingDay` if `range >= p75(ranges)`
  (A day can be more than one — e.g. a hot *and* swingy day — each is a distinct exposure occurrence, keyed on the same source event.)
- `EdgeIdentity` (`fromToken`/`parseFrom`): `.swingDay ↔ "derived:swingDay"`. `EvidenceConfig.lagWindow`: `.swingDay → outsideFactorLagHours`. `InsightPhrasing.derivedExposureLabel`: `"swingDay" → "Big temperature swings"`. `PlausibilityCatalog`: `"swingDay" → .contested`.
- `HumidityExposureSource` — unchanged (still `.humidDay` on the humidity value's top quartile).

### D. Display (app)

- `WeatherValueFormatter.line` — for a `temperature` event, decode `metadata["low"]`; if present, render a **range** "`lowConv–highConv°U`" (each pole converted to the user's unit + rounded); if absent (old snapshot), render the single `highConv°U`. Humidity unchanged (`"N%"`).

## 4. Reused / unchanged

- The **percentile + spread-guard + min-readings** machinery from the weather round (the swing series rides it identically).
- The **tier framework** (contested tag, `.environment` icon), phrasing, gates, and the units feature (`WeatherValueFormatter` gains the range branch; conversion/rounding logic reused).
- **Pressure** ingestion (still `/weather` current-conditions; unchanged).

## 5. Testing

- **Core (`swift test`):**
  - `EnvironmentalEventFactoryTests` — a reading with high+low emits ONE `temperature` event, `value == high`, `metadata["low"] == low`; high or low nil → no temperature event; humidity emitted from `humidityPct`.
  - `WeatherExposureSourcesTests` (extend) — a series of combined events with a spread pins Hot (top-quartile highs), Cold (bottom-quartile lows), **Swing (top-quartile ranges)** on known inputs; an event **without** `metadata["low"]` is skipped (old-snapshot migration); the degenerate/flat series (all equal → each spread guard bails) emits nothing; below-min emits nothing. A day that is both hot and swingy yields both occurrences.
  - `EdgeIdentityTests` — `.swingDay` round-trips. `InsightPhrasingTests` — "Big temperature swings". `PlausibilityCatalogTests` — `swingDay → .contested`. `EvidenceConfigTests` — `lagWindow(.swingDay) == 0...24`.
- **App (`-parallel-testing-enabled NO`):**
  - `WeatherValueFormatterTests` (extend) — a temperature event with `metadata["low"]` renders the range ("12–24°C", "54–75°F" converted+rounded); without metadata → single value (legacy).
  - a forecast-aggregation test — given synthetic 3-hourly slots over 24h, `high/low/mean` are the max/min/mean, and slots outside the 24h window are excluded; < 3 in-window slots → nil. (Extract the aggregation into a pure, testable function.)
  - `InsightsViewModelTests` — a seeded `swingDay` edge surfaces contested (mirrors the hotDay test).
- **Device:** the debug "Load WEATHER demo" seed (updated to emit combined high/low events + humidity + a correlated symptom on top-quartile hot/swing days) → the Timeline shows `12–24°C` range rows; Insights shows "Hot days"/"Cold days"/"Big temperature swings"/"Humid days" as contested cards; light + dark.

## 6. Out of scope

- One Call API / true calendar-day min/max (the free forecast's forward 24h window is the chosen tradeoff).
- Migrating or re-emitting old snapshot events (they're pre-launch; skipped by mining, shown as single legacy values).
- Pressure changes, absolute thresholds, a "dry/low-humidity" exposure, humidity's own high/low split.
- Any change to the gates, tier UI, or the units picker.

## 7. Next / future

- One Call `daily[0]` upgrade for calendar-exact min/max, if the forward-window proves too coarse once real data accrues.
- Collapsing the daily environmental events into a single compact "Weather" Timeline summary row (if the auto-logged rows feel noisy).
