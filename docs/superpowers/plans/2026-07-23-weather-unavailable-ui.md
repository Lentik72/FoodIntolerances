# Weather-Unavailable UI State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make failed environment fetches visible instead of silent — a muted per-day Timeline marker and a Health-tab status screen — recording per-capability fetch health, and stop the pressure fallback fabricating readings.

**Architecture:** All new code is app-layer; `HealthGraphCore` is untouched. A single `@MainActor` `EnvironmentStatusStore` records five capabilities' health (last success, a live failure that self-heals, a retained failure for history), each failure carrying the day-range and timezone it blocked. `EnvironmentalDataService` classifies fetch failures into reasons and rejects fabricated coordinates; the emitter records backfill health; a pure `EnvironmentGapResolver` turns the store into a per-day marker; pure presentation logic drives the Health screen. Pressure gains a time-stamped genuine-reading carry so a fallback never poisons the mined pressure-drop delta.

**Tech Stack:** Swift, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), CoreLocation, `UserDefaults` persistence, `HealthGraphCore` (unchanged).

## Global Constraints

- **No `HealthGraphCore` changes.** Every file touched is in the app target (`Food Intolerances`) or its test target (`Food IntolerancesTests`).
- **App test command** (single suite shown; swap the `-only-testing` suite per step):
  `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/<Suite>" -parallel-testing-enabled NO`
- **`-parallel-testing-enabled NO` is mandatory** for the app test target. A lone `** TEST FAILED **` originating only from `SwiftDataMigratorTests` teardown is a known pre-existing crash — ignore it; treat a run as green when your suite's `#expect`s pass.
- **Capability order (fixed everywhere):** `currentPressure` → `forecastWeather` → `observedWeather` → `forecastAirQuality` → `observedAirQuality`. Used for the Health summary "earliest failing" pick.
- **Marker tone:** muted caption, `HealthTheme.inkMuted`, no color, no SF Symbol, no alarming words. Copy exactly: `Weather unavailable` / `Air quality unavailable`.
- **Constants:** pressure sudden-change window `pressureReadingInterval = 3600` s (existing); pressure-drop threshold `6.0` hPa (existing, in core factory); location freshness window `300` s (existing literal, lifted to a named constant this round).
- **Health copy** strings are exact — copy them verbatim from Task 4's tables.
- DRY, YAGNI, TDD, frequent commits. One `#expect`-backed reason per test.

---

## File Structure

**New (app):**
- `Models/EnvironmentStatus.swift` — value types (`EnvironmentCapability`, `EnvironmentFailureReason`, `EnvironmentFailure`, `EnvironmentCapabilityStatus`, `LocationProvenance`, `EnvironmentLocationAuthorization`) + the pure `LocationTrust` decision.
- `Models/EnvironmentStatusStore.swift` — the `@MainActor`, `UserDefaults`-backed observable store.
- `Views/HealthOS/Timeline/EnvironmentGapResolver.swift` — pure resolver + `EnvironmentGap`.
- `Views/HealthOS/Health/EnvironmentStatusPresentation.swift` — pure Health-screen formatting.
- `Views/HealthOS/Health/EnvironmentStatusView.swift` — the Health detail screen (thin SwiftUI over the presentation type).

**New (tests):** `LocationTrustTests`, `EnvironmentStatusStoreTests`, `EnvironmentGapResolverTests`, `EnvironmentStatusPresentationTests`, `EnvironmentFailureClassificationTests`, `PressureTrustTests`.

**Modified (app):** `HTTPTransport.swift` (protocol), `EnvironmentalDataService.swift` (service + nested `LocationService`), `Models/EnvironmentalEventEmitter.swift`, `FoodIntolerancesApp.swift`, `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift`, `Views/HealthOS/Timeline/TimelineView.swift`, `Views/HealthOS/Health/HealthTabView.swift`.

**Modified (tests):** `EnvironmentalEmitterTests.swift`, `EnvironmentalDataServiceDITests.swift`, `WeatherHistoryTests.swift`, `AirQualityHistoryTests.swift` (stub conformance + `.fetchError` → `.fetchError(reason)` assertions).

**Task order** (each boundary compiles + tests green): T1 types → T2 store → T3 resolver → T4 presentation (T1–T4 are independent new files) → T5 trusted-coordinate seam → T6 backfill enums+status → T7 pressure trust → T8 today-capability classification → T9 app wiring → T10 Timeline marker → T11 Health UI.

---

### Task 1: Status value types + `LocationTrust`

**Files:**
- Create: `Models/EnvironmentStatus.swift`
- Test: `Food IntolerancesTests/LocationTrustTests.swift`

**Interfaces:**
- Produces: the enums/structs listed below; `LocationTrust.trustedCoordinate(manual:provenance:deviceCoordinate:cachedCoordinate:cachedAt:authorization:now:freshness:) -> CLLocationCoordinate2D?`.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/LocationTrustTests.swift`:

```swift
import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

