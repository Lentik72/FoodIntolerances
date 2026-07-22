# Observed-Weather Mining Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ingest observed completed-day temperature/humidity via One Call 3.0 `day_summary` (stamped `.observedCompletedDay`) so the existing fail-closed weather sources resume mining, and make observed values win over forecast in display for completed days — per `docs/superpowers/specs/2026-07-22-observed-weather-mining-design.md`.

**Architecture:** Four pieces, mirroring proven templates. (1) The factory gains `weatherProvenance: TemporalProvenance = .forecast` so the observed backfill can stamp temp/humidity mineable — every existing call site untouched by the default. (2) A core precedence helper `EnvironmentDaySummaryBuilder.observedPrecedenceFiltered(_:timeZone:)` drops a day+subtype's forecast events when an observed sibling exists (deterministic winner), applied at both display choke points (the hide-season architecture). (3) `EnvironmentalDataService` gains a per-day `day_summary` fetch (`WeatherDayResult`), same key/location/transport seams as the AQI history fetch. (4) The emitter's AQI backfill is extracted into a private function and a parallel observed-weather backfill is added (own watermark/throttle, same cap/grace policy, per-day calls). Mining needs zero changes.

**Tech Stack:** Swift / SwiftUI app + HealthGraphCore local SwiftPM package (GRDB). Swift Testing in both suites. OpenWeather One Call 3.0 `day_summary` (requires the account subscription; app degrades gracefully without it).

## Global Constraints

