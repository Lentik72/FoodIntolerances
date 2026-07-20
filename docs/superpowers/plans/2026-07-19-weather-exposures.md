# Weather Exposures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture temperature + humidity from the existing weather call, emit them as daily `.environment` events, and mine them as **personal-percentile** exposures — Hot / Cold / Humid days — presented as **contested** under the existing tier framework.

**Architecture:** `EnvironmentalReading` + `EnvironmentalEventFactory` gain temp/humidity events (parallel to pressure). Two NEW *stateful* exposure sources compute p25/p75 over the user's own temperature/humidity series and bucket days into `hotDay`/`coldDay`/`humidDay`. `PlausibilityCatalog` classifies all three as contested (reusing last round's presentation). The app service decodes the two already-present API fields and threads them into the reading.

**Tech Stack:** Swift, Swift Testing, GRDB, SwiftUI, OpenWeatherMap (existing, `units=metric`). Core via `swift test`; app via `xcodebuild ... -parallel-testing-enabled NO`.

Design: `docs/superpowers/specs/2026-07-19-weather-exposures-design.md`.

## Global Constraints

- **Three new `DerivedExposureKind` cases** (`hotDay`, `coldDay`, `humidDay`) are additive. They force the two exhaustive switches over `DerivedExposureKind` — `EdgeIdentity.fromToken` and `EvidenceConfig.lagWindow(for:)` — to add cases. Grep to confirm those are the only two. `parseFrom` is an `if`+`switch`-with-default; `derivedExposureLabel` keys on a String; `PlausibilityCatalog` keys on a String.
- **Percentile bucketing is per-user, computed over the full series** (a NEW source shape — not stateless per-event): sort the values, compute p25/p75, bucket `>= p75` (hot/humid) and `<= p25` (cold). A **min-readings guard** (`config.minWeatherReadings`, default 20) — below it, emit NO weather exposures.
- **`units=metric`** (`APIConfig.swift:45`) → OpenWeather `main.temp` is already **°C** and `main.humidity` is **%** — no conversion.
- **`EnvironmentalReading`'s new params are defaulted `nil`** so the two existing construction sites (`emitIfNeeded`, `backfillDerived`) and any tests compile unchanged; `backfillDerived` leaves them nil (no weather history).
- **Tier = contested** for all three (reuse the framework: evidence feed + "unproven mechanism · your pattern" tag, `.environment` icon). No gate/phrasing/tier-UI change.
- **Percentile method is nearest-rank, deterministic** (defined once, pinned by tests). Ties at the cutoff count as in-bucket (`>=`/`<=`).
- **App-target tests MUST run `-parallel-testing-enabled NO`;** the lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing teardown crash.
- **Simulator:** iPhone 17 Pro (iOS 26.5).
- **Out of scope:** absolute thresholds, dry/low-humidity, temperature-swing, season, historical backfill, threshold settings UI.
- **Intermediate state:** after Task 2 (mining) but before Task 3 (app capture), the sources exist but no real temp/humidity events flow yet — fine; nothing merges until all tasks land.

---

### Task 1: Core — emit temperature + humidity events

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift` (`EnvironmentalReading` + `events(for:)`)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift` (create if absent, else extend)

**Interfaces:** Produces daily `.environment` events `subtype "temperature"` (value °C) and `"humidity"` (value %). Task 2's sources read them; Task 3's app populates the reading.

- [ ] **Step 1: Write the failing test first.** In `EnvironmentalEventFactoryTests.swift` (check whether it exists first; if not, create with `import Testing/Foundation/@testable import HealthGraphCore`):