struct LocationTrustTests {
    private let device = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)   // London
    private let cached = CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35)   // Paris
    private let manual = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0)   // Tokyo
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let freshness: TimeInterval = 300

    private func trusted(provenance: LocationProvenance,
                         cachedAt: Date?,
                         authorization: EnvironmentLocationAuthorization,
                         manual: CLLocationCoordinate2D? = nil) -> CLLocationCoordinate2D? {
        LocationTrust.trustedCoordinate(
            manual: manual, provenance: provenance,
            deviceCoordinate: device, cachedCoordinate: cached, cachedAt: cachedAt,
            authorization: authorization, now: now, freshness: freshness)
    }

    @Test func deviceProvenanceIsAlwaysTrusted() {
        #expect(trusted(provenance: .device, cachedAt: nil, authorization: .authorized)?.latitude == device.latitude)
    }
    @Test func fabricatedIsNeverTrusted() {
        #expect(trusted(provenance: .fabricated, cachedAt: now, authorization: .authorized) == nil)
    }
    @Test func cachedTrustedWhenAuthorizedAndFresh() {
        let at = now.addingTimeInterval(-120)   // 2 min old
        #expect(trusted(provenance: .cached, cachedAt: at, authorization: .authorized)?.latitude == cached.latitude)
    }
    @Test func cachedRejectedWhenStale() {
        let at = now.addingTimeInterval(-600)   // 10 min old
        #expect(trusted(provenance: .cached, cachedAt: at, authorization: .authorized) == nil)
    }
    @Test func cachedRejectedWhenDeniedEvenIfFresh() {
        let at = now.addingTimeInterval(-10)
        #expect(trusted(provenance: .cached, cachedAt: at, authorization: .denied) == nil)
    }
    @Test func cachedRejectedWhenTimestampMissing() {
        #expect(trusted(provenance: .cached, cachedAt: nil, authorization: .authorized) == nil)
    }
    @Test func manualWinsOverFabricatedAndStaleCache() {
        #expect(trusted(provenance: .fabricated, cachedAt: nil, authorization: .denied, manual: manual)?.latitude == manual.latitude)
    }
    @Test func failureCodableRoundTripsTimezone() throws {
        let f = EnvironmentFailure(at: now, reason: .rejected,
                                   scopeStart: now, scopeEnd: now, timezoneID: "America/Los_Angeles")
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(EnvironmentFailure.self, from: data)
        #expect(back == f)
        #expect(back.timezoneID == "America/Los_Angeles")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/LocationTrustTests" -parallel-testing-enabled NO`
Expected: FAIL — `LocationTrust`, `LocationProvenance`, `EnvironmentLocationAuthorization`, `EnvironmentFailure` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Models/EnvironmentStatus.swift`:

```swift
import Foundation
import CoreLocation

/// One environmental fetch that can fail independently of the others.
enum EnvironmentCapability: String, CaseIterable, Codable {
    case currentPressure, forecastWeather, forecastAirQuality
    case observedAirQuality, observedWeather
}

/// Why a fetch could not produce a usable value.
enum EnvironmentFailureReason: String, Codable {
    case notConfigured        // no API key in the build
    case rejected             // 401/403: key invalid/revoked, or One Call not subscribed
    case locationDenied       // authorization .denied / .restricted — user-fixable
    case locationUnavailable  // authorized/.notDetermined, or only a fabricated coord
    case offline              // URLError, excluding .cancelled
    case insufficientData     // 2xx, but the response held no usable value for the day
    case badResponse          // decode failure, unexpected shape, other HTTP error
}

/// A recorded failure and the day-range (in its own timezone) it blocked.
struct EnvironmentFailure: Codable, Equatable {
    let at: Date
    let reason: EnvironmentFailureReason
    let scopeStart: Date    // local start-of-day, inclusive
    let scopeEnd: Date      // local start-of-day, inclusive
    let timezoneID: String  // the calendar tz the scope was computed in
}

/// Per-capability health. `liveFailure` self-heals (drives the Timeline);
/// `lastFailure` is retained history (drives the Health "why").
struct EnvironmentCapabilityStatus: Codable, Equatable {
    var lastSuccess: Date?
    var liveFailure: EnvironmentFailure?
    var lastFailure: EnvironmentFailure?
}

/// Where `LocationService.currentLocation` came from — the fabricated NYC
/// fallback must never be ingested into the graph.
enum LocationProvenance { case device, cached, fabricated }

/// App-level mirror of `CLAuthorizationStatus`, so the injectable location seam
/// need not import CoreLocation's enum. Public: it appears in the public
/// `LocationProviding` protocol's requirements.
public enum EnvironmentLocationAuthorization { case denied, restricted, authorized, notDetermined }

/// Pure decision: the coordinate the graph is allowed to ingest, or nil if none
/// is trustworthy. Manual always wins; device always trusted; cached trusted
/// only when authorized AND fresh; fabricated never trusted.
enum LocationTrust {
    static func trustedCoordinate(
        manual: CLLocationCoordinate2D?,
        provenance: LocationProvenance,
        deviceCoordinate: CLLocationCoordinate2D?,
        cachedCoordinate: CLLocationCoordinate2D?,
        cachedAt: Date?,
        authorization: EnvironmentLocationAuthorization,
        now: Date,
        freshness: TimeInterval
    ) -> CLLocationCoordinate2D? {
        if let manual { return manual }
        switch provenance {
        case .device:
            return deviceCoordinate
        case .cached:
            guard authorization == .authorized,
                  let cachedCoordinate, let cachedAt,
                  now.timeIntervalSince(cachedAt) <= freshness else { return nil }
            return cachedCoordinate
        case .fabricated:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/LocationTrustTests" -parallel-testing-enabled NO`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add "Models/EnvironmentStatus.swift" "Food IntolerancesTests/LocationTrustTests.swift"
git commit -m "feat(env-status): status value types + pure LocationTrust decision"
```

---

### Task 2: `EnvironmentStatusStore`

**Files:**
- Create: `Models/EnvironmentStatusStore.swift`
- Test: `Food IntolerancesTests/EnvironmentStatusStoreTests.swift`

**Interfaces:**
- Consumes: Task 1 value types.
- Produces: `@MainActor final class EnvironmentStatusStore: ObservableObject` with `@Published private(set) var statuses: [EnvironmentCapability: EnvironmentCapabilityStatus]`; `init(defaults: UserDefaults = .standard)`; `recordSuccess(_:at:)`; `recordFailure(_:reason:scopeStart:scopeEnd:timezoneID:at:)`.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/EnvironmentStatusStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import Food_Intolerances

@MainActor
struct EnvironmentStatusStoreTests {
    private func ephemeral() -> UserDefaults {
        // A unique volatile suite per test so nothing leaks into `.standard`.
        let name = "test.env.status." + UUID().uuidString
        return UserDefaults(suiteName: name)!
    }
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func recordFailureSetsBothSlots() {
        let store = EnvironmentStatusStore(defaults: ephemeral())
        store.recordFailure(.observedWeather, reason: .rejected,
                            scopeStart: t0, scopeEnd: t0, timezoneID: "UTC", at: t0)
        let s = store.statuses[.observedWeather]
        #expect(s?.liveFailure?.reason == .rejected)
        #expect(s?.lastFailure?.reason == .rejected)
        #expect(s?.lastSuccess == nil)
    }

    @Test func recordSuccessClearsLiveButRetainsLast() {
        let store = EnvironmentStatusStore(defaults: ephemeral())
        store.recordFailure(.observedWeather, reason: .locationDenied,
                            scopeStart: t0, scopeEnd: t0, timezoneID: "UTC", at: t0)
        store.recordSuccess(.observedWeather, at: t0.addingTimeInterval(60))
        let s = store.statuses[.observedWeather]
        #expect(s?.liveFailure == nil)                 // healed
        #expect(s?.lastFailure?.reason == .locationDenied)   // retained
        #expect(s?.lastSuccess == t0.addingTimeInterval(60))
    }

    @Test func persistsAcrossInstancesIncludingTimezone() {
        let defaults = ephemeral()
        do {
            let store = EnvironmentStatusStore(defaults: defaults)
            store.recordFailure(.observedAirQuality, reason: .offline,
                                scopeStart: t0, scopeEnd: t0.addingTimeInterval(86_400),
                                timezoneID: "America/Los_Angeles", at: t0)
        }
        let reloaded = EnvironmentStatusStore(defaults: defaults)
        let f = reloaded.statuses[.observedAirQuality]?.liveFailure
        #expect(f?.reason == .offline)
        #expect(f?.timezoneID == "America/Los_Angeles")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentStatusStoreTests" -parallel-testing-enabled NO`
Expected: FAIL — `EnvironmentStatusStore` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Models/EnvironmentStatusStore.swift`:

```swift
import Foundation
import Combine

/// The single source of truth for environment-fetch health. Created once in
/// `FoodIntolerancesApp`, injected into `EnvironmentalDataService` and the
/// emitter, and read by the Timeline + Health surfaces. `@MainActor`: every
/// reader is UI and every write point is already on the main actor.
@MainActor
final class EnvironmentStatusStore: ObservableObject {
    @Published private(set) var statuses: [EnvironmentCapability: EnvironmentCapabilityStatus] = [:]

    private let defaults: UserDefaults
    private static let storageKey = "hg.env.status"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: EnvironmentCapabilityStatus].self, from: data) {
            var restored: [EnvironmentCapability: EnvironmentCapabilityStatus] = [:]
            for (raw, value) in decoded {
                if let cap = EnvironmentCapability(rawValue: raw) { restored[cap] = value }
            }
            statuses = restored
        }
    }

    func recordSuccess(_ capability: EnvironmentCapability, at: Date) {
        var s = statuses[capability] ?? EnvironmentCapabilityStatus()
        s.lastSuccess = at
        s.liveFailure = nil          // heal the Timeline; lastFailure is retained
        statuses[capability] = s
        persist()
    }

    func recordFailure(_ capability: EnvironmentCapability, reason: EnvironmentFailureReason,
                       scopeStart: Date, scopeEnd: Date, timezoneID: String, at: Date) {
        let failure = EnvironmentFailure(at: at, reason: reason,
                                         scopeStart: scopeStart, scopeEnd: scopeEnd, timezoneID: timezoneID)
        var s = statuses[capability] ?? EnvironmentCapabilityStatus()
        s.liveFailure = failure
        s.lastFailure = failure
        statuses[capability] = s
        persist()
    }

    private func persist() {
        var encodable: [String: EnvironmentCapabilityStatus] = [:]
        for (cap, value) in statuses { encodable[cap.rawValue] = value }
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentStatusStoreTests" -parallel-testing-enabled NO`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add "Models/EnvironmentStatusStore.swift" "Food IntolerancesTests/EnvironmentStatusStoreTests.swift"
git commit -m "feat(env-status): UserDefaults-backed EnvironmentStatusStore"
```

---

### Task 3: `EnvironmentGapResolver`

**Files:**
- Create: `Views/HealthOS/Timeline/EnvironmentGapResolver.swift`
- Test: `Food IntolerancesTests/EnvironmentGapResolverTests.swift`

**Interfaces:**
- Consumes: Task 1 types; `EnvironmentDaySummary`, `HealthEvent` (core).
- Produces: `enum EnvironmentGap { case weather, airQuality; var label: String }`; `EnvironmentGapResolver.gap(for:status:) -> EnvironmentGap?`.

**Note on signature:** the spec's `now:calendar:` parameters are omitted — scope-with-timezone fully encodes both reach and "today" (§3E: the resolver's own calendar/now would be "used only where no scope is involved," and there is no such place). Containment builds its calendar from `failure.timezoneID`.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/EnvironmentGapResolverTests.swift`:

```swift
import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

struct EnvironmentGapResolverTests {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func day(_ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: 2025, month: m, day: d))!
    }
    private func summary(_ dayStart: Date, subtypes: [String]) -> EnvironmentDaySummary {
        let noon = utc.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)!
        let events = subtypes.map {
            HealthEvent(timestamp: noon, category: .environment, subtype: $0,
                        value: 1, unit: nil, source: .weatherAPI)
        }
        return EnvironmentDaySummary(dayStart: dayStart, timestamp: noon, events: events)
    }
    private func failure(_ start: Date, _ end: Date, reason: EnvironmentFailureReason = .rejected) -> EnvironmentFailure {
        EnvironmentFailure(at: start, reason: reason, scopeStart: start, scopeEnd: end, timezoneID: "UTC")
    }
    private func status(_ pairs: [(EnvironmentCapability, EnvironmentFailure)]) -> [EnvironmentCapability: EnvironmentCapabilityStatus] {
        var out: [EnvironmentCapability: EnvironmentCapabilityStatus] = [:]
        for (cap, f) in pairs { out[cap] = EnvironmentCapabilityStatus(lastSuccess: nil, liveFailure: f, lastFailure: f) }
        return out
    }

    @Test func insideScopeMissingReadingMarksWeather() {
        let d = day(6, 10)
        let g = EnvironmentGapResolver.gap(for: summary(d, subtypes: ["moonPhase"]),
                                           status: status([(.observedWeather, failure(day(6, 1), day(6, 10)))]))
        #expect(g == .weather)
    }
    @Test func insideScopeButReadingPresentIsNil() {
        let d = day(6, 10)
        let g = EnvironmentGapResolver.gap(for: summary(d, subtypes: ["temperature", "moonPhase"]),
                                           status: status([(.observedWeather, failure(day(6, 1), day(6, 10)))]))
        #expect(g == nil)
    }
    @Test func outsideEveryScopeIsNil() {   // the 200-day-old moon-only row
        let g = EnvironmentGapResolver.gap(for: summary(day(1, 1), subtypes: ["moonPhase"]),
                                           status: status([(.observedWeather, failure(day(6, 1), day(6, 10)))]))
        #expect(g == nil)
    }
    @Test func missingBothMarksWeatherOnly() {
        let d = day(6, 10)
        let g = EnvironmentGapResolver.gap(for: summary(d, subtypes: ["moonPhase"]),
                                           status: status([(.observedWeather, failure(day(6, 1), day(6, 10))),
                                                           (.observedAirQuality, failure(day(6, 1), day(6, 10)))]))
        #expect(g == .weather)
    }
    @Test func missingOnlyAQIMarksAirQuality() {
        let d = day(6, 10)
        let g = EnvironmentGapResolver.gap(for: summary(d, subtypes: ["temperature"]),
                                           status: status([(.observedAirQuality, failure(day(6, 1), day(6, 10)))]))
        #expect(g == .airQuality)
    }
    @Test func insufficientDataTodayMarksWeather() {
        let d = day(6, 10)
        let g = EnvironmentGapResolver.gap(for: summary(d, subtypes: ["moonPhase"]),
                                           status: status([(.forecastWeather, failure(d, d, reason: .insufficientData))]))
        #expect(g == .weather)
    }
    @Test func pressureOnlyFailureNeverMarks() {
        let d = day(6, 10)
        let g = EnvironmentGapResolver.gap(for: summary(d, subtypes: ["moonPhase"]),
                                           status: status([(.currentPressure, failure(d, d))]))
        #expect(g == nil)
    }
    @Test func containmentUsesFailureTimezoneNotDeviceCalendar() {
        // Scope day recorded in LA. Summary dayStart is the SAME calendar instant.
        var la = Calendar(identifier: .gregorian); la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let laDay = la.date(from: DateComponents(year: 2025, month: 6, day: 10))!
        let noon = la.date(bySettingHour: 12, minute: 0, second: 0, of: laDay)!
        let s = EnvironmentDaySummary(dayStart: laDay, timestamp: noon,
            events: [HealthEvent(timestamp: noon, category: .environment, subtype: "moonPhase",
                                 value: 1, unit: nil, source: .weatherAPI)])
        let f = EnvironmentFailure(at: laDay, reason: .rejected, scopeStart: laDay, scopeEnd: laDay,
                                   timezoneID: "America/Los_Angeles")
        let status: [EnvironmentCapability: EnvironmentCapabilityStatus] =
            [.observedWeather: EnvironmentCapabilityStatus(lastSuccess: nil, liveFailure: f, lastFailure: f)]
        #expect(EnvironmentGapResolver.gap(for: s, status: status) == .weather)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentGapResolverTests" -parallel-testing-enabled NO`
Expected: FAIL — `EnvironmentGap`, `EnvironmentGapResolver` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Views/HealthOS/Timeline/EnvironmentGapResolver.swift`:

```swift
import Foundation
import HealthGraphCore

/// The one thing a day's Environment row can be missing because a fetch failed.
enum EnvironmentGap {
    case weather
    case airQuality

    var label: String {
        switch self {
        case .weather:    return "Weather unavailable"
        case .airQuality: return "Air quality unavailable"
        }
    }
}

/// Pure: does this day lack a reading that a *live* failure says was attempted?
/// Scope containment uses each failure's own timezone, so a marker stays anchored
/// to the days it was about even if the device timezone later changes.
enum EnvironmentGapResolver {
    static func gap(for summary: EnvironmentDaySummary,
                    status: [EnvironmentCapability: EnvironmentCapabilityStatus]) -> EnvironmentGap? {
        let hasTemperature = summary.events.contains { $0.subtype == "temperature" }
        let hasAirQuality  = summary.events.contains { $0.subtype == "airQuality" }

        // Rule 1 (today) + Rule 2 (completed days): weather leads.
        if !hasTemperature {
            if liveScopeContains(summary.dayStart, status[.forecastWeather]?.liveFailure) { return .weather }
            if liveScopeContains(summary.dayStart, status[.observedWeather]?.liveFailure) { return .weather }
        }
        // Rule 3: air quality, only when weather didn't already fire.
        if !hasAirQuality,
           liveScopeContains(summary.dayStart, status[.observedAirQuality]?.liveFailure) {
            return .airQuality
        }
        return nil
    }

    /// `dayStart` (an instant) falls inside `[scopeStart, scopeEnd]` when its
    /// start-of-day in the failure's own timezone lies within the stored bounds.
    private static func liveScopeContains(_ dayStart: Date, _ failure: EnvironmentFailure?) -> Bool {
        guard let failure else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: failure.timezoneID) ?? .current
        let day = cal.startOfDay(for: dayStart)
        return day >= failure.scopeStart && day <= failure.scopeEnd
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentGapResolverTests" -parallel-testing-enabled NO`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Timeline/EnvironmentGapResolver.swift" "Food IntolerancesTests/EnvironmentGapResolverTests.swift"
git commit -m "feat(env-status): pure EnvironmentGapResolver for the Timeline marker"
```

---

### Task 4: Health-screen presentation logic

**Files:**
- Create: `Views/HealthOS/Health/EnvironmentStatusPresentation.swift`
- Test: `Food IntolerancesTests/EnvironmentStatusPresentationTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces: `EnvironmentStatusPresentation` with `Summary`, `Row`/`RowStatus`/`Section`, `Explanation`, and static `summary(_:)`, `rows(_:)`, `explanation(_:)`.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/EnvironmentStatusPresentationTests.swift`:

```swift
import Testing
import Foundation
@testable import Food_Intolerances

struct EnvironmentStatusPresentationTests {
    private let t = Date(timeIntervalSince1970: 1_000_000)
    private func fail(_ reason: EnvironmentFailureReason, at: Date) -> EnvironmentFailure {
        EnvironmentFailure(at: at, reason: reason, scopeStart: at, scopeEnd: at, timezoneID: "UTC")
    }

    @Test func summaryNotCheckedWhenAllNil() {
        #expect(EnvironmentStatusPresentation.summary([:]) == .notChecked)
    }
    @Test func summaryUsesLeastRecentSuccess() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .currentPressure:   .init(lastSuccess: t.addingTimeInterval(500), liveFailure: nil, lastFailure: nil),
            .forecastWeather:   .init(lastSuccess: t.addingTimeInterval(100), liveFailure: nil, lastFailure: nil),
            .forecastAirQuality:.init(lastSuccess: t.addingTimeInterval(300), liveFailure: nil, lastFailure: nil),
            .observedAirQuality:.init(lastSuccess: t.addingTimeInterval(400), liveFailure: nil, lastFailure: nil),
            .observedWeather:   .init(lastSuccess: t.addingTimeInterval(200), liveFailure: nil, lastFailure: nil),
        ]
        #expect(EnvironmentStatusPresentation.summary(s) == .updated(t.addingTimeInterval(100)))
    }
    @Test func summaryNotCheckedIfAnyEndpointNeverRan() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .currentPressure: .init(lastSuccess: t, liveFailure: nil, lastFailure: nil)
            // others absent → nil lastSuccess
        ]
        #expect(EnvironmentStatusPresentation.summary(s) == .notChecked)
    }
    @Test func summaryNamesEarliestFailingGroup() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .observedWeather:   .init(lastSuccess: nil, liveFailure: fail(.rejected, at: t), lastFailure: fail(.rejected, at: t)),
            .observedAirQuality:.init(lastSuccess: nil, liveFailure: fail(.offline, at: t), lastFailure: fail(.offline, at: t)),
        ]
        #expect(EnvironmentStatusPresentation.summary(s) == .unavailable("Weather history unavailable"))
    }
    @Test func explanationLiveLocationDeniedShowsOpenSettings() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .forecastWeather: .init(lastSuccess: nil, liveFailure: fail(.locationDenied, at: t), lastFailure: fail(.locationDenied, at: t)),
        ]
        let e = EnvironmentStatusPresentation.explanation(s)
        #expect(e?.isResolved == false)
        #expect(e?.showOpenSettings == true)
        #expect(e?.heading == "Why it stopped")
    }
    @Test func explanationResolvedIsPastTenseNoAction() {
        // liveFailure cleared, lastFailure retained → resolved.
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .forecastWeather: .init(lastSuccess: t.addingTimeInterval(60), liveFailure: nil, lastFailure: fail(.locationDenied, at: t)),
        ]
        let e = EnvironmentStatusPresentation.explanation(s)
        #expect(e?.isResolved == true)
        #expect(e?.showOpenSettings == false)     // no action even though it was locationDenied
        #expect(e?.heading == "Last issue — resolved")
    }
    @Test func observedWeatherRejectedUsesNeutralKeyOrSubscriptionCopy() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .observedWeather: .init(lastSuccess: nil, liveFailure: fail(.rejected, at: t), lastFailure: fail(.rejected, at: t)),
        ]
        #expect(EnvironmentStatusPresentation.explanation(s)?.body
                == "Historical weather may need a valid API key or an active One Call subscription.")
    }
    @Test func rowStatusPerCapability() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .currentPressure: .init(lastSuccess: t, liveFailure: nil, lastFailure: nil),
            .observedWeather: .init(lastSuccess: nil, liveFailure: fail(.rejected, at: t), lastFailure: fail(.rejected, at: t)),
        ]
        let rows = EnvironmentStatusPresentation.rows(s)
        let pressure = rows.first { $0.capability == .currentPressure }
        let obsWeather = rows.first { $0.capability == .observedWeather }
        let obsAQI = rows.first { $0.capability == .observedAirQuality }
        #expect(pressure?.status == .updated(t))
        #expect(obsWeather?.status == .unavailable)
        #expect(obsAQI?.status == .notChecked)
        #expect(rows.count == 5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentStatusPresentationTests" -parallel-testing-enabled NO`