- **Mining sources untouched** — `TemperatureExposureSource`/`HumidityExposureSource` change zero lines; they already require `.observedCompletedDay`.
- **Presentation precedence only, never deletion** — stored forecast events remain intact; no migration.
- **Precedence granularity:** independent per `day + subtype` (an observed temperature suppresses ONLY that day's forecast temperature, never humidity or another day); deterministic among duplicate observed events (latest `createdAt`, then `id.uuidString`).
- **Observed humidity = `humidity.afternoon`** (documented semantics); **missing afternoon humidity → NO observed humidity event** (that day's forecast humidity stays visible, the day is unmined for humidity); never numerically combined with the forecast aggregate.
- **Graceful degradation:** a One Call auth failure (401 body → decode failure) behaves exactly like `.fetchError` — retry-throttled, no events, forecast display unaffected.
- **On a per-day `.fetchError`, the backfill pass aborts entirely: nothing ingested, watermark held** (spec §3B literal; dedup makes the eventual re-fetch idempotent).
- Watermark keys: `hg.env.lastWeatherDay` / `hg.env.lastWeatherAttempt`; cap/grace reuse `maxBackfillDays` (30) / `gracePartialDays` (2); throttle constant `minWeatherRetryInterval` = 3600.
- App tests MUST run with `-parallel-testing-enabled NO` ("green modulo the known `SwiftDataMigratorTests` teardown crash" is the accepted bar for the FULL suite only; targeted runs fully succeed). Destination: `platform=iOS Simulator,name=iPhone 17 Pro`. Core tests: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test`.
- Commits: conventional-commit style, trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Working directory: `/Users/leo/dev/FoodIntolerances` (paths below relative to it).

---

### Task 1: Factory — `weatherProvenance` on `EnvironmentalReading`

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift:4-31,81-88`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces (Task 4 relies on this): `EnvironmentalReading.init(..., weatherProvenance: TemporalProvenance = .forecast)` — a new last-position defaulted parameter; the factory stamps the `temperature` and `humidity` events with `r.weatherProvenance` instead of hardcoded `.forecast`.

- [ ] **Step 1: Write the failing tests**

In `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift`, add at the end of the struct:

```swift
    // weatherProvenance: default keeps forecast; the observed backfill stamps mineable.
    @Test func observedWeatherProvenanceStampsTempAndHumidity() throws {
        let r = EnvironmentalReading(date: Date(timeIntervalSince1970: 1_700_000_000),
            pressureHPa: nil, previousPressureHPa: nil, moonPhaseName: nil,
            isMercuryRetrograde: false, timezoneID: "UTC",
            temperatureHighC: 24, temperatureLowC: 12, humidityPct: 64,
            weatherProvenance: .observedCompletedDay)
        let events = EnvironmentalEventFactory.events(for: r)
        #expect(events.first { $0.subtype == "temperature" }?.temporalProvenance == .observedCompletedDay)
        #expect(events.first { $0.subtype == "humidity" }?.temporalProvenance == .observedCompletedDay)
        // Provenance scopes the dedup key → observed and forecast same-day coexist.
        let observedKey = try #require(events.first { $0.subtype == "temperature" }?.dedupKey)
        let forecastKey = try #require(EnvironmentalEventFactory.events(for: EnvironmentalReading(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            pressureHPa: nil, previousPressureHPa: nil, moonPhaseName: nil,
            isMercuryRetrograde: false, timezoneID: "UTC",
            temperatureHighC: 24, temperatureLowC: 12)).first { $0.subtype == "temperature" }?.dedupKey)
        #expect(observedKey != forecastKey)
    }
    @Test func observedReadingWithNilHumidityEmitsNoHumidityEvent() {
        let r = EnvironmentalReading(date: Date(timeIntervalSince1970: 1_700_000_000),
            pressureHPa: nil, previousPressureHPa: nil, moonPhaseName: nil,
            isMercuryRetrograde: false, timezoneID: "UTC",
            temperatureHighC: 24, temperatureLowC: 12, humidityPct: nil,
            weatherProvenance: .observedCompletedDay)
        let events = EnvironmentalEventFactory.events(for: r)
        #expect(events.contains { $0.subtype == "temperature" })
        #expect(!events.contains { $0.subtype == "humidity" })   // missing afternoon humidity → no observed event
    }
```

(The existing `stampsPerSignalProvenanceOnEveryEvent` test already pins the default `.forecast` behavior — leave it untouched; it must keep passing.)

- [ ] **Step 2: Run to verify they fail to compile**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test --filter EnvironmentalEventFactoryTests 2>&1 | tail -8`
Expected: BUILD FAILS — `extra argument 'weatherProvenance' in call`.

- [ ] **Step 3: Implement**

In `HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift`:

Add the stored property after `airQualityAQI` (line 14) and the init parameter/assignment:

```swift
public struct EnvironmentalReading: Sendable {
    public let date: Date
    public let pressureHPa: Double?
    public let previousPressureHPa: Double?
    public let moonPhaseName: String?
    public let isMercuryRetrograde: Bool
    public let timezoneID: String
    public let temperatureHighC: Double?
    public let temperatureLowC: Double?
    public let humidityPct: Double?
    public let airQualityAQI: Int?
    /// Provenance stamped on the temperature/humidity events. `.forecast` (the
    /// default) is today's forward-looking reading — display only, never mined.
    /// The observed backfill passes `.observedCompletedDay` for completed days'
    /// measured values — mineable by the fail-closed weather sources.
    public let weatherProvenance: TemporalProvenance

    public init(date: Date, pressureHPa: Double?, previousPressureHPa: Double?,
                moonPhaseName: String?,
                isMercuryRetrograde: Bool, timezoneID: String,
                temperatureHighC: Double? = nil, temperatureLowC: Double? = nil, humidityPct: Double? = nil,
                airQualityAQI: Int? = nil,
                weatherProvenance: TemporalProvenance = .forecast) {
        self.date = date
        self.pressureHPa = pressureHPa
        self.previousPressureHPa = previousPressureHPa
        self.moonPhaseName = moonPhaseName
        self.isMercuryRetrograde = isMercuryRetrograde
        self.timezoneID = timezoneID
        self.temperatureHighC = temperatureHighC
        self.temperatureLowC = temperatureLowC
        self.humidityPct = humidityPct
        self.airQualityAQI = airQualityAQI
        self.weatherProvenance = weatherProvenance
    }
}
```

And replace the temperature/humidity blocks (lines 81-88):

```swift
        if let high = r.temperatureHighC, let low = r.temperatureLowC {
            // Forecast weather is display/warnings only; the observed backfill
            // passes .observedCompletedDay → mineable (fail-closed sources).
            events.append(event("temperature", value: high, unit: "°C", metadata: ["low": String(low)],
                                provenance: r.weatherProvenance))
        }
        if let humidity = r.humidityPct {
            events.append(event("humidity", value: humidity, unit: "%", provenance: r.weatherProvenance))
        }
```

- [ ] **Step 4: Run to verify green**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: PASS, full core suite (the defaulted parameter leaves every existing call site compiling and behaving identically).

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift
git commit -m "feat(core): EnvironmentalReading.weatherProvenance — observed backfill can stamp temp/humidity mineable (default .forecast unchanged)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Core display precedence — observed wins per day+subtype at both choke points

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift:22-53`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift:77-83`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentDaySummaryBuilderTests.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift`

**Interfaces:**
- Consumes: `HealthEvent.temporalProvenance` (existing metadata accessor), `retiredSubtypes` precedent.
- Produces: `public static func observedPrecedenceFiltered(_ events: [HealthEvent], timeZone: TimeZone) -> [HealthEvent]` and `static let observedPrecedenceSubtypes: Set<String> = ["temperature", "humidity"]` on `EnvironmentDaySummaryBuilder`. Applied inside `summaries(from:timeZone:)` and inside `TimelineDayBuilder.days`.

- [ ] **Step 1: Write the failing builder tests**

In `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentDaySummaryBuilderTests.swift`, add a provenance-aware helper below the existing `env(_:_:)` helper, and the new tests at the end of the struct:

```swift
    private func weather(_ subtype: String, day: Int, provenance: TemporalProvenance,
                         created: TimeInterval = 0, id: UUID = UUID()) -> HealthEvent {
        HealthEvent(id: id,
                    timestamp: Date(timeIntervalSince1970: Double(day) * 86_400 + 43_200),
                    timezoneID: "UTC", category: .environment, subtype: subtype,
                    value: 20, source: .weatherAPI,
                    metadata: try! JSONEncoder().encode(["provenance": provenance.rawValue]),
                    createdAt: Date(timeIntervalSince1970: created))
    }

    // Observed-wins display precedence (presentation-only; per day + subtype).
    @Test func observedSuppressesSameDaySameSubtypeForecastOnly() {
        let events = [weather("temperature", day: 0, provenance: .forecast),
                      weather("temperature", day: 0, provenance: .observedCompletedDay),
                      weather("humidity", day: 0, provenance: .forecast),          // no observed sibling → stays
                      weather("temperature", day: 1, provenance: .forecast)]       // other day → stays
        let s = EnvironmentDaySummaryBuilder.summaries(from: events, timeZone: tz)
        #expect(s.count == 2)
        let day0 = s.first { $0.dayStart == Date(timeIntervalSince1970: 0) }!
        #expect(day0.events.filter { $0.subtype == "temperature" }.count == 1)
        #expect(day0.events.first { $0.subtype == "temperature" }?.temporalProvenance == .observedCompletedDay)
        #expect(day0.events.contains { $0.subtype == "humidity" })                 // mixed availability: one of each
        let day1 = s.first { $0.dayStart == Date(timeIntervalSince1970: 86_400) }!
        #expect(day1.events.first { $0.subtype == "temperature" }?.temporalProvenance == .forecast)
    }
    @Test func duplicateObservedResolvesDeterministicallyByCreatedAt() {
        let older = weather("temperature", day: 0, provenance: .observedCompletedDay, created: 100)
        let newer = weather("temperature", day: 0, provenance: .observedCompletedDay, created: 200)
        for input in [[older, newer], [newer, older]] {   // input order must not matter
            let s = EnvironmentDaySummaryBuilder.summaries(from: input, timeZone: tz)
            #expect(s[0].events.map(\.id) == [newer.id])
        }
    }
    /// Secondary tie-break: identical createdAt → the documented winner is the
    /// larger id.uuidString, regardless of input order.
    @Test func duplicateObservedWithEqualCreatedAtTieBreaksOnUUIDString() {
        let low = weather("temperature", day: 0, provenance: .observedCompletedDay, created: 100,
                          id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let high = weather("temperature", day: 0, provenance: .observedCompletedDay, created: 100,
                           id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        for input in [[low, high], [high, low]] {
            let s = EnvironmentDaySummaryBuilder.summaries(from: input, timeZone: tz)
            #expect(s[0].events.map(\.id) == [high.id])
        }
    }
    /// Only forecast + duplicate observed are dropped — .currentSnapshot and
    /// provenance-less events of the same day+subtype pass through untouched.
    @Test func precedenceDropsOnlyForecastAndDuplicateObserved() {
        let observed = weather("temperature", day: 0, provenance: .observedCompletedDay)
        let forecast = weather("temperature", day: 0, provenance: .forecast)
        let snapshot = weather("temperature", day: 0, provenance: .currentSnapshot)
        let unflagged = HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200),
                                    timezoneID: "UTC", category: .environment, subtype: "temperature",
                                    value: 20, source: .weatherAPI)   // no provenance metadata at all
        let s = EnvironmentDaySummaryBuilder.summaries(from: [observed, forecast, snapshot, unflagged], timeZone: tz)
        let ids = Set(s[0].events.map(\.id))
        #expect(ids == Set([observed.id, snapshot.id, unflagged.id]))   // forecast gone; others preserved
    }
    @Test func forecastOnlyDayAndNonWeatherSubtypesPassThrough() {
        let events = [weather("temperature", day: 0, provenance: .forecast),
                      weather("humidity", day: 0, provenance: .forecast),
                      env("moonPhase", 0), env("pressure", 0)]
        let s = EnvironmentDaySummaryBuilder.summaries(from: events, timeZone: tz)
        #expect(s[0].events.count == 4)   // nothing dropped without an observed sibling
    }
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test --filter EnvironmentDaySummaryBuilderTests 2>&1 | tail -8`
Expected: FAIL — `observedSuppressesSameDaySameSubtypeForecastOnly`, `duplicateObservedResolvesDeterministicallyByCreatedAt`, `duplicateObservedWithEqualCreatedAtTieBreaksOnUUIDString`, and `precedenceDropsOnlyForecastAndDuplicateObserved` (nothing is filtered yet). `forecastOnlyDayAndNonWeatherSubtypesPassThrough` PASSES already.

- [ ] **Step 3: Implement the helper and apply it in `summaries`**

In `HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift`, add after `retiredSubtypes` (line 31):

```swift
    /// Weather subtypes where an observed completed-day reading supersedes the
    /// morning forecast IN DISPLAY for the same local day ("observed wins").
    static let observedPrecedenceSubtypes: Set<String> = ["temperature", "humidity"]

    /// Presentation-only precedence: per local day + subtype, when at least one
    /// `.observedCompletedDay` event exists, that day+subtype's `.forecast` events
    /// are dropped and duplicate observed events resolve deterministically (latest
    /// `createdAt`, then `id.uuidString`). ONLY those two drops are licensed —
    /// any other or missing provenance passes through untouched. Resolved
    /// independently per day+subtype — an observed temperature never suppresses
    /// humidity or another day. Stored events are untouched; mining reads the
    /// store, not this filter.
    public static func observedPrecedenceFiltered(_ events: [HealthEvent], timeZone: TimeZone) -> [HealthEvent] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        struct Key: Hashable { let day: Date; let subtype: String }
        var winner: [Key: HealthEvent] = [:]
        for e in events where e.category == .environment
            && observedPrecedenceSubtypes.contains(e.subtype ?? "")
            && e.temporalProvenance == .observedCompletedDay {
            let key = Key(day: calendar.startOfDay(for: e.timestamp), subtype: e.subtype ?? "")
            if let cur = winner[key] {
                if (e.createdAt, e.id.uuidString) > (cur.createdAt, cur.id.uuidString) { winner[key] = e }
            } else {
                winner[key] = e
            }
        }
        guard !winner.isEmpty else { return events }
        return events.filter { e in
            guard e.category == .environment,
                  let subtype = e.subtype, observedPrecedenceSubtypes.contains(subtype),
                  let w = winner[Key(day: calendar.startOfDay(for: e.timestamp), subtype: subtype)]
            else { return true }               // not a precedence subtype, or no observed that day → untouched
            switch e.temporalProvenance {
            case .forecast?:             return false          // superseded by the observed sibling
            case .observedCompletedDay?: return e.id == w.id   // deterministic winner among observed
            default:                     return true           // .currentSnapshot / nil / future kinds: not ours to drop
            }
        }
    }
```

And in `summaries(from:timeZone:)`, replace the env filter (lines 40-41):

```swift
        let env = observedPrecedenceFiltered(events, timeZone: timeZone)
            .filter { $0.category == .environment
                && !retiredSubtypes.contains($0.subtype ?? "") }
```

- [ ] **Step 4: Run core tests to verify green**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: PASS (full core suite — existing builder tests use single-provenance fixtures and are unaffected).

- [ ] **Step 5: Write the failing raw-mode test**

In `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift`, add after `rawModeFiltersRetiredEnvironmentSubtypes`:

```swift
    /// Observed-wins precedence applies in RAW mode too — the filter lives in
    /// days(), so search can never show a completed day's forecast next to its actuals.
    @Test func rawModeAppliesObservedPrecedence() {
        let tz = TimeZone(identifier: "UTC")!
        func weather(_ provenance: TemporalProvenance) -> HealthEvent {
            HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200), timezoneID: "UTC",
                        category: .environment, subtype: "temperature", value: 20, source: .weatherAPI,
                        metadata: try! JSONEncoder().encode(["provenance": provenance.rawValue]))
        }
        let days = TimelineDayBuilder.days(from: [weather(.forecast), weather(.observedCompletedDay)], timeZone: tz,
                                           sessionizeSleep: false, groupEnvironment: false)
        let temps = days.flatMap(\.events).filter { $0.subtype == "temperature" }
        #expect(temps.count == 1)
        #expect(temps.first?.temporalProvenance == .observedCompletedDay)
    }
```

- [ ] **Step 6: Run to verify it fails**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test --filter TimelineDayBuilderTests 2>&1 | tail -8`
Expected: FAIL — both temperature rows present in raw mode.

- [ ] **Step 7: Apply the helper in `TimelineDayBuilder.days`**

In `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift`, replace the `visibleEvents` block (lines 77-83):

```swift
        // Stored rows of retired env subtypes (season) must never display, in ANY
        // mode — raw/search rows included — and a completed day's forecast weather
        // is superseded by its observed sibling ("observed wins", presentation
        // only). Filtered here so no caller can leak them; the summary builder
        // re-filters for its own public callers.
        let visibleEvents = EnvironmentDaySummaryBuilder.observedPrecedenceFiltered(
            events.filter {
                !($0.category == .environment &&
                  EnvironmentDaySummaryBuilder.retiredSubtypes.contains($0.subtype ?? ""))
            },
            timeZone: timeZone)
```

- [ ] **Step 8: Run core tests to verify green**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: PASS (full core suite).

- [ ] **Step 9: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift \
        HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentDaySummaryBuilderTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift
git commit -m "feat(core): observed-wins display precedence — per day+subtype, deterministic, at both display choke points

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Service — One Call `day_summary` fetch (`WeatherDayResult`)

**Files:**
- Modify: `APIConfig.swift` (append after `airPollutionHistoryURL`)
- Modify: `EnvironmentalDataService.swift` (result type near `AQIRangeResult` ~line 21; fetch + response model near `fetchCompletedAirQualityRange` ~line 485)
- Test (create): `Food IntolerancesTests/WeatherHistoryTests.swift`

**Interfaces:**
- Consumes: existing seams — `HTTPTransport`, `resolvedCoordinate()`, injected `calendar`, `APIConfig.openWeatherAPIKey`.
- Produces (Task 4 relies on these exact names): `enum WeatherDayResult: Equatable { case fetchError; case absent; case value(highC: Double, lowC: Double, humidityPct: Double?) }` and `func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult` on `EnvironmentalDataService`; `APIConfig.oneCallDaySummaryURL(latitude:longitude:date:)`.

- [ ] **Step 1: Write the failing tests**

Create `Food IntolerancesTests/WeatherHistoryTests.swift` (transport/location stub idiom copied from `AirQualityHistoryTests.swift:109-136`):

```swift
import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

/// One Call 3.0 day_summary fetch: URL shape, decode (incl. optional afternoon
/// humidity), absence vs fetch-error discipline, and auth-failure degradation.
struct WeatherHistoryTests {

    private struct StubTransport: HTTPTransport {
        let payload: Data
        let makeError: Bool
        let requestedURLs: URLBox
        init(payload: Data, makeError: Bool = false, requestedURLs: URLBox = URLBox()) {
            self.payload = payload
            self.makeError = makeError
            self.requestedURLs = requestedURLs
        }
        final class URLBox: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var urls: [URL] = []
            func append(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        }
        func data(from url: URL) async throws -> (Data, URLResponse) {
            requestedURLs.append(url)
            struct StubError: Error {}
            if makeError { throw StubError() }
            let response = URLResponse(url: url, mimeType: "application/json",
                                        expectedContentLength: payload.count, textEncodingName: "utf-8")
            return (payload, response)
        }
    }
    private struct StubLocation: LocationProviding {
        let coordinate: CLLocationCoordinate2D?
    }
    private func ensureTestAPIKeyConfigured() { setenv("OPENWEATHER_API_KEY", "test-key", 1) }
    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func makeService(payload: Data, makeError: Bool = false) -> EnvironmentalDataService {
        ensureTestAPIKeyConfigured()
        return EnvironmentalDataService(
            transport: StubTransport(payload: payload, makeError: makeError),
            calendar: utcCalendar,
            location: StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)))
    }
    private let day = Date(timeIntervalSince1970: 1_750_000_000)   // 2025-06-15 UTC

    // MARK: - URL builder

    @Test func daySummaryURLUsesOneCallBaseDateAndEncodedTZ() throws {
        ensureTestAPIKeyConfigured()
        let url = try #require(APIConfig.oneCallDaySummaryURL(latitude: 40.0, longitude: -74.0,
                                                              date: "2025-06-15", tz: "+00:00"))
        let s = url.absoluteString
        #expect(s.contains("/data/3.0/onecall/day_summary"))
        #expect(s.contains("date=2025-06-15"))
        #expect(s.contains("tz=%2B00:00"))            // "+" must be percent-encoded
        #expect(s.contains("units=metric"))
        #expect(s.contains("lat=40.0") && s.contains("lon=-74.0"))
        let negative = try #require(APIConfig.oneCallDaySummaryURL(latitude: 40.0, longitude: -74.0,
                                                                   date: "2025-01-15", tz: "-08:00"))
        #expect(negative.absoluteString.contains("tz=-08:00"))   // "-" needs no encoding
    }

    // MARK: - fetchCompletedWeatherDay

    @Test func decodesHighLowAndAfternoonHumidity() async {
        let json = #"{"temperature":{"min":12.3,"max":24.6},"humidity":{"afternoon":64.0}}"#
        let result = await makeService(payload: Data(json.utf8)).fetchCompletedWeatherDay(for: day)
        #expect(result == .value(highC: 24.6, lowC: 12.3, humidityPct: 64.0))
    }
    @Test func missingAfternoonHumidityYieldsNilHumidityNotAbsent() async {
        let json = #"{"temperature":{"min":12.3,"max":24.6},"humidity":{}}"#
        let result = await makeService(payload: Data(json.utf8)).fetchCompletedWeatherDay(for: day)
        #expect(result == .value(highC: 24.6, lowC: 12.3, humidityPct: nil))
    }
    @Test func missingTemperatureIsAbsentNotError() async {
        let json = #"{"humidity":{"afternoon":64.0}}"#
        let result = await makeService(payload: Data(json.utf8)).fetchCompletedWeatherDay(for: day)
        #expect(result == .absent)
    }
    @Test func transportErrorIsFetchError() async {
        let result = await makeService(payload: Data(), makeError: true).fetchCompletedWeatherDay(for: day)
        #expect(result == .fetchError)
    }
    @Test func malformedPayloadIsFetchError() async {
        let result = await makeService(payload: Data("not json".utf8)).fetchCompletedWeatherDay(for: day)
        #expect(result == .fetchError)
    }
    /// A One Call 401 (subscription not active) returns a JSON error body — not a
    /// throw. It must decode-fail into .fetchError, never be mistaken for absence.
    @Test func authErrorBodyIsFetchError() async {
        let json = #"{"cod":401,"message":"Please note that using One Call 3.0 requires a separate subscription"}"#
        let result = await makeService(payload: Data(json.utf8)).fetchCompletedWeatherDay(for: day)
        #expect(result == .fetchError)
    }
    /// The tz offset is DATE-specific from the injected calendar: a January day
    /// in Los Angeles is PST (-08:00), a July day PDT (-07:00) — the app's
    /// calendar controls the provider's aggregation day, not the location.
    @Test func fetchPassesDateSpecificCalendarTZOffset() async throws {
        ensureTestAPIKeyConfigured()
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let box = StubTransport.URLBox()
        let json = #"{"temperature":{"min":1.0,"max":2.0},"humidity":{"afternoon":50.0}}"#
        let service = EnvironmentalDataService(
            transport: StubTransport(payload: Data(json.utf8), requestedURLs: box),
            calendar: la,
            location: StubLocation(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -118.0)))
        _ = await service.fetchCompletedWeatherDay(for: la.date(from: DateComponents(year: 2025, month: 1, day: 15))!)
        _ = await service.fetchCompletedWeatherDay(for: la.date(from: DateComponents(year: 2025, month: 7, day: 15))!)
        let urls = box.urls.map(\.absoluteString)
        #expect(urls.count == 2)
        #expect(urls[0].contains("date=2025-01-15") && urls[0].contains("tz=-08:00"))   // PST
        #expect(urls[1].contains("date=2025-07-15") && urls[1].contains("tz=-07:00"))   // PDT
    }

    @Test func noLocationIsFetchError() async {
        ensureTestAPIKeyConfigured()
        let service = EnvironmentalDataService(
            transport: StubTransport(payload: Data(), makeError: false),
            calendar: utcCalendar, location: StubLocation(coordinate: nil))
        let result = await service.fetchCompletedWeatherDay(for: day)
        #expect(result == .fetchError)
    }
}
```

- [ ] **Step 2: Run to verify they fail to compile**

Run:
```bash
cd /Users/leo/dev/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/WeatherHistoryTests" 2>&1 | tail -8
```
Expected: BUILD FAILS — `cannot find 'oneCallDaySummaryURL'` / `no member 'fetchCompletedWeatherDay'`.

- [ ] **Step 3: Implement `APIConfig` + the fetch**

Append to `APIConfig.swift` (inside the enum, after `airPollutionHistoryURL`):

```swift
    /// Base URL for OpenWeather One Call 3.0 (separate subscription; a 401 error
    /// body — not a transport failure — is what "not subscribed" looks like).
    static let openWeatherOneCallBaseURL = "https://api.openweathermap.org/data/3.0"

    /// Build a One Call day_summary URL for observed completed-day weather.
    /// `date` is a local "yyyy-MM-dd" string; `tz` is the "±HH:MM" offset that
    /// controls the provider's aggregation day (WITHOUT it, OpenWeather derives
    /// the timezone from the location — for a remote manual location that would
    /// disagree with the app's stored local day, so the caller always supplies
    /// the app calendar's date-specific offset). "+" is percent-encoded (%2B) so
    /// no query parser can read it as a space. Nil if the API key is missing.
    static func oneCallDaySummaryURL(latitude: Double, longitude: Double, date: String, tz: String) -> URL? {
        guard let apiKey = openWeatherAPIKey else {
            return nil
        }
        let encodedTZ = tz.replacingOccurrences(of: "+", with: "%2B")
        let urlString = "\(openWeatherOneCallBaseURL)/onecall/day_summary?lat=\(latitude)&lon=\(longitude)&date=\(date)&tz=\(encodedTZ)&units=metric&appid=\(apiKey)"
        return URL(string: urlString)
    }
