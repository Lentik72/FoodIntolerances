# Daily High/Low Weather Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the once-a-day temperature *snapshot* with a **daily high/low** from the free `/forecast` endpoint (next-24h window), emit temperature as one combined range event, and mine **Hot / Cold / Big-swing** (+ Humid) — all personal-percentile, contested.

**Architecture:** The app aggregates the forecast's next-24h slots → daily high/low/mean-humidity. The factory emits one `temperature` event (value = high, `metadata["low"]` = low). `TemperatureExposureSource` is rewritten to read that combined event and bucket Hot (high top-quartile), Cold (low bottom-quartile), Swing (range top-quartile). `WeatherValueFormatter` renders a range. Old single-value snapshots (no `low`) are skipped.

**Tech Stack:** Swift, Swift Testing, SwiftUI, OpenWeatherMap `/forecast` (free, `units=metric`).

Design: `docs/superpowers/specs/2026-07-20-daily-weather-highlow-design.md`.

## Global Constraints

- **Combined temperature event:** `subtype "temperature"`, `value = dailyHigh` (°C), `metadata` = JSON `["low": String(dailyLow)]`. Emitted only when BOTH high+low present.
- **Mining reads the combined shape:** `TemperatureExposureSource` requires `value` AND a decodable `metadata["low"]`; events lacking `low` (old snapshots) are **skipped** (clean migration, no data change).
- **Swing is personal-percentile** (top-quartile of the daily `high−low` series), NOT an absolute cutoff — same climate-degeneracy reasoning as Hot/Cold.
- **Per-series spread guard:** each of highs / lows / ranges buckets only if that series has spread (`p75 > p25`); a flat series → that bucket emits nothing.
- **`/forecast` + `units=metric` + next-24h window** (≥3 in-window slots required, else nil). Pressure stays on the current-conditions call (untouched).
- **`.swingDay` is additive** to `DerivedExposureKind` — updates the two exhaustive switches (`EdgeIdentity.fromToken`, `EvidenceConfig.lagWindow`); grep to confirm those are the only two.
- **Contested tier** for swingDay (reuse the framework). Display-only °C canonical; the range formatter reuses the units-round conversion.
- **Intermediate state:** Task 1 changes `EnvironmentalReading` (`temperatureC` → `temperatureHighC`/`LowC`), which breaks the app-layer emitter until Task 3 rewires it. Expected — Task 1/2 gate on core `swift test`; the app builds again at Task 3; nothing merges until all four land.
- **App-target tests `-parallel-testing-enabled NO`;** the lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing crash. **Simulator:** iPhone 17 Pro (iOS 26.5). New app files under the tracked `Views/HealthOS/…` path.

---

### Task 1: Core — the combined daily temperature event

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift` (`EnvironmentalReading` fields + `events(for:)`)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift`

**Interfaces:** Produces a `temperature` event with `value = high`, `metadata["low"] = low`; `humidity` event unchanged. Task 2 mines it; Task 3's app populates the reading.

- [ ] **Step 1: Update the failing tests first.** In `EnvironmentalEventFactoryTests.swift`, **delete** the shipped single-value `emitsTemperatureAndHumidityWhenPresent` (uses `temperatureC: 28.5` — the only `temperatureC:`-based test); **keep** `emitsNoTempHumidityWhenNil` (passes no temp args — still valid under the new defaulted-nil fields). Add the combined-shape tests:

```swift
    @Test func emitsExactlyOneCombinedTemperatureWithLowInMetadata() {
        let r = EnvironmentalReading(date: Date(timeIntervalSince1970: 1_700_000_000),
            pressureHPa: nil, previousPressureHPa: nil, moonPhaseName: nil, season: nil,
            isMercuryRetrograde: false, timezoneID: "UTC",
            temperatureHighC: 24, temperatureLowC: 12, humidityPct: 68)
        let events = EnvironmentalEventFactory.events(for: r)
        #expect(events.filter { $0.subtype == "temperature" }.count == 1)   // ONE combined event, not two
        let temp = events.first { $0.subtype == "temperature" }
        #expect(temp?.value == 24 && temp?.unit == "°C" && temp?.dedupKey != nil)
        let meta = temp?.metadata.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        #expect(meta?["low"] == "12.0")
        #expect(events.first { $0.subtype == "humidity" }?.value == 68)
    }
    // Either pole nil → no temperature event; humidity is INDEPENDENT (still emits).
    @Test func skipsTemperatureWhenEitherPoleNilButKeepsHumidity() {
        func temps(high: Double?, low: Double?) -> [HealthEvent] {
            EnvironmentalEventFactory.events(for: EnvironmentalReading(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                pressureHPa: nil, previousPressureHPa: nil, moonPhaseName: nil, season: nil,
                isMercuryRetrograde: false, timezoneID: "UTC",
                temperatureHighC: high, temperatureLowC: low, humidityPct: 55))
        }
        #expect(!temps(high: 24, low: nil).contains { $0.subtype == "temperature" })   // low-nil branch
        #expect(!temps(high: nil, low: 12).contains { $0.subtype == "temperature" })   // high-nil branch
        #expect(temps(high: 24, low: nil).contains { $0.subtype == "humidity" })       // humidity independent
    }
```

- [ ] **Step 2: Run to confirm failure.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → FAIL to compile (`temperatureHighC:` unknown).

- [ ] **Step 3: Update `EnvironmentalReading`.** Replace `public let temperatureC: Double?` with `public let temperatureHighC: Double?` and `public let temperatureLowC: Double?`; update the init (defaulted `temperatureHighC: Double? = nil, temperatureLowC: Double? = nil, humidityPct: Double? = nil`) and assignments. (`humidityPct` stays.)

- [ ] **Step 4: Emit the combined event.** In `events(for:)`, replace the temperature block with:

```swift
        if let high = r.temperatureHighC, let low = r.temperatureLowC {
            events.append(event("temperature", value: high, unit: "°C", metadata: ["low": String(low)]))
        }
        if let humidity = r.humidityPct {
            events.append(event("humidity", value: humidity, unit: "%"))
        }
```

- [ ] **Step 5: Run the core suite.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → all green (the existing `WeatherExposureSourcesTests` still pass — they use the OLD single-value shape and the OLD source, both untouched until Task 2). Report counts.