Expected: FAIL — `EnvironmentStatusPresentation` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Views/HealthOS/Health/EnvironmentStatusPresentation.swift`:

```swift
import Foundation

/// Pure formatting for the Health "Environment data" screen. Returns dates (not
/// formatted strings) so the view owns time formatting and this stays testable.
enum EnvironmentStatusPresentation {

    // Order used to pick the earliest failing capability for the summary + explanation.
    static let order: [EnvironmentCapability] = [
        .currentPressure, .forecastWeather, .observedWeather, .forecastAirQuality, .observedAirQuality
    ]

    enum Section { case weather, airQuality }

    // MARK: Summary row

    enum Summary: Equatable {
        case unavailable(String)   // an affected-group phrase
        case notChecked
        case updated(Date)         // the LEAST-recent success across all five
    }

    static func summary(_ statuses: [EnvironmentCapability: EnvironmentCapabilityStatus]) -> Summary {
        if let cap = order.first(where: { statuses[$0]?.liveFailure != nil }) {
            return .unavailable(groupPhrase(for: cap))
        }
        let successes = EnvironmentCapability.allCases.map { statuses[$0]?.lastSuccess }
        if successes.contains(where: { $0 == nil }) { return .notChecked }
        let leastRecent = successes.compactMap { $0 }.min()!
        return .updated(leastRecent)
    }

    /// A live-failure group phrase for the summary.
    private static func groupPhrase(for capability: EnvironmentCapability) -> String {
        switch capability {
        case .currentPressure, .forecastWeather: return "Weather unavailable"
        case .observedWeather:                    return "Weather history unavailable"
        case .forecastAirQuality:                 return "Air quality unavailable"
        case .observedAirQuality:                 return "Air quality history unavailable"
        }
    }

    // MARK: Per-capability rows

    enum RowStatus: Equatable { case unavailable, notChecked, updated(Date) }
    struct Row: Equatable {
        let capability: EnvironmentCapability
        let section: Section
        let title: String
        let status: RowStatus
    }

    static func rows(_ statuses: [EnvironmentCapability: EnvironmentCapabilityStatus]) -> [Row] {
        order.map { cap in
            Row(capability: cap, section: section(for: cap), title: title(for: cap), status: rowStatus(statuses[cap])) }
    }

    private static func rowStatus(_ s: EnvironmentCapabilityStatus?) -> RowStatus {
        if s?.liveFailure != nil { return .unavailable }
        if let success = s?.lastSuccess { return .updated(success) }
        return .notChecked
    }

    private static func section(for capability: EnvironmentCapability) -> Section {
        switch capability {
        case .currentPressure, .forecastWeather, .observedWeather: return .weather
        case .forecastAirQuality, .observedAirQuality: return .airQuality
        }
    }

    private static func title(for capability: EnvironmentCapability) -> String {
        switch capability {
        case .currentPressure:    return "Air pressure"
        case .forecastWeather:    return "Today's forecast"
        case .observedWeather:    return "Observed history"
        case .forecastAirQuality: return "Today's forecast"
        case .observedAirQuality: return "Observed history"
        }
    }

    // MARK: Bottom explanation (live > resolved > none)

    struct Explanation: Equatable {
        let heading: String       // "Why it stopped" | "Last issue — resolved"
        let body: String
        let showOpenSettings: Bool
        let isResolved: Bool
    }

    static func explanation(_ statuses: [EnvironmentCapability: EnvironmentCapabilityStatus]) -> Explanation? {
        if let cap = order.first(where: { statuses[$0]?.liveFailure != nil }),
           let live = statuses[cap]?.liveFailure {
            return Explanation(heading: "Why it stopped",
                               body: liveCopy(live.reason, capability: cap),
                               showOpenSettings: live.reason == .locationDenied,
                               isResolved: false)
        }
        // All healed: the most recent retained failure, past tense, no action.
        let retained = EnvironmentCapability.allCases.compactMap { statuses[$0]?.lastFailure }
        if let mostRecent = retained.max(by: { $0.at < $1.at }) {
            return Explanation(heading: "Last issue — resolved",
                               body: resolvedCopy(mostRecent.reason),
                               showOpenSettings: false,
                               isResolved: true)
        }
        return nil
    }

    private static func liveCopy(_ reason: EnvironmentFailureReason, capability: EnvironmentCapability) -> String {
        switch reason {
        case .notConfigured:      return "Weather data isn't configured in this build."
        case .rejected:
            return capability == .observedWeather
                ? "Historical weather may need a valid API key or an active One Call subscription."
                : "The weather service rejected the request."
        case .locationDenied:     return "Location access is off, so conditions can't be looked up for where you are."
        case .locationUnavailable:return "Your location hasn't been determined yet."
        case .offline:            return "No internet connection the last time we checked."
        case .insufficientData:   return "The forecast didn't include enough data for today yet."
        case .badResponse:        return "The weather service returned something unexpected."
        }
    }