```

In `EnvironmentalDataService.swift`, add the result type directly below `AQIRangeResult` (~line 24):

```swift
/// Result of a completed-day weather fetch (One Call day_summary): the request
/// failed (transport OR decode OR auth-error body — always retryable, never
/// conflated with absence), the provider has no temperature for the day, or the
/// day's observed values. `humidityPct` is the provider's observed AFTERNOON
/// humidity and can be missing independently of temperature (nil → the emitter
/// writes no observed humidity event for that day).
enum WeatherDayResult: Equatable {
    case fetchError
    case absent
    case value(highC: Double, lowC: Double, humidityPct: Double?)
}
```

And add the fetch + response model after `fetchCompletedAirQualityRange` (after its closing brace):

```swift
    /// One Call 3.0 day_summary decode target — only the fields this feature reads.
    private struct DaySummaryResponse: Decodable {
        struct Temperature: Decodable { let min: Double?; let max: Double? }
        struct Humidity: Decodable { let afternoon: Double? }
        let temperature: Temperature?
        let humidity: Humidity?
    }

    /// GETs One Call day_summary for ONE completed local day. Same location
    /// resolution as every other fetch. A 401 "requires a separate subscription"
    /// body has no `temperature` field and fails decode-shape checks → treated as
    /// `.fetchError` (graceful degradation; the emitter's throttle paces retries).
    func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult {
        guard let location = self.resolvedCoordinate() else {
            Logger.warning("No location available for weather day fetch.", category: .location)
            return .fetchError
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        // The app's calendar timezone is authoritative for the aggregation day —
        // date-SPECIFIC offset (DST changes it across the backfill window).
        let seconds = calendar.timeZone.secondsFromGMT(for: day)
        let tzOffset = String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+",
                              abs(seconds) / 3600, (abs(seconds) % 3600) / 60)
        guard let url = APIConfig.oneCallDaySummaryURL(
            latitude: location.latitude, longitude: location.longitude,
            date: formatter.string(from: day), tz: tzOffset) else {
            Logger.error("Invalid URL for One Call day_summary API", category: .network)
            return .fetchError
        }
        do {
            let (data, _) = try await transport.data(from: url)
            let decoded = try JSONDecoder().decode(DaySummaryResponse.self, from: data)
            guard let high = decoded.temperature?.max, let low = decoded.temperature?.min else {
                // An auth/error body decodes to an empty shell (no temperature) —
                // but so could a legitimate no-data day. Distinguish: an error body
                // always carries "message"; treat that as fetchError, else absent.
                if (try? JSONDecoder().decode(OneCallErrorBody.self, from: data)) != nil {
                    return .fetchError
                }
                return .absent
            }
            return .value(highC: high, lowC: low, humidityPct: decoded.humidity?.afternoon)
        } catch {
            return .fetchError
        }
    }

    /// One Call error envelope — a "message" field marks an API error body (401
    /// not-subscribed, 404 bad date, …), which must be retryable, not absent.
    /// (Keyed on "message" alone: OpenWeather's "cod" is inconsistently typed —
    /// Int on some endpoints, String on others.)
    private struct OneCallErrorBody: Decodable {
        let message: String
    }