```swift
    @Test func emitsTemperatureAndHumidityWhenPresent() {
        let r = EnvironmentalReading(date: Date(timeIntervalSince1970: 1_700_000_000),
            pressureHPa: nil, previousPressureHPa: nil, moonPhaseName: nil, season: nil,
            isMercuryRetrograde: false, timezoneID: "UTC", temperatureC: 28.5, humidityPct: 82)
        let events = EnvironmentalEventFactory.events(for: r)
        let temp = events.first { $0.subtype == "temperature" }
        let hum = events.first { $0.subtype == "humidity" }
        #expect(temp?.category == .environment && temp?.value == 28.5 && temp?.unit == "°C")
        #expect(hum?.category == .environment && hum?.value == 82 && hum?.unit == "%")
        #expect(temp?.dedupKey != nil && hum?.dedupKey != nil)   // daily dedupKey (idempotent re-emission)
    }
    @Test func emitsNoTempHumidityWhenNil() {
        let r = EnvironmentalReading(date: Date(timeIntervalSince1970: 1_700_000_000),
            pressureHPa: 1013, previousPressureHPa: nil, moonPhaseName: nil, season: nil,
            isMercuryRetrograde: false, timezoneID: "UTC")   // temp/humidity default nil
        let events = EnvironmentalEventFactory.events(for: r)
        #expect(!events.contains { $0.subtype == "temperature" || $0.subtype == "humidity" })
    }
```

- [ ] **Step 2: Run to confirm failure.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → FAIL to compile (`EnvironmentalReading` has no `temperatureC:`).

- [ ] **Step 3: Add the reading fields.** In `EnvironmentalEventFactory.swift`, add to `EnvironmentalReading`:
  - Two stored props after `timezoneID`: `public let temperatureC: Double?` and `public let humidityPct: Double?`.
  - Two DEFAULTED init params (at the end of the init signature): `temperatureC: Double? = nil, humidityPct: Double? = nil`, and assign them.

- [ ] **Step 4: Emit the events.** In `events(for:)`, after the `season` block (before `return events`), add:

```swift
        if let temp = r.temperatureC {
            events.append(event("temperature", value: temp, unit: "°C"))
        }
        if let humidity = r.humidityPct {
            events.append(event("humidity", value: humidity, unit: "%"))
        }
```

- [ ] **Step 5: Run the core suite.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → all green. Report counts.

- [ ] **Step 6: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift
git commit -m "feat(core): EnvironmentalReading + factory emit daily temperature/humidity events"
```

---

### Task 2: Core — percentile Hot/Cold/Humid exposures + tiering

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift` (`DerivedExposureKind`)
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/WeatherExposureSources.swift` (Percentile + two sources)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift` (register sources)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EdgeIdentity.swift` (`fromToken`, `parseFrom`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift` (percentile + min-readings knobs; lag)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPhrasing.swift` (`derivedExposureLabel`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Insights/PlausibilityCatalog.swift` (three → contested)
- Test: `WeatherExposureSourcesTests.swift` (new), `EdgeIdentityTests.swift`, `InsightPhrasingTests.swift`, `PlausibilityCatalogTests.swift`, `ExposureSourceTests.swift` (config)

