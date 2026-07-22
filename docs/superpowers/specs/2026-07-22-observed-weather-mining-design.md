# Observed-Weather Mining (One Call day_summary) — Design

**Date:** 2026-07-22
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Ingest **observed completed-day** temperature (min/max) and humidity via OpenWeather One Call 3.0 `day_summary`, stamped `.observedCompletedDay`, so the existing fail-closed weather exposure sources resume mining — re-activating the dormant Hot/Cold/Humid/Big-swing cards. Completed days' Environment rows display the measured actuals in place of that morning's forecast ("observed wins" presentation precedence). The follow-through the ingestion-correctness round was built waiting for.

**Not touched:** the mining sources (`TemperatureExposureSource`/`HumidityExposureSource` — zero changes; they already require `.observedCompletedDay`), the evidence gates/tiers, forecast fetching and today's forecast display, AQI ingestion, pressure/moon/mercury, the frozen migrations, stored events (nothing deleted — precedence is presentation-only), the debug view (stays raw/diagnostic).

---

## 1. Problem

The ingestion-correctness round correctly stopped mining forecast weather (future data must not feed past correlations): the factory stamps temperature/humidity `.forecast` and the sources fail closed on anything else. The accepted consequence was that users' active Hot/Cold/Humid/Big-swing edges decayed to dormant. They have been dormant since. This round supplies the missing input — real observed completed-day weather — through the exact template the observed-AQI backfill proved (per-day watermark, cap, grace, throttle, provenance-scoped dedup). The mining side needs nothing: `TemperatureExposureSource` already consumes observed `temperature` events (`value` = high, `metadata["low"]`), `HumidityExposureSource` observed `humidity` events, and hot/cold/humid/swing all derive from single-day values via personal percentiles.

A forced sub-problem: once observed weather lands, a completed day holds BOTH a forecast temperature event (emitted that morning, display-only) and an observed one (backfilled later) — provenance-scoped dedup keys mean both persist. Unhandled, the Environment row would render two "Temperature" lines and pick an arbitrary one for the headline. A display-precedence rule is therefore part of this round, not an option.