```

- [ ] **Step 4: Run to verify green**

Run: the same command as Step 2.
Expected: `** TEST SUCCEEDED **` — all 9 `@Test` cases pass.

- [ ] **Step 5: Commit**

```bash
git add APIConfig.swift EnvironmentalDataService.swift "Food IntolerancesTests/WeatherHistoryTests.swift"
git commit -m "feat(app): One Call day_summary fetch — WeatherDayResult with afternoon-humidity + auth-body/absence discipline

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Emitter — observed-weather backfill (+ full verification)

The emitter's AQI backfill section ends in early `return`s, so appending a weather section after it would be silently skipped. Extract the AQI block VERBATIM into a private function, add the parallel weather backfill, and call both from `emitIfNeeded`.

**Files:**
- Modify: `Models/EnvironmentalEventEmitter.swift:7-15` (protocol), `:49-65` (keys/constants), `:105-160` (extraction + new backfill)
- Test: `Food IntolerancesTests/EnvironmentalEmitterTests.swift` (StubProvider + new tests)

**Interfaces:**
- Consumes: `WeatherDayResult` + `fetchCompletedWeatherDay(for:)` (Task 3); `EnvironmentalReading(..., weatherProvenance: .observedCompletedDay)` (Task 1).
- Produces: `EnvironmentalDataProviding` gains `func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult` (conformers: the real service — already satisfied by Task 3 — and the test stub). New emitter members: `lastWeatherDayKey = "hg.env.lastWeatherDay"`, `lastWeatherAttemptKey = "hg.env.lastWeatherAttempt"`, `minWeatherRetryInterval: TimeInterval = 3600`.

