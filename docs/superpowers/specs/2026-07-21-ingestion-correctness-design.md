# Environmental Ingestion Correctness — Design

**Date:** 2026-07-21
**Status:** Approved (decisions made interactively with Leo, from an external code review)
**Scope:** Fix four real defects in the environmental ingestion that an external review surfaced — a self-cancelling refresh task, outdated AQI breakpoints, an all-or-nothing daily lock, and (the deepest) future forecast data being mined as retrospective exposure. Three are pre-existing and shared with the already-merged weather feature; the air-quality work surfaced them. Built on the unmerged `air-quality-exposure` branch (on top of `2eb76d0`/`3bb0e78`); the full review is re-run before any merge.

**Not touched:** the evidence gates, tiers, Insights UI, the Environment summary row layout, moon/mercury/season/pressure exposures. This corrects HOW environmental data is fetched, provenance-marked, and fed to the engine.

---

## 1. Problem

An external review (which I confirmed line-by-line) found four defects:

1. **Self-cancelling refresh (BLOCKER).** `fetchAtmosphericPressure()` calls `currentAtmosphericTask?.cancel()`, which — during `fetchAllData()` — cancels the **outer refresh task itself** (it was stored in the same property at `fetchAllData:96`). After pressure, `if !Task.isCancelled` at `EnvironmentalDataService:78/83` is false, so **`fetchDailyForecast()` AND `fetchAirQuality()` are skipped.** In live usage `forecastHighC/LowC/Humidity/AQI` are nil when the emitter reads them → **temperature, humidity, and air quality have never been emitted from the real API.** Only the debug seed populated them. `fetchAtmosphericPressure` also returns fire-and-forget (its inner task is not awaited), so even pressure completes after the reading is built.
2. **Outdated AQI breakpoints.** `AirQualityIndex` uses the pre-2024 EPA PM2.5 table (Good `0–12.0`). The 2024 revision lowered Good to `0.0–9.0` and compressed the upper bins. The `poorAirDay` threshold (PM2.5 35.5 → AQI 101) is stable across both tables, so exposure detection is unaffected, but displayed AQI numbers/categories are wrong away from 35.5.
3. **All-or-nothing daily lock.** `emitIfNeeded` sets `lastEmitDayKey` after any successful ingest; since moon/season always succeed, a day is marked done even when the API fetches returned nil → no same-day retry.
4. **Forecast mined as retrospective exposure (methodology).** We average the **next-24h forecast** PM2.5/temp/humidity and file it as **today's** exposure — future conditions the user has not experienced, leaking into retrospective symptom correlation.