- [ ] **Step 6: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift
git commit -m "feat(core): emit one combined daily temperature event (value=high, metadata low)"
```

---

### Task 2: Core — rewrite `TemperatureExposureSource` (Hot/Cold/Swing) + tier

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift` (`.swingDay`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/WeatherExposureSources.swift` (rewrite `TemperatureExposureSource`)
- Modify: `EdgeIdentity.swift`, `EvidenceConfig.swift` (lag), `Insights/InsightPhrasing.swift` (label), `Insights/PlausibilityCatalog.swift` (tier)
- Test: `WeatherExposureSourcesTests.swift` (rewrite the temperature tests), `EdgeIdentityTests.swift`, `InsightPhrasingTests.swift`, `PlausibilityCatalogTests.swift`, `ExposureSourceTests.swift`

**Interfaces:** `.derived(.swingDay)`, edge token `"derived:swingDay"`, label "Big temperature swings", tier `.contested`. `TemperatureExposureSource` now emits Hot/Cold/Swing from combined events.

- [ ] **Step 1: Rewrite the failing tests first.** In `WeatherExposureSourcesTests.swift`, replace the `temp(_:_:)` helper + the temperature tests (`hotAndColdByQuartile`, `percentileIsNearestRankNotFloorOrLinear`, `belowMinReadingsEmitsNothing`, `atMinMinusOneEmitsNothing`, the temperature half of `degenerateAllEqualSeriesEmitsNothing`, `eachSourceIgnoresOtherSubtypes`) with combined-event versions below. **Keep the `shuffled20` fixture and the humidity tests untouched.** The `tempDay` low is threaded through `metadata["low"]`, so these fixtures exercise the real decode path.

```swift
    private func tempDay(high: Double, low: Double, _ i: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                    category: .environment, subtype: "temperature", value: high, unit: "°C",
                    source: .weatherAPI, metadata: try? JSONEncoder().encode(["low": String(low)]))
    }
    // A fixed NON-sorted permutation of 1…21 (odds then evens) — catches a dropped `.sorted()`,
    // and n=21 gives a FRACTIONAL rank so it discriminates nearest-rank (ceil) from floor.
    private let shuffled21: [Double] =
        Array(stride(from: 1.0, through: 21.0, by: 2)) + Array(stride(from: 2.0, through: 20.0, by: 2))

    @Test func hotOnHighQuartileColdOnLowQuartile() {
        // highs = shuffled 1…20, lows = high − 10 (constant 10° range → no swing spread)
        let events = shuffled20.enumerated().map { tempDay(high: $0.element, low: $0.element - 10, $0.offset) }
        let occ = TemperatureExposureSource(config: .default).occurrences(from: events)
        #expect(occ.filter { $0.key == .derived(.hotDay) }.count == 6)    // high ≥ p75(1…20)=15 → 15…20
        #expect(occ.filter { $0.key == .derived(.coldDay) }.count == 5)   // low ≤ p25(lows −9…10)=−5 → highs 1…5
        #expect(occ.filter { $0.key == .derived(.swingDay) }.isEmpty)     // ranges all 10 → range spread guard bails
    }
    @Test func percentileIsNearestRankNotFloorOnCombinedEvents() {
        // n=21: p75·21=15.75 → ceil→rank16 → cutoff 16 → hot={16…21}=6. Floor(15) would give 7; a
        // dropped .sorted() on the odds-then-evens input would also miss. Pins the rank arithmetic.
        let events = shuffled21.enumerated().map { tempDay(high: $0.element, low: $0.element - 10, $0.offset) }
        #expect(TemperatureExposureSource(config: .default).occurrences(from: events)
            .filter { $0.key == .derived(.hotDay) }.count == 6)
    }
    @Test func swingOnRangeQuartile() {
        // high = 20 (flat → no hot), low = 20 − range, ranges = shuffled 1…20; lows land at 0…19
        let events = shuffled20.enumerated().map { tempDay(high: 20, low: 20 - $0.element, $0.offset) }
        let occ = TemperatureExposureSource(config: .default).occurrences(from: events)
        #expect(occ.filter { $0.key == .derived(.swingDay) }.count == 6)  // range ≥ p75(1…20)=15
        #expect(occ.filter { $0.key == .derived(.hotDay) }.isEmpty)       // highs all 20 → high spread guard bails
        #expect(occ.filter { $0.key == .derived(.coldDay) }.count == 5)   // low ≤ p25(lows 0…19)=4 → pins cold reads LOW
    }
    @Test func aDayCanBeBothHotAndSwing() {
        // low = 0 for all → range = high; both the highs series AND the ranges series are 1…20
        // (both have spread), so the top day (high 20, range 20) is both hot AND swingy.
        let events = shuffled20.enumerated().map { tempDay(high: $0.element, low: 0, $0.offset) }
        let occ = TemperatureExposureSource(config: .default).occurrences(from: events)
        let top = events.first { $0.value == 20 }!
        let keys = occ.filter { $0.sourceEventID == top.id }.map(\.key)
        #expect(keys.contains(.derived(.hotDay)) && keys.contains(.derived(.swingDay)))
        #expect(occ.filter { $0.key == .derived(.coldDay) }.isEmpty)      // lows all 0 → low spread guard bails
    }
    @Test func oldSnapshotEventsWithoutLowAreSkippedNotMined() {
        // 20 valid combined events + 5 legacy single-value snapshots (no metadata.low, extreme value).
        // If the skip were broken the 999° snapshots would blow up the hot count / percentiles.
        let valid = shuffled20.enumerated().map { tempDay(high: $0.element, low: $0.element - 10, $0.offset) }
        let snapshots = (0..<5).map { i in HealthEvent(timestamp: Date(timeIntervalSince1970: Double(100 + i) * 86_400),
            timezoneID: "UTC", category: .environment, subtype: "temperature", value: 999, unit: "°C", source: .weatherAPI) }
        let validIDs = Set(valid.map(\.id))
        let occ = TemperatureExposureSource(config: .default).occurrences(from: valid + snapshots)
        #expect(!occ.isEmpty)                                             // not vacuously empty
        #expect(occ.allSatisfy { validIDs.contains($0.sourceEventID) })   // no snapshot produced an occurrence
        #expect(occ.filter { $0.key == .derived(.hotDay) }.count == 6)    // hot count unchanged by the 999° snapshots
    }
    @Test func degenerateFlatSeriesEmitsNothing() {   // all identical → every series has no spread → all cutoffs nil
        #expect(TemperatureExposureSource(config: .default)
            .occurrences(from: (1...25).map { tempDay(high: 20, low: 10, $0) }).isEmpty)
    }
    @Test func belowMinAtBoundaryEmitsNothing() {     // 19 = minWeatherReadings − 1 → catches a too-lenient guard
        #expect(TemperatureExposureSource(config: .default)
            .occurrences(from: (1...19).map { tempDay(high: Double($0), low: Double($0) - 10, $0) }).isEmpty)
    }