- [ ] **Step 1: Add the protocol requirement + stub support (compile-first)**

In `Models/EnvironmentalEventEmitter.swift`, add to `EnvironmentalDataProviding` (after the AQI requirement, line 14):

```swift
    func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult
```

(`extension EnvironmentalDataService: EnvironmentalDataProviding {}` is already satisfied by Task 3.)

In `Food IntolerancesTests/EnvironmentalEmitterTests.swift`, extend `StubProvider` (after the AQI members, lines 29-45):

```swift
        /// Scripted per-day weather; days not listed return `weatherDefault`.
        /// Default `.fetchError` keeps every pre-existing AQI/orchestration test
        /// meaningful unchanged: the weather pass aborts, emits nothing.
        var weatherByDay: [Date: WeatherDayResult] = [:]
        var weatherDefault: WeatherDayResult = .fetchError
        private(set) var weatherCallCount = 0
        private(set) var weatherDaysRequested: [Date] = []

        func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult {
            weatherCallCount += 1
            weatherDaysRequested.append(day)
            return weatherByDay[day] ?? weatherDefault
        }
```

- [ ] **Step 2: Run the existing emitter tests to verify they still pass (baseline before behavior lands)**

Run:
```bash
cd /Users/leo/dev/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/EnvironmentalEmitterTests" 2>&1 | tail -8
```
Expected: fully GREEN — the protocol gained a requirement and both conformers now satisfy it (the real service via Task 3, the stub via Step 1), and no weather backfill exists yet. This run proves the protocol change alone breaks nothing.