    private static func resolvedCopy(_ reason: EnvironmentFailureReason) -> String {
        switch reason {
        case .notConfigured:      return "Weather data wasn't configured."
        case .rejected:           return "The weather service was rejecting requests."
        case .locationDenied:     return "Location access was off."
        case .locationUnavailable:return "Your location couldn't be determined."
        case .offline:            return "There was no internet connection."
        case .insufficientData:   return "The forecast was briefly incomplete."
        case .badResponse:        return "The weather service returned something unexpected."
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentStatusPresentationTests" -parallel-testing-enabled NO`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Health/EnvironmentStatusPresentation.swift" "Food IntolerancesTests/EnvironmentStatusPresentationTests.swift"
git commit -m "feat(env-status): pure Health-screen presentation (summary/rows/explanation)"
```

---

### Task 5: Trusted-coordinate seam + authorization + provenance

Compiler-enforced protocol change; behavior-neutral for existing tests once stubs conform. Provenance stamping in `LocationService` is device-pass-verified (CoreLocation-backed); the trust decision itself is already unit-tested (Task 1).

**Files:**
- Modify: `HTTPTransport.swift:21` (protocol)
- Modify: `EnvironmentalDataService.swift` — `DefaultLocationProvider` (`:92-98`); `LocationService` NYC/cached/device sites + new members; add `locationFreshnessInterval`.
- Modify: `Food IntolerancesTests/EnvironmentalDataServiceDITests.swift:23-25`, `WeatherHistoryTests.swift:33-35`, `AirQualityHistoryTests.swift:130` (`StubLocation` gains `authorization`).

**Interfaces:**
- Consumes: Task 1 (`EnvironmentLocationAuthorization`, `LocationProvenance`, `LocationTrust`).
- Produces: `LocationProviding.authorization`; `LocationService.provenance`, `.authorization`, `.cachedLocationAt`; `EnvironmentalDataService.locationFreshnessInterval`; `DefaultLocationProvider.coordinate` returns a trusted-only coordinate.

- [ ] **Step 1: Update the protocol + existing stubs (compile-driven, no new test)**

In `HTTPTransport.swift`, replace the `LocationProviding` protocol (`:21-23`):

```swift
public protocol LocationProviding {
    var coordinate: CLLocationCoordinate2D? { get }   // trusted only — nil hides a fabricated fix
    var authorization: EnvironmentLocationAuthorization { get }
}
```

In each of the three test files, extend `StubLocation` to satisfy the new requirement with a trusting default:

```swift
private struct StubLocation: LocationProviding {
    var coordinate: CLLocationCoordinate2D?
    var authorization: EnvironmentLocationAuthorization = .authorized
}
```

(Change `let coordinate` → `var coordinate` and add the `authorization` stored property in `EnvironmentalDataServiceDITests.swift:23`, `WeatherHistoryTests.swift:33`, `AirQualityHistoryTests.swift:130`.)

- [ ] **Step 2: Add provenance + authorization + freshness to `LocationService` and the service**

In `EnvironmentalDataService.swift`, add the freshness constant near the other private constants (after `:74`):

```swift
    /// Trusted-cache window: a cached fix older than this is not ingested (it is
    /// still shown by the legacy display). Matches the existing 300 s location
    /// cadence used elsewhere in `LocationService`.
    static let locationFreshnessInterval: TimeInterval = 300
```

In `LocationService` (starts `:766`), add published/stored members after `@Published var currentLocation` (`:768`):

```swift
    /// Where `currentLocation` came from. Default `.fabricated` so an un-set state
    /// is untrusted (safe default); every real assignment stamps it via `apply(_:provenance:)`.
    @Published private(set) var provenance: LocationProvenance = .fabricated
    /// Epoch of the last DEVICE fix, persisted alongside the cached lat/lon so the
    /// cache's age is knowable. Nil until a device fix has ever landed.
    @AppStorage("lastKnownLocationAt") private var cachedLocationAtEpoch: Double = 0

    var cachedLocationAt: Date? { cachedLocationAtEpoch == 0 ? nil : Date(timeIntervalSince1970: cachedLocationAtEpoch) }

    /// App-level authorization, mapped from the private `CLLocationManager`.
    var authorization: EnvironmentLocationAuthorization {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return .authorized
        case .denied:      return .denied
        case .restricted:  return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:  return .notDetermined
        }
    }

    /// Single choke point for setting `currentLocation` with its provenance, so no
    /// call site can set the coordinate without also declaring where it came from.
    private func apply(_ coordinate: CLLocationCoordinate2D?, provenance: LocationProvenance) {
        self.currentLocation = coordinate
        self.provenance = provenance
    }
```

(The cached-freshness gate lives entirely inside `LocationTrust.trustedCoordinate`, which `DefaultLocationProvider.coordinate` calls directly in Step 4 — `LocationService` needs no separate `trustedCachedCoordinate` member.)

- [ ] **Step 3: Stamp provenance at the nine assignment sites**

Replace each raw `self.currentLocation = …` in `LocationService` with an `apply(_:provenance:)` call:

- Device fix (`:960-964`) — set device provenance AND the timestamp:
```swift
        DispatchQueue.main.async {
            self.apply(newLocation.coordinate, provenance: .device)
            self.cachedLatitude = newLocation.coordinate.latitude
            self.cachedLongitude = newLocation.coordinate.longitude
            self.cachedLocationAtEpoch = Date().timeIntervalSince1970
            if shouldLog { self.lastLoggedLocation = newLocation.coordinate }
            self.locationManager.stopUpdatingLocation()
        }
```
- Timeout fallback (`:884-891`):
```swift
                    if let cached = lastKnownLocation {
                        self.apply(cached, provenance: .cached)
                    } else {
                        self.apply(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), provenance: .fabricated) // NYC
                    }
```
- `handleLocationPermissionDenied` (`:903-908`):
```swift
                if let cached = lastKnownLocation {
                    self.apply(cached, provenance: .cached)
                } else {
                    self.apply(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), provenance: .fabricated) // NYC
                }
```
- `handleLocationDenied` (`:997-1002`):
```swift
            if let cachedLat = cachedLatitude, let cachedLon = cachedLongitude {
                self.apply(CLLocationCoordinate2D(latitude: cachedLat, longitude: cachedLon), provenance: .cached)
            } else {
                self.apply(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), provenance: .fabricated)
            }
```
- `locationManagerDidChangeAuthorization` (`:1026-1031`):
```swift
                if let cachedLat = cachedLatitude, let cachedLon = cachedLongitude {
                    apply(CLLocationCoordinate2D(latitude: cachedLat, longitude: cachedLon), provenance: .cached)
                } else {
                    apply(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), provenance: .fabricated)
                }
```

- [ ] **Step 4: Route `DefaultLocationProvider` through `LocationTrust`; expose authorization**

Replace `DefaultLocationProvider` (`:92-98`):

```swift
    private final class DefaultLocationProvider: LocationProviding {
        private unowned let service: EnvironmentalDataService
        init(service: EnvironmentalDataService) { self.service = service }
        var coordinate: CLLocationCoordinate2D? {
            guard let loc = service.locationManager else { return service.manualLocation }
            return LocationTrust.trustedCoordinate(
                manual: service.manualLocation,
                provenance: loc.provenance,
                deviceCoordinate: loc.currentLocation,
                cachedCoordinate: loc.lastKnownLocation,
                cachedAt: loc.cachedLocationAt,
                authorization: loc.authorization,
                now: service.now(),
                freshness: EnvironmentalDataService.locationFreshnessInterval)
        }
        var authorization: EnvironmentLocationAuthorization {
            service.locationManager?.authorization ?? .notDetermined
        }
    }
```

- [ ] **Step 5: Build + run existing location/DI suites to prove the refactor is behavior-neutral**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentalDataServiceDITests" -only-testing:"Food IntolerancesTests/LocationTrustTests" -parallel-testing-enabled NO`
Expected: PASS. (`fetchDailyForecastWithNoLocationLeavesForecastNil` still holds: a `nil`-coordinate stub is trusted-nil.)

- [ ] **Step 6: Commit**

```bash
git add "HTTPTransport.swift" "EnvironmentalDataService.swift" \
        "Food IntolerancesTests/EnvironmentalDataServiceDITests.swift" \
        "Food IntolerancesTests/WeatherHistoryTests.swift" \
        "Food IntolerancesTests/AirQualityHistoryTests.swift"
git commit -m "feat(env-status): trusted-coordinate seam + LocationService provenance/authorization"
```

---

### Task 6: Backfill result enums + reason classification + cancellation + emitter status

**Files:**
- Modify: `EnvironmentalDataService.swift` — `AQIRangeResult` (`:21-24`), `WeatherDayResult` (`:32-36`); `fetchCompletedAirQualityRange` (`:497-550`); `fetchCompletedWeatherDay` (`:564-608`); add a `locationReason()` helper + `isCancellation(_:)` helper.
- Modify: `Models/EnvironmentalEventEmitter.swift` — `emitIfNeeded` gains `statusStore`; `backfillObservedAQI`/`backfillObservedWeather` handle `.cancelled`/`.fetchError(reason)`, record scope failure, record success after persist.
- Modify: `Food IntolerancesTests/EnvironmentalEmitterTests.swift` — stub `weatherDefault`/`rangeResult` new shapes; add scope + cancellation tests.
- Modify: `Food IntolerancesTests/WeatherHistoryTests.swift`, `AirQualityHistoryTests.swift` — `.fetchError` → `.fetchError(reason)` assertions.

**Interfaces:**
- Consumes: Task 1 (`EnvironmentFailureReason`), Task 2 (`EnvironmentStatusStore`), Task 5 (`authorization`).
- Produces: `AQIRangeResult.fetchError(EnvironmentFailureReason)` + `.cancelled`; `WeatherDayResult.fetchError(EnvironmentFailureReason)` + `.cancelled`; `EnvironmentalEventEmitter.emitIfNeeded(…, statusStore:)`.

- [ ] **Step 1: Write the failing tests (emitter scope + cancellation)**

Add to `Food IntolerancesTests/EnvironmentalEmitterTests.swift`. First, extend the in-file `StubProvider` to script cancellation and carry the new default, and give the tests a status store. Update the stub's weather default and add a range-result helper:

```swift
        // In StubProvider: default weather result now carries a reason.
        var weatherDefault: WeatherDayResult = .fetchError(.badResponse)
```