## 2. Decisions (Leo, 2026-07-21)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Task ownership | **`fetchAllData()` is the SOLE cancellation owner.** Child fetches (pressure/forecast/AQI) become plain inline `await`ed async functions — no inner `Task`, no self-cancel. |
| 2 | Testability | **Dependency-inject** the network transport, clock, calendar/timezone, and location into `EnvironmentalDataService` (and the clock + watermark store into the emitter). No reliance on global `URLProtocol` registration, real `Date()`, `Calendar.current`, or live location. |
| 3 | AQI window | **Previous completed local calendar day.** `/air_pollution/history` (free) for `[startOfYesterday, startOfToday)` in local time → 24-hour mean PM2.5 → EPA AQI, event **timestamped to yesterday**. A real 24h metric, genuinely retrospective. |
| 4 | Missed-day backfill | Track the last successfully-ingested completed AQI day; on foreground, fetch **every missing day** from the watermark up to yesterday, **capped** (default 30 days) and dedup-idempotent — so gaps aren't correlated with app-open frequency. |
| 5 | Forecast weather | **Keep fetching `/forecast` for display** (today's range in the Environment row) but mark it **`.forecast`** and **exclude it from mining.** Historical weather is deferred, so the Hot/Cold/Swing/Humid exposures **go dormant** from real data (code intact). |
| 6 | Provenance | A typed **`TemporalProvenance` enum** (`.observedCompletedDay | .forecast | .currentSnapshot`) stamped on every environmental event. **Mining is fail-closed: the weather + AQI sources mine ONLY `.observedCompletedDay`** — they do NOT merely skip `.forecast` (a legacy/malformed event lacking a flag must not be mined). |
| 7 | Dedup identity | **Provenance is part of the dedup identity** — so a `.forecast` temperature and a future `.observedCompletedDay` temperature for the same day+subtype coexist instead of overwriting. |
| 8 | Per-signal watermarks | Drop the global `lastEmitDayKey` lock. **Completed AQI advances a per-day watermark and stops refetching once stored** (failed days retry); **forecast + current pressure keep their own time-based refresh interval** (the existing cooldown) — no full refetch every foreground. |
| 9 | Breakpoints | Update `AirQualityIndex` to the **2024 EPA PM2.5 breakpoints**. |
| 10 | Debug data | Debug weather is emitted **explicitly `.observedCompletedDay`** so the Hot/Cold/Swing/Humid card layouts stay testable on demand. |
| 11 | Deferred | **Historical weather mining** (One Call 4.0 — has a free 1,000-calls/day pay-as-you-go tier, or another source) and **proactive warnings** are their own future rounds. |

## 3. Architecture

### A. Task ownership + cancellation (`EnvironmentalDataService`)

`fetchAllData()` owns exactly one task. `fetchAtmosphericPressure()`, `fetchDailyForecast()`, and `fetchAirQuality()` become plain `async` functions that do their work inline (location resolve → transport GET → decode → `MainActor.run` publish) and **return only when done** — no inner `Task`, no `currentAtmosphericTask?.cancel()`, no fire-and-forget. `fetchAllData` awaits each in sequence under one `if !Task.isCancelled` regime it alone controls. Pressure's 5-second fallback timeout, if kept, is a local `withTimeout`-style helper that does not touch the shared task.

### B. Dependency injection (`EnvironmentalDataService`, emitter)

Introduce narrow injectable seams (protocols with production defaults):
- **`HTTPTransport`** — `func data(from: URL) async throws -> (Data, URLResponse)`; default `URLSession.shared`; tests inject a stub mapping URL → canned JSON (or a thrown error) per endpoint.
- **Clock** — `() -> Date` (or a `Clock` protocol); default `Date.init`.
- **Calendar/timezone** — an injected `Calendar` (with timezone); default `Calendar(identifier: .gregorian)` + `.current` timezone.
- **Location** — a protocol yielding an optional `CLLocationCoordinate2D`; wraps the existing `LocationService`/`manualLocation`.

The emitter takes the clock + a `WatermarkStore` (default `UserDefaults`) so day math and watermarks are deterministic in tests.

### C. Air quality — retrospective, backfilled (`EnvironmentalDataService`, factory)

- **`APIConfig.airPollutionHistoryURL(latitude:longitude:start:end:)`** → `/air_pollution/history?lat=&lon=&start=&end=&appid=` (Unix `start`/`end`; free).
- A **pure static** `dailyMeanPM25(slots:dayStart:dayEnd:) -> Double?` — mean PM2.5 over `dt ∈ [dayStart, dayEnd)`; requires **≥ `minAirQualityHours` (e.g. 20 of 24)** in-window slots else nil (partial-history guard → a legitimately absent day, not a misleading AQI).
- `fetchCompletedAirQuality(for dayStart:)` — resolves the local day window `[startOfDay(D), startOfDay(D+1))` (DST-correct via the injected calendar), GETs the history URL, aggregates, `epaAQI`, and returns a three-state `AQIDayResult` — `.value(Int)` / `.absentData` (partial or empty history) / `.fetchError` (network OR decode failure). Three states are required because the watermark advances on `.value`/`.absentData` but must NOT advance on `.fetchError` (an `Int?` would conflate error and empty).
- **Backfill loop (in the emitter):** for `D` from `max(lastAQIDay + 1 day, yesterday − maxBackfillDays)` up to `yesterday`: fetch + emit `D`'s observed AQI. Advance `lastAQIDay` past a day when it **succeeds OR is legitimately empty** (partial-history); **stop advancing on a network error** (retry that day next foreground). Cap the loop at `maxBackfillDays` iterations.
- Each emitted AQI event: `subtype "airQuality"`, `value = Double(aqi)`, **`temporalProvenance = .observedCompletedDay`**, `timestamp` = `D`'s local noon, daily dedupKey for `D` (provenance-scoped, §E).

### D. Temporal provenance + fail-closed mining (`HealthGraphCore`)

- **`TemporalProvenance`** — `public enum { case observedCompletedDay, forecast, currentSnapshot }`, `Sendable`/`Equatable`, `rawValue` string. Stamped into each environmental event by the factory and exposed via a typed accessor `HealthEvent.temporalProvenance` (decoded from the event's metadata; **absent/unknown → nil**).
- **Factory stamps per signal:** temperature/humidity → `.forecast`; airQuality → `.observedCompletedDay`; pressure/pressureDrop → `.currentSnapshot`; moonPhase/season/mercuryRetrograde → `.observedCompletedDay` (deterministic facts of the day).
- **Fail-closed gating:** `TemperatureExposureSource`, `HumidityExposureSource`, and `AirQualityExposureSource` mine an event **only if `temporalProvenance == .observedCompletedDay`** — an event with a missing, malformed, or non-observed provenance is NOT mined. (Pressure/Moon/Mercury/Season sources are unchanged — those signals have no forecast variant, and `.currentSnapshot` pressure is a real observation, not future-leakage.)
- **Consequence:** real temperature/humidity are `.forecast` → the weather sources produce nothing → **Hot / Cold / Big-swing / Humid cards go dormant** until observed weather exists. AQI (`.observedCompletedDay`, yesterday) mines correctly.

### E. Provenance-scoped dedup (`HealthGraphCore`)

`DedupKey.daily` gains a provenance component: `"environment|{subtype}|{provenance}|day|{minuteOfDayStart}"`. So a `.forecast` temperature and a future `.observedCompletedDay` temperature for the same day+subtype have distinct keys and coexist (addition B). All environmental factory call sites pass the event's provenance.

### F. Emit orchestration (`EnvironmentalEventEmitter`)

Replace the single `lastEmitDayKey` guard with per-signal handling on foreground:
- **Forecast weather + current pressure:** refetch only if past the existing `minimumRefreshInterval` (cooldown); emit today's `.forecast` temperature/humidity (display) + `.currentSnapshot` pressure.
- **Deterministic (moon/season/mercury):** emit for today (`.observedCompletedDay`, no fetch).
- **Observed AQI:** run the backfill loop (§C) against the `lastAQIDay` watermark.
- Dedup keys keep every re-emit idempotent. A transient failure never locks the day — the failed signal simply isn't watermarked/advanced and retries next foreground.

### G. Display + debug (app)

- The Environment summary row is **unchanged in layout.** It shows today's forecast temp/humidity range (from `.forecast` events) and, on **completed days**, the observed AQI line (`.observedCompletedDay`). Today's row has no AQI line until the day completes — honest (no completed-day AQI mid-day). `EnvironmentSummaryFormatter`/`EventDisplay` render regardless of provenance.
- **Debug seed:** `loadWeatherDemo` emits its temperature/humidity/AQI as **`.observedCompletedDay`** so the Hot/Cold/Swing/Humid + Poor-air card layouts stay verifiable on device (demonstrating "with observed data").

### H. AQI breakpoints (`AirQualityIndex`)

Replace with the 2024 EPA PM2.5 table: `0.0–9.0→0–50`, `9.1–35.4→51–100`, `35.5–55.4→101–150`, `55.5–125.4→151–200`, `125.5–225.4→201–300`, `225.5–325.4→301–500` (clamp above 325.4 → 500). Categories/bands and `poorAirThreshold = 101` unchanged; update the affected test expectations (e.g. `12.0→56`, `6.0→33`).

## 4. Testing

All tests use the injected transport/clock/calendar/location — deterministic, no network/real-clock.
- **Orchestration (the #1 regression):** one `fetchAllData()` with a stub transport answering all three endpoints → `currentPressure` AND `forecastHighC` AND `forecastAQI` are all populated. A version pinning that the outer task is NOT cancelled after the pressure fetch.
- **Independent failure:** each endpoint stubbed to fail in turn → the other two still complete (no all-or-nothing).
- **Retry / dedup:** a failed AQI fetch does not advance the watermark and does not lock the day; the next foreground retries; re-emit is idempotent (same dedup key updates in place).
- **Local-day boundary / DST:** yesterday's window computed via the injected calendar across a spring-forward (23h) and fall-back (25h) day, and across a month/year rollover — `start`/`end` are the correct local midnights.
- **Partial-history:** history returns `< minAirQualityHours` slots → `dailyMeanPM25` nil → no AQI event for that day, and the watermark advances past it (legitimate absence, not a retry loop).
- **Backfill cap:** a watermark far in the past → at most `maxBackfillDays` days fetched in one foreground; each dated to its own day.
- **Provenance gating (fail-closed):** a `.forecast` temperature event → `TemperatureExposureSource` yields nothing; an event with NO provenance → also nothing; a `.observedCompletedDay` event → mined. Same for humidity/AQI.
- **Provenance dedup:** a `.forecast` and an `.observedCompletedDay` temperature for the same day+subtype produce two distinct dedup keys.
- **AQI breakpoints (2024):** boundary + interpolation values updated (`9.0→50`, `9.1→51`, `12.0→56`, `35.5→101`, `55.5→151`, `125.5→201`, clamp).
- **Device:** real ingestion (or the observed debug seed) → the Environment row shows the forecast weather range + observed AQI on completed days; the Poor-air card appears from observed AQI; Hot/Cold/Swing/Humid cards are absent from real data but present from the observed debug seed; light + dark.

## 5. Out of scope

- **Historical weather mining** (One Call 4.0 / alternate source) — the future round that re-activates Hot/Cold/Swing/Humid from observed data (decision #11).
- **Proactive "poor air expected" warnings** — the round that consumes the forecast AQI (kept available, not mined).
- Ozone/other pollutants, pollen, AQI color coding, promoting provenance from metadata to a dedicated GRDB column.
- Fixing the pressure current-snapshot's app-open-time bias (a lesser, separate issue; pressure is not future-leakage).

## 6. Next / future

- **Observed weather** via One Call 4.0 (free pay-as-you-go tier) → emit `.observedCompletedDay` temperature/humidity → the dormant Hot/Cold/Swing/Humid exposures re-activate automatically (the provenance gate already admits them).
- **Warnings round** built on the retained forecast AQI/weather.
- Optionally promote `temporalProvenance` from metadata to a first-class event column if it earns broader query use.
