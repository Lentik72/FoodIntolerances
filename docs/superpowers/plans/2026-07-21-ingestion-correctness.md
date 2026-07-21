# Environmental Ingestion Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the environmental ingestion so it actually runs, marks data with temporal provenance, mines only completed observations (fail-closed), records air quality retrospectively (yesterday's completed day + missed-day backfill), and uses the current EPA breakpoints.

**Architecture:** A typed `TemporalProvenance` on every environmental event (in metadata) gates mining fail-closed and disambiguates dedup keys. `fetchAllData` becomes the sole cancellation owner with inline child fetches; dependencies (transport/clock/calendar/location) are injected for deterministic tests. AQI switches from next-24h forecast to a completed-day history window with per-day backfill and watermarks. Forecast temp/humidity stay for display but are `.forecast` → dormant in mining until observed weather is added.

**Tech Stack:** Swift, Swift Testing, SwiftUI, OpenWeather `/air_pollution/history` (free).

Design: `docs/superpowers/specs/2026-07-21-ingestion-correctness-design.md`. Built on the `air-quality-exposure` branch (on top of `2eb76d0`/`3bb0e78`).

## Global Constraints

- **Fail-closed mining:** `TemperatureExposureSource`, `HumidityExposureSource`, `AirQualityExposureSource` mine an event ONLY when `event.temporalProvenance == .observedCompletedDay`. Missing/malformed/other provenance → NOT mined. (Pressure/Moon/Mercury/Season sources are unchanged.)
- **Provenance by signal (real ingestion):** temperature/humidity → `.forecast`; airQuality → `.observedCompletedDay`; pressure/pressureDrop → `.currentSnapshot`; moonPhase/season/mercuryRetrograde → `.observedCompletedDay`. The debug seed stamps its weather `.observedCompletedDay` directly (so the dormant card layouts stay verifiable).
- **Provenance is in metadata**, key `"provenance"`, alongside existing keys (`low`/`phase`/`season`). Accessor `HealthEvent.temporalProvenance` decodes it; **absent/unknown → nil** (fail-closed). No GRDB schema change.
- **Provenance is in the daily dedup identity:** `"environment|{subtype}|{provenance}|day|{minute}"`.
- **AQI is retrospective:** the previous completed local calendar day via `/air_pollution/history`, 24h mean PM2.5 → EPA AQI (2024 table), the event **timestamped to D's local NOON**; missed days backfilled over the window **`[yesterday − (maxBackfillDays − 1), yesterday]` (= `maxBackfillDays = 30` days inclusive)**; a day advances the `lastAQIDay` watermark on success OR legitimate-empty, and a network error stops advancement (retry). Partial history (`< minAirQualityHours = 20`) → no event (legitimate absence). The `lastAQIDay` watermark defaults to **`.distantPast`** when unset (so a fresh install backfills the full capped window). Day stepping uses `calendar.date(byAdding: .day, …)`, NOT `+86_400` (DST-safe).
- **Forecast AQI is KEPT, not removed:** `fetchAirQuality()`/`meanPM25`/`forecastAQI` (from the air-quality round) stay — the forecast AQI remains fetched and *available* for the future warnings round (spec §5) and is asserted by the orchestration test — but the emitter does NOT emit it as a mined event (mined AQI comes only from history). This round changes what the emitter *emits*, not what the service *fetches*.
- **Tasks 2–8 must land together (do not merge mid-sequence).** Between Task 2 (factory stamps `airQuality → .observedCompletedDay`) and Task 8 (emitter stops threading `forecastAQI`), the old emitter would briefly feed forecast AQI into an `.observedCompletedDay`-stamped event — branch-internal only, no test asserts it, corrected by Task 8, and the whole-branch review re-runs before any merge.
- **`fetchAllData` is the sole cancellation owner** — child fetches are plain `await`ed async funcs (no inner `Task`, no `currentAtmosphericTask?.cancel()`, no fire-and-forget).
- **Dependency injection:** `EnvironmentalDataService` and the emitter take injectable transport/clock/calendar/location/watermark seams (production defaults). Tests never touch the real network/clock/location.
- **App-target tests `-parallel-testing-enabled NO`;** known `SwiftDataMigratorTests` crash. iPhone 17 Pro (iOS 26.5). Device testing must **Reset first** (the dedup-key format changed). Ignore SourceKit stale-index diagnostics; `swift test`/`xcodebuild` authoritative.