```

Rewrite `eachSourceIgnoresOtherSubtypes` so its temperature fixture is 20 spread `tempDay(high: element, low: element − 10, i)` events (reuse the hot/cold shape) and the `TemperatureExposureSource` assertion becomes `allSatisfy { $0.key == .derived(.hotDay) || $0.key == .derived(.coldDay) || $0.key == .derived(.swingDay) }` — `swingDay` is now part of temperature's own output, so omitting it would make the test flaky/false. Keep the humidity half (HumiditySource ignores temperature events) unchanged. Also add: `EdgeIdentityTests` `roundTrip(.derived(.swingDay), .symptom("migraine"))`; `InsightPhrasingTests.derivedLabels` `"swingDay" → "Big temperature swings"`; `PlausibilityCatalogTests` `"swingDay" → .contested`; `EvidenceConfigTests` `lagWindow(.swingDay) == 0...24`.

- [ ] **Step 2: Run to confirm failure.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → FAIL (`.swingDay` undefined; the rewritten temperature tests fail against the old single-value source).

- [ ] **Step 3: Add the enum case.** In `ExposureModel.swift`, `DerivedExposureKind`: add `case hotDay, coldDay, humidDay, swingDay` (append `swingDay` to the existing line).

- [ ] **Step 4: Rewrite `TemperatureExposureSource`** in `WeatherExposureSources.swift`:

```swift
public struct TemperatureExposureSource: ExposureSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    private struct DayTemp { let event: HealthEvent; let high: Double; let low: Double }

    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        // Combined daily events only: value = high, metadata["low"] = low. Old single-value
        // snapshots (no "low") are skipped — clean migration, no data change.
        let days: [DayTemp] = events.compactMap { e in
            guard e.category == .environment, e.subtype == "temperature", let high = e.value,
                  let data = e.metadata,
                  let meta = try? JSONDecoder().decode([String: String].self, from: data),
                  let low = meta["low"].flatMap({ Double($0) }) else { return nil }
            return DayTemp(event: e, high: high, low: low)
        }
        guard days.count >= config.minWeatherReadings else { return [] }

        // (lo, hi) quartile cutoffs for a series, or nil if it has no spread (flat/degenerate).
        func cutoffs(_ values: [Double]) -> (lo: Double, hi: Double)? {
            let sorted = values.sorted()
            let hi = Percentile.value(sorted, config.weatherHighPercentile)
            let lo = Percentile.value(sorted, config.weatherLowPercentile)
            return hi > lo ? (lo, hi) : nil
        }
        let highCut = cutoffs(days.map(\.high))
        let lowCut = cutoffs(days.map(\.low))
        let rangeCut = cutoffs(days.map { $0.high - $0.low })

        func occ(_ k: DerivedExposureKind, _ e: HealthEvent) -> ExposureOccurrence {
            ExposureOccurrence(key: .derived(k), timestamp: e.timestamp, timezoneID: e.timezoneID, sourceEventID: e.id)
        }
        var out: [ExposureOccurrence] = []
        for d in days {
            if let c = highCut, d.high >= c.hi { out.append(occ(.hotDay, d.event)) }
            if let c = lowCut, d.low <= c.lo { out.append(occ(.coldDay, d.event)) }
            if let c = rangeCut, (d.high - d.low) >= c.hi { out.append(occ(.swingDay, d.event)) }
        }
        return out
    }
}
```

(Leave `HumidityExposureSource` unchanged.)

- [ ] **Step 5: Wire identity/config/label/tier.**
  - `EdgeIdentity.fromToken` `.derived` switch: `case .swingDay: return "derived:swingDay"`. `parseFrom` `derived:` switch: `case "swingDay": return .derived(.swingDay)`.
  - `EvidenceConfig.lagWindow` `.derived` switch: extend the weather arm → `case .hotDay, .coldDay, .humidDay, .swingDay: return outsideFactorLagHours`.
  - `InsightPhrasing.derivedExposureLabel`: `case "swingDay": return "Big temperature swings"`.
  - `PlausibilityCatalog.tier`: extend the weather case → `case "hotDay", "coldDay", "humidDay", "swingDay": return .contested`.

- [ ] **Step 6: Run the core suite.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → all green. Report counts.

- [ ] **Step 7: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/WeatherExposureSources.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EdgeIdentity.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPhrasing.swift \
        HealthGraphCore/Sources/HealthGraphCore/Insights/PlausibilityCatalog.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/WeatherExposureSourcesTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EdgeIdentityTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/InsightPhrasingTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/PlausibilityCatalogTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "feat(core): Temperature source reads daily high/low → Hot/Cold/Swing (percentile); + swingDay contested"
```

