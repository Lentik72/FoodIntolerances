# Air Quality Exposure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ingest air quality (PM2.5 → US EPA AQI) as an established-tier exposure, mine `poorAirDay` (AQI ≥ 101) against outcomes, and surface it in Insights + the Environment Timeline row (leading the headline on a poor-air day).

**Architecture:** A pure core `AirQualityIndex` (EPA breakpoints + category) is used at ingest (app computes AQI from the day's mean PM2.5) and at display (core derives the category). A daily `airQuality` `.environment` event (value = AQI) is emitted by the factory, mined by a new `AirQualityExposureSource` (absolute threshold, no percentile), and folded into the Environment summary row. Mirrors the weather pipeline; no evidence-gate or tier-framework change (established is the default).

**Tech Stack:** Swift, Swift Testing, SwiftUI, OpenWeather `/air_pollution/forecast` (free, same key).

Design: `docs/superpowers/specs/2026-07-20-air-quality-exposure-design.md`.

## Global Constraints

- **Exposure:** one binary `poorAirDay` = **AQI ≥ 101** ("Unhealthy for Sensitive Groups"+). Absolute health threshold — NO percentile, NO min-readings guard (each poor-air day is independently valid; the evidence gates handle significance).
- **AQI source:** US EPA AQI computed from the **day's mean PM2.5** over the next-24h `/air_pollution/forecast` slots (≥3 in-window slots else nil) — same open-time-bias fix as the weather high/low.
- **Tier:** established — `PlausibilityCatalog` is UNCHANGED (`"poorAirDay"` falls through to the `.established` default). No "unproven mechanism" tag.
- **Event shape:** `subtype "airQuality"`, `value = Double(aqi)`, `unit nil`, no metadata (category derived from the AQI at display), daily dedupKey.
- **`.poorAirDay` is additive** to `DerivedExposureKind` — three sites need the arm: the two **compiler-exhaustive** switches (`EdgeIdentity.fromToken`, `EvidenceConfig.lagWindow`) that hard-fail without it, PLUS the **non-exhaustive** `EdgeIdentity.parseFrom` (has a `default:`, so it compiles without the arm but breaks `.poorAirDay` round-trip — Task 2 Step 6 adds it; the round-trip test catches a miss). Grep `case .shortSleep` to confirm the two exhaustive switches are the only two.  Everything else is additive/defaulted, so **the app never breaks** (unlike the weather round) — each task keeps both `swift test` and the app build green.
- **Separators are byte-identical:** the AQI value line/headline use a **U+00B7 MIDDLE DOT** with surrounding spaces (`"132 · Unhealthy…"`), and temperature ranges use a **U+2013 EN DASH** (`"12–24°C"`). Copy both exactly into impl and test literals — a bullet (U+2022) or hyphen slip is a silent string-equality failure.
- **Timeline:** air quality folds into the Environment summary row — a detail line always (via `subtypeOrder` + `EventDisplay`, automatic), and it **leads the collapsed headline only on a poor-air day** (AQI ≥ 101). Normal days unchanged.
- **App-target tests `-parallel-testing-enabled NO`;** the lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing crash. **Simulator:** iPhone 17 Pro (iOS 26.5). New app files under the tracked paths. Ignore SourceKit "No such module"/"Cannot find type" diagnostics (stale-index noise); `swift test`/`xcodebuild` are authoritative.

---

### Task 1: Core — `AirQualityIndex` (pure EPA AQI math)

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/AirQualityIndex.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/AirQualityIndexTests.swift`

**Interfaces:** `AirQualityIndex.epaAQI(pm25:) -> Int`, `AirQualityIndex.category(aqi:) -> AQICategory` (+ `.name`), `AirQualityIndex.poorAirThreshold = 101`. Task 2 mines with it; the app (Task 3) computes AQI at ingest; core `EventDisplay` (Task 2) derives the category.

- [ ] **Step 1: Write the failing tests first** in `AirQualityIndexTests.swift`:

```swift
import Testing
@testable import HealthGraphCore

struct AirQualityIndexTests {
    @Test func epaAQIAtCategoryBoundaries() {
        #expect(AirQualityIndex.epaAQI(pm25: 0) == 0)
        #expect(AirQualityIndex.epaAQI(pm25: 12.0) == 50)
        #expect(AirQualityIndex.epaAQI(pm25: 12.1) == 51)
        #expect(AirQualityIndex.epaAQI(pm25: 35.4) == 100)
        #expect(AirQualityIndex.epaAQI(pm25: 35.5) == 101)   // the poorAirDay boundary
        #expect(AirQualityIndex.epaAQI(pm25: 55.4) == 150)
        #expect(AirQualityIndex.epaAQI(pm25: 55.5) == 151)
        #expect(AirQualityIndex.epaAQI(pm25: 9999) == 500)   // clamps above the top breakpoint
    }
    @Test func epaAQIInterpolatesWithinABin() {
        #expect(AirQualityIndex.epaAQI(pm25: 6.0) == 25)     // midpoint of Good bin (0–12→0–50)
        #expect(AirQualityIndex.epaAQI(pm25: 45.0) == 124)   // interior of 35.5–55.4 bin: (49/19.9)*9.5+101 → 124
    }
    @Test func epaAQITruncatesConcentrationToTenth() {
        // Pins the EPA 0.1-truncation: 35.49 → 35.4 → AQI 100 (NOT poor). Without the
        // truncation the value would round to 101 and flip poorAirDay. (Real meanPM25
        // output has many decimals, so this step is health-critical near the threshold.)
        #expect(AirQualityIndex.epaAQI(pm25: 35.49) == 100)
    }
    @Test func categoryNamesAndThreshold() {
        #expect(AirQualityIndex.category(aqi: 50).name == "Good")
        #expect(AirQualityIndex.category(aqi: 100).name == "Moderate")
        #expect(AirQualityIndex.category(aqi: 101).name == "Unhealthy for sensitive groups")
        #expect(AirQualityIndex.category(aqi: 175).name == "Unhealthy")
        #expect(AirQualityIndex.category(aqi: 250).name == "Very unhealthy")
        #expect(AirQualityIndex.category(aqi: 400).name == "Hazardous")
        #expect(AirQualityIndex.poorAirThreshold == 101)
    }
}
```

- [ ] **Step 2: Run to confirm failure.** `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -20` → FAIL (`AirQualityIndex` undefined).

- [ ] **Step 3: Implement** `AirQualityIndex.swift`:

```swift
import Foundation

/// US EPA Air Quality Index from PM2.5 (fine particulates). Pure; no I/O. Used at
/// ingest (app computes AQI from the day's mean PM2.5) and display (category name).
public enum AirQualityIndex {
    public static let poorAirThreshold = 101   // AQI ≥ 101 = "Unhealthy for Sensitive Groups"+

    /// EPA 24-hr PM2.5 breakpoints (µg/m³ → AQI), piecewise-linear.
    private static let breakpoints: [(cLo: Double, cHi: Double, iLo: Int, iHi: Int)] = [
        (0.0, 12.0, 0, 50), (12.1, 35.4, 51, 100), (35.5, 55.4, 101, 150),
        (55.5, 150.4, 151, 200), (150.5, 250.4, 201, 300),
        (250.5, 350.4, 301, 400), (350.5, 500.4, 401, 500),
    ]

    /// EPA AQI for a PM2.5 concentration (µg/m³). Concentration truncated to 0.1 per
    /// EPA convention; above the top breakpoint clamps to 500.
    public static func epaAQI(pm25: Double) -> Int {
        let c = (max(0, pm25) * 10).rounded(.down) / 10          // truncate to 0.1
        guard let bp = breakpoints.first(where: { c <= $0.cHi }) else { return 500 }
        let aqi = (Double(bp.iHi - bp.iLo) / (bp.cHi - bp.cLo)) * (c - bp.cLo) + Double(bp.iLo)
        return Int(aqi.rounded())
    }

    public enum AQICategory: Sendable, Equatable {
        case good, moderate, unhealthySensitive, unhealthy, veryUnhealthy, hazardous
        public var name: String {
            switch self {
            case .good: "Good"
            case .moderate: "Moderate"
            case .unhealthySensitive: "Unhealthy for sensitive groups"
            case .unhealthy: "Unhealthy"
            case .veryUnhealthy: "Very unhealthy"
            case .hazardous: "Hazardous"
            }
        }
    }

    public static func category(aqi: Int) -> AQICategory {
        switch aqi {
        case ..<51: .good
        case ..<101: .moderate
        case ..<151: .unhealthySensitive
        case ..<201: .unhealthy
        case ..<301: .veryUnhealthy
        default: .hazardous
        }
    }
}
```

- [ ] **Step 4: Run the core suite.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → all green. Report counts.

- [ ] **Step 5: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Ingestion/AirQualityIndex.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/AirQualityIndexTests.swift
git commit -m "feat(core): AirQualityIndex — EPA AQI from PM2.5 + category (pure)"
```

---

### Task 2: Core — the `airQuality` event + `poorAirDay` exposure + wiring

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift` (`EnvironmentalReading` + `events(for:)`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/EventDisplay.swift` (title + value line)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift` (`subtypeOrder`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift` (`.poorAirDay`)
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/AirQualityExposureSource.swift`
- Modify: `Evidence/EvidenceEngine.swift` (register), `Evidence/EdgeIdentity.swift`, `Evidence/EvidenceConfig.swift` (lag), `Insights/InsightPhrasing.swift` (label)
- Test: `EnvironmentalEventFactoryTests.swift`, `ExposureSourceTests.swift` (or a new `AirQualityExposureSourceTests.swift`), `EdgeIdentityTests.swift`, `InsightPhrasingTests.swift`, `PlausibilityCatalogTests.swift`, `EvidenceConfigTests.swift`, `EventDisplayTests.swift`

**Interfaces:** `.derived(.poorAirDay)`, token `"derived:poorAirDay"`, label "Poor air quality", tier `.established`. `AirQualityExposureSource().occurrences(from:)` emits `.poorAirDay` for `airQuality` events with `value ≥ 101`.

- [ ] **Step 1: Write the failing tests first.**
  - `EnvironmentalEventFactoryTests` — a reading with `airQualityAQI: 132` emits exactly one `airQuality` event, `value == 132`, `unit == nil`, non-nil daily dedupKey; a nil-AQI reading → no airQuality event.
  - `AirQualityExposureSourceTests` — three `airQuality` events (values 42, 101, 175) → exactly TWO `.poorAirDay` occurrences (the 101 and 175), keyed on those events; a value-100 event and a non-airQuality env event → none.
  - `EventDisplayTests` — `title` for `airQuality` == "Air quality"; `valueLine` for an `airQuality` event value 132 == `"132 · Unhealthy for sensitive groups"`.
  - `EdgeIdentityTests` — `roundTrip(.derived(.poorAirDay), .symptom("migraine"))`. `InsightPhrasingTests` — `"poorAirDay" → "Poor air quality"`. `PlausibilityCatalogTests` — `tier(forExposureCategory: "poorAirDay") == .established`. `EvidenceConfigTests` — `lagWindow(.derived(.poorAirDay)) == 0...24`.

```swift
    // AirQualityExposureSourceTests
    private func aq(_ v: Double, _ i: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                    category: .environment, subtype: "airQuality", value: v, source: .weatherAPI)
    }
    @Test func poorAirDayOnlyAtOrAbove101ByEvent() {
        let good = aq(42, 0), poor1 = aq(101, 1), poor2 = aq(175, 2), boundaryBelow = aq(100, 3)
        let occ = AirQualityExposureSource().occurrences(from: [good, poor1, poor2, boundaryBelow])
        #expect(occ.allSatisfy { $0.key == .derived(.poorAirDay) })
        // Exactly the ≥101 events fired — 100 (boundary-below) and 42 excluded. Pins the
        // threshold AND that the RIGHT events keyed (not just a count).
        #expect(Set(occ.map(\.sourceEventID)) == Set([poor1.id, poor2.id]))
    }
    @Test func ignoresNonAirQualitySubtypeAndNonEnvironmentCategory() {
        let humidity = HealthEvent(timestamp: Date(timeIntervalSince1970: 0), timezoneID: "UTC",
                                   category: .environment, subtype: "humidity", value: 500, source: .weatherAPI)
        let mislabeled = HealthEvent(timestamp: Date(timeIntervalSince1970: 0), timezoneID: "UTC",
                                     category: .symptom, subtype: "airQuality", value: 300, source: .manual)
        #expect(AirQualityExposureSource().occurrences(from: [humidity, mislabeled]).isEmpty)   // subtype + category guards
    }