---

### Task 1: Core — `TemporalProvenance` + accessor

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/TemporalProvenance.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TemporalProvenanceTests.swift`

**Interfaces:** `TemporalProvenance` enum + `HealthEvent.temporalProvenance: TemporalProvenance?`. Task 2 stamps it; Task 3 gates on it.

- [ ] **Step 1: Write the failing tests first:**

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct TemporalProvenanceTests {
    private func event(meta: [String: String]?) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 0), timezoneID: "UTC",
                    category: .environment, subtype: "temperature", value: 20, source: .weatherAPI,
                    metadata: meta.map { try! JSONEncoder().encode($0) })
    }
    @Test func decodesProvenanceFromMetadata() {
        #expect(event(meta: ["provenance": "observedCompletedDay"]).temporalProvenance == .observedCompletedDay)
        #expect(event(meta: ["provenance": "forecast"]).temporalProvenance == .forecast)
        #expect(event(meta: ["provenance": "currentSnapshot"]).temporalProvenance == .currentSnapshot)
    }
    @Test func failClosedOnMissingOrUnknown() {
        #expect(event(meta: nil).temporalProvenance == nil)                       // no metadata
        #expect(event(meta: ["low": "12"]).temporalProvenance == nil)             // metadata without provenance
        #expect(event(meta: ["provenance": "banana"]).temporalProvenance == nil)  // unknown value
    }
}
```

- [ ] **Step 2: Run to confirm failure.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → FAIL.

- [ ] **Step 3: Implement** `TemporalProvenance.swift`:

```swift
import Foundation

/// Whether an environmental event reflects reality the user has already experienced
/// (mineable) or a forecast (display/warnings only). Stored in event metadata under
/// "provenance"; the mining sources are fail-closed on `.observedCompletedDay`.
public enum TemporalProvenance: String, Sendable, Equatable {
    case observedCompletedDay   // a completed local day's observation (or a deterministic date-fact)
    case forecast               // future conditions — never mined
    case currentSnapshot        // a current-conditions reading (e.g. pressure)
}

extension HealthEvent {
    /// Fail-closed: nil when metadata is absent, has no "provenance", or holds an
    /// unknown value — mining treats nil as NOT observed.
    public var temporalProvenance: TemporalProvenance? {
        guard let data = metadata,
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let raw = dict["provenance"] else { return nil }
        return TemporalProvenance(rawValue: raw)
    }
}
```

- [ ] **Step 4: Run + commit.** `swift test` green; commit both files (`feat(core): TemporalProvenance + fail-closed accessor`).

---

### Task 2: Core — provenance-scoped dedup + factory stamping

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/DedupKey.swift`, `Ingestion/EnvironmentalEventFactory.swift`
- Test: `HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift`, `DedupKeyTests.swift` (if present, else add cases)

**Interfaces:** `DedupKey.daily(_:_:dayStart:provenance:)`; every factory env event carries a provenance in metadata + dedup key.

- [ ] **Step 1: Write the failing tests first.** Assert: a factory `temperature` event has `temporalProvenance == .forecast`; `airQuality` → `.observedCompletedDay`; `pressure` → `.currentSnapshot`; `moonPhase`/`season`/`mercuryRetrograde` → `.observedCompletedDay`. Assert a `.forecast` temperature and an `.observedCompletedDay` temperature for the same day+subtype produce DIFFERENT `DedupKey.daily(...)` strings, and that the key contains the provenance rawValue.

- [ ] **Step 2: Run to confirm failure.**

- [ ] **Step 3: Provenance in the dedup key.** In `DedupKey.swift`:

```swift
    public static func daily(_ category: EventCategory, _ subtype: String?, dayStart: Date,
                             provenance: TemporalProvenance? = nil) -> String {
        let p = provenance.map { "|\($0.rawValue)" } ?? ""
        return "\(category.rawValue)|\(subtype ?? "")\(p)|day|\(minute(dayStart))"
    }