---

### Task 3: App — forecast ingestion + range display

**Files:**
- Modify: `APIConfig.swift` (`forecastURL` + `units=metric`)
- Modify: `EnvironmentalDataService.swift` (forecast fetch + a pure aggregation function)
- Modify: `Models/EnvironmentalEventEmitter.swift` (thread high/low into the reading)
- Modify: `Views/HealthOS/Timeline/WeatherValueFormatter.swift` (range display)
- Modify: `Views/HealthOS/Insights/InsightsViewModel.swift` (map `swingDay` → `.environment` icon)
- Test: `Food IntolerancesTests/ForecastAggregationTests.swift`, `Food IntolerancesTests/WeatherValueFormatterTests.swift`, `Food IntolerancesTests/InsightsViewModelTests.swift`

**Interfaces:** Consumes the combined event (Task 1) + the tier (Task 2). Populates the real daily high/low so data flows going-forward; renders the range; gives the swing card the environment icon.

> **Why the icon fix lives here:** `InsightsViewModel` picks the card icon by string-matching the derived token (`fc == "hotDay" || … ? .environment : .note`). `"swingDay"` is absent, so a swing card silently falls through to `.note` — not a compile error, and no existing VM test asserts the icon, so it would slip every gate except the Task 4 device check. This app-layer file is unrelated to Task 2's core wiring, so it belongs in the app task, guarded by a VM test that asserts the category.