- [ ] **Step 3: Write the failing weather-backfill tests**

Add at the end of `EnvironmentalEmitterTests` (reusing the file's `utc`/`day(_:_:_:)`/`allEvents` helpers and `MemoryWatermarkStore`):

```swift
    // MARK: - Observed-weather backfill

    private let weatherDayKey = EnvironmentalEventEmitter.lastWeatherDayKey

    private func observedWeatherDays(_ db: AppDatabase, _ cal: Calendar) async throws -> Set<Date> {
        let events = try await allEvents(db)
        return Set(events.filter { $0.subtype == "temperature" && $0.temporalProvenance == .observedCompletedDay }
            .map { cal.startOfDay(for: $0.timestamp) })
    }

    /// Value days emit observed temp (+humidity when present) and advance the
    /// weather watermark; a nil afternoon humidity emits NO humidity event.
    @Test func weatherBackfillEmitsObservedDaysAndMissingHumidityEmitsNoEvent() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)   // 2025-06-10 09:00
        let d8 = day(cal, 6, 8), d9 = day(cal, 6, 9)
        store.set(day(cal, 6, 7), for: weatherDayKey)            // watermark → start = 06-08
        stub.weatherByDay = [d8: .value(highC: 24, lowC: 12, humidityPct: 64),
                             d9: .value(highC: 30, lowC: 18, humidityPct: nil)]
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        let events = try await allEvents(db)
        let observed = try await observedWeatherDays(db, cal)
        #expect(observed == [d8, d9])
        let d8Humidity = events.first { $0.subtype == "humidity" && cal.startOfDay(for: $0.timestamp) == d8 }
        #expect(d8Humidity?.temporalProvenance == .observedCompletedDay)
        #expect(d8Humidity?.value == 64)
        #expect(!events.contains { $0.subtype == "humidity" && $0.temporalProvenance == .observedCompletedDay
            && cal.startOfDay(for: $0.timestamp) == d9 })        // nil afternoon → no observed humidity event
        #expect(store.date(for: weatherDayKey) == d9)
        #expect(stub.weatherCallCount == 2)
        // Today's forecast events are still forecast — precedence is display-side, not ingest-side.
        #expect(events.contains { $0.subtype == "temperature" && $0.temporalProvenance == .forecast })
    }

    /// A per-day fetchError aborts the WHOLE pass: nothing ingested, watermark held.
    @Test func weatherFetchErrorAbortsPassWithoutIngestOrAdvance() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)
        store.set(day(cal, 6, 7), for: weatherDayKey)
        stub.weatherByDay = [day(cal, 6, 8): .value(highC: 24, lowC: 12, humidityPct: 64)]
        // 06-09 falls to weatherDefault = .fetchError → abort; even 06-08's fetched value must not ingest.
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        #expect(try await observedWeatherDays(db, cal).isEmpty)
        #expect(store.date(for: weatherDayKey) == day(cal, 6, 7))   // held
    }

    /// Recent absent day (grace) holds the contiguous watermark; old absent advances it.
    @Test func weatherWatermarkStopsAtRecentGapButAdvancesOverOldGap() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)   // yesterday = 06-09; graceCutoff = 06-07
        store.set(day(cal, 6, 5), for: weatherDayKey)            // start = 06-06
        stub.weatherByDay = [day(cal, 6, 6): .absent,             // old gap → resolved-absent, advances
                             day(cal, 6, 7): .value(highC: 20, lowC: 10, humidityPct: 50),
                             day(cal, 6, 8): .absent,             // RECENT gap → holds contiguity
                             day(cal, 6, 9): .value(highC: 22, lowC: 11, humidityPct: 55)]
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        let observed = try await observedWeatherDays(db, cal)
        #expect(observed == [day(cal, 6, 7), day(cal, 6, 9)])     // beyond-gap value still emits (idempotent)
        #expect(store.date(for: weatherDayKey) == day(cal, 6, 7)) // stopped before the recent gap
    }

    /// Unset watermark → the weather loop requests EXACTLY the capped window:
    /// 30 distinct calendar days, yesterday−29 through yesterday, stepped
    /// correctly across the LA fall-back DST transition (its own loop — the AQI
    /// cap test cannot protect it).
    @Test func weatherNilWatermarkRequestsExactlyThirtyDaysAcrossDSTFallBack() async throws {
        let cal = losAngeles
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        stub.weatherDefault = .absent                             // every day resolves; loop must run the full window
        let now = day(cal, 11, 9).addingTimeInterval(9 * 3600)    // 2025-11-09 09:00 PST; fall-back was 11-02
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        #expect(stub.weatherCallCount == 30)
        let requested = stub.weatherDaysRequested.map { cal.startOfDay(for: $0) }
        #expect(Set(requested).count == 30)                       // 30 DISTINCT local days (no DST double-step)
        #expect(requested.first == day(cal, 10, 11))              // yesterday − 29
        #expect(requested.last == day(cal, 11, 8))                // yesterday
        var expected = day(cal, 10, 11)
        for d in requested {                                      // contiguous local-day stepping
            #expect(d == expected)
            expected = cal.date(byAdding: .day, value: 1, to: expected)!
        }
    }

    /// The weather throttle is independent: a second foreground within the hour
    /// makes no weather calls; after the hour it retries.
    @Test func weatherRetryThrottleIsIndependentOfAQI() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        var now = day(cal, 6, 10).addingTimeInterval(9 * 3600)
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        let firstCalls = stub.weatherCallCount
        #expect(firstCalls >= 1)
        now = now.addingTimeInterval(600)                        // +10 min → throttled
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        #expect(stub.weatherCallCount == firstCalls)
        now = now.addingTimeInterval(3600)                       // past the hour → retries
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        #expect(stub.weatherCallCount > firstCalls)
    }
```

- [ ] **Step 4: Run to verify the new tests fail**

Run: the same command as Step 2.
Expected: BUILD FAILS — `cannot find 'lastWeatherDayKey'` (the constants land in Step 5). This is the compile-RED for the new tests, same as Tasks 1 and 3.

- [ ] **Step 5: Implement — extract the AQI backfill, add the weather backfill**

In `Models/EnvironmentalEventEmitter.swift`:

Update the protocol doc comment (lines 4-6) to `/// ...the ranged retrospective-AQI fetch and the per-day observed-weather fetch.` Add the new keys/constants after `minAQIRetryInterval` (line 65):

```swift
    /// Last completed local day whose observed weather is ingested + watermarked.
    static let lastWeatherDayKey = "hg.env.lastWeatherDay"
    /// Last time the weather backfill was attempted (retry-throttle watermark).
    static let lastWeatherAttemptKey = "hg.env.lastWeatherAttempt"
    /// Minimum spacing between weather backfill passes (peer of `minAQIRetryInterval`;
    /// its own constant so the two backfills stay independently tunable).
    static let minWeatherRetryInterval: TimeInterval = 3600   // 1 hour
```

Replace the AQI backfill section of `emitIfNeeded` (everything from the `// BACKFILL — observed AQI…` comment at line 105 through the closing `}` of the `do/catch` at line 160) with two calls:

```swift
        await backfillObservedAQI(pipeline: pipeline, service: service, now: now, calendar: calendar, store: store, tz: tz)
        await backfillObservedWeather(pipeline: pipeline, service: service, now: now, calendar: calendar, store: store, tz: tz)
    }
```

Then add the two private functions after `emitIfNeeded`. `backfillObservedAQI` is the MOVED body, verbatim except `return`s now exit only this function (no logic changes — the existing AQI tests are the proof):

```swift
    /// BACKFILL — observed AQI for each completed local day, from a contiguous
    /// watermark up to yesterday, via ONE range request (retry-throttled).
    @MainActor
    private static func backfillObservedAQI(pipeline: IngestPipeline, service: EnvironmentalDataProviding,
                                            now: () -> Date, calendar: Calendar,
                                            store: WatermarkStore, tz: String) async {
        let watermark: Date? = store.date(for: lastAQIDayKey)   // nil when unset
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now()))!
        let capFloor = calendar.date(byAdding: .day, value: -(maxBackfillDays - 1), to: yesterday)!
        let start: Date = watermark.map { max(calendar.date(byAdding: .day, value: 1, to: $0)!, capFloor) } ?? capFloor
        guard start <= yesterday else { return }
        // Throttle: while the tail day is a recent gap or the range keeps failing,
        // `start` stays ≤ yesterday, so without this a rapid foreground would
        // re-download the 30-day range every time (independent of the
        // pressure/forecast cooldown). Own interval, own attempt watermark.
        if let last = store.date(for: lastAQIAttemptKey), now().timeIntervalSince(last) < minAQIRetryInterval { return }
        store.set(now(), for: lastAQIAttemptKey)
        guard case .days(let byDay) = await service.fetchCompletedAirQualityRange(from: start, through: yesterday)
        else { return }   // .fetchError → watermark unchanged, retry after the throttle interval

        // "recent" = the last `gracePartialDays` completed days (provider-lag grace).
        let graceCutoff = calendar.date(byAdding: .day, value: -gracePartialDays, to: yesterday)!
        var newWatermark: Date? = watermark, contiguous = true
        var aqiEvents: [HealthEvent] = []
        // Reading dated D's local noon with ONLY airQualityAQI set → the factory
        // stamps `.observedCompletedDay`, timestamps + groups under day D.
        func emitObservedAQI(_ aqi: Int, on day: Date) {
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
            let reading = EnvironmentalReading(
                date: noon, pressureHPa: nil, previousPressureHPa: nil,
                moonPhaseName: nil, isMercuryRetrograde: false,
                timezoneID: tz, airQualityAQI: aqi)
            aqiEvents.append(contentsOf: EnvironmentalEventFactory.events(for: reading))
        }
        var D = start
        while D <= yesterday {
            switch byDay[calendar.startOfDay(for: D)] ?? .absent {
            case .value(let aqi):
                emitObservedAQI(aqi, on: D)                 // value days beyond a recent gap still emit (dedup-idempotent)
                if contiguous { newWatermark = D }
            case .absent:
                if D > graceCutoff { contiguous = false }   // recent → provider lag; retry, don't advance past
                else if contiguous { newWatermark = D }     // old gap → resolved-absent; advance so it can't block forever
            }
            D = calendar.date(byAdding: .day, value: 1, to: D)!
        }
        // Advance the watermark only once the emitted days are actually persisted;
        // a failed ingest holds it for retry (same as `.fetchError`).
        do {
            if !aqiEvents.isEmpty {
                _ = try await pipeline.ingest(aqiEvents)
            }
            if let nw = newWatermark { store.set(nw, for: lastAQIDayKey) }
        } catch {
            Logger.info("Environmental AQI backfill ingest failed; watermark held for retry", category: .data)
        }
    }

    /// BACKFILL — observed completed-day weather (One Call day_summary), same
    /// contiguous-watermark/cap/grace policy as AQI but ONE CALL PER MISSED DAY
    /// (day_summary has no range endpoint). A per-day `.fetchError` aborts the
    /// whole pass — nothing ingested, watermark held (dedup makes the eventual
    /// re-fetch idempotent; the throttle paces retries, incl. the not-subscribed
    /// 401 case, which the service maps to `.fetchError`).
    @MainActor
    private static func backfillObservedWeather(pipeline: IngestPipeline, service: EnvironmentalDataProviding,
                                                now: () -> Date, calendar: Calendar,
                                                store: WatermarkStore, tz: String) async {
        let watermark: Date? = store.date(for: lastWeatherDayKey)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now()))!
        let capFloor = calendar.date(byAdding: .day, value: -(maxBackfillDays - 1), to: yesterday)!
        let start: Date = watermark.map { max(calendar.date(byAdding: .day, value: 1, to: $0)!, capFloor) } ?? capFloor
        guard start <= yesterday else { return }
        if let last = store.date(for: lastWeatherAttemptKey), now().timeIntervalSince(last) < minWeatherRetryInterval { return }
        store.set(now(), for: lastWeatherAttemptKey)

        let graceCutoff = calendar.date(byAdding: .day, value: -gracePartialDays, to: yesterday)!
        var newWatermark: Date? = watermark, contiguous = true
        var weatherEvents: [HealthEvent] = []
        // Reading dated D's local noon with ONLY weather fields + observed
        // provenance → the factory stamps `.observedCompletedDay` (mineable);
        // nil humidity emits no humidity event (missing afternoon observation).
        func emitObservedWeather(highC: Double, lowC: Double, humidityPct: Double?, on day: Date) {
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
            let reading = EnvironmentalReading(
                date: noon, pressureHPa: nil, previousPressureHPa: nil,
                moonPhaseName: nil, isMercuryRetrograde: false,
                timezoneID: tz, temperatureHighC: highC, temperatureLowC: lowC,
                humidityPct: humidityPct, weatherProvenance: .observedCompletedDay)
            weatherEvents.append(contentsOf: EnvironmentalEventFactory.events(for: reading))
        }
        var D = start
        while D <= yesterday {
            switch await service.fetchCompletedWeatherDay(for: D) {
            case .fetchError:
                return   // abort the WHOLE pass: nothing ingested, watermark held (spec §3B)
            case .value(let high, let low, let humidity):
                emitObservedWeather(highC: high, lowC: low, humidityPct: humidity, on: D)
                if contiguous { newWatermark = D }
            case .absent:
                if D > graceCutoff { contiguous = false }
                else if contiguous { newWatermark = D }
            }
            D = calendar.date(byAdding: .day, value: 1, to: D)!
        }
        do {
            if !weatherEvents.isEmpty {
                _ = try await pipeline.ingest(weatherEvents)
            }
            if let nw = newWatermark { store.set(nw, for: lastWeatherDayKey) }
        } catch {
            Logger.info("Environmental weather backfill ingest failed; watermark held for retry", category: .data)
        }
    }
```

Also update `emitIfNeeded`'s type doc comment (lines 46-48) to mention both backfills: `Retrospective AQI (one ranged request) and observed completed-day weather (one day_summary call per missed day) are backfilled from independent contiguous per-day watermarks, each gated by its own retry throttle.`

- [ ] **Step 6: Run the emitter tests to verify all green**

Run: the same command as Step 2.
Expected: `** TEST SUCCEEDED **` — the 4 new tests AND every pre-existing test pass (the moved AQI body behaves identically; the AQI tests are the regression net for the extraction).

- [ ] **Step 7: Full-suite verification (both packages)**

Run:
```bash
cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3
cd /Users/leo/dev/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -8
```
Expected: core all pass; app green modulo the ONE known pre-existing `SwiftDataMigratorTests` teardown crash.

- [ ] **Step 8: Commit**

```bash
git add Models/EnvironmentalEventEmitter.swift "Food IntolerancesTests/EnvironmentalEmitterTests.swift"
git commit -m "feat(app): observed-weather backfill — per-day day_summary with own watermark/throttle; AQI backfill extracted intact

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Device gate (Leo, after Task 4)

Not a plan task — the round's final verification, per the spec's Testing section. Prerequisite first: activate the One Call 3.0 subscription on the OpenWeather account (optionally set the account call cap).
1. Completed days' Environment rows show measured actuals (visibly different from the forecast numbers where they diverge); today still shows forecast.
2. After the backfill + a recompute, the dormant Hot/Cold/Humid/Big-swing Insights cards re-activate.
3. A day whose afternoon humidity was missing shows the forecast humidity line and no observed one.
4. With the subscription disabled (or key removed), everything behaves exactly as before this round — no errors surface.