```

- [ ] **Step 4: Factory stamps provenance per signal.** In `EnvironmentalEventFactory.swift`, change the `event(...)` helper to take a `provenance` and fold it into both metadata and the dedup key:

```swift
        func event(_ subtype: String, value: Double? = nil, unit: String? = nil,
                   metadata: [String: String]? = nil, provenance: TemporalProvenance) -> HealthEvent {
            var meta = metadata ?? [:]
            meta["provenance"] = provenance.rawValue
            return HealthEvent(
                timestamp: r.date, timezoneID: r.timezoneID,
                category: .environment, subtype: subtype,
                value: value, unit: unit, source: .weatherAPI,
                metadata: try? JSONEncoder().encode(meta),
                dedupKey: DedupKey.daily(.environment, subtype, dayStart: dayStart, provenance: provenance)
            )
        }
```

  Then pass provenance at each call: `pressure`/`pressureDrop` → `.currentSnapshot`; `moonPhase`/`mercuryRetrograde`/`season` → `.observedCompletedDay`; `temperature`/`humidity` → `.forecast`; `airQuality` → `.observedCompletedDay`. (Provenance is intrinsic to each signal's real source; document it.)

- [ ] **Step 5: Run + commit** (`feat(core): stamp temporal provenance on env events + provenance-scoped dedup`).

---

### Task 3: Core — fail-closed mining

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/WeatherExposureSources.swift`, `Evidence/AirQualityExposureSource.swift`
- Test: `HealthGraphCoreTests/WeatherExposureSourcesTests.swift`, `AirQualityExposureSourceTests.swift`

**Interfaces:** the three forecast-capable sources require `.observedCompletedDay`.

- [ ] **Step 1: Update the tests first.** In each source's test, make the fixture helpers stamp `metadata["provenance"] = "observedCompletedDay"` so the existing observed-data tests keep passing after the gate lands. Note the current helpers' metadata state: `WeatherExposureSourcesTests.tempDay` already encodes a `["low": …]` dict (just add the `provenance` key); the humidity and `AirQualityExposureSourceTests.aq` helpers currently pass **no metadata at all** → they must now build a `["provenance": "observedCompletedDay"]` dict. Then ADD a self-contained three-way fail-closed test per source:

```swift
    // Self-contained: observed → occurrences; forecast → none; NO-flag (legacy) → none.
    @Test func temperatureMinedOnlyWhenObserved() {
        func tempDay(_ high: Double, _ low: Double, _ i: Int, _ provenance: String?) -> HealthEvent {
            var meta = ["low": String(low)]; if let p = provenance { meta["provenance"] = p }
            return HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                               category: .environment, subtype: "temperature", value: high, unit: "°C",
                               source: .weatherAPI, metadata: try? JSONEncoder().encode(meta))
        }
        func run(_ p: String?) -> [ExposureOccurrence] {
            TemperatureExposureSource(config: .default)
                .occurrences(from: shuffled20.enumerated().map { tempDay($0.element, $0.element - 10, $0.offset, p) })
        }
        #expect(run("observedCompletedDay").contains { $0.key == .derived(.hotDay) })   // gate isn't just `return []`
        #expect(run("forecast").isEmpty)                                                 // forecast never mined
        #expect(run(nil).isEmpty)                                                        // fail-closed: no flag → not mined
    }
```

  (Mirror the three-way for `HumidityExposureSource` and `AirQualityExposureSource`, using their own fixtures.)