- [ ] **Step 1: Write the failing tests first.**
  - A forecast-aggregation test in `Food IntolerancesTests/ForecastAggregationTests.swift` (pure function): given synthetic slots `[(dt, temp, humidity)]`, `EnvironmentalDataService.aggregate24h(slots:now:)` returns `high == max`, `low == min`, `humidity == mean` over slots with `dt ∈ [now, now+24h]`; slots outside the window are excluded; `< 3` in-window slots → nil.
  - In `WeatherValueFormatterTests` — a `temperature` event WITH `metadata["low"]` renders a **range**: high 24 / low 12 → `"12–24°C"` (celsius) and `"54–75°F"` (fahrenheit: 12→53.6→54, 24→75.2→75); a temperature event WITHOUT metadata → single value (legacy, `"24°C"`). Use a U+2013 EN DASH in the expected literal, byte-identical to the formatter.
  - In `InsightsViewModelTests` — mirror `hotDayEdgeSurfacesInActiveWithContestedTier`: seed a `derived:swingDay → symptom` edge, build the VM, and assert the surfaced card is `tier == .contested` AND its exposure icon/category is `.environment` (NOT `.note`). The category assertion is what guards Step 7's one-liner.

- [ ] **Step 2: Run to confirm failure.** `xcodebuild build-for-testing … -only-testing:"Food IntolerancesTests"` (or the test run) → FAIL: `aggregate24h`/`forecastHighC` unresolved and the range/`.environment` assertions fail against current behavior.

- [ ] **Step 3: Add `units=metric` to `forecastURL`.** In `APIConfig.swift:54`, append `&units=metric` to the forecast URL string (mirroring `weatherURL`).

- [ ] **Step 4: Forecast fetch + aggregation.** In `EnvironmentalDataService.swift`:
  - Add `ForecastResponse { let list: [Slot] }`, `Slot { let dt: TimeInterval; let main: Main }`, extending the existing `Main` (or a forecast-specific `Main { let temp: Double; let humidity: Int }`).
  - Add a **pure static** `aggregate24h(slots: [(dt: TimeInterval, temp: Double, humidity: Double)], now: Date) -> (high: Double, low: Double, humidity: Double)?` — filter `dt ∈ [now.timeIntervalSince1970, +86_400]`, require `≥ 3`, return `(max temp, min temp, mean humidity)`.
  - Add a `fetchDailyForecast()` that GETs `APIConfig.forecastURL(latitude:longitude:)` — **reuse the exact location-resolution the existing pressure fetch uses** (same `CLLocation`/coordinate source; do not add a new location path), decodes `ForecastResponse`, maps to the tuple list, calls `aggregate24h(slots:now: Date())`, and sets `@Published var forecastHighC / forecastLowC / forecastHumidity: Double?` (all nil on failure/<3 slots). Call it from `fetchAllData()` alongside the pressure fetch.
- [ ] **Step 5: Thread into the reading.** In `EnvironmentalEventEmitter.emitIfNeeded`, replace the `temperatureC:`/`humidityPct:` args on the `EnvironmentalReading(...)` init with `temperatureHighC: service.forecastHighC, temperatureLowC: service.forecastLowC, humidityPct: service.forecastHumidity`. (`backfillDerived` unchanged — leaves them nil.)
- [ ] **Step 6: Range display.** In `WeatherValueFormatter.line`, the `"temperature"` case: decode `metadata["low"]`; if present, convert BOTH poles to `unit` + round, return `"\(lowR)–\(highR)°\(unit.rawValue)"`; if absent, keep the current single-value path.

```swift
        case "temperature":
            func conv(_ c: Double) -> Int { Int((unit == .fahrenheit ? c * 9 / 5 + 32 : c).rounded()) }
            if let data = event.metadata,
               let low = (try? JSONDecoder().decode([String: String].self, from: data))?["low"].flatMap({ Double($0) }) {
                return "\(conv(low))–\(conv(v))°\(unit.rawValue)"   // separator is U+2013 EN DASH — must match the test literal
            }
            return "\(conv(v))°\(unit.rawValue)"
```