```

- [ ] **Step 2: Run to confirm failure.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → FAIL (`.poorAirDay`/`AirQualityExposureSource`/`airQualityAQI` undefined).

- [ ] **Step 3: The reading + factory event.** In `EnvironmentalEventFactory.swift`:
  - Add `public let airQualityAQI: Int?` to `EnvironmentalReading`; add `airQualityAQI: Int? = nil` to the init (defaulted) + assignment.
  - In `events(for:)`, after the humidity block: `if let aqi = r.airQualityAQI { events.append(event("airQuality", value: Double(aqi))) }`.

- [ ] **Step 4: EventDisplay.** In `EventDisplay.swift`: add `"airQuality": "Air quality"` to the `titles` map (environment section). At the TOP of `valueLine(for:)` (before the metadata env branch), add:

```swift
        if event.category == .environment, event.subtype == "airQuality", let v = event.value {
            return "\(Int(v)) · \(AirQualityIndex.category(aqi: Int(v)).name)"
        }
```

- [ ] **Step 5: Canonical order.** In `EnvironmentDaySummary.swift`, `EnvironmentDaySummaryBuilder.subtypeOrder`: insert `"airQuality"` after `"humidity"` → `["temperature", "humidity", "airQuality", "pressure", "pressureDrop", "moonPhase", "season", "mercuryRetrograde"]`.

- [ ] **Step 6: The exposure + wiring.**
  - `ExposureModel.swift`, `DerivedExposureKind`: append `poorAirDay` to the case list.
  - Create `AirQualityExposureSource.swift`:

```swift
import Foundation