Also update the two other `.fetchError` literals the reshape breaks (compiler-enforced): the AQI-error test at `EnvironmentalEmitterTests.swift:109` becomes `provider.rangeResult = .fetchError(.badResponse)`. (These sites don't assert on the reason — any reason keeps the abort behavior identical.)

Then add tests (place after `weatherFetchErrorAbortsPassWithoutIngestOrAdvance`). The suite struct is already `@MainActor`, so `status.statuses` is a synchronous access — no `await`:

```swift
    /// A per-day fetchError records ONE observedWeather failure scoped to the whole
    /// intended range (start…yesterday), even though the pass aborts on day 2.
    @Test func weatherFetchErrorRecordsScopeOverWholeIntendedRange() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let status = EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!)
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)   // yesterday = 06-09
        store.set(day(cal, 6, 6), for: weatherDayKey)            // start = 06-07
        stub.weatherByDay = [day(cal, 6, 7): .value(highC: 20, lowC: 10, humidityPct: 50)]
        stub.weatherDefault = .fetchError(.rejected)             // 06-08 fails → abort
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
            now: { now }, calendar: cal, store: store, statusStore: status)
        let f = status.statuses[.observedWeather]?.liveFailure
        #expect(f?.reason == .rejected)
        #expect(f?.scopeStart == day(cal, 6, 7))
        #expect(f?.scopeEnd == day(cal, 6, 9))                   // yesterday, not day-of-abort
        #expect(f?.timezoneID == "UTC")
    }

    /// A cancelled weather day records NOTHING: no status, watermark held.
    @Test func weatherCancelledRecordsNothing() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let status = EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!)
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)
        store.set(day(cal, 6, 7), for: weatherDayKey)
        stub.weatherDefault = .cancelled
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
            now: { now }, calendar: cal, store: store, statusStore: status)
        #expect(status.statuses[.observedWeather] == nil)        // nothing recorded
        #expect(store.date(for: weatherDayKey) == day(cal, 6, 7))
    }

    /// A completed weather pass records observedWeather success.
    @Test func weatherSuccessfulPassRecordsSuccess() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let status = EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!)
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)
        store.set(day(cal, 6, 8), for: weatherDayKey)            // start = 06-09 = yesterday
        stub.weatherByDay = [day(cal, 6, 9): .value(highC: 22, lowC: 11, humidityPct: 55)]
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
            now: { now }, calendar: cal, store: store, statusStore: status)
        #expect(status.statuses[.observedWeather]?.lastSuccess != nil)
        #expect(status.statuses[.observedWeather]?.liveFailure == nil)
    }
```

Note: the pre-existing emitter tests call `emitIfNeeded(...)` without `statusStore`; they keep compiling via the `nil` default and record nothing. Only update `weatherDefault`'s declared default to `.fetchError(.badResponse)` as shown so those tests' abort behavior is unchanged.

- [ ] **Step 2: Update the History/AQI fetch assertions to the new shape**

In `WeatherHistoryTests.swift`, change the four `.fetchError` expectations:
- `transportErrorIsFetchError`: change the stub throw and assertion. In `StubTransport.data(from:)` replace `struct StubError: Error {}; if makeError { throw StubError() }` with `if makeError { throw URLError(.timedOut) }`, and assert `#expect(result == .fetchError(.offline))`.
- `malformedPayloadIsFetchError`: `#expect(result == .fetchError(.badResponse))`.
- `authErrorBodyIsFetchError`: `#expect(result == .fetchError(.rejected))`.
- `noLocationIsFetchError`: `#expect(result == .fetchError(.locationUnavailable))` (nil coordinate, default `.authorized`).

In `AirQualityHistoryTests.swift`:
- In `CountingStubTransport.data(from:)` replace the thrown `StubError` with `throw URLError(.timedOut)`.
- `fetchCompletedAirQualityRangeTransportFailureReturnsFetchError`: `#expect(result == .fetchError(.offline))`.
- `fetchCompletedAirQualityRangeMalformedJSONReturnsFetchError`: `#expect(result == .fetchError(.badResponse))`.
- `fetchCompletedAirQualityRangeWithNoLocationReturnsFetchErrorWithoutTouchingTransport`: `#expect(result == .fetchError(.locationUnavailable))`.

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentalEmitterTests" -only-testing:"Food IntolerancesTests/WeatherHistoryTests" -only-testing:"Food IntolerancesTests/AirQualityHistoryTests" -parallel-testing-enabled NO`
Expected: FAIL — `.fetchError(_:)`, `.cancelled`, and the `statusStore:` parameter don't exist yet.

- [ ] **Step 4: Reshape the enums + classification + emitter**

In `EnvironmentalDataService.swift`, replace the two result enums:

```swift
enum AQIRangeResult: Equatable {
    case fetchError(EnvironmentFailureReason)
    case cancelled
    case days([Date: AQIDayValue])
}

enum WeatherDayResult: Equatable {
    case fetchError(EnvironmentFailureReason)
    case cancelled
    case absent
    case value(highC: Double, lowC: Double, humidityPct: Double?)
}
```

Add two private helpers to `EnvironmentalDataService` (near `resolvedCoordinate()`):

```swift
    /// Cancellation must never be recorded as a failure or a success.
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// The reason to record when there is no trusted coordinate.
    private func locationReason() -> EnvironmentFailureReason {
        switch locationProvider.authorization {
        case .denied, .restricted: return .locationDenied
        default:                   return .locationUnavailable
        }
    }

    /// Maps a thrown error into a reason (used in every fetch's `catch`).
    /// A `URLError` (not cancelled) is a connectivity failure; anything else
    /// reaching the catch is a decode/unexpected-shape failure.
    private func classifyThrown(_ error: Error) -> EnvironmentFailureReason {
        if let urlError = error as? URLError, urlError.code != .cancelled { return .offline }
        return .badResponse
    }
```

(An HTTP-status pre-check, `httpStatusReason`, is added to the three today fetches in Task 8 — it must run *before* decode, since a 401 body decodes to a throw that would otherwise mask the status. The backfill fetches don't need it: a One Call 401 already carries a `message` error body that `fetchCompletedWeatherDay` maps to `.rejected` directly.)

Rewrite `fetchCompletedAirQualityRange` (`:497-550`) guards + catch:

```swift
    func fetchCompletedAirQualityRange(from startDay: Date, through endDay: Date) async -> AQIRangeResult {
        guard let location = self.resolvedCoordinate() else {
            Logger.warning("No location available for air quality range fetch.", category: .location)
            return .fetchError(locationReason())
        }
        // …unchanged requestWindow + URL guard, except the URL-nil return:
        guard let url = APIConfig.airPollutionHistoryURL(/* …unchanged args… */) else {
            Logger.error("Invalid URL for air pollution history API", category: .network)
            return .fetchError(.notConfigured)
        }
        do {
            let (data, _) = try await transport.data(from: url)
            // …unchanged decode + byDay building…
            return .days(byDay)
        } catch {
            if isCancellation(error) { return .cancelled }
            Logger.error(error, message: "Error fetching air quality history range", category: .network)
            return .fetchError(classifyThrown(error))
        }
    }
```

(Keep the existing body between the guards verbatim; only the three `return` sites and the `catch` change.)

Rewrite `fetchCompletedWeatherDay` (`:564-608`) guards + error-body + catch:

```swift
    func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult {
        guard let location = self.resolvedCoordinate() else {
            Logger.warning("No location available for weather day fetch.", category: .location)
            return .fetchError(locationReason())
        }
        // …unchanged tz/date formatting…
        guard let url = APIConfig.oneCallDaySummaryURL(/* …unchanged args… */) else {
            Logger.error("Invalid URL for One Call day_summary API", category: .network)
            return .fetchError(.notConfigured)
        }
        do {
            let (data, _) = try await transport.data(from: url)
            let decoded = try JSONDecoder().decode(DaySummaryResponse.self, from: data)
            guard let high = decoded.temperature?.max, let low = decoded.temperature?.min else {
                if let errorBody = try? JSONDecoder().decode(OneCallErrorBody.self, from: data) {
                    Logger.error("One Call day_summary error body: \(errorBody.message)", category: .network)
                    return .fetchError(.rejected)   // 401 not-subscribed / bad key — retryable, never absent
                }
                return .absent
            }
            return .value(highC: high, lowC: low, humidityPct: decoded.humidity?.afternoon)
        } catch {
            if isCancellation(error) { return .cancelled }
            Logger.error(error, message: "Error fetching weather day summary", category: .network)
            return .fetchError(classifyThrown(error))
        }
    }
```

In `Models/EnvironmentalEventEmitter.swift`, thread the status store and handle the new cases.

Change `emitIfNeeded` signature + the two backfill calls (`:84-118`):

```swift
    @MainActor
    static func emitIfNeeded(database: AppDatabase = HealthGraphProvider.shared,
                             service: EnvironmentalDataProviding,
                             now: @escaping () -> Date = Date.init,
                             calendar: Calendar = defaultCalendar(),
                             store: WatermarkStore = UserDefaultsWatermarkStore(),
                             statusStore: EnvironmentStatusStore? = nil) async {
        // …unchanged today-emit block…
        await backfillObservedAQI(pipeline: pipeline, service: service, now: now, calendar: calendar, store: store, tz: tz, statusStore: statusStore)
        await backfillObservedWeather(pipeline: pipeline, service: service, now: now, calendar: calendar, store: store, tz: tz, statusStore: statusStore)
    }
```

**Why `statusStore` is `EnvironmentStatusStore?` (nil default), not a defaulted instance:** `EnvironmentStatusStore` is `@MainActor`, so a `= EnvironmentStatusStore()` default argument would be *constructed at each call site in that caller's isolation*. The pre-existing emitter tests (and the non-`@MainActor` `WeatherHistoryTests`/`AirQualityHistoryTests`/`EnvironmentalDataServiceDITests` that construct the service, Task 8) are nonisolated — evaluating a `@MainActor` initializer there does not compile. A `nil` default constructs nothing; recording is done through optional chaining, and the App passes the one real store (Task 9). This also means the pre-existing tests record nothing (no `.standard` pollution) instead of writing to a throwaway store.

In `backfillObservedAQI` (`:122-179`), give it the `statusStore` param and replace the range switch:

```swift
    private static func backfillObservedAQI(pipeline: IngestPipeline, service: EnvironmentalDataProviding,
                                            now: () -> Date, calendar: Calendar,
                                            store: WatermarkStore, tz: String,
                                            statusStore: EnvironmentStatusStore?) async {
        // …unchanged watermark/start/throttle up to the fetch…
        let byDay: [Date: AQIDayValue]
        switch await service.fetchCompletedAirQualityRange(from: start, through: yesterday) {
        case .cancelled:
            return                                     // no status, watermark held
        case .fetchError(let reason):
            statusStore?.recordFailure(.observedAirQuality, reason: reason,
                                       scopeStart: start, scopeEnd: yesterday, timezoneID: tz, at: now())
            return
        case .days(let d):
            byDay = d
        }
        // …unchanged emit loop over byDay…
        do {
            if !aqiEvents.isEmpty { _ = try await pipeline.ingest(aqiEvents) }
            if let nw = newWatermark { store.set(nw, for: lastAQIDayKey) }
            statusStore?.recordSuccess(.observedAirQuality, at: now())   // full pass persisted
        } catch {
            Logger.info("Environmental AQI backfill ingest failed; watermark held for retry", category: .data)
        }
    }
```

In `backfillObservedWeather` (`:187-236`), capture the intended range, handle the loop cases, record success after persist:

```swift
    private static func backfillObservedWeather(pipeline: IngestPipeline, service: EnvironmentalDataProviding,
                                                now: () -> Date, calendar: Calendar,
                                                store: WatermarkStore, tz: String,
                                                statusStore: EnvironmentStatusStore?) async {
        // …unchanged watermark/start/throttle…
        let scopeStart = start, scopeEnd = yesterday    // intended range, captured before the loop
        // …unchanged newWatermark/contiguous/weatherEvents setup + emitObservedWeather closure…
        var D = start
        while D <= yesterday {
            switch await service.fetchCompletedWeatherDay(for: D) {
            case .cancelled:
                return                                   // no status, nothing ingested, watermark held
            case .fetchError(let reason):
                statusStore?.recordFailure(.observedWeather, reason: reason,
                                           scopeStart: scopeStart, scopeEnd: scopeEnd, timezoneID: tz, at: now())
                return                                   // abort whole pass
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
            if !weatherEvents.isEmpty { _ = try await pipeline.ingest(weatherEvents) }
            if let nw = newWatermark { store.set(nw, for: lastWeatherDayKey) }
            statusStore?.recordSuccess(.observedWeather, at: now())   // full pass persisted
        } catch {
            Logger.info("Environmental weather backfill ingest failed; watermark held for retry", category: .data)
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentalEmitterTests" -only-testing:"Food IntolerancesTests/WeatherHistoryTests" -only-testing:"Food IntolerancesTests/AirQualityHistoryTests" -parallel-testing-enabled NO`
Expected: PASS — new scope/cancellation/success tests green; the reshaped `.fetchError(reason)` assertions green; every pre-existing emitter test still green.

- [ ] **Step 6: Commit**

```bash
git add "EnvironmentalDataService.swift" "Models/EnvironmentalEventEmitter.swift" \
        "Food IntolerancesTests/EnvironmentalEmitterTests.swift" \
        "Food IntolerancesTests/WeatherHistoryTests.swift" \
        "Food IntolerancesTests/AirQualityHistoryTests.swift"
git commit -m "feat(env-status): backfill failure reasons, .cancelled, scoped status recording"
```

---

### Task 7: Pressure trust separation

**Files:**
- Modify: `EnvironmentalDataService.swift` — new pressure state + `recordGenuinePressure`/`clearFetchedPressure`; `fetchAtmosphericPressure` success/fallback; `useFallbackPressureData` (`:618`), `setFallbackAtmosphericPressure` (`:686`), `updateAtmosphericPressure` (`:647`).
- Modify: `Models/EnvironmentalEventEmitter.swift` — `EnvironmentalDataProviding` pressure props → optionals (`:8-17`); today reading construction (`:99-109`).
- Modify: `Food IntolerancesTests/EnvironmentalEmitterTests.swift` — `StubProvider` pressure props → optionals.
- Test: `Food IntolerancesTests/PressureTrustTests.swift`

**Interfaces:**
- Consumes: prior tasks.
- Produces: `EnvironmentalDataService.latestFetchedPressure: Double?`, `.lastTrustedPressure: Double?`, `recordGenuinePressure(_ value: Double, at: Date)`; `EnvironmentalDataProviding` now declares `var latestFetchedPressure: Double? { get }` / `var lastTrustedPressure: Double? { get }`.

- [ ] **Step 1: Write the failing tests**

Create `Food IntolerancesTests/PressureTrustTests.swift`:

```swift
import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct PressureTrustTests {
    private let t = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Service-side carry/time-gate (recordGenuinePressure)

    @Test func firstGenuineReadingHasNoTrustedPrevious() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1010, at: t)
        #expect(s.latestFetchedPressure == 1010)
        #expect(s.lastTrustedPressure == nil)           // no prior carry
    }
    @Test func secondGenuineWithinWindowExposesPreviousAndComputesDrop() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        s.recordGenuinePressure(1006, at: t.addingTimeInterval(600))   // 10 min later, 7 hPa fall
        #expect(s.latestFetchedPressure == 1006)
        #expect(s.lastTrustedPressure == 1013)
        #expect(s.suddenPressureChange == true)
    }
    @Test func genuineAfterFallbackDoesNotFabricateDrop() {
        let s = EnvironmentalDataService()
        s.useFallbackPressureData()                      // 1013 legacy fallback — not genuine
        s.recordGenuinePressure(1006, at: t)             // first genuine → no prior carry
        #expect(s.latestFetchedPressure == 1006)
        #expect(s.lastTrustedPressure == nil)            // no fabricated 7 hPa drop
    }
    @Test func twoGenuineReadingsBeyondWindowEmitNoDrop() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        s.recordGenuinePressure(1006, at: t.addingTimeInterval(7200))  // 2 h later > 1 h window
        #expect(s.lastTrustedPressure == nil)            // stale prior → not comparable
        #expect(s.suddenPressureChange == false)
    }
    @Test func thirdConsecutiveGenuineStillExposesAPrevious() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        s.recordGenuinePressure(1012, at: t.addingTimeInterval(300))
        s.recordGenuinePressure(1005, at: t.addingTimeInterval(600))   // carry regression guard
        #expect(s.lastTrustedPressure == 1012)           // NOT equal to latest → drop still possible
        #expect(s.suddenPressureChange == true)
    }
    @Test func setFallbackRouteDoesNotContaminateCarry() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        s.setFallbackAtmosphericPressure()               // cached/fabricated route
        s.recordGenuinePressure(1006, at: t.addingTimeInterval(7200))  // > window → no drop off the stale genuine
        #expect(s.lastTrustedPressure == nil)
    }

    // MARK: Emitter-side (protocol optionals → factory)

    private final class PressureStub: EnvironmentalDataProviding, @unchecked Sendable {
        var latestFetchedPressure: Double?
        var lastTrustedPressure: Double?
        var forecastHighC: Double?; var forecastLowC: Double?; var forecastHumidity: Double?
        func requestRefreshWithCooldown() async -> Bool { true }
        func fetchCompletedAirQualityRange(from: Date, through: Date) async -> AQIRangeResult { .days([:]) }
        func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult { .cancelled }
    }
    private func utc() -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private final class MemStore: WatermarkStore, @unchecked Sendable {
        private var s: [String: Date] = [:]
        func date(for key: String) -> Date? { s[key] }
        func set(_ date: Date, for key: String) { s[key] = date }
    }
    private func pressureEvents(_ db: AppDatabase) async throws -> [HealthEvent] {
        try await GRDBEventStore(database: db).recentEvents(limit: 1000)
            .filter { $0.subtype == "pressure" || $0.subtype == "pressureDrop" }
    }

    @Test func emitterEmitsNoPressureWhenLatestNil() async throws {
        let cal = utc(); let now = cal.date(from: DateComponents(year: 2025, month: 6, day: 11))!.addingTimeInterval(36_000)
        let db = try AppDatabase.inMemory()
        let stub = PressureStub()   // latestFetchedPressure nil (a failed/absent fetch)
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub, now: { now }, calendar: cal,
            store: MemStore(), statusStore: EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!))
        #expect(try await pressureEvents(db).isEmpty)
    }
    @Test func emitterEmitsNoDropWhenPreviousNil() async throws {
        let cal = utc(); let now = cal.date(from: DateComponents(year: 2025, month: 6, day: 11))!.addingTimeInterval(36_000)
        let db = try AppDatabase.inMemory()
        let stub = PressureStub(); stub.latestFetchedPressure = 1006; stub.lastTrustedPressure = nil
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub, now: { now }, calendar: cal,
            store: MemStore(), statusStore: EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!))
        let events = try await pressureEvents(db)
        #expect(events.contains { $0.subtype == "pressure" })
        #expect(!events.contains { $0.subtype == "pressureDrop" })   // no fabricated drop
    }
    @Test func emitterEmitsRealDropWhenPreviousPresent() async throws {
        let cal = utc(); let now = cal.date(from: DateComponents(year: 2025, month: 6, day: 11))!.addingTimeInterval(36_000)
        let db = try AppDatabase.inMemory()
        let stub = PressureStub(); stub.latestFetchedPressure = 1006; stub.lastTrustedPressure = 1013
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub, now: { now }, calendar: cal,
            store: MemStore(), statusStore: EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!))
        #expect(try await pressureEvents(db).contains { $0.subtype == "pressureDrop" && ($0.value ?? 0) >= 6 })
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/PressureTrustTests" -parallel-testing-enabled NO`
Expected: FAIL — `recordGenuinePressure`, `latestFetchedPressure`, `lastTrustedPressure` undefined; the `PressureStub` doesn't satisfy the (still old) protocol.

- [ ] **Step 3: Change the protocol + emitter reading construction**

In `Models/EnvironmentalEventEmitter.swift`, replace the pressure requirements in `EnvironmentalDataProviding` (`:8-17`):

```swift
protocol EnvironmentalDataProviding {
    var latestFetchedPressure: Double? { get }   // this refresh's genuine reading; nil on failure/fallback
    var lastTrustedPressure: Double? { get }      // prior genuine reading, only if recent enough to compare
    var forecastHighC: Double? { get }
    var forecastLowC: Double? { get }
    var forecastHumidity: Double? { get }
    func requestRefreshWithCooldown() async -> Bool
    func fetchCompletedAirQualityRange(from: Date, through: Date) async -> AQIRangeResult
    func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult
}
```

Replace the today reading's pressure fields (`:99-109`) — drop the `> 0` sentinel:

```swift
        let todayReading = EnvironmentalReading(
            date: today,
            pressureHPa: service.latestFetchedPressure,
            previousPressureHPa: service.lastTrustedPressure,
            moonPhaseName: getMoonPhase(for: today),
            isMercuryRetrograde: MercuryRetrograde.isRetrograde(on: today),
            timezoneID: tz,
            temperatureHighC: service.forecastHighC,
            temperatureLowC: service.forecastLowC,
            humidityPct: service.forecastHumidity,
            airQualityAQI: nil)
```

Update the in-file `StubProvider` in `EnvironmentalEmitterTests.swift` (`:23-27`): replace `var currentPressure: Double = 1015` / `var previousPressure: Double = 1015` with:

```swift
        var latestFetchedPressure: Double? = 1015
        var lastTrustedPressure: Double? = nil
```

- [ ] **Step 4: Add the time-stamped carry to the service**

In `EnvironmentalDataService.swift`, add stored state near the pressure privates (`:66-69`):

```swift
    /// The emitter's inputs. `latestFetchedPressure` is this refresh's genuine
    /// reading (nil on failure/fallback). `lastTrustedPressure` is the prior
    /// genuine reading, exposed only when recent enough to compare.
    @Published private(set) var latestFetchedPressure: Double? = nil
    @Published private(set) var lastTrustedPressure: Double? = nil
    /// The last genuine API reading + when it landed. Never cleared at refresh
    /// start, never written by a fallback/cancellation — the carry that makes the
    /// previous/current shift correct across refreshes.
    private var mostRecentGenuinePressure: (value: Double, at: Date)? = nil
```

Add the two record methods (near `updateAtmosphericPressure`, `:647`):

```swift
    /// Record a genuine API pressure reading: shift the carry, expose the prior
    /// genuine value ONLY if within `pressureReadingInterval`, and set the legacy
    /// sudden-change flag off that gated comparison. This is the sole writer of
    /// `latestFetchedPressure`/`lastTrustedPressure`/`mostRecentGenuinePressure`.
    func recordGenuinePressure(_ value: Double, at: Date) {
        let prior = mostRecentGenuinePressure
        let comparable = prior.map { at.timeIntervalSince($0.at) <= pressureReadingInterval } ?? false
        lastTrustedPressure = comparable ? prior?.value : nil
        suddenPressureChange = comparable ? (abs((prior!.value) - value) >= pressureChangeThreshold) : false
        mostRecentGenuinePressure = (value, at)
        latestFetchedPressure = value
    }

    /// Clear the fetched reading at the start of a genuine refresh, so a cancelled
    /// refresh leaves nothing for the emitter to restamp. Carry untouched.
    func clearFetchedPressure() { latestFetchedPressure = nil }
```

In `fetchAtmosphericPressure` (`:279-334`): at the start of the genuine attempt (right after the "Loading…" set, before the network call) call `await MainActor.run { self.clearFetchedPressure() }`. In the success `MainActor.run` block (`:322-329`) — after the existing legacy display assignments — add `self.recordGenuinePressure(pressureValue, at: self.now())`. In the `catch` fallback (`:332`) leave `useFallbackPressureData()` only (it must NOT record genuine).

Make the fallbacks legacy-display-only. In `useFallbackPressureData()` (`:618-633`) and `setFallbackAtmosphericPressure()` (`:686-715`): keep every existing assignment to `atmosphericPressure`/`atmosphericPressureCategory`/`currentPressure`/`previousPressure`/`suddenPressureChange`, but do NOT call `recordGenuinePressure` and do NOT touch `latestFetchedPressure`/`mostRecentGenuinePressure`. `setFallbackAtmosphericPressure` currently routes through `updateAtmosphericPressure` — that's fine as long as `updateAtmosphericPressure` no longer writes the carry (next paragraph).

Refactor `updateAtmosphericPressure` (`:647-684`): it stays the owner of the LEGACY display fields (`pressureReadings`, `currentPressure`, `previousPressure`, `atmosphericPressureCategory`, and the legacy `suddenPressureChange` it computes for the legacy card). It must NOT write `latestFetchedPressure`, `lastTrustedPressure`, or `mostRecentGenuinePressure`. The genuine carry + the emitter-facing `suddenPressureChange` are owned solely by `recordGenuinePressure`. (Net: the legacy card behaves exactly as before; the emitter reads only the carry-gated optionals.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/PressureTrustTests" -only-testing:"Food IntolerancesTests/EnvironmentalEmitterTests" -parallel-testing-enabled NO`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add "EnvironmentalDataService.swift" "Models/EnvironmentalEventEmitter.swift" \
        "Food IntolerancesTests/EnvironmentalEmitterTests.swift" "Food IntolerancesTests/PressureTrustTests.swift"
git commit -m "feat(env-status): time-stamped genuine-pressure carry; fallbacks stop poisoning the drop delta"
```

---

### Task 8: Today-capability classification + status writes

**Files:**
- Modify: `EnvironmentalDataService.swift` — `init` gains `statusStore`; `fetchAtmosphericPressure`, `fetchDailyForecast`, `fetchAirQuality` record success/failure with today scope; response status inspection.
- Test: `Food IntolerancesTests/EnvironmentFailureClassificationTests.swift`

**Interfaces:**
- Consumes: Task 2 store, Task 5 authorization, Task 6 `failureReason`/`locationReason`/`isCancellation`.
- Produces: `EnvironmentalDataService(…, statusStore: EnvironmentStatusStore? = nil)`; today-scoped `recordSuccess`/`recordFailure` on the three fetches.

- [ ] **Step 1: Write the failing tests**

Create `Food IntolerancesTests/EnvironmentFailureClassificationTests.swift`:

```swift
import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

@MainActor
struct EnvironmentFailureClassificationTests {
    private func store() -> EnvironmentStatusStore { EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!) }
    private func key() { setenv("OPENWEATHER_API_KEY", "cls-test-key", 1) }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private struct StatusTransport: HTTPTransport {
        let payload: Data
        let status: Int?          // nil → plain URLResponse (no HTTP status)
        let error: Error?
        func data(from url: URL) async throws -> (Data, URLResponse) {
            if let error { throw error }
            let response: URLResponse = status.map {
                HTTPURLResponse(url: url, statusCode: $0, httpVersion: nil, headerFields: nil)!
            } ?? URLResponse(url: url, mimeType: "application/json", expectedContentLength: payload.count, textEncodingName: "utf-8")
            return (payload, response)
        }
    }
    private struct StubLocation: LocationProviding {
        var coordinate: CLLocationCoordinate2D?
        var authorization: EnvironmentLocationAuthorization = .authorized
    }
    private func forecastJSON(_ base: TimeInterval, slots: Int = 3) -> Data {
        let items = (0..<slots).map { #"{"dt": \#(base + Double($0) * 3600), "main": {"temp": 12, "humidity": 50}}"# }
        return Data(("{\"list\":[" + items.joined(separator: ",") + "]}").utf8)
    }

    @Test func forecast401RecordsRejected() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: Data("{}".utf8), status: 401, error: nil),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure?.reason == .rejected)
    }
    @Test func forecastOfflineRecordsOffline() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: Data(), status: nil, error: URLError(.notConnectedToInternet)),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure?.reason == .offline)
    }
    @Test func forecastThinResponseRecordsInsufficientDataScopedToday() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: forecastJSON(self.at.timeIntervalSince1970, slots: 2), status: 200, error: nil),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        let f = s.statuses[.forecastWeather]?.liveFailure
        #expect(f?.reason == .insufficientData)
        #expect(f?.scopeStart == utc.startOfDay(for: at))
        #expect(f?.scopeEnd == utc.startOfDay(for: at))
        #expect(f?.timezoneID == "UTC")
    }
    @Test func forecastSuccessRecordsSuccessAndClearsLive() async {
        key()
        let s = store()
        s.recordFailure(.forecastWeather, reason: .offline, scopeStart: at, scopeEnd: at, timezoneID: "UTC", at: at)
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: forecastJSON(self.at.timeIntervalSince1970), status: 200, error: nil),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure == nil)
        #expect(s.statuses[.forecastWeather]?.lastSuccess == at)
    }
    @Test func forecastDeniedLocationRecordsLocationDenied() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: Data(), status: nil, error: nil),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: nil, authorization: .denied), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure?.reason == .locationDenied)
    }
    @Test func forecastUnavailableLocationRecordsLocationUnavailable() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: Data(), status: nil, error: nil),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: nil, authorization: .authorized), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure?.reason == .locationUnavailable)
    }
    // NOTE: `.notConfigured` (URL-nil) is intentionally NOT unit-tested. Forcing the
    // URL to nil requires the API key to be absent, but `APIConfig.openWeatherAPIKey`
    // reads the built bundle's Info.plist FIRST — which carries a real key whenever
    // Secrets.xcconfig is present — so `setenv("…","")` can't reliably force nil. The
    // `.notConfigured` code path (URL guard → recordTodayFailure) is trivial and is
    // confirmed by the device pass (a keyless build shows the marker + Health reason).
    @Test func forecastCancellationRecordsNothing() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: Data(), status: nil, error: URLError(.cancelled)),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather] == nil)   // no write at all
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentFailureClassificationTests" -parallel-testing-enabled NO`
Expected: FAIL — the `statusStore:` init parameter doesn't exist; no status is recorded by `fetchDailyForecast`.