**Interfaces:** Produces `.derived(.hotDay/.coldDay/.humidDay)` exposures (percentile-bucketed), edge tokens `"derived:hotDay"` etc., labels "Hot/Cold/Humid days", tier `.contested`. Task 3 renders them (icon + it's already contested-tagged).

- [ ] **Step 1: Write the failing tests first.**

`WeatherExposureSourcesTests.swift` (new) — pin the percentile boundaries on a known input (values 1…20, n=20 ≥ min 20; nearest-rank p75 = 15, p25 = 5):

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct WeatherExposureSourcesTests {
    private func temp(_ v: Double, _ i: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                    category: .environment, subtype: "temperature", value: v, unit: "°C", source: .weatherAPI)
    }
    private func humid(_ v: Double, _ i: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                    category: .environment, subtype: "humidity", value: v, unit: "%", source: .weatherAPI)
    }
    // Values 1…20 in SHUFFLED input order — the source must sort internally (a dropped
    // `.sorted()` would pass a pre-sorted fixture but fail this one).
    private let shuffled20: [Double] = [11, 3, 17, 8, 20, 1, 14, 6, 19, 9, 2, 15, 7, 12, 4, 18, 10, 5, 16, 13]

    @Test func hotAndColdByQuartile() {
        let events = shuffled20.enumerated().map { temp($0.element, $0.offset) }   // n=20, values 1…20
        let occ = TemperatureExposureSource(config: .default).occurrences(from: events)
        let hot = occ.filter { $0.key == .derived(.hotDay) }.count
        let cold = occ.filter { $0.key == .derived(.coldDay) }.count
        #expect(hot == 6)     // >= p75(15): 15…20
        #expect(cold == 5)    // <= p25(5): 1…5
        #expect(occ.count == hot + cold)   // middle → neither
    }
    @Test func percentileIsNearestRankNotFloorOrLinear() {   // n=21 → fractional rank exercises .rounded(.up)
        let occ = TemperatureExposureSource(config: .default).occurrences(from: (1...21).map { temp(Double($0), $0) })
        #expect(occ.filter { $0.key == .derived(.hotDay) }.count == 6)    // p75 rank=ceil(15.75)=16 → cutoff 16 → 16…21
        #expect(occ.filter { $0.key == .derived(.coldDay) }.count == 6)   // p25 rank=ceil(5.25)=6 → cutoff 6 → 1…6
    }
    @Test func belowMinReadingsEmitsNothing() {
        #expect(TemperatureExposureSource(config: .default).occurrences(from: (1...10).map { temp(Double($0), $0) }).isEmpty)
    }
    @Test func atMinMinusOneEmitsNothing() {   // n=19 = minWeatherReadings−1 → catches a too-lenient guard
        #expect(TemperatureExposureSource(config: .default).occurrences(from: (1...19).map { temp(Double($0), $0) }).isEmpty)
    }
    @Test func degenerateAllEqualSeriesEmitsNothing() {   // no spread → NO false signal (the percentile-design guarantee)
        #expect(TemperatureExposureSource(config: .default).occurrences(from: (1...25).map { temp(20, $0) }).isEmpty)
        #expect(HumidityExposureSource(config: .default).occurrences(from: (1...25).map { humid(55, $0) }).isEmpty)
    }
    @Test func humidityTopQuartileOnly() {
        let occ = HumidityExposureSource(config: .default).occurrences(from: shuffled20.enumerated().map { humid($0.element, $0.offset) })
        #expect(occ.allSatisfy { $0.key == .derived(.humidDay) })
        #expect(occ.count == 6)   // >= p75(15)
    }
    @Test func humidityBelowMinReadingsEmitsNothing() {
        #expect(HumidityExposureSource(config: .default).occurrences(from: (1...10).map { humid(Double($0), $0) }).isEmpty)
    }
    @Test func eachSourceIgnoresOtherSubtypes() {   // mixed batch → each source reacts only to its own subtype
        var events = shuffled20.enumerated().map { temp($0.element, $0.offset) }
        events += shuffled20.enumerated().map { humid($0.element, $0.offset + 100) }
        events.append(HealthEvent(timestamp: Date(timeIntervalSince1970: 900 * 86_400), timezoneID: "UTC",
            category: .environment, subtype: "pressure", value: 1013, unit: "hPa", source: .weatherAPI))
        #expect(TemperatureExposureSource(config: .default).occurrences(from: events)
            .allSatisfy { $0.key == .derived(.hotDay) || $0.key == .derived(.coldDay) })
        #expect(HumidityExposureSource(config: .default).occurrences(from: events)
            .allSatisfy { $0.key == .derived(.humidDay) })
    }
}
```

`EdgeIdentityTests` — extend `derivedExposuresRoundTrip`: `roundTrip(.derived(.hotDay), .symptom("migraine"))`, `roundTrip(.derived(.coldDay), .symptom("jointPain"))`, `roundTrip(.derived(.humidDay), .lowMood)`.
`InsightPhrasingTests.derivedLabels` — add: `"hotDay" → "Hot days"`, `"coldDay" → "Cold days"`, `"humidDay" → "Humid days"`.
`PlausibilityCatalogTests.tiers` — add: `"hotDay"`, `"coldDay"`, `"humidDay"` → `.contested`.
`ExposureSourceTests.EvidenceConfigTests` — add: `#expect(c.minWeatherReadings == 20)`, `#expect(c.weatherHighPercentile == 0.75)`, `#expect(c.weatherLowPercentile == 0.25)`, and the lag for **all three** kinds (the three share one switch arm, so assert each to catch a copy-paste): `#expect(c.lagWindow(for: .derived(.hotDay)) == 0...24)`, `.coldDay`, `.humidDay`.

- [ ] **Step 2: Run to confirm failure.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → FAIL to compile.

- [ ] **Step 3: Add the enum cases.** In `ExposureModel.swift`, `DerivedExposureKind`:

```swift
    case shortSleep, highStress, pressureDrop
    case cyclePhase(CyclePhase)
    case fullMoon, mercuryRetrograde
    case hotDay, coldDay, humidDay
```

- [ ] **Step 4: Create `WeatherExposureSources.swift`:**

```swift
import Foundation

/// Deterministic nearest-rank percentile over an ascending-sorted, non-empty array.
/// `p` in 0...1. Ties at the cutoff are the caller's to include (`>=`/`<=`).
enum Percentile {
    static func value(_ sortedAscending: [Double], _ p: Double) -> Double {
        guard let first = sortedAscending.first else { return 0 }
        guard sortedAscending.count > 1 else { return first }
        let rank = Int((p * Double(sortedAscending.count)).rounded(.up))   // 1-based
        return sortedAscending[max(1, min(sortedAscending.count, rank)) - 1]
    }
}

/// Temperature exposures — personal-percentile: a day's temp in the user's top
/// quartile → hotDay, bottom quartile → coldDay. Needs ≥ minWeatherReadings for a
/// stable distribution (below that, no exposures — the engine's own cold-start).
public struct TemperatureExposureSource: ExposureSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        let temps = events.filter { $0.category == .environment && $0.subtype == "temperature" && $0.value != nil }
        guard temps.count >= config.minWeatherReadings else { return [] }
        let sorted = temps.compactMap(\.value).sorted()
        let hi = Percentile.value(sorted, config.weatherHighPercentile)
        let lo = Percentile.value(sorted, config.weatherLowPercentile)
        guard hi > lo else { return [] }   // no spread (flat/degenerate series) → no buckets, no false signal
        return temps.compactMap { e in
            guard let v = e.value else { return nil }
            if v >= hi { return ExposureOccurrence(key: .derived(.hotDay), timestamp: e.timestamp,
                                                   timezoneID: e.timezoneID, sourceEventID: e.id) }
            if v <= lo { return ExposureOccurrence(key: .derived(.coldDay), timestamp: e.timestamp,
                                                   timezoneID: e.timezoneID, sourceEventID: e.id) }
            return nil
        }
    }
}

/// Humidity exposures — top-quartile day → humidDay (high humidity is the cited pole).
public struct HumidityExposureSource: ExposureSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        let hums = events.filter { $0.category == .environment && $0.subtype == "humidity" && $0.value != nil }
        guard hums.count >= config.minWeatherReadings else { return [] }
        let sorted = hums.compactMap(\.value).sorted()
        let hi = Percentile.value(sorted, config.weatherHighPercentile)
        let lo = Percentile.value(sorted, config.weatherLowPercentile)
        guard hi > lo else { return [] }   // no spread → no buckets
        return hums.compactMap { e in
            guard let v = e.value, v >= hi else { return nil }
            return ExposureOccurrence(key: .derived(.humidDay), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
```

- [ ] **Step 5: Register the sources.** In `EvidenceEngine.swift`'s `sources` array (after the mercury/full-moon entries):

```swift
            TemperatureExposureSource(config: config),
            HumidityExposureSource(config: config),
```

- [ ] **Step 6: Config knobs.** In `EvidenceConfig.swift`, add near the other thresholds:

```swift
    public var weatherHighPercentile: Double = 0.75
    public var weatherLowPercentile: Double = 0.25
    public var minWeatherReadings: Int = 20
```

and in `lagWindow(for:)`'s `.derived(kind)` switch, add: `case .hotDay, .coldDay, .humidDay: return outsideFactorLagHours`.

- [ ] **Step 7: Edge identity.** In `EdgeIdentity.swift`: `fromToken`'s `.derived` switch gains `case .hotDay: return "derived:hotDay"` (and coldDay/humidDay); `parseFrom`'s `derived:` `switch kind` gains `case "hotDay": return .derived(.hotDay)` (and coldDay/humidDay).

- [ ] **Step 8: Labels.** In `InsightPhrasing.derivedExposureLabel`, add before `default`: `case "hotDay": return "Hot days"`, `case "coldDay": return "Cold days"`, `case "humidDay": return "Humid days"`.

- [ ] **Step 9: Tier.** In `PlausibilityCatalog.tier(forExposureCategory:)`, add to the `switch`: `case "hotDay", "coldDay", "humidDay": return .contested`.