/// Poor-air-day exposures. The factory emits a daily `airQuality` event whose value
/// is the US EPA AQI; a day at or above the "Unhealthy for Sensitive Groups"
/// threshold (AQI ≥ 101) is a `poorAirDay`. Absolute health threshold — no
/// percentile, no min-readings guard.
public struct AirQualityExposureSource: ExposureSource {
    public init() {}
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .environment, e.subtype == "airQuality",
                  let aqi = e.value, Int(aqi) >= AirQualityIndex.poorAirThreshold else { return nil }
            return ExposureOccurrence(key: .derived(.poorAirDay), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
```

  - `EvidenceEngine.swift:40-41` — register `AirQualityExposureSource()` in the `sources` array (no `config:` arg).
  - `EdgeIdentity.swift` `.derived` switch: `case .poorAirDay: return "derived:poorAirDay"`. `parseFrom` `derived:` switch: `case "poorAirDay": return .derived(.poorAirDay)`.
  - `EvidenceConfig.swift:84` — extend the weather arm → `case .hotDay, .coldDay, .humidDay, .swingDay, .poorAirDay: return outsideFactorLagHours`.
  - `InsightPhrasing.swift` `derivedExposureLabel`: `case "poorAirDay": return "Poor air quality"`.
  - `PlausibilityCatalog` — NO change (established default); the test in Step 1 pins it.

- [ ] **Step 7: Run the core suite.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → all green. Report counts.

- [ ] **Step 8: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift \
        HealthGraphCore/Sources/HealthGraphCore/Timeline/EventDisplay.swift \
        HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/AirQualityExposureSource.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EdgeIdentity.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPhrasing.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/
git commit -m "feat(core): airQuality event + poorAirDay exposure (AQI>=101, established) + wiring"
```

---

### Task 3: App — air-quality ingestion

**Files:**
- Modify: `APIConfig.swift` (`airPollutionURL`)
- Modify: `EnvironmentalDataService.swift` (`AirPollutionResponse`, `meanPM25`, `fetchAirQuality`, `@Published forecastAQI`, call in `fetchAllData`)
- Modify: `Models/EnvironmentalEventEmitter.swift` (thread `forecastAQI`)
- Test: `Food IntolerancesTests/AirQualityIngestionTests.swift`

**Interfaces:** Consumes `AirQualityIndex` (Task 1) + the reading field (Task 2). Populates real daily AQI going forward.

- [ ] **Step 1: Write the failing test first** in `AirQualityIngestionTests.swift`:

```swift
import Testing
import Foundation
@testable import Food_Intolerances

struct AirQualityIngestionTests {
    @Test func meanPM25AveragesInWindowAndExcludesOutside() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let t = now.timeIntervalSince1970
        // 3 in-window slots average 10; the out-of-window 100s must NOT move the mean.
        let slots: [(dt: TimeInterval, pm25: Double)] = [
            (t, 10), (t + 3600, 10), (t + 86_400, 10),   // dt == now and dt == now+24h are INCLUSIVE
            (t - 1, 100), (t + 86_401, 100),             // just outside both boundaries → excluded
        ]
        #expect(EnvironmentalDataService.meanPM25(slots: slots, now: now) == 10)
    }
    @Test func meanPM25NilBelowThreeInWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let t = now.timeIntervalSince1970
        #expect(EnvironmentalDataService.meanPM25(slots: [(t, 10), (t + 3600, 20)], now: now) == nil)   // only 2 → nil
    }
}
```

- [ ] **Step 2: Run to confirm failure.** App test build → FAIL (`meanPM25` unresolved).

- [ ] **Step 3: `airPollutionURL`.** In `APIConfig.swift`, mirror `forecastURL`: `static func airPollutionURL(latitude:longitude:) -> URL?` → `"\(openWeatherBaseURL)/air_pollution/forecast?lat=\(latitude)&lon=\(longitude)&appid=\(apiKey)"` (no `units`).

- [ ] **Step 4: Fetch + aggregate.** In `EnvironmentalDataService.swift`:
  - **Add `import HealthGraphCore`** at the top — the file currently imports only Foundation/CoreLocation/Combine/SwiftUI/UIKit and has NO `HealthGraphCore` reference, so `AirQualityIndex.epaAQI(...)` below would fail to compile without it.
  - Add the decode model: `struct AirPollutionResponse: Codable { struct Slot: Codable { struct Components: Codable { let pm2_5: Double }; let dt: TimeInterval; let components: Components }; let list: [Slot] }`.
  - Add a **pure static** `meanPM25(slots: [(dt: TimeInterval, pm25: Double)], now: Date) -> Double?` — filter `dt ∈ [now.timeIntervalSince1970, +86_400]`, require `≥ 3`, return the mean (mirrors `aggregate24h`).
  - Add `@Published var forecastAQI: Int? = nil`.
  - Add `func fetchAirQuality() async` mirroring `fetchDailyForecast` EXACTLY (same location resolution, same "extract scalar before `MainActor.run`" pattern): GET `APIConfig.airPollutionURL`, decode `AirPollutionResponse`, map to `(dt, pm25)` slots, `meanPM25(...)`, then `let aqi = mean.map { AirQualityIndex.epaAQI(pm25: $0) }`, and set `self.forecastAQI = aqi` inside `MainActor.run` (nil on failure/<3). Call `await fetchAirQuality()` from `fetchAllData()` alongside `fetchDailyForecast()`.

- [ ] **Step 5: Thread into the reading.** In `EnvironmentalEventEmitter.emitIfNeeded`, add `airQualityAQI: service.forecastAQI` to the `EnvironmentalReading(...)` init. (`backfillDerived` leaves it nil.)

- [ ] **Step 6: Build + regression.**
  - App build succeeds; `xcodebuild test … -only-testing:"Food IntolerancesTests/AirQualityIngestionTests" … -parallel-testing-enabled NO` green.
  - Core still green: `cd HealthGraphCore && swift test 2>&1 | tail -3`.

- [ ] **Step 7: Commit.**

```bash
git add "APIConfig.swift" "EnvironmentalDataService.swift" "Models/EnvironmentalEventEmitter.swift" \
        "Food IntolerancesTests/AirQualityIngestionTests.swift"
git commit -m "feat(app): air-quality ingestion — /air_pollution next-24h mean PM2.5 → EPA AQI"
```

---

### Task 4: App — display, Insights icon, debug seed, e2e

**Files:**
- Modify: `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift` (headline lead)
- Modify: `Views/HealthOS/Insights/InsightsViewModel.swift` (icon)
- Modify: `Views/HealthGraphDebugView.swift` (seed poor-air days)
- Test: `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift`, `Food IntolerancesTests/InsightsViewModelTests.swift`

- [ ] **Step 1: Write the failing tests first.**
  - `EnvironmentSummaryFormatterTests` — reuse the shipped in-file helpers (`day`, `temp`, `humidity`, `ev`, `c`) and add `airQuality(_:)`. The temp literal uses a U+2013 EN DASH; the AQI/`· Good` literals use a U+00B7 MIDDLE DOT — byte-identical to the impl.

```swift
    private func airQuality(_ aqi: Double) -> HealthEvent { ev("airQuality", value: aqi) }

    @Test func poorAirDayLeadsHeadlineOverTemperature() {
        // temperature IS present → proves the AQI branch is FIRST (wins over temp), not merely non-empty.
        let s = day([temp(24, 12), humidity(69), airQuality(132)])
        #expect(EnvironmentSummaryFormatter.headline(s, unit: c) == "AQI 132 · Unhealthy for sensitive groups")
    }
    @Test func goodAirDoesNotLeadAndSortsAfterHumidity() {
        let s = day([temp(24, 12), humidity(69), airQuality(42)])
        #expect(EnvironmentSummaryFormatter.headline(s, unit: c) == "12–24°C · 69%")   // AQI 42 < 101 → temp still leads
        let rows = EnvironmentSummaryFormatter.detailLines(s, unit: c)
        #expect(rows.map(\.label) == ["Temperature", "Humidity", "Air quality"])       // pins the canonical position
        #expect(rows.first(where: { $0.label == "Air quality" })?.value == "42 · Good")
    }
```

  - `InsightsViewModelTests` — mirror the existing `hotDayEdgeSurfaces…`/`swingDayEdgeSurfaces…` test's edge-seeding exactly, but with the token `derived:poorAirDay → symptom`, and assert BOTH `tier == .established` (NOT contested — pins "no unproven tag") AND the card's `exposureCategory == .environment` (pins the icon fix). Both assertions must be present: without the `InsightPhrasing` + icon wiring the category falls to `.note`; a wrong tier classification would misfire the tag.

- [ ] **Step 2: Run to confirm failure.** App test build → FAIL (headline still leads with temp; poorAirDay icon `.note`).

- [ ] **Step 3: Headline lead.** In `EnvironmentSummaryFormatter.headline`, add as the FIRST branch:

```swift
        // Poor-air days lead with the AQI — the most health-salient signal that day.
        if let aq = summary.events.first(where: { $0.subtype == "airQuality" }),
           let v = aq.value, Int(v) >= AirQualityIndex.poorAirThreshold {
            return "AQI \(Int(v)) · \(AirQualityIndex.category(aqi: Int(v)).name)"
        }
```

  (The `detailLines` "Air quality" row is automatic — the event sorts via `subtypeOrder` and renders via `EventDisplay` through the existing `default` branch; no `detailLines` change.)

- [ ] **Step 4: Insights icon.** In `InsightsViewModel.swift:72`, add `|| fc == "poorAirDay"` to the `.environment` OR-chain.

- [ ] **Step 5: Debug seed.** In `HealthGraphDebugView.swift` `loadWeatherDemo`, emit a daily `airQuality` event (value = EPA AQI from a synthetic PM2.5 series where ~20% of days land ≥ 101), and correlate a symptom (~80% on poor-air days, ~4% baseline) so an established "Poor air quality → …" card surfaces. In the full-env enrichment block (the last-3-days loop), give the most recent day an `airQuality` value ≥ 101 so the Environment row shows the "Air quality" line AND the headline leads with `AQI …`.

- [ ] **Step 6: Build + full regression.** App build; core `swift test` green; full app suite green modulo the known `SwiftDataMigratorTests` crash (incl. the new formatter + VM tests).

- [ ] **Step 7: On-device / simulator check** (device preferred; human's gate). Reset → Load WEATHER demo →:
  - The Environment row shows an **"Air quality"** detail line (e.g. `132 · Unhealthy for sensitive groups`).
  - A **poor-air day leads the collapsed headline** with `AQI 132 · Unhealthy for sensitive groups`; a good-air day still leads with the temperature.
  - **Insights** shows an **established** "Poor air quality → …" card — **no** "unproven mechanism · your pattern" tag, environment icon.
  - Light + dark.

- [ ] **Step 8: Commit.**

```bash
git add "Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift" \
        "Views/HealthOS/Insights/InsightsViewModel.swift" "Views/HealthGraphDebugView.swift" \
        "Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift" \
        "Food IntolerancesTests/InsightsViewModelTests.swift"
git commit -m "feat(app): air quality in the Environment row (headline lead on poor-air days) + established Insights card"
```

---

## Definition of Done

- Air quality (EPA AQI from the day's mean PM2.5) is ingested daily, mined as an **established** `poorAirDay` (AQI ≥ 101) exposure, and correlated with outcomes by the existing engine.
- It folds into the Environment Timeline row (an "Air quality" line always; leads the collapsed headline on a poor-air day) and shows in Insights as an established card (no unproven tag).
- Core AQI math + the exposure + wiring unit-tested; the PM2.5 aggregation + formatter headline + Insights tier tested; the app wired + device-verified.
- No change to the evidence gates, the tier framework, percentile machinery, weather/moon/mercury exposures, or the units picker. Pollen and proactive warnings remain future rounds.