- [ ] **Step 3: Inject the store + record today status in the three fetches**

In `EnvironmentalDataService.swift`, add a stored `statusStore` and an init parameter. Add near the DI seams (`:81-84`):

```swift
    private let statusStore: EnvironmentStatusStore?
```

Add the parameter to `init` (`:100-104`) — **optional, `nil` default** (`EnvironmentStatusStore` is `@MainActor`; a constructed default argument would not compile at the non-`@MainActor` call sites in `WeatherHistoryTests`/`AirQualityHistoryTests`/`EnvironmentalDataServiceDITests`). The App passes the one real store (Task 9); tests that assert on status pass their own; everything else records nothing:

```swift
    init(locationManager: LocationService? = nil,
         transport: HTTPTransport = URLSession.shared,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }(),
         location: LocationProviding? = nil,
         statusStore: EnvironmentStatusStore? = nil) {
        self.transport = transport
        self.now = now
        self.calendar = calendar
        self.injectedLocation = location
        self.statusStore = statusStore
        // …unchanged locationManager assignment…
    }
```

Add a today-scope helper, the HTTP-status pre-check, and record helpers (near `locationReason()`). The record helpers `guard let` the optional store, so a nil store is a no-op:

```swift
    private func todayScope() -> (start: Date, end: Date, tz: String) {
        let d = calendar.startOfDay(for: now())
        return (d, d, calendar.timeZone.identifier)
    }
    /// A non-2xx HTTP status → a reason, checked BEFORE decode (a 401 body
    /// decodes to a throw that would otherwise be miscounted as `.badResponse`).
    /// nil for 2xx or a non-`HTTPURLResponse` stub (no status info → proceed).
    private func httpStatusReason(_ response: URLResponse?) -> EnvironmentFailureReason? {
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 || http.statusCode == 403 { return .rejected }
        if !(200...299).contains(http.statusCode) { return .badResponse }
        return nil
    }
    @MainActor private func recordTodaySuccess(_ capability: EnvironmentCapability) {
        guard let statusStore else { return }
        statusStore.recordSuccess(capability, at: now())
    }
    @MainActor private func recordTodayFailure(_ capability: EnvironmentCapability, _ reason: EnvironmentFailureReason) {
        guard let statusStore else { return }
        let s = todayScope()
        statusStore.recordFailure(capability, reason: reason, scopeStart: s.start, scopeEnd: s.end, timezoneID: s.tz, at: now())
    }
```