- [ ] **Step 10: Run the core suite.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → all green. Report counts.

- [ ] **Step 11: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/WeatherExposureSources.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EdgeIdentity.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPhrasing.swift \
        HealthGraphCore/Sources/HealthGraphCore/Insights/PlausibilityCatalog.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/WeatherExposureSourcesTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EdgeIdentityTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/InsightPhrasingTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/PlausibilityCatalogTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "feat(core): personal-percentile Hot/Cold/Humid exposures + contested tier"
```

---

### Task 3: App — capture temp/humidity + weather icon

**Files:**
- Modify: `EnvironmentalDataService.swift` (decode temp/humidity + published props)
- Modify: `Models/EnvironmentalEventEmitter.swift` (thread into the reading)
- Modify: `Views/HealthOS/Insights/InsightsViewModel.swift` (`exposure(for:)` icon for the 3 tokens)
- Test: `Food IntolerancesTests/InsightsViewModelTests.swift` (a hotDay edge surfaces contested)

**Interfaces:** Consumes the factory events (Task 1) + tier (Task 2). Populates the real reading so temp/humidity flow going-forward.

- [ ] **Step 1: Write the failing VM test first.** In `InsightsViewModelTests.swift`, add (mirrors `fullMoonEdgeSurfacesInActiveWithContestedTier`):

```swift
    @Test func hotDayEdgeSurfacesInActiveWithContestedTier() async throws {
        let refNow = Date(timeIntervalSince1970: 1_713_000_000)
        let db = try AppDatabase.inMemory()
        let hot = Relationship(
            fromCategory: "hotDay", toCategory: "symptom", type: .possibleTrigger,
            evidenceCount: 6, contradictionCount: 2, confidence: 0.6, strength: 5, lagHours: 12,
            firstSeen: refNow.addingTimeInterval(-30 * 86_400), lastSeen: refNow, lastRecomputed: refNow,
            status: .active, edgeKey: "derived:hotDay|symptom:migraine|possibleTrigger", toSubtype: "migraine")
        try await GRDBRelationshipStore(database: db).save(hot)
        let vm = InsightsViewModel(database: db, now: { refNow })
        await vm.load()
        let card = vm.feed.sections.first { $0.kind == .active }?.cards.first
        #expect(card?.tier == .contested)
        #expect(card?.claim.contains("Hot days") == true)
    }
```

- [ ] **Step 2: Decode temp/humidity in the service.** In `EnvironmentalDataService.swift`:
  - `WeatherResponse.Main`: add `let temp: Double?` and `let humidity: Int?` — **optional**, so a missing/renamed key on either doesn't also fail the (previously pressure-only) decode; defensive and consistent with the optionals below.
  - Add `@Published var currentTemperatureC: Double? = nil` and `@Published var currentHumidityPct: Double? = nil` near the other published props. **Optionals, NOT a `0` default** — 0 °C is a legitimate (freezing) reading, and a `> 0` guard would silently discard exactly the *cold days* the Cold-day exposure needs. Optionals distinguish "no reading yet" from "0 °C". (Pressure uses a `0`/`> 0` guard because 0 hPa is physically impossible; temperature is different.)
  - In `fetchAtmosphericPressure`'s success branch, **extract scalars before the `MainActor.run` closure** (mirroring the existing `let pressureValue = ...`, to avoid capturing the non-Sendable `WeatherResponse` across the hop): `let temp = decodedResponse.main.temp` and `let humidity = decodedResponse.main.humidity.map(Double.init)`, then inside the closure set `self.currentTemperatureC = temp` and `self.currentHumidityPct = humidity`.

- [ ] **Step 3: Thread into the reading.** In `EnvironmentalEventEmitter.emitIfNeeded`, add to the `EnvironmentalReading(...)` init call: `temperatureC: service.currentTemperatureC, humidityPct: service.currentHumidityPct` (already optional — nil when never fetched, so no event is emitted that day; a genuine 0 °C reading is preserved). `backfillDerived` leaves them nil (unchanged — no weather history).

- [ ] **Step 4: Weather icon.** In `InsightsViewModel.exposure(for:)`, add `"hotDay"`, `"coldDay"`, `"humidDay"` to the `.environment` branch (mirroring `pressureDrop`/`fullMoon`/`mercuryRetrograde`) so weather cards get the environment icon, not `.note`.

- [ ] **Step 5: Build + VM tests.**

Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -8` → `** BUILD SUCCEEDED **`.