## 2. Decisions (Leo, 2026-07-22)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Display rule | **Observed wins in display** — one authoritative Temperature/Humidity line per day: in-progress day shows forecast; completed day shows observed actuals. Presentation precedence only, never deletion; stored forecast events remain intact. Rejected: mined-only observed (past days would knowingly show forecast when actuals exist) and both-lines (the noise the Environment-summary round removed). |
| 2 | Precedence granularity | **Independent per `day + subtype`** — an observed temperature suppresses ONLY that day's forecast temperature, never humidity or another day. Mixed availability must work: observed temperature + forecast-only humidity → one of each. |
| 3 | Determinism | Duplicate observed events for the same day+subtype resolve deterministically (latest `createdAt`, then `id.uuidString` — stable across rebuilds). |
| 4 | Where precedence lives | **Core, both choke points** (the hide-season architecture): a shared pure helper applied in `TimelineDayBuilder.days` (browse AND raw/search, every caller) and in `EnvironmentDaySummaryBuilder.summaries` (public direct entry point). Search/raw paths follow the same rule; the debug view is the explicitly diagnostic surface that exposes everything. |
| 5 | Observed humidity semantics | **Accept `humidity.afternoon`** as the day's observed humidity. UI label stays simply "Humidity"; the semantic definition (provider's observed afternoon value) is documented here and in code. A consistently-sampled afternoon series is valid for percentile `humidDay` mining. Safeguards: provenance `.observedCompletedDay`; precedence over forecast humidity only for the same completed day; NEVER numerically combined or compared with the forecast next-24h aggregate; **missing afternoon humidity → no observed humidity event** (that day's forecast stays visible, the day is unmined for humidity). Field meaning + missing-value behavior pinned in ingestion and precedence tests. |
| 6 | Fetch shape | One Call 3.0 `day_summary`, **one call per missed day** (no range endpoint exists), inside a single backfill pass bounded by the AQI-style cap. Same API key and resolved-coordinate path as every other fetch. |
| 7 | Failure mode | **Graceful degradation** — 401/402 (One Call subscription not active) behaves exactly like a fetch error: retry-throttled, no events, forecast display unaffected. The app ships safely before the subscription exists. |

## 3. Architecture

### A. Fetch (app service)

- **`APIConfig`**: new `oneCallDaySummaryURL(latitude:longitude:date:)` against a new `data/3.0` base (`https://api.openweathermap.org/data/3.0/onecall/day_summary?lat=…&lon=…&date=YYYY-MM-DD&units=metric&appid=…`); nil when the key is missing, like the existing builders.
- **`EnvironmentalDataService`**: new completed-weather-day fetch (shape mirroring `fetchCompletedAirQualityRange`'s result discipline), returning per day:
  - `.value(highC: Double, lowC: Double, humidityPct: Double?)` — from `temperature.max`, `temperature.min`, `humidity.afternoon` (humidity optional per Decision 5);
  - `.absent` — the provider has no data for that day;
  - `.fetchError` — transport/decode/auth failure for the day (triggers retry, never mistaken for absence).
  Uses `resolvedCoordinate()` (manual override → LocationService), injected transport/clock/calendar like the AQI path. Past days use the CURRENT resolved coordinate — the same accepted limitation as AQI history.

### B. Backfill (emitter)

`EnvironmentalEventEmitter` gains an observed-weather backfill mirroring the AQI one:
- Own keys: `hg.env.lastWeatherDay` (contiguous per-day watermark), `hg.env.lastWeatherAttempt` (retry throttle, 1h) — peers of `lastAQIDayKey`/`lastAQIAttemptKey`.
- Same policy: `maxBackfillDays` (30) cap, `gracePartialDays` (2) recent-gap grace (a recent absent day holds the watermark for retry; an old absent day is resolved-absent and advances), watermark advances only after the emitted days actually persist (a failed ingest holds it).
- Difference from AQI: one `day_summary` call per missed day inside the pass (≤30 calls; the free tier allows 1,000/day) instead of one range call. A `.fetchError` on any day aborts the pass with the watermark held (contiguity preserved) — retried after the throttle interval.

### C. Factory (core)

`EnvironmentalReading` gains `weatherProvenance: TemporalProvenance = .forecast`; the factory stamps the temperature and humidity events with it instead of hardcoding `.forecast`. Every existing call site is untouched by the default; the observed backfill passes `.observedCompletedDay` with only the weather fields set (the AQI-backfill pattern). Provenance already scopes the dedup key, so observed and forecast events coexist; no migration.

### D. Display precedence (core, both choke points)

New shared pure helper in `EnvironmentDaySummary.swift` (peer of `retiredSubtypes`): `EnvironmentDaySummaryBuilder.observedPrecedenceFiltered(_ events: [HealthEvent], timeZone: TimeZone) -> [HealthEvent]`:
- Groups `temperature`/`humidity` env events per local day; when a day+subtype has at least one `.observedCompletedDay` event, all `.forecast` events of that day+subtype are dropped from presentation; among multiple observed, the deterministic winner (Decision 3) is kept.
- Every other subtype and provenance passes through untouched; resolved independently per day+subtype.
- Applied in `EnvironmentDaySummaryBuilder.summaries` (its own filter — public direct entry point) AND in `TimelineDayBuilder.days` (feeding sessions/summaries/rowEvents, both modes — no caller can leak a suppressed forecast row, mirroring the retired-subtypes wiring).
- `EnvironmentSummaryFormatter` needs no change — it renders whatever the (now-precedence-filtered) summary carries.

### E. Mining

Zero changes. On the next recompute after ≥ `EvidenceConfig.minWeatherReadings` observed days exist, the fail-closed sources emit occurrences again and the dormant edges re-activate. The initial 30-day backfill makes that near-immediate for active users. Forecast humidity and observed humidity never meet numerically — the sources only ever see `.observedCompletedDay`.

## 4. Files

- **Modify** `APIConfig.swift` — `data/3.0` base + `oneCallDaySummaryURL(...)`.
- **Modify** `EnvironmentalDataService.swift` — completed-weather-day fetch + response model (`temperature.min/max`, `humidity.afternoon`).
- **Modify** `Models/EnvironmentalEventEmitter.swift` — observed-weather backfill (watermark/throttle/grace/per-day loop).
- **Modify** `HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift` — `weatherProvenance` field + stamped temp/humidity.
- **Modify** `HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift` — the precedence helper + its application in `summaries`.
- **Modify** `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift` — apply the precedence helper to the raw path.
- **Tests:** `EnvironmentalEventFactoryTests`, `EnvironmentDaySummaryBuilderTests`, `TimelineDayBuilderTests` (core); service fetch/decode tests + emitter backfill tests (app, mirroring `AirQualityHistoryTests`/`EnvironmentalEmitterTests` harnesses).

## 5. Testing

- **Service (app):** day_summary decode → high/low/humidity; missing `humidity.afternoon` → `.value` with nil humidity; malformed payload → `.fetchError`; 401 → `.fetchError` (subscription-not-active degradation); URL builder date formatting.
- **Emitter (app):** first run backfills capped window; watermark advances only on persisted ingest; recent absent day holds (grace), old absent day advances; throttle prevents rapid refetch; `.fetchError` mid-pass holds the watermark (contiguity).
- **Factory (core):** default reading stamps temp/humidity `.forecast` (existing behavior pinned); `weatherProvenance: .observedCompletedDay` stamps both; nil observed humidity → no humidity event.
- **Precedence (core, builder + day-builder):** observed suppresses same-day same-subtype forecast only — mixed availability yields observed temperature + forecast humidity on one day; other days untouched; duplicate observed → deterministic winner; forecast-only day (today) unchanged; raw/search mode follows the same rule; non-weather subtypes and other provenances pass through.
- **Mining:** existing source tests already cover observed-event consumption — no new mining tests needed; one integration-style check that a precedence-filtered display does not affect what the engine sees (mining reads the store, not the display filter).
- **Device gate (Leo):** completed days show measured actuals (visibly different from the forecast numbers where they diverge); today still shows forecast; after backfill + recompute, Hot/Cold/Humid/Swing cards re-activate; with the subscription disabled, everything behaves as before.

## 6. Prerequisite (Leo)

Activate the **One Call API 3.0 subscription** on the OpenWeather account (separate opt-in; 1,000 calls/day free) and optionally set the account's calls-per-day cap so it cannot bill. The app ships safely before/without it (Decision 7).

## 7. Out of scope

- The proactive poor-air / conditions warnings round (consumes the kept forecast AQI; separate round).
- Pollen (new provider; separate round).
- day_summary's pressure/precipitation/wind/cloud fields.
- Historical-location accuracy for traveling users (current coordinate, as AQI).
- Any change to forecast fetching, today's display, or the °C/°F setting (reused as-is).
- Deleting or migrating stored forecast events (precedence is presentation-only).