Wire the three fetches (each already hops to `MainActor.run` for its publishes; record inside those hops):

**`fetchAtmosphericPressure` (`:279-334`)** — `.currentPressure`:
- No trusted coordinate guard (`:303-307`): before returning, `await MainActor.run { self.recordTodayFailure(.currentPressure, self.locationReason()) }`.
- URL-nil guard (`:309-312`): `await MainActor.run { self.recordTodayFailure(.currentPressure, .notConfigured) }` before `return`.
- Change `let (data, _) = try await self.transport.data(from: url)` → `let (data, response) = …`, then immediately: `if let reason = httpStatusReason(response) { await MainActor.run { self.recordTodayFailure(.currentPressure, reason); self.useFallbackPressureData() }; return }` (before decode).
- Success block (`:322-329`): after the existing assignments + `recordGenuinePressure`, add `self.recordTodaySuccess(.currentPressure)`.
- `catch` (`:330-333`): `if !self.isCancellation(error) { await MainActor.run { self.recordTodayFailure(.currentPressure, self.classifyThrown(error)) } }` — then the existing `useFallbackPressureData()`.

**`fetchDailyForecast` (`:356-398`)** — `.forecastWeather`:
- No-location branch (`:358-366`): before the `MainActor.run`, `await MainActor.run { self.recordTodayFailure(.forecastWeather, self.locationReason()) }` (keep the existing nil-forecast reset).
- URL-nil (`:368-371`): `await MainActor.run { self.recordTodayFailure(.forecastWeather, .notConfigured) }` before `return`.
- Change `let (data, _) = try await transport.data(from: url)` → `let (data, response) = …`, then before decode: `if let reason = httpStatusReason(response) { await MainActor.run { self.forecastHighC = nil; self.forecastLowC = nil; self.forecastHumidity = nil; self.recordTodayFailure(.forecastWeather, reason) }; return }`.
- After computing `aggregate` (`:381`): if `aggregate == nil`, record `insufficientData`; else record success. In the success `MainActor.run` (`:385-389`):
```swift
            await MainActor.run {
                self.forecastHighC = high
                self.forecastLowC = low
                self.forecastHumidity = humidity
                if aggregate == nil { self.recordTodayFailure(.forecastWeather, .insufficientData) }
                else { self.recordTodaySuccess(.forecastWeather) }
            }
```
- `catch` (`:390-397`): `if !self.isCancellation(error) { await MainActor.run { self.recordTodayFailure(.forecastWeather, self.classifyThrown(error)) } }`. Keep the existing nil-forecast reset.

**`fetchAirQuality` (`:415-449`)** — `.forecastAirQuality`, same structure (no-location → `locationReason`; URL-nil → `notConfigured`; `let (data, response)` + `httpStatusReason` pre-check with `forecastAQI = nil` on failure; `mean == nil` → `insufficientData` else success; `catch` non-cancellation → `classifyThrown(error)`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:"Food IntolerancesTests/EnvironmentFailureClassificationTests" -only-testing:"Food IntolerancesTests/EnvironmentalDataServiceDITests" -parallel-testing-enabled NO`
Expected: PASS. (The DI tests' forecast-success paths now also record success — still green because they only assert on `forecastHighC/Low/Humidity`.)

- [ ] **Step 5: Commit**

```bash
git add "EnvironmentalDataService.swift" "Food IntolerancesTests/EnvironmentFailureClassificationTests.swift"
git commit -m "feat(env-status): today-capability fetch-health classification + status writes"
```

---

### Task 9: App wiring — one shared store

**Files:**
- Modify: `FoodIntolerancesApp.swift` (`:12-13`, `:24-44`, `:91-127`)

**Interfaces:**
- Consumes: `EnvironmentStatusStore`, `EnvironmentalDataService(statusStore:)`, `emitIfNeeded(statusStore:)`.
- Produces: one store injected into the service, the emitter call, and the view tree.

- [ ] **Step 1: Thread one store instance via `init()`**

Replace the two `@StateObject` declarations (`:12-13`) and construct them in `init` (matching the existing redFlag pattern at `:36-38`). Add the store property:

```swift
    @StateObject private var logItemViewModel = LogItemViewModel()
    @StateObject private var environmentStatusStore: EnvironmentStatusStore
    @StateObject private var environmentalService: EnvironmentalDataService
```

In `init()` (after the redFlag block, before `setupGlobalErrorHandling()`):

```swift
        let statusStore = EnvironmentStatusStore()
        _environmentStatusStore = StateObject(wrappedValue: statusStore)
        _environmentalService = StateObject(wrappedValue:
            EnvironmentalDataService(locationManager: LocationService(), statusStore: statusStore))
```

(`EnvironmentStatusStore` and `EnvironmentalDataService.init` are `@MainActor`; App `init` runs on the main actor, so this is valid.)

- [ ] **Step 2: Provide the store to the view tree + emitter**

In `body` (`:95-100`), add the environment object after the existing ones:

```swift
                .environmentObject(environmentStatusStore)
```

Update both `emitIfNeeded` calls (`:122`, `:125`) to pass the store:

```swift
                .task { await EnvironmentalEventEmitter.emitIfNeeded(service: environmentalService, statusStore: environmentStatusStore) }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await EnvironmentalEventEmitter.emitIfNeeded(service: environmentalService, statusStore: environmentStatusStore) }
                }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add "FoodIntolerancesApp.swift"