- [ ] **Step 7: Fix the swingDay insight icon.** In `Views/HealthOS/Insights/InsightsViewModel.swift`, find the derived-token → icon ternary that lists `"hotDay" || "coldDay" || "humidDay" ? .environment : .note` and add `|| fc == "swingDay"` so the swing card gets the `.environment` icon like the other weather exposures. (Makes the Step 1 `.environment` assertion pass.)

- [ ] **Step 8: Build + regression.**
  - App build succeeds (this task re-fixes the emitter that Task 1 broke).
  - `xcodebuild test … -only-testing:"Food IntolerancesTests" … -parallel-testing-enabled NO` → every suite green except the known `SwiftDataMigratorTests` crash (incl. the new aggregation, range, and VM tests).
  - Core still green: `cd HealthGraphCore && swift test 2>&1 | tail -3`.

- [ ] **Step 9: Commit.**

```bash
git add "APIConfig.swift" "EnvironmentalDataService.swift" "Models/EnvironmentalEventEmitter.swift" \
        "Views/HealthOS/Timeline/WeatherValueFormatter.swift" "Views/HealthOS/Insights/InsightsViewModel.swift" \
        "Food IntolerancesTests/WeatherValueFormatterTests.swift" \
        "Food IntolerancesTests/ForecastAggregationTests.swift" "Food IntolerancesTests/InsightsViewModelTests.swift"
git commit -m "feat(app): daily high/low from /forecast next-24h + Timeline range display + swing icon"
```

---

### Task 4: Debug demo seed + end-to-end verification

**Files:** Modify `Views/HealthGraphDebugView.swift` (update `loadWeatherDemo`).

- [ ] **Step 1: Update the demo seed.** Change `loadWeatherDemo` to emit **combined** temperature events (`value = daily high`, `metadata ["low": String(dailyLow)]`) over ~200 days with a spread of highs, lows, and *ranges* (e.g. `high = 20 + 12·sin(2π·d/365) + (d%7)`, `low = high − (4 + (d%9))` → varied ranges), plus humidity, plus a `.symptom "migraine"` correlated (~70%, running counters) with the top-quartile hot days AND top-quartile swing days — so Hot / Cold / Swing / Humid can all surface. Recompute + refresh (reuse the existing shell).

- [ ] **Step 2: Build + full regression.** App build; core `swift test` green; full app suite green modulo the known `SwiftDataMigratorTests` crash.

- [ ] **Step 3: On-device / simulator check** (device preferred). Health tab → Debug → Reset → "Load WEATHER demo" → :
  - **Timeline** shows temperature as a **range** row (e.g. `12–24°C`, or `54–75°F` if the unit is °F) — one row/day, not two; humidity `69%`.
  - **Insights** shows contested cards among: **"Hot days"**, **"Cold days"**, **"Big temperature swings"**, **"Humid days"** — each with the "unproven mechanism · your pattern" tag + environment icon.
  - Toggle the Health-tab °C/°F picker → the Timeline range flips units live.
  - Light + dark; XXL Dynamic Type.

- [ ] **Step 4: Record observed behavior** in the ledger.

---

## Definition of Done

- Temperature is captured as a **daily high/low** from the free `/forecast` next-24h window (open-time-independent), emitted as one combined range event, and shown as `12–24°C` (unit-aware) in the Timeline.
- The engine mines **Hot / Cold / Big-swing** (personal-percentile over daily highs / lows / ranges) + **Humid**, all contested; old single-value snapshots are skipped (no migration).
- Core (factory, source rewrite incl. swing + skip-old + spread guards, identity, label, tier, config) unit-tested; the forecast aggregation + range formatter + swing-card `.environment` icon tested; the app wired + device-verified.
- Pressure, the gates, the tier UI, and the units picker are unchanged. One Call / calendar-day min/max remains a future option.