Run: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests/InsightsViewModelTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "Test run with|✔ Test|✘ Test|TEST (SUCCEEDED|FAILED)" | tail -10` → `** TEST SUCCEEDED **` (existing + `hotDayEdgeSurfacesInActiveWithContestedTier`).

- [ ] **Step 6: Commit.**

```bash
git add "EnvironmentalDataService.swift" "Models/EnvironmentalEventEmitter.swift" \
        "Views/HealthOS/Insights/InsightsViewModel.swift" \
        "Food IntolerancesTests/InsightsViewModelTests.swift"
git commit -m "feat(app): capture temperature/humidity from the weather call + environment icon for weather factors"
```

---

### Task 4: Debug demo seed + end-to-end verification

**Files:**
- Modify: `Views/HealthGraphDebugView.swift` ("Load WEATHER demo" button + seed)

- [ ] **Step 1: Add the demo seed.** Add a button next to the other demo seeds → `Task { await loadWeatherDemo() }`, and a `loadWeatherDemo()` (reuse `loadMoodDemo()`'s `isWorking`/`defer`/`do-catch` shell). Hand-build ~200 days of `.environment` events + a correlated symptom, save via `GRDBEventStore(database:).save(_:)`, then `try await EvidenceEngine(database:).recompute(asOf: Date())` + `await refresh()`:
  - For each day `d` in 0..<200 (dayStart = now − (200−d) days): a `temperature` event (value = a spread, e.g. `20 + 12*sin(2π·d/365) + (d % 7)` for seasonal + noise → a real distribution) and a `humidity` event (value = `50 + 25*sin(2π·d/180) + (d % 5)`), both `.environment`, `source: .weatherAPI`, daily dedupKey.
  - A correlated `.symptom` "migraine" (value ~5, `.manual`) a few hours after ~70% of the top-quartile-temperature days and ~70% of the top-quartile-humidity days (use running counters, not a `d`-modulus, to avoid spurious perfect correlation), plus ~5% baseline.
  - ≥20 temp/humidity readings (200 ≫ 20 → percentiles compute); enough hot/humid days at ~70% follow to clear the gates → "Hot days → migraine" / "Humid days → migraine" activate as contested cards.

- [ ] **Step 2: Build + full regression.**
  - App build succeeds.
  - Core: `cd HealthGraphCore && swift test 2>&1 | tail -3` → all green.
  - App target: `xcodebuild test ... -only-testing:"Food IntolerancesTests" ... -parallel-testing-enabled NO 2>&1 | grep -E "✔ Suite|✘|Test run with|\*\* TEST"` → every suite green except the known `SwiftDataMigratorTests` crash.

- [ ] **Step 3: On-device / simulator check** (device preferred). Health tab → Health Graph Debug → Reset → **"Load WEATHER demo"** → Insights:
  - **"Hot days → migraine"** and/or **"Humid days → migraine"** appear in the evidence feed, each with the **"unproven mechanism · your pattern"** contested tag and the environment/cloud icon.
  - Phrasing tentative; no causal language; established factors unlabeled; light + dark; XXL Dynamic Type.

- [ ] **Step 4: Record observed behavior** in the review notes / ledger.

---

## Definition of Done

- Temperature + humidity are captured going-forward from the existing weather call and emitted as daily `.environment` events (parallel to pressure; nil when unavailable).
- The engine mines **Hot / Cold / Humid** day exposures via **personal-percentile (quartile)** bucketing over the user's own series, with a min-readings cold-start guard; all three round-trip through edge identity, have labels, and are tiered **contested** (evidence feed + "unproven mechanism · your pattern" tag + environment icon).
- The evidence gates + phrasing rule + tier UI are unchanged; no causal language; no absolute thresholds / dry / swing / season / backfill.
- Core (factory, percentile sources, identity, labels, catalog, config) unit-tested (incl. exact percentile boundaries + the cold-start guard); the app capture + icon wired + VM-tested; a debug demo seed for device verification.
- This completes the outside-factors arc; no further environmental factors are committed.