git commit -m "feat(env-status): create one EnvironmentStatusStore and thread it to service, emitter, and views"
```

---

### Task 10: Timeline marker

**Files:**
- Modify: `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift` (`:8-92`)
- Modify: `Views/HealthOS/Timeline/TimelineView.swift` (`:16-17` add store; `:162-169` resolve + pass gap)
- Modify: `Views/HealthOS/Shell/HealthOSRootView.swift` (`:55-70` inject the store into both previews, since they mount `TimelineView`)

**Interfaces:**
- Consumes: Task 3 (`EnvironmentGap`, `EnvironmentGapResolver`), Task 2 store from the environment.
- Produces: `EnvironmentSummaryRow(summary:gap:isExpanded:onToggle:)`.

- [ ] **Step 1: Add the `gap` parameter + muted sub-line to the row**

In `EnvironmentSummaryRow.swift`, add the stored property after `let summary` (`:9`):

```swift
    var gap: EnvironmentGap? = nil
```

Wrap the existing trailing headline block (`:50-65`) in a `VStack(alignment: .trailing, spacing: 2)` and append the marker line. Replace lines `:50-65` with:

```swift
                    VStack(alignment: .trailing, spacing: 2) {
                        if let aqi = headlineResult.aqi {
                            AQIValueLabel(value: headline, aqi: aqi)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                                .multilineTextAlignment(.trailing)
                        } else if let phase = headlineResult.moonPhase {
                            MoonPhaseLabel(value: headline, phase: phase)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                                .multilineTextAlignment(.trailing)
                        } else {
                            Text(headline)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                                .multilineTextAlignment(.trailing)
                        }
                        if let gap {
                            Text(gap.label)                    // status, not warning: caption, muted, no color/icon
                                .font(.caption2)
                                .foregroundStyle(HealthTheme.inkMuted)
                                .multilineTextAlignment(.trailing)
                        }
                    }
```

Extend the a11y label (`:79`) to include the marker:

```swift
            .accessibilityLabel(gap == nil ? "Environment, \(headline)" : "Environment, \(headline), \(gap!.label.lowercased())")
```

- [ ] **Step 2: Resolve + pass the gap from `TimelineView`**

In `TimelineView.swift`, add the store to the view (after `:17`):

```swift
    @EnvironmentObject private var statusStore: EnvironmentStatusStore
```

At the `.environmentSummary` case (`:162-169`), compute the gap and pass it:

```swift
                        case .environmentSummary(let summary):
                            EnvironmentSummaryRow(
                                summary: summary,
                                gap: EnvironmentGapResolver.gap(for: summary, status: statusStore.statuses),
                                isExpanded: expandedEnvironment.contains(summary.id)) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if expandedEnvironment.contains(summary.id) { expandedEnvironment.remove(summary.id) }
                                    else { expandedEnvironment.insert(summary.id) }
                                }
                            }
```

- [ ] **Step 3: Inject the store into the previews that now mount `TimelineView`**

`TimelineView` now reads `@EnvironmentObject var statusStore` — a missing environment object compiles but **crashes at render**, so every preview that mounts `TimelineView` needs the store. Add `.environmentObject(EnvironmentStatusStore(defaults: UserDefaults(suiteName: "preview")!))` to **both `HealthOSRootView` previews** (`Views/HealthOS/Shell/HealthOSRootView.swift:55-70`, which mount `TimelineView` via the tab shell). Any `EnvironmentSummaryRow(...)` preview needs no change (its `gap` default is `nil` and it takes no environment object).

- [ ] **Step 4: Build + run the resolver suite (unchanged) to confirm no regression**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Timeline/EnvironmentSummaryRow.swift" "Views/HealthOS/Timeline/TimelineView.swift" \
        "Views/HealthOS/Shell/HealthOSRootView.swift"
git commit -m "feat(env-status): muted Weather/Air quality unavailable Timeline sub-line"
```

---

### Task 11: Health tab "Data sources" card + detail screen

**Files:**
- Create: `Views/HealthOS/Health/EnvironmentStatusView.swift`
- Modify: `Views/HealthOS/Health/HealthTabView.swift` (`:8-11` add store; `:72-73` insert card above the Safety/Temperature/Units card)

**Interfaces:**
- Consumes: Task 4 (`EnvironmentStatusPresentation`), Task 2 store from the environment.
- Produces: the Health summary row + `EnvironmentStatusView`.

- [ ] **Step 1: Build the detail screen over the presentation type**

Create `Views/HealthOS/Health/EnvironmentStatusView.swift`:

```swift
import SwiftUI
import UIKit

/// The "Environment data" detail screen: five per-capability rows grouped into
/// Weather / Air quality, then a live-or-resolved explanation. All strings come
/// from the pure `EnvironmentStatusPresentation`.
struct EnvironmentStatusView: View {
    @EnvironmentObject private var statusStore: EnvironmentStatusStore

    private var rows: [EnvironmentStatusPresentation.Row] { EnvironmentStatusPresentation.rows(statusStore.statuses) }
    private var explanation: EnvironmentStatusPresentation.Explanation? { EnvironmentStatusPresentation.explanation(statusStore.statuses) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Environment data")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                section("Weather", rows.filter { $0.section == .weather })
                section("Air quality", rows.filter { $0.section == .airQuality })
                if let explanation { explanationCard(explanation) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
    }

    private func section(_ title: String, _ rows: [EnvironmentStatusPresentation.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.caption).foregroundStyle(HealthTheme.inkMuted)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                HStack {
                    Text(row.title).font(.body).foregroundStyle(HealthTheme.ink)
                    Spacer()
                    Text(statusText(row.status)).font(.footnote).foregroundStyle(HealthTheme.inkMuted)
                }
                .padding(16)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.title), \(statusText(row.status))")
                if idx != rows.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .hgCard()
    }

    private func statusText(_ status: EnvironmentStatusPresentation.RowStatus) -> String {
        switch status {
        case .unavailable:        return "Unavailable"
        case .notChecked:         return "Not checked yet"
        case .updated(let date):  return "Updated \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    private func explanationCard(_ e: EnvironmentStatusPresentation.Explanation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(e.heading.uppercased())
                .font(.caption).foregroundStyle(HealthTheme.inkMuted)
            Text(e.body).font(.subheadline).foregroundStyle(HealthTheme.inkSecondary)
            if e.showOpenSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HealthTheme.accent)
                .frame(minHeight: 44)
                .accessibilityHint("Opens this app's settings to enable location")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
    }
}
```

- [ ] **Step 2: Add the summary row + NavigationLink to `HealthTabView`**

In `HealthTabView.swift`, add the store (after `:10`):

```swift
    @EnvironmentObject private var statusStore: EnvironmentStatusStore
```

Add a summary-text helper (near `tempUnitBinding`):

```swift
    private var environmentSummaryText: String {
        switch EnvironmentStatusPresentation.summary(statusStore.statuses) {
        case .unavailable(let phrase): return phrase
        case .notChecked:              return "Not checked yet"
        case .updated(let date):       return "Updated \(date.formatted(date: .omitted, time: .shortened))"
        }
    }
```

Insert a "Data sources" card immediately before the Safety/Temperature/Units card (i.e. before the `VStack(spacing: 0) { NavigationLink { RedFlagRemindersView() } … }` at `:73`):

```swift
                VStack(spacing: 0) {
                    NavigationLink {
                        EnvironmentStatusView()
                    } label: {
                        HStack {
                            Image(systemName: "cloud.sun")
                                .foregroundStyle(HealthTheme.accent)
                            Text("Environment")
                                .foregroundStyle(HealthTheme.ink)
                            Spacer()
                            Text(environmentSummaryText)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint("Shows when weather and air quality data last updated")
                }
                .hgCard()
```

- [ ] **Step 3: Preview for the new detail screen**

The `HealthOSRootView` previews already received the store in Task 10 Step 3, and that one environment object reaches `HealthTabView` too — no change needed there. Optionally add a standalone `#Preview` to `EnvironmentStatusView.swift`, injecting `.environmentObject(EnvironmentStatusStore(defaults: UserDefaults(suiteName: "preview")!))`.

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Full app test suite**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -parallel-testing-enabled NO`
Expected: all new + existing suites green (the lone `SwiftDataMigratorTests` teardown crash aside).

- [ ] **Step 6: Commit**

```bash
git add "Views/HealthOS/Health/EnvironmentStatusView.swift" "Views/HealthOS/Health/HealthTabView.swift"
git commit -m "feat(env-status): Health 'Environment' status row + detail screen"
```

---

## Device Verification (after Task 11)

Run the app on a device/simulator and confirm (spec §5 Device pass):

- **Turn location off** (Settings → deny) → Environment Timeline rows show a muted `Weather unavailable` sub-line under the headline; the Health → Environment row reads a weather-group phrase; the detail screen shows `Why it stopped` with a working **Open Settings**; and — via Health Graph Debug's event view — **no New York weather and no fabricated 1013 pressure** are ingested for those days.
- **Restore location** → one successful foreground clears every marker together; Health flips each row to `Updated …`; the bottom section now reads `Last issue — resolved` with **no** Open Settings.
- A day whose forecast is present but observed history failed keeps showing its forecast with **no** marker.
- The legacy app's pressure card (Health tab → Open legacy app) looks identical to before, on both fallback routes.

---

## Self-Review Notes (author)

- **Spec coverage:** §3A store → T1/T2/T9; §3B classification + §3B.1 trusted coords + §3B.2 insufficientData → T5/T6/T8; §3C cancellation → T6/T8; §3D scope + success contracts + timezone → T6/T8; §3E resolver → T3/T10; §3F Timeline row → T10; §3G Health → T4/T11; §3H pressure → T7. All spec §5 tests mapped to a task's tests or the device pass.
- **`now:calendar:` dropped from the resolver** is a deliberate, documented simplification (Task 3 note) — flag for reviewer.
- **HTTP status is checked before decode** (`httpStatusReason`, Task 8): a 401 body decodes to a throw, so a post-decode `catch` would misclassify it as `.badResponse` instead of `.rejected`. The pre-check fixes that; `.insufficientData` is raised only on the 2xx-but-thin path (aggregate nil), never in the `catch`, which handles only thrown errors via `classifyThrown` (`URLError` → `.offline`, else `.badResponse`).
- **`emitIfNeeded`'s defaulted `statusStore`** lets the ~15 pre-existing emitter tests keep compiling unchanged; they use a throwaway store on `.standard` and never assert on it. Only the new scope/cancellation/success tests pass an explicit ephemeral-suite store.
- **Two success contracts** (spec §3D): backfills record success after a full persisted pass (emitter, Task 6); today capabilities record success on a valid decoded response (service, Task 8). Today's *ingestion* failure is out of scope — the transient bare-row consequence is documented in the spec, not a task.