- [ ] **Step 2: Run to confirm failure.** After Step 1, the existing observed tests stay GREEN (the sources don't yet check provenance), so the RED is specifically the new `run("forecast")`/`run(nil)` assertions (the un-gated source still mines them). `cd HealthGraphCore && swift test 2>&1 | tail -20` → those cases FAIL.

- [ ] **Step 3: Add the gate.** In each source's filter/compactMap, add `e.temporalProvenance == .observedCompletedDay`:
  - `TemperatureExposureSource` compactMap guard: `guard e.category == .environment, e.subtype == "temperature", e.temporalProvenance == .observedCompletedDay, let high = e.value, …`.
  - `HumidityExposureSource` filter: `$0.category == .environment && $0.subtype == "humidity" && $0.temporalProvenance == .observedCompletedDay && $0.value != nil`.
  - `AirQualityExposureSource` compactMap guard: add `e.temporalProvenance == .observedCompletedDay`.

- [ ] **Step 4: Run + commit** (`feat(core): fail-closed mining — weather/AQI sources mine only observed-completed-day events`).

---

### Task 4: Core — 2024 EPA breakpoints

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/AirQualityIndex.swift`
- Test: `HealthGraphCoreTests/AirQualityIndexTests.swift`

- [ ] **Step 1: Update the failing tests first** to the 2024 expectations: `epaAQI(9.0)==50`, `9.1==51`, `12.0==56`, `12.1==57`, `6.0==33`, `35.4==100`, `35.5==101`, `55.4==150`, `55.5==151`, `125.4==200`, `125.5==201`, `225.4==300`, `225.5==301`, `9999==500`. **The existing `epaAQI(12.1)==51` and `epaAQI(6.0)==25` assertions MUST be updated (to 57 and 33)** — they were correct only under the old table; leaving them fails after Step 3. `45.0==124` and `35.49==100` are unchanged. Category names/bands unchanged; keep `poorAirThreshold==101` and `category(101)==.unhealthySensitive`. (Arithmetic: `12.1` → bin (9.1,35.4,51,100): `(49/26.3)*(12.1−9.1)+51 = 56.59 → 57`; `12.0 → 56`; `6.0` → (0,9,0,50): `(50/9)*6 = 33.3 → 33`.)

- [ ] **Step 2: Run to confirm failure.**

- [ ] **Step 3: Swap the breakpoint table:**

```swift
    private static let breakpoints: [(cLo: Double, cHi: Double, iLo: Int, iHi: Int)] = [
        (0.0, 9.0, 0, 50), (9.1, 35.4, 51, 100), (35.5, 55.4, 101, 150),
        (55.5, 125.4, 151, 200), (125.5, 225.4, 201, 300), (225.5, 325.4, 301, 500),
    ]
```

  (Clamp above 325.4 → 500 via the existing `else { return 500 }`.)

- [ ] **Step 4: Run + commit** (`fix(core): 2024 EPA PM2.5 AQI breakpoints`).

---

### Task 5: App — dependency-injection seams

**Files:**
- Modify: `EnvironmentalDataService.swift` (inject transport/clock/calendar/location; behavior-preserving)
- Create: `HTTPTransport.swift` (or inline) — the transport protocol + `URLSession` conformance + a `LocationProviding` protocol
- Test: `Food IntolerancesTests/EnvironmentalDataServiceDITests.swift` (a smoke test with a stub transport)

**Interfaces:** `EnvironmentalDataService(locationManager:transport:now:calendar:location:)` with production defaults; internal calls route through the injected seams (`HTTPTransport`, `LocationProviding`, `now`, `calendar`). **No behavior change** — this task only adds the seams and rewires existing calls.

- [ ] **Step 1: Define the seams.**

```swift
public protocol HTTPTransport: Sendable { func data(from url: URL) async throws -> (Data, URLResponse) }
extension URLSession: HTTPTransport {}   // URLSession already provides `data(from:)`

public protocol LocationProviding { var coordinate: CLLocationCoordinate2D? { get } }
```

  Add to `EnvironmentalDataService`: `private let transport: HTTPTransport`, `private let now: () -> Date`, `private let calendar: Calendar`, and a `LocationProviding` seam; default them in `init` (`transport: HTTPTransport = URLSession.shared`, `now: @escaping () -> Date = Date.init`, `calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }()`). The default `LocationProviding` wraps the existing `manualLocation` → `locationManager?.currentLocation`; a private `resolvedCoordinate()` reads through it (tests inject a fixed coordinate).

- [ ] **Step 2: Rewire existing calls (no behavior change):** replace `URLSession.shared.data(from:)` → `transport.data(from:)`; replace `Date()` used for windowing/day-math → `now()`; replace `Calendar.current`/`.current` timezone in day math → `calendar`; route location reads through `resolvedCoordinate()`. Leave the concurrency structure alone (Task 6 fixes it).

- [ ] **Step 3: Verify behavior-preserving.** This is a pure refactor with no new behavior, so there is no new functional test — the gate is that the **app builds and the existing full suite stays green** (`xcodebuild test … -parallel-testing-enabled NO`, green modulo the known crash; core `swift test` green). The injected seams are exercised by Task 6's orchestration tests. (Do NOT add a smoke test that awaits a fire-and-forget value — pressure is still detached until Task 6, so such a test would be flaky.)

- [ ] **Step 4: Commit** (`refactor(app): inject transport/clock/calendar/location into EnvironmentalDataService`).

---

### Task 6: App — single-owner cancellation + orchestration tests

**Files:**
- Modify: `EnvironmentalDataService.swift` (`fetchAllData`, `fetchAtmosphericPressure`)
- Test: `Food IntolerancesTests/EnvironmentalOrchestrationTests.swift`

**Interfaces:** one refresh reaches pressure + forecast; child fetches are plain inline `await`s.

- [ ] **Step 1: Write the failing tests first** (using the Task-5 DI): a stub `HTTPTransport` that answers the three endpoints `fetchAllData` hits — `/weather` (pressure), `/forecast` (temp/humidity), `/air_pollution/forecast` (forecast AQI, kept for warnings) — with canned JSON, plus an injected coordinate.
  - **Orchestration (the #1 regression, RED first):** one `await fetchAllData()` → `currentPressure` AND `forecastHighC` AND `forecastAQI` are ALL populated. (Do NOT add the "outer task `.isCancelled` is false" assertion — `currentAtmosphericTask` is `private(set)` and internally nil in a test, so it passes even with the bug; the observable all-three assertion is the real regression coverage.)
  - **Independent failure:** each of the three endpoints stubbed to throw in turn → the other two still populate (no all-or-nothing).

- [ ] **Step 2: Run to confirm failure** — today, `fetchAtmosphericPressure` self-cancels the outer task, so forecast + AQI are skipped → `forecastHighC`/`forecastAQI` nil → the orchestration test FAILS, reproducing the bug.

- [ ] **Step 3: Refactor `fetchAtmosphericPressure()`** to a plain inline async function: resolve the coordinate, `transport.data(from: weatherURL)`, decode, `MainActor.run` publish — **remove** the `currentAtmosphericTask?.cancel()` (line 207), the inner `Task { }`, the `currentAtmosphericTask = newTask` (line 281), and the fire-and-forget return. Keep the 5s fallback as a local `withThrowingTaskGroup`/timeout helper that does not touch `currentAtmosphericTask`. `fetchAllData` keeps its single outer task + the `!Task.isCancelled` gates (which now only trip when a NEW refresh supersedes this one).

- [ ] **Step 4: Run + commit** (`fix(app): fetchAllData is the sole cancellation owner — pressure no longer cancels the refresh`).

---

### Task 7: App — retrospective AQI primitives

**Files:**
- Modify: `APIConfig.swift` (`airPollutionHistoryURL`), `EnvironmentalDataService.swift` (`dailyMeanPM25`, `fetchCompletedAirQuality`)
- Test: `Food IntolerancesTests/AirQualityHistoryTests.swift`

**Interfaces:** `dailyMeanPM25(slots:dayStart:dayEnd:) -> Double?`; `fetchCompletedAirQuality(dayStart:) async -> AQIDayResult`.

- [ ] **Step 1: Write the failing tests first.**
  - `dailyMeanPM25` — mean over `dt ∈ [dayStart, dayEnd)`; a mean-CHANGING out-of-window slot is excluded; **boundary: exactly `minAirQualityHours (20)` in-window → value, exactly `19` → nil** (pins `>=` not `>`); **half-open: a slot at exactly `dayEnd` is EXCLUDED** (a `<=` bug would fold next-day midnight in).
  - **Local-day/DST window** — a helper `completedDayWindow(for:calendar:) -> (start: Date, end: Date)` returning `[startOfDay(D), startOfDay(D+1))`. With an injected **America/Los_Angeles** calendar, assert the window spans **23h on 2025-03-09 (spring-forward)** and **25h on 2025-11-02 (fall-back)**, and that it rolls a month boundary (e.g. D = 2025-01-31) correctly. (A naive `now − 86_400` or a UTC calendar yields 24h and fails these — discriminating.)
  - `fetchCompletedAirQuality` (stub transport) — full 24-slot history → `.value(aqi)`; `< 20` slots → `.absentData`; transport throws → `.fetchError`; **malformed/garbage JSON (decode throws) → `.fetchError`** (NOT `.absentData` — a decode error must retry, not advance the watermark past a failed day).

- [ ] **Step 2: Run to confirm failure.**

- [ ] **Step 3: Implement.**
  - `APIConfig.airPollutionHistoryURL(latitude:longitude:start:end:)` → `\(base)/air_pollution/history?lat=&lon=&start=\(Int(start))&end=\(Int(end))&appid=` .
  - `enum AQIDayResult { case value(Int), absentData, fetchError }`.
  - `static func dailyMeanPM25(slots: [(dt: TimeInterval, pm25: Double)], dayStart: Date, dayEnd: Date, minHours: Int) -> Double?` — filter `dt ∈ [dayStart.tis, dayEnd.tis)`, `guard count >= minHours`, return mean.
  - `func fetchCompletedAirQuality(dayStart: Date) async -> AQIDayResult` — get the window from the tested `completedDayWindow(for: dayStart, calendar:)` (NOT inline `startOfDay` math, so the DST guarantee is exercised on the production path); GET `airPollutionHistoryURL(start:end:)`; on transport OR **decode** throw → `.fetchError`; else `dailyMeanPM25(...)` → nil → `.absentData`, else `.value(AirQualityIndex.epaAQI(pm25: mean))`. Reuse `resolvedCoordinate()`; no location → `.fetchError`.

- [ ] **Step 4: Run + commit** (`feat(app): completed-day AQI via /air_pollution/history (DST-correct window, partial-history guard)`).

---

### Task 8: App — emitter orchestration, debug seed, e2e

**Files:**
- Modify: `Models/EnvironmentalEventEmitter.swift` (remove global lock; inject clock/calendar/watermark; watermark + backfill; provenance-correct emits; stop threading the forecast AQI into an emitted event)
- Modify: `Views/HealthGraphDebugView.swift` (`loadWeatherDemo` weather/AQI → `.observedCompletedDay`, provenance stamped on ALL env events it emits)
- Test: `Food IntolerancesTests/EnvironmentalEmitterTests.swift`
- **Do NOT delete** `EnvironmentalDataService.fetchAirQuality`/`meanPM25`/`AirPollutionResponse`/`APIConfig.airPollutionURL`/`forecastAQI` or `Food IntolerancesTests/AirQualityIngestionTests.swift` — the forecast AQI stays fetched + `forecastAQI` populated (available for the future warnings round, asserted by Task 6). This task only stops the EMITTER from turning it into a mined event.

**Interfaces:** foreground emit produces today's forecast weather + pressure + deterministic signals AND backfilled `.observedCompletedDay` AQI for completed days; NO `airQuality` event for today.

- [ ] **Step 1: Write the failing tests first** (inject the clock + calendar + an in-memory `WatermarkStore` + a stub service double whose `fetchCompletedAirQuality` returns scripted `AQIDayResult`s):
  - **Retry / no lock:** a foreground where a day's fetch returns `.fetchError` does NOT advance `lastAQIDay`, does NOT emit that day, and does NOT block later foregrounds; a subsequent foreground retries that same day and, on `.value`, emits + advances.
  - **`.absentData` (fully pinned):** the watermark advances PAST D, NO `airQuality` event exists for D, and a subsequent foreground does NOT re-fetch D (no retry loop).
  - **Today has no observed AQI:** a foreground emits today's `temperature`/`humidity` (`.forecast`) + pressure, but **no `airQuality` event dated today** (guards against a forecast AQI being mislabeled `.observedCompletedDay`).
  - **Backfill cap:** unset watermark (`.distantPast`) → exactly `maxBackfillDays (30)` days fetched in one foreground (window `[yesterday−29, yesterday]`), each event dated to its own day at local noon.
  - **DST-safe stepping:** with an America/Los_Angeles calendar and a clock straddling a DST transition, the backfill iterates the correct distinct days (no skipped/repeated day) — a `+86_400` increment would drift.
  - **Provenance-correct emits:** emitted `airQuality` → `.observedCompletedDay`; emitted `temperature`/`humidity` → `.forecast`.
  - **Idempotent re-emit:** two foregrounds covering the same completed AQI day produce one event (dedup).

- [ ] **Step 2: Run to confirm failure.**

- [ ] **Step 3: Rewrite `emitIfNeeded`.** Inject the clock, calendar (timezone), and a `WatermarkStore` (default `UserDefaults`); do all day math through them.
  - Remove the `lastEmitDayKey` guard. Add the `lastAQIDay` watermark via the injected store; **an unset watermark reads as `.distantPast`.**
  - Today (past cooldown → `await service.fetchAllData()`): build a today reading (dated `now`) with `pressureHPa`/`previousPressureHPa`, `moonPhaseName`/`season`/`isMercuryRetrograde`, and `temperatureHighC`/`LowC`/`humidityPct` from `service.forecast*` → emit (factory stamps forecast/current/observed per §Global Constraints). Do NOT thread `service.forecastAQI` into the reading — there is NO `airQuality` event for today.
  - Backfill: `let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now()))!`. Start day `= max(calendar.date(byAdding: .day, value: 1, to: watermark)!, calendar.date(byAdding: .day, value: -(maxBackfillDays - 1), to: yesterday)!)`. Iterate `D` from start to `yesterday` inclusive, advancing with `calendar.date(byAdding: .day, value: 1, to: D)` (DST-safe — NOT `+86_400`): `switch await service.fetchCompletedAirQuality(dayStart: D)` → `.value(aqi)`: emit a reading dated **D's local noon** with only `airQualityAQI` (factory stamps `.observedCompletedDay`, dedupKey for D), then set watermark = D; `.absentData`: set watermark = D (no event); `.fetchError`: `break` (leave the watermark, retry next foreground).
  - The backfill reading's `date` is `calendar.date(bySettingHour: 12, minute: 0, second: 0, of: D)` (local noon), so the event timestamps + groups under day D.
- [ ] **Step 4: Debug seed** — in `loadWeatherDemo`, stamp provenance on **every** `.environment` event it emits so the demo keys match the new factory format (and the mined ones surface cards): temperature/humidity/airQuality → `.observedCompletedDay` (so Hot/Cold/Swing/Humid + Poor-air cards render); pressure/pressureDrop → `.currentSnapshot`; any moon/season/mercury → `.observedCompletedDay`. Each event gets `"provenance": <raw>` in its metadata AND `provenance: <case>` in its `DedupKey.daily(...)` call. (Do the same for `loadOutsideFactorsDemo`'s moon/mercury events so their keys stay consistent.)
- [ ] **Step 5: Build + full regression.** App build; `cd HealthGraphCore && swift test` green; app suite green modulo the known crash (incl. the new emitter/orchestration/history tests).
- [ ] **Step 6: On-device / simulator check** (human's gate; **Reset first** — dedup format changed). Load WEATHER demo → the Environment row shows the forecast temp/humidity range + an observed AQI line on completed days; **Insights shows the Poor-air card + (from the observed demo) Hot/Cold/Swing/Humid cards**; confirm on a REAL run (no demo) that weather cards are absent while the Environment row still shows the forecast range. Light + dark.
- [ ] **Step 7: Commit** (`feat(app): retrospective AQI emit + backfill/watermarks, drop global daily lock, observed debug weather`).

---

## Definition of Done

- One refresh reaches pressure + forecast weather (the #1 bug is fixed, with an orchestration regression test); dependencies are injected and the concurrency is deterministically tested.
- Every environmental event carries a `TemporalProvenance`; mining is fail-closed on `.observedCompletedDay`; provenance is in the dedup identity.
- AQI is recorded retrospectively (previous completed local day, DST-correct, partial-history-guarded) with missed-day backfill + per-signal watermarks and no all-or-nothing daily lock.
- AQI uses the 2024 EPA breakpoints.
- Forecast temp/humidity display but are dormant in mining; the debug seed keeps the weather card layouts verifiable. Observed weather (One Call) + warnings remain future rounds.
