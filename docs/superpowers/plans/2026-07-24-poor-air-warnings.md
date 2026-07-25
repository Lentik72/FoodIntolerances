# Proactive poor-air warnings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the next-24h forecast AQI is unhealthy, show a calm, dismissible, tier-scaled warning at the top of Home — universal, with a personalized line when the evidence graph links poor-air days to a symptom.

**Architecture:** A pure decision core + personalization pick + `AQICategory` ordering/token live in `HealthGraphCore`. The app reuses `EnvironmentalDataService.forecastAQI` (adding a pass-scoped freshness state), a UserDefaults dismissal store, a Home view-model that composes them (settled-state gated, async-staleness guarded), and a dismissible Home banner behind a default-on preference.

**Tech Stack:** Swift 6, SwiftUI, GRDB, Swift Testing (`import Testing`), the `HealthGraphCore` SPM package, the app target `Food_Intolerances`.

## Global Constraints

- **Reuse `EnvironmentalDataService.forecastAQI`** (next-24h mean PM2.5 → EPA AQI). No new provider/endpoint. It stays display-and-warning-only — never ingested/mined.
- **Copy is forecast-oriented** ("forecast to be unhealthy" / 301+ "forecast to be hazardous"), never "current".
- **Trigger at AQI ≥ 101** (`AirQualityIndex.poorAirThreshold`); bands come from `AirQualityIndex.category(aqi:)` — the warning code NEVER duplicates numeric AQI ranges.
- **Freshness:** decide only on a settled pass-scoped state (`.pending`/`.value`/`.unavailable`); the not-configured path must clear the stale value; `.unavailable`/nil ⇒ no warning (fail-safe).
- **Once per local calendar day; re-show on band escalation.** Persist the **highest DISMISSED band per local day** as a **stable token** (never `name` or `severityRank`).
- **Lifecycle invariants (VM):** bump the async-invalidation `generation` on EVERY state transition (settle, pending, foreground re-eval, dismissal, toggle change); the banner is **dismissible only when it reflects a SETTLED value** (`isDismissible == false` while `.pending`, so a held cross-day banner can't write today's dismissal); a **foreground/day-rollover** path re-decides the last settled value against today even when the service skips a refetch; **toggle-off clears the mounted banner synchronously** (Home observes the preference).
- **Reuse the tuned AQI palette** (`aqiColor(for:)` / `AQIValueLabel`) — do NOT introduce a second color mapping. Dismiss button ≥44×44.
- **Settings toggle lives on the always-visible Health tab**, NOT inside `NotificationSettingsView`'s notification-gated section.
- **Personalization** = active graph edge `fromCategory=="poorAirDay"` && `toCategory=="symptom"` && `type==.possibleTrigger`; deterministic pick by `confidence` desc, `evidenceCount` desc, **raw** `toSubtype` asc; humanize via `SymptomCatalog.displayName(for:)`. A personalization failure/empty degrades to the base warning — NEVER suppresses it. A late lookup must not clobber a newer decision (async-staleness guard).
- **The four tier guidance strings are finalized (Task 6) and pinned verbatim in tests.**
- **Not a takeover.** Dismissible banner; salience scales with band; stays outside the red-flag/crisis interstitial system.
- **Dedicated default-on preference `hg.poorAirWarningsEnabled`** — the legacy `enableEnvironmentalAlerts` is untouched.
- **Test env:** HealthGraphCore tests → `swift test --package-path HealthGraphCore --filter <Suite>`. App tests → `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"…" -parallel-testing-enabled NO` (iPhone 17 Pro is the only runnable sim; `-parallel-testing-enabled NO` mandatory; a lone `SwiftDataMigratorTests` teardown crash is known/unrelated). New package files auto-discovered by SPM; new app files by PBXFileSystemSynchronizedRootGroup — never hand-edit `.pbxproj`. **Never** stage the cosmetic `.pbxproj` re-sort or `UserInterfaceState.xcuserstate`.
- **Swift 6.3.3 toolchain note:** the `#expect` macro can fail to compile with a `try` directly inside certain nested closures; let-bind first, never change the assertion.

---

## File Structure

**Create (HealthGraphCore):**
- `HealthGraphCore/Sources/HealthGraphCore/Warnings/PoorAirWarningDecision.swift` — pure decision core.
- `HealthGraphCore/Sources/HealthGraphCore/Warnings/PoorAirPersonalization.swift` — pure edge-pick.
- Tests: `AQICategoryOrderingTests.swift`, `PoorAirWarningDecisionTests.swift`, `PoorAirPersonalizationTests.swift`.

**Create (app):**
- `Models/PoorAirDismissalStore.swift` — per-local-day dismissed-band store.
- `Models/PoorAirWarningViewModel.swift` — composition VM.
- `Views/HealthOS/Home/PoorAirWarningBanner.swift` — the banner view.
- Tests: `PoorAirDismissalStoreTests.swift`, `PoorAirWarningViewModelTests.swift`, `ForecastAQIFreshnessTests.swift`.

**Modify:**
- `HealthGraphCore/Sources/HealthGraphCore/Ingestion/AirQualityIndex.swift` — `AQICategory` severity ordering + stable persistence token.
- `EnvironmentalDataService.swift` — add `ForecastAQIState` + `forecastAQIState`; drive it through `fetchAirQuality()`; fix the not-configured stale-value bug.
- `Views/HealthOS/Home/HomeView.swift` — observe the service, host the banner.
- `Views/HealthOS/Shell/HealthOSRootView.swift` — inject `EnvironmentalDataService` into the two `#Preview`s.
- The settings surface (Task 7 locates it) — the `hg.poorAirWarningsEnabled` toggle.

---

## Task 1: `AQICategory` severity ordering + stable persistence token

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/AirQualityIndex.swift:24-47` (the `AQICategory` enum)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/AQICategoryOrderingTests.swift`

**Interfaces:**
- Consumes: existing `AirQualityIndex.AQICategory` (`good/moderate/unhealthySensitive/unhealthy/veryUnhealthy/hazardous`, with `.name`).
- Produces: `AQICategory.severityRank: Int`, `AQICategory: Comparable`, `AQICategory.persistedToken: String`, `AQICategory.init?(persistedToken:)`.

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/AQICategoryOrderingTests.swift`:
```swift
import Testing
@testable import HealthGraphCore

@Suite struct AQICategoryOrderingTests {
    typealias Cat = AirQualityIndex.AQICategory

    @Test func severityIsMonotonic() {
        let ordered: [Cat] = [.good, .moderate, .unhealthySensitive, .unhealthy, .veryUnhealthy, .hazardous]
        #expect(ordered == ordered.sorted())                 // Comparable agrees with the listed order
        #expect(Cat.hazardous > Cat.unhealthySensitive)
        #expect(Cat.unhealthySensitive > Cat.moderate)
    }

    @Test func persistedTokensAreStableAndRoundTrip() {
        let expected: [Cat: String] = [
            .good: "good", .moderate: "moderate", .unhealthySensitive: "unhealthySensitive",
            .unhealthy: "unhealthy", .veryUnhealthy: "veryUnhealthy", .hazardous: "hazardous"]
        for (cat, token) in expected {
            #expect(cat.persistedToken == token)
            #expect(Cat(persistedToken: token) == cat)
        }
        #expect(Cat(persistedToken: "bogus") == nil)         // unknown token → nil, never a crash
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter AQICategoryOrderingTests`
Expected: FAIL — `severityRank`/`Comparable`/`persistedToken`/`init?(persistedToken:)` do not exist.

- [ ] **Step 3: Implement**

In `AirQualityIndex.swift`, extend the `AQICategory` enum (keep `name` as-is). Add inside the enum (after `name`):
```swift
        /// Ordinal for comparing bands (escalation). NOT persisted — see `persistedToken`.
        public var severityRank: Int {
            switch self {
            case .good: 0
            case .moderate: 1
            case .unhealthySensitive: 2
            case .unhealthy: 3
            case .veryUnhealthy: 4
            case .hazardous: 5
            }
        }

        /// STABLE identifier for UserDefaults persistence — frozen, independent of
        /// `name` (localized) and `severityRank` (an ordering that could be renumbered).
        public var persistedToken: String {
            switch self {
            case .good: "good"
            case .moderate: "moderate"
            case .unhealthySensitive: "unhealthySensitive"
            case .unhealthy: "unhealthy"
            case .veryUnhealthy: "veryUnhealthy"
            case .hazardous: "hazardous"
            }
        }

        public init?(persistedToken token: String) {
            switch token {
            case "good": self = .good
            case "moderate": self = .moderate
            case "unhealthySensitive": self = .unhealthySensitive
            case "unhealthy": self = .unhealthy
            case "veryUnhealthy": self = .veryUnhealthy
            case "hazardous": self = .hazardous
            default: return nil
            }
        }
```
And make the enum `Comparable` + `Hashable` — change the declaration line `public enum AQICategory: Sendable, Equatable {` to `public enum AQICategory: Sendable, Equatable, Comparable, Hashable {` (`Hashable` is synthesized for this payload-free enum; the test uses `AQICategory` as a dictionary key) and add:
```swift
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.severityRank < rhs.severityRank }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path HealthGraphCore --filter AQICategoryOrderingTests`
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Ingestion/AirQualityIndex.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/AQICategoryOrderingTests.swift"
git commit -m "feat(aqi): AQICategory severity ordering + stable persistence token"
```

---

## Task 2: `PoorAirWarningDecision` pure decision core

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Warnings/PoorAirWarningDecision.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/PoorAirWarningDecisionTests.swift`

**Interfaces:**
- Consumes: `AirQualityIndex.poorAirThreshold`, `AirQualityIndex.category(aqi:)`, `AirQualityIndex.AQICategory` (+ `Comparable` from Task 1).
- Produces:
  - `enum PoorAirWarning: Equatable { case none; case show(aqi: Int, band: AirQualityIndex.AQICategory, personalizedSymptom: String?) }`
  - `enum PoorAirWarningDecision { static func decide(forecastAQI: Int?, highestDismissedBandToday: AirQualityIndex.AQICategory?, personalizedSymptom: String?) -> PoorAirWarning }`

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/PoorAirWarningDecisionTests.swift`:
```swift
import Testing
@testable import HealthGraphCore

@Suite struct PoorAirWarningDecisionTests {
    typealias Cat = AirQualityIndex.AQICategory
    func decide(_ aqi: Int?, dismissed: Cat? = nil, symptom: String? = nil) -> PoorAirWarning {
        PoorAirWarningDecision.decide(forecastAQI: aqi, highestDismissedBandToday: dismissed, personalizedSymptom: symptom)
    }

    @Test func nilOrBelowThresholdIsNone() {
        #expect(decide(nil) == .none)
        #expect(decide(100) == .none)                         // below 101
    }
    @Test func atThresholdShowsUnhealthySensitive() {
        #expect(decide(101) == .show(aqi: 101, band: .unhealthySensitive, personalizedSymptom: nil))
    }
    @Test func bandMatchesCategoryMapping() {
        #expect(decide(175) == .show(aqi: 175, band: .unhealthy, personalizedSymptom: nil))
        #expect(decide(350) == .show(aqi: 350, band: .hazardous, personalizedSymptom: nil))
    }
    @Test func suppressedWhenDismissedSameBand() {
        #expect(decide(120, dismissed: .unhealthySensitive) == .none)
        #expect(decide(120, dismissed: .unhealthy) == .none)  // dismissed a HIGHER band today → still suppressed
    }
    @Test func reshownWhenBandEscalatesAboveDismissed() {
        #expect(decide(175, dismissed: .unhealthySensitive) == .show(aqi: 175, band: .unhealthy, personalizedSymptom: nil))
    }
    @Test func personalizedSymptomPassesThrough() {
        #expect(decide(160, symptom: "cough") == .show(aqi: 160, band: .unhealthy, personalizedSymptom: "cough"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter PoorAirWarningDecisionTests`
Expected: FAIL — `PoorAirWarning` / `PoorAirWarningDecision` undefined.

- [ ] **Step 3: Implement**

Create `HealthGraphCore/Sources/HealthGraphCore/Warnings/PoorAirWarningDecision.swift`:
```swift
import Foundation

/// The warning to render, or `.none`.
public enum PoorAirWarning: Equatable {
    case none
    case show(aqi: Int, band: AirQualityIndex.AQICategory, personalizedSymptom: String?)
}

/// Pure decision — no I/O, dates, or SwiftUI. All day-scoping is resolved by the
/// caller (which passes today's `highestDismissedBandToday`).
public enum PoorAirWarningDecision {
    public static func decide(
        forecastAQI: Int?,
        highestDismissedBandToday: AirQualityIndex.AQICategory?,
        personalizedSymptom: String?
    ) -> PoorAirWarning {
        guard let aqi = forecastAQI, aqi >= AirQualityIndex.poorAirThreshold else { return .none }
        let band = AirQualityIndex.category(aqi: aqi)
        // Show unless the user has already dismissed this band or a higher one today.
        if let dismissed = highestDismissedBandToday, band <= dismissed { return .none }
        return .show(aqi: aqi, band: band, personalizedSymptom: personalizedSymptom)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path HealthGraphCore --filter PoorAirWarningDecisionTests`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Warnings/PoorAirWarningDecision.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/PoorAirWarningDecisionTests.swift"
git commit -m "feat(warnings): pure poor-air decision core (threshold, band, escalation)"
```

---

## Task 3: `PoorAirPersonalization` — deterministic edge pick

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Warnings/PoorAirPersonalization.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/PoorAirPersonalizationTests.swift`

**Interfaces:**
- Consumes: `Relationship` (fields `fromCategory: String?`, `toCategory: String?`, `type: RelationshipType`, `status: RelStatus`, `confidence: Double`, `evidenceCount: Int`, `toSubtype: String?`), `RelationshipType.possibleTrigger`, `RelStatus.active`.
- Produces: `enum PoorAirPersonalization { static func bestSymptomSubtype(from relationships: [Relationship]) -> String? }` — the **raw** subtype of the best matching edge, or nil. (Humanization via `SymptomCatalog.displayName(for:)` happens in the app VM, Task 6.)

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/PoorAirPersonalizationTests.swift`:
```swift
import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct PoorAirPersonalizationTests {
    // Minimal edge builder — only the fields the pick reads.
    func edge(from: String? = "poorAirDay", to: String? = "symptom", type: RelationshipType = .possibleTrigger,
              status: RelStatus = .active, confidence: Double = 0.5, evidence: Int = 1,
              subtype: String?) -> Relationship {
        Relationship(fromCategory: from, toCategory: to, type: type,
                     evidenceCount: evidence, confidence: confidence,
                     firstSeen: Date(timeIntervalSince1970: 0), lastSeen: Date(timeIntervalSince1970: 0),
                     lastRecomputed: Date(timeIntervalSince1970: 0), status: status, toSubtype: subtype)
    }

    @Test func picksTheOnlyQualifyingEdge() {
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: [edge(subtype: "cough")]) == "cough")
    }
    @Test func nilWhenNoQualifyingEdge() {
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: []) == nil)
    }
    @Test func ignoresWrongStatusCategoryOrType() {
        let bad = [
            edge(status: .decayed, subtype: "a"),
            edge(from: "hotDay", subtype: "b"),
            edge(to: "mood", subtype: "c"),
            edge(type: .improves, subtype: "d"),
        ]
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: bad) == nil)
    }
    @Test func tiebreakByConfidenceThenEvidenceThenRawSubtype() {
        // Same confidence+evidence → lower raw subtype wins ("aaa" < "zzz").
        let a = edge(confidence: 0.7, evidence: 5, subtype: "zzz")
        let b = edge(confidence: 0.7, evidence: 5, subtype: "aaa")
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: [a, b]) == "aaa")
        // Higher confidence wins regardless of evidence/name.
        let c = edge(confidence: 0.9, evidence: 1, subtype: "zzz")
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: [b, c]) == "zzz")
        // Equal confidence → higher evidence wins.
        let d = edge(confidence: 0.7, evidence: 9, subtype: "mmm")
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: [b, d]) == "mmm")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter PoorAirPersonalizationTests`
Expected: FAIL — `PoorAirPersonalization` undefined.

- [ ] **Step 3: Implement**

Create `HealthGraphCore/Sources/HealthGraphCore/Warnings/PoorAirPersonalization.swift`:
```swift
import Foundation

/// Picks the user's most-supported active poor-air→symptom trigger edge, if any.
/// Pure over a relationship list so it is trivially testable; the app supplies the
/// list (typically `relationships(status: .active)`) and humanizes the returned
/// raw subtype via `SymptomCatalog.displayName(for:)`.
public enum PoorAirPersonalization {
    public static func bestSymptomSubtype(from relationships: [Relationship]) -> String? {
        relationships
            .filter { $0.status == .active
                   && $0.fromCategory == "poorAirDay"
                   && $0.toCategory == "symptom"
                   && $0.type == .possibleTrigger }
            .compactMap { rel -> (Relationship, String)? in
                guard let subtype = rel.toSubtype else { return nil }   // need a symptom key
                return (rel, subtype)
            }
            // Deterministic: confidence desc, evidenceCount desc, raw subtype asc.
            .sorted { l, r in
                if l.0.confidence != r.0.confidence { return l.0.confidence > r.0.confidence }
                if l.0.evidenceCount != r.0.evidenceCount { return l.0.evidenceCount > r.0.evidenceCount }
                return l.1 < r.1
            }
            .first?.1
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path HealthGraphCore --filter PoorAirPersonalizationTests`
Expected: PASS — 4 tests.

- [ ] **Step 5: Run the full package suite (Tasks 1–3 are all package-side)**

Run: `swift test --package-path HealthGraphCore`
Expected: PASS — no regressions.

- [ ] **Step 6: Commit**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Warnings/PoorAirPersonalization.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/PoorAirPersonalizationTests.swift"
git commit -m "feat(warnings): deterministic poor-air->symptom edge pick"
```

---

## Task 4: Forecast freshness state (the P1)

**Files:**
- Modify: `EnvironmentalDataService.swift` (add `ForecastAQIState` + `@Published var forecastAQIState`; drive it through `fetchAirQuality()`; fix the not-configured stale-value bug at `:589`)
- Test: `Food IntolerancesTests/ForecastAQIFreshnessTests.swift`

**Interfaces:**
- Consumes: existing `fetchAirQuality()` settle paths, the test ctor `EnvironmentalDataService(transport:now:location:)`, and the `HTTPTransport` stub pattern from `EnvironmentFailureClassificationTests`.
- Produces: `enum ForecastAQIState: Equatable { case pending, value(Int), unavailable }` and `@Published var forecastAQIState: ForecastAQIState` on `EnvironmentalDataService`, settled on every path; the not-configured path also clears `forecastAQI`.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/ForecastAQIFreshnessTests.swift`. The stub `HTTPTransport` and `StubLocation` (a `LocationProviding`) match `EnvironmentFailureClassificationTests` verbatim — the ctor's `location:` param is `LocationProviding?`, NOT a raw coordinate. Every failure path proves the pass settles to `(.unavailable, forecastAQI == nil)`, so no stale value can survive a failing refresh; the not-configured branch (invalid URL — not reachable in tests, since `APIConfig.airPollutionURL` resolves for the test config) applies the identical clear by inspection.
```swift
import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

@MainActor
@Suite struct ForecastAQIFreshnessTests {
    let at = Date(timeIntervalSince1970: 1_700_000_000)

    struct StubTransport: HTTPTransport {
        let payload: Data; let status: Int?; let error: Error?
        func data(from url: URL) async throws -> (Data, URLResponse) {
            if let error { throw error }
            let response: URLResponse = status.map {
                HTTPURLResponse(url: url, statusCode: $0, httpVersion: nil, headerFields: nil)!
            } ?? URLResponse(url: url, mimeType: "application/json",
                             expectedContentLength: payload.count, textEncodingName: "utf-8")
            return (payload, response)
        }
    }
    struct StubLocation: LocationProviding {
        var coordinate: CLLocationCoordinate2D? = .init(latitude: 42, longitude: -71)
        var authorization: EnvironmentLocationAuthorization = .authorized
    }
    func svc(_ payload: Data, status: Int? = 200, error: Error? = nil,
             location: LocationProviding = StubLocation()) -> EnvironmentalDataService {
        // Sibling env tests do this: without a key, APIConfig.airPollutionURL is nil and
        // the fetch never reaches the stub transport (it hits the not-configured branch).
        setenv("OPENWEATHER_API_KEY", "freshness-test-key", 1)
        return EnvironmentalDataService(transport: StubTransport(payload: payload, status: status, error: error),
                                        now: { self.at }, location: location)
    }
    // ≥3 next-24h slots whose mean PM2.5 (~40 µg/m³) → EPA AQI ≥ 101.
    func poorAirJSON() -> Data {
        let base = Int(at.timeIntervalSince1970)
        let slots = (1...4).map { "{\"dt\": \(base + $0*3600), \"components\": {\"pm2_5\": 40.0}}" }
            .joined(separator: ",")
        return Data("{\"list\": [\(slots)]}".utf8)
    }

    @Test func startsPendingThenSettlesToValueOnHealthyFetch() async {
        let s = svc(poorAirJSON())
        #expect(s.forecastAQIState == .pending)               // initial
        await s.fetchAirQuality()
        if case .value(let aqi) = s.forecastAQIState { #expect(aqi >= 101) }
        else { Issue.record("expected .value, got \(s.forecastAQIState)") }
        #expect(s.forecastAQI == s.forecastAQIState.valueOrNil)   // both consistent
    }

    @Test func httpErrorSettlesUnavailableAndClearsValue() async {
        let s = svc(Data("{}".utf8), status: 401)
        await s.fetchAirQuality()
        #expect(s.forecastAQIState == .unavailable)
        #expect(s.forecastAQI == nil)
    }

    @Test func thrownErrorSettlesUnavailableAndClearsValue() async {
        let s = svc(Data(), status: nil, error: URLError(.notConnectedToInternet))
        await s.fetchAirQuality()
        #expect(s.forecastAQIState == .unavailable)
        #expect(s.forecastAQI == nil)
    }

    @Test func insufficientSlotsSettleUnavailable() async {
        // A clean 200 with only 1 slot → mean == nil → .unavailable, no value.
        let base = Int(at.timeIntervalSince1970)
        let oneSlot = Data("{\"list\": [{\"dt\": \(base + 3600), \"components\": {\"pm2_5\": 40.0}}]}".utf8)
        let s = svc(oneSlot)
        await s.fetchAirQuality()
        #expect(s.forecastAQIState == .unavailable)
        #expect(s.forecastAQI == nil)
    }

    @Test func noLocationSettlesUnavailableAndClearsValue() async {
        // The no-location branch — part of the P1 fix. StubLocation with a nil coordinate.
        let s = svc(poorAirJSON(), location: StubLocation(coordinate: nil))
        await s.fetchAirQuality()
        #expect(s.forecastAQIState == .unavailable)
        #expect(s.forecastAQI == nil)
    }

    @Test func cancelledPassDoesNotSettleToAStaleValue() async {
        // A pass whose transport self-cancels after a clean 200 bails at the post-transport
        // Task.isCancelled guard — it must NOT settle; state stays .pending for the superseding
        // pass to resolve (never a stale .value/.unavailable). Mirrors EnvironmentFailure-
        // ClassificationTests.SelfCancellingTransport.
        struct SelfCancellingTransport: HTTPTransport {
            let payload: Data
            func data(from url: URL) async throws -> (Data, URLResponse) {
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                withUnsafeCurrentTask { $0?.cancel() }        // cancel our own calling task
                return (payload, resp)
            }
        }
        setenv("OPENWEATHER_API_KEY", "freshness-test-key", 1)
        let s = EnvironmentalDataService(transport: SelfCancellingTransport(payload: poorAirJSON()),
                                         now: { self.at }, location: StubLocation())
        await s.fetchAirQuality()
        #expect(s.forecastAQIState == .pending)               // never settled to a stale value
    }

    @Test func stateIsPendingWhileTransportSuspended() async {
        // While a fetch is suspended (transport awaiting), state must be .pending — an old
        // value is never surfaced mid-flight. Covers the "old value while suspended" regression.
        actor Latch {
            private var cont: CheckedContinuation<Void, Never>?
            func wait() async { await withCheckedContinuation { cont = $0 } }
            func open() { cont?.resume(); cont = nil }
        }
        struct GatedTransport: HTTPTransport {
            let latch: Latch; let payload: Data
            func data(from url: URL) async throws -> (Data, URLResponse) {
                await latch.wait()                            // suspend here
                return (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        setenv("OPENWEATHER_API_KEY", "freshness-test-key", 1)
        let latch = Latch()
        let s = EnvironmentalDataService(transport: GatedTransport(latch: latch, payload: poorAirJSON()),
                                         now: { self.at }, location: StubLocation())
        async let fetch: Void = s.fetchAirQuality()
        await Task.yield(); await Task.yield()
        #expect(s.forecastAQIState == .pending)               // suspended mid-flight → pending
        await latch.open()
        await fetch
        if case .value = s.forecastAQIState {} else { Issue.record("should settle to .value after resume") }
    }
}

// Small test helper — add to the test file.
private extension EnvironmentalDataService.ForecastAQIState {
    var valueOrNil: Int? { if case .value(let v) = self { v } else { nil } }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/ForecastAQIFreshnessTests" -parallel-testing-enabled NO`
Expected: FAIL — `forecastAQIState` does not exist / not settled.

- [ ] **Step 3: Add the state type + property**

In `EnvironmentalDataService.swift`, near the `forecastAQI` declaration (line 60), add:
```swift
    /// Pass-scoped freshness for the forecast AQI. `.pending` while a fetch is in
    /// flight; `.value`/`.unavailable` once the LATEST pass settles. Home decides
    /// only on a settled state so it never shows/dismisses a stale tier.
    enum ForecastAQIState: Equatable { case pending, value(Int), unavailable }
    @Published var forecastAQIState: ForecastAQIState = .pending
```

- [ ] **Step 4: Drive the state through `fetchAirQuality()`**

In `fetchAirQuality()`, set `.pending` first, and settle on EVERY path (all state writes go inside the existing `MainActor.run` blocks; add a `MainActor.run` for the pending set at the very top):

1. Top of the method (before `guard let location = self.resolvedCoordinate()`):
```swift
        await MainActor.run { self.forecastAQIState = .pending }
```
2. No-location guard block — add `self.forecastAQIState = .unavailable` alongside `self.forecastAQI = nil`.
3. **Invalid-URL / not-configured block (the bug, `:589`)** — currently `await MainActor.run { self.recordTodayFailure(.forecastAirQuality, .notConfigured) }`. Replace with:
```swift
            await MainActor.run {
                self.forecastAQI = nil
                self.forecastAQIState = .unavailable
                self.recordTodayFailure(.forecastAirQuality, .notConfigured)
            }
```
4. HTTP-status-reason block — add `self.forecastAQIState = .unavailable` alongside `self.forecastAQI = nil`.
5. Success block — after `self.forecastAQI = aqi`, set:
```swift
                if let aqi { self.forecastAQIState = .value(aqi) } else { self.forecastAQIState = .unavailable }
```
   (mirrors the existing `mean == nil` insufficient-data branch: nil aqi ⇒ `.unavailable`.)
6. `catch` block — add `self.forecastAQIState = .unavailable` alongside `self.forecastAQI = nil`.

Leave both `Task.isCancelled` early-returns untouched: a cancelled pass keeps `.pending` and the superseding pass re-enters `.pending` then settles — the latest pass wins, which is the intended behaviour.

- [ ] **Step 5: Run the tests + the existing env suites**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/ForecastAQIFreshnessTests" -only-testing:"Food IntolerancesTests/EnvironmentFailureClassificationTests" -only-testing:"Food IntolerancesTests/AirQualityHistoryTests" -parallel-testing-enabled NO`
Expected: PASS — new freshness tests green; the existing air-quality suites unaffected (adding a published property + settling it is additive).

- [ ] **Step 6: Commit**

```bash
git add "EnvironmentalDataService.swift" "Food IntolerancesTests/ForecastAQIFreshnessTests.swift"
git commit -m "fix(env): pass-scoped forecastAQIState; clear stale value on not-configured path"
```

---

## Task 5: `PoorAirDismissalStore` — highest-dismissed-band per local day

**Files:**
- Create: `Models/PoorAirDismissalStore.swift`
- Test: `Food IntolerancesTests/PoorAirDismissalStoreTests.swift`

**Interfaces:**
- Consumes: `AirQualityIndex.AQICategory` (+ `persistedToken`/`init?(persistedToken:)`/`Comparable` from Task 1).
- Produces: `struct PoorAirDismissalStore` with `init(defaults: UserDefaults)`, `func highestDismissedBandToday(now: Date, calendar: Calendar) -> AirQualityIndex.AQICategory?`, `func recordDismissed(_ band: AirQualityIndex.AQICategory, now: Date, calendar: Calendar)`.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/PoorAirDismissalStoreTests.swift`:
```swift
import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct PoorAirDismissalStoreTests {
    typealias Cat = AirQualityIndex.AQICategory
    func store() -> PoorAirDismissalStore {
        PoorAirDismissalStore(defaults: UserDefaults(suiteName: "poorair.\(UUID().uuidString)")!)
    }
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    let day1 = Date(timeIntervalSince1970: 1_700_000_000)          // some day
    var day2: Date { day1.addingTimeInterval(86_400) }             // next day

    @Test func recordsAndReadsTheMaxBandForTheDay() {
        let s = store()
        s.recordDismissed(.unhealthySensitive, now: day1, calendar: utc)
        #expect(s.highestDismissedBandToday(now: day1, calendar: utc) == .unhealthySensitive)
        s.recordDismissed(.unhealthy, now: day1, calendar: utc)     // higher
        #expect(s.highestDismissedBandToday(now: day1, calendar: utc) == .unhealthy)
        s.recordDismissed(.unhealthySensitive, now: day1, calendar: utc)   // lower — max stays
        #expect(s.highestDismissedBandToday(now: day1, calendar: utc) == .unhealthy)
    }
    @Test func rollsOverToNilNextDay() {
        let s = store()
        s.recordDismissed(.hazardous, now: day1, calendar: utc)
        #expect(s.highestDismissedBandToday(now: day2, calendar: utc) == nil)   // new local day → eligible again
    }
    @Test func unknownStoredTokenReadsNil() {
        let d = UserDefaults(suiteName: "poorair.\(UUID().uuidString)")!
        let s = PoorAirDismissalStore(defaults: d)
        // Simulate a legacy/corrupt token for today's key.
        s.recordDismissed(.unhealthy, now: day1, calendar: utc)
        d.set("bogus", forKey: s.debugKey(now: day1, calendar: utc))
        #expect(s.highestDismissedBandToday(now: day1, calendar: utc) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/PoorAirDismissalStoreTests" -parallel-testing-enabled NO`
Expected: FAIL — `PoorAirDismissalStore` undefined.

- [ ] **Step 3: Implement**

Create `Models/PoorAirDismissalStore.swift`:
```swift
import Foundation
import HealthGraphCore

/// Persists, per LOCAL calendar day, the highest AQI band the user has dismissed —
/// so a warning re-shows only on a new day or when the forecast escalates to a
/// higher band. Stored as the band's STABLE token (never `name`/`severityRank`).
struct PoorAirDismissalStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(now: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: now)
        // Stable, locale-independent day key.
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        return "hg.poorAir.dismissed.\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    /// Test-only key exposure (used to seed a corrupt token).
    func debugKey(now: Date, calendar: Calendar) -> String { key(now: now, calendar: calendar) }

    func highestDismissedBandToday(now: Date, calendar: Calendar) -> AirQualityIndex.AQICategory? {
        guard let token = defaults.string(forKey: key(now: now, calendar: calendar)) else { return nil }
        return AirQualityIndex.AQICategory(persistedToken: token)   // unknown token → nil
    }

    func recordDismissed(_ band: AirQualityIndex.AQICategory, now: Date, calendar: Calendar) {
        let existing = highestDismissedBandToday(now: now, calendar: calendar)
        let maxBand = max(existing ?? band, band)                  // Comparable from Task 1
        defaults.set(maxBand.persistedToken, forKey: key(now: now, calendar: calendar))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/PoorAirDismissalStoreTests" -parallel-testing-enabled NO`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add "Models/PoorAirDismissalStore.swift" "Food IntolerancesTests/PoorAirDismissalStoreTests.swift"
git commit -m "feat(warnings): per-local-day dismissed-band store (stable token)"
```

---

## Task 6: `PoorAirWarningViewModel` — composition, freshness gate, staleness guard

**Files:**
- Create: `Models/PoorAirWarningViewModel.swift`
- Test: `Food IntolerancesTests/PoorAirWarningViewModelTests.swift`

**Interfaces:**
- Consumes: `EnvironmentalDataService.ForecastAQIState`, `PoorAirWarningDecision.decide(...)`, `PoorAirPersonalization.bestSymptomSubtype(from:)`, `SymptomCatalog.displayName(for:)`, `PoorAirDismissalStore`, `GRDBRelationshipStore.relationships(status:)`, the preference `hg.poorAirWarningsEnabled`, `AirQualityIndex.AQICategory`.
- Produces: `@MainActor final class PoorAirWarningViewModel: ObservableObject` with `@Published private(set) var warning: PoorAirWarning`, `func evaluate(state: EnvironmentalDataService.ForecastAQIState) async`, `func dismissCurrent()`, and the four finalized tier guidance strings via `static func guidance(for band:) -> String`.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/PoorAirWarningViewModelTests.swift`:
```swift
import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct PoorAirWarningViewModelTests {
    typealias Cat = AirQualityIndex.AQICategory
    typealias State = EnvironmentalDataService.ForecastAQIState

    func makeVM(enabled: Bool = true,
                symptomLookup: @escaping () async -> String? = { nil }) -> PoorAirWarningViewModel {
        let d = UserDefaults(suiteName: "poorairvm.\(UUID().uuidString)")!
        d.set(enabled, forKey: "hg.poorAirWarningsEnabled")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        return PoorAirWarningViewModel(
            defaults: d, calendar: utc, now: { Date(timeIntervalSince1970: 1_700_000_000) },
            personalizedSymptomSubtype: symptomLookup)
    }

    @Test func toggleOffNeverShows() async {
        let vm = makeVM(enabled: false)
        await vm.evaluate(state: .value(160))
        #expect(vm.warning == .none)
    }
    @Test func pendingHoldsNonDismissible_unavailableClears() async {
        let vm = makeVM()
        await vm.evaluate(state: .value(160))
        #expect(vm.warning != .none && vm.isDismissible)      // settled → dismissible
        await vm.evaluate(state: .pending)
        #expect(vm.warning != .none)                          // HELD — pending doesn't clear
        #expect(vm.isDismissible == false)                    // …but NOT dismissible while pending
        await vm.evaluate(state: .unavailable)
        #expect(vm.warning == .none)                          // settled-unavailable clears
    }
    @Test func dismissSuppressesSameDayUntilEscalation() async {
        let vm = makeVM()
        await vm.evaluate(state: .value(120))                 // unhealthySensitive
        vm.dismissCurrent()
        await vm.evaluate(state: .value(120))
        #expect(vm.warning == .none)                          // suppressed
        await vm.evaluate(state: .value(175))                 // unhealthy — escalation
        #expect(vm.warning != .none)                          // re-shown
    }
    @Test func personalizationFailureDegradesToBase() async {
        // Lookup throws/returns nil → base warning still shows.
        let vm = makeVM(symptomLookup: { nil })
        await vm.evaluate(state: .value(160))
        if case .show(_, _, let symptom) = vm.warning { #expect(symptom == nil) }
        else { Issue.record("expected base warning") }
    }
    @Test func humanizesSymptomWhenPresent() async {
        let vm = makeVM(symptomLookup: { "cough" })           // raw subtype
        await vm.evaluate(state: .value(160))
        if case .show(_, _, let symptom) = vm.warning {
            // Qualified — the app has its own `SymptomCatalog` struct; use the Core enum.
            #expect(symptom == HealthGraphCore.SymptomCatalog.displayName(for: "cough"))
        } else { Issue.record("expected personalized warning") }
    }

    // Gate to sequence two overlapping lookups.
    actor Gate {
        private var cont: CheckedContinuation<Void, Never>?
        private var opened = false
        private var calls = 0
        func next() async -> Int {
            calls += 1; let n = calls
            if n == 1 && !opened { await withCheckedContinuation { cont = $0 } }
            return n
        }
        func open() { opened = true; cont?.resume(); cont = nil }
    }

    @Test func lateStaleLookupDoesNotClobberNewerDecision() async {
        // The 1st evaluate's personalization blocks on the gate; a 2nd evaluate supersedes it
        // (returns nil). Releasing the stale 1st lookup ("cough") must NOT re-personalize.
        let gate = Gate()
        let vm = makeVM(symptomLookup: { let n = await gate.next(); return n == 1 ? "cough" : nil })
        async let first: Void = vm.evaluate(state: .value(160))   // gen 1 — blocks in lookup
        await Task.yield(); await Task.yield()
        await vm.evaluate(state: .value(160))                     // gen 2 — lookup returns nil
        await gate.open()                                         // release gen-1's stale "cough"
        await first
        if case .show(_, _, let symptom) = vm.warning { #expect(symptom == nil) }  // gen-2 won
        else { Issue.record("expected base warning after staleness drop") }
    }

    @Test func toggleOffInvalidatesInFlightLookup() async {
        // A lookup in flight from an enabled .value pass must NOT re-show a warning after
        // the toggle flips off mid-flight (the disabled path bumps generation).
        let gate = Gate()
        let d = UserDefaults(suiteName: "poorairvm.\(UUID().uuidString)")!
        d.set(true, forKey: "hg.poorAirWarningsEnabled")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let vm = PoorAirWarningViewModel(defaults: d, calendar: utc,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            personalizedSymptomSubtype: { _ = await gate.next(); return "cough" })
        async let first: Void = vm.evaluate(state: .value(160))   // enabled → base shown, lookup blocks
        await Task.yield(); await Task.yield()
        d.set(false, forKey: "hg.poorAirWarningsEnabled")
        await vm.evaluate(state: .value(160))                     // now disabled → .none, generation bumped
        await gate.open()
        await first
        #expect(vm.warning == .none)                              // stale lookup could not re-show
    }

    @Test func dismissDuringPendingIsNoOp() async {
        // Cross-day hazard: a held banner while a fresh fetch is pending must not be
        // dismissible — otherwise it writes TODAY's dismissal for YESTERDAY's forecast.
        let vm = makeVM()
        await vm.evaluate(state: .value(120))                 // settled → dismissible
        await vm.evaluate(state: .pending)                    // now held, non-dismissible
        vm.dismissCurrent()                                   // must be a no-op
        #expect(vm.warning != .none)                          // still held
        // And nothing was recorded: a fresh settle of the SAME tier still shows.
        await vm.evaluate(state: .value(120))
        #expect(vm.warning != .none)
    }

    @Test func dismissDuringPersonalizationDropsLateLookup() async {
        // Dismiss while personalization is in flight: the late lookup must NOT resurrect
        // the dismissed banner (dismiss bumps generation).
        let gate = Gate()
        let vm = makeVM(symptomLookup: { _ = await gate.next(); return "cough" })
        async let first: Void = vm.evaluate(state: .value(160))   // base shown (dismissible), lookup blocks
        await Task.yield(); await Task.yield()
        vm.dismissCurrent()                                       // dismiss now — bumps generation
        #expect(vm.warning == .none)
        await gate.open()                                         // release the stale "cough" lookup
        await first
        #expect(vm.warning == .none)                             // NOT resurrected
    }

    @Test func onEnabledChangedClearsMountedBannerSynchronously() async {
        let d = UserDefaults(suiteName: "poorairvm.\(UUID().uuidString)")!
        d.set(true, forKey: "hg.poorAirWarningsEnabled")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let vm = PoorAirWarningViewModel(defaults: d, calendar: utc,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }, personalizedSymptomSubtype: { nil })
        await vm.evaluate(state: .value(160))
        #expect(vm.warning != .none)
        d.set(false, forKey: "hg.poorAirWarningsEnabled")        // user flips it off
        vm.onEnabledChanged()                                    // synchronous
        #expect(vm.warning == .none && vm.isDismissible == false)
    }

    @Test func foregroundReevaluatesForNewDayAfterDismissal() async {
        // Dismiss on day 1, then a NEW local day foreground (service skipped a refetch,
        // so state is unchanged) must re-show via reevaluateForForeground().
        let d = UserDefaults(suiteName: "poorairvm.\(UUID().uuidString)")!
        d.set(true, forKey: "hg.poorAirWarningsEnabled")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        var currentNow = Date(timeIntervalSince1970: 1_700_000_000)
        let vm = PoorAirWarningViewModel(defaults: d, calendar: utc,
            now: { currentNow }, personalizedSymptomSubtype: { nil })
        await vm.evaluate(state: .value(140))                    // day 1: settled, shown
        vm.dismissCurrent()                                     // dismissed for day 1
        #expect(vm.warning == .none)
        currentNow = currentNow.addingTimeInterval(86_400)       // → next local day
        await vm.reevaluateForForeground()                       // no state change; re-decide last value
        #expect(vm.warning != .none)                             // yesterday's dismissal no longer suppresses
    }

    @Test func guidanceStringsAreExactPerBand() {
        #expect(PoorAirWarningViewModel.guidance(for: .unhealthySensitive) ==
                "Sensitive groups should reduce prolonged or heavy outdoor exertion.")
        #expect(PoorAirWarningViewModel.guidance(for: .unhealthy) ==
                "Sensitive groups should avoid prolonged or heavy outdoor exertion; everyone else should reduce it.")
        #expect(PoorAirWarningViewModel.guidance(for: .veryUnhealthy) ==
                "Sensitive groups should avoid all outdoor physical activity; everyone else should avoid prolonged or intense outdoor activity.")
        #expect(PoorAirWarningViewModel.guidance(for: .hazardous) ==
                "Everyone should avoid all outdoor physical activity; sensitive groups should stay indoors and keep activity low.")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/PoorAirWarningViewModelTests" -parallel-testing-enabled NO`
Expected: FAIL — `PoorAirWarningViewModel` undefined.

- [ ] **Step 3: Implement**

Create `Models/PoorAirWarningViewModel.swift`. The lifecycle is the subtle part — read the invariants first:
- **`generation` is bumped on EVERY state transition** — settle, `.pending`, foreground re-eval, dismissal, toggle change — so no late async personalization can resurrect or clobber a newer decision.
- **`isDismissible` is true ONLY when the banner reflects a SETTLED value.** It is `false` while a fetch is `.pending`, so a held cross-day banner cannot write *today's* dismissal for *yesterday's* forecast. `dismissCurrent()` is a no-op unless `isDismissible`.
- **A settle drives the normal path; a foreground/day-rollover re-decides the LAST settled value against TODAY** (via `reevaluateForForeground()`), so a new local day clears yesterday's dismissal even when the service skips a refetch (cooldown).
- **`onEnabledChanged()` synchronously clears + invalidates** when the toggle flips off.

```swift
import Foundation
import HealthGraphCore

@MainActor
final class PoorAirWarningViewModel: ObservableObject {
    @Published private(set) var warning: PoorAirWarning = .none
    /// The banner shows a Dismiss button ONLY when this is true — i.e. the warning
    /// reflects a SETTLED forecast. False while `.pending`, so a held cross-day banner
    /// can never write today's dismissal against yesterday's forecast.
    @Published private(set) var isDismissible: Bool = false

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let store: PoorAirDismissalStore
    /// Injectable so tests don't need a live graph. Production wires this to a
    /// relationship-store query (Task 7). Returns the RAW symptom subtype, or nil.
    private let personalizedSymptomSubtype: () async -> String?
    /// Bumped on EVERY state transition — invalidates any in-flight async personalization.
    private var generation = 0
    /// The last SETTLED forecast AQI, so a foreground/day-rollover can re-decide it
    /// against today's dismissed state even if the service skips a refetch.
    private var lastSettledAQI: Int?

    init(defaults: UserDefaults = .standard,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init,
         personalizedSymptomSubtype: @escaping () async -> String?) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.store = PoorAirDismissalStore(defaults: defaults)
        self.personalizedSymptomSubtype = personalizedSymptomSubtype
    }

    private var enabled: Bool {
        defaults.object(forKey: "hg.poorAirWarningsEnabled") as? Bool ?? true   // default ON
    }

    /// SETTLE-driven path (Home observes `forecastAQIState`).
    func evaluate(state: EnvironmentalDataService.ForecastAQIState) async {
        generation &+= 1                                   // every transition invalidates in-flight work
        let mine = generation
        guard enabled else { clear(); return }
        switch state {
        case .pending:
            // Hold whatever is shown, but make it NON-dismissible: no stale-dismissal write,
            // and any in-flight lookup is already invalidated by the generation bump above.
            isDismissible = false
        case .unavailable:
            lastSettledAQI = nil
            decideBase(aqi: nil)                            // → .none
        case .value(let v):
            lastSettledAQI = v
            await decide(aqi: v, mine: mine)
        }
    }

    /// FOREGROUND / DAY-ROLLOVER path (Home calls on scenePhase → .active). Re-decides the
    /// LAST settled value against TODAY, so crossing midnight clears yesterday's dismissal
    /// and re-shows if still warranted — even when the service's cooldown skips a refetch.
    func reevaluateForForeground() async {
        generation &+= 1
        let mine = generation
        guard enabled else { clear(); return }
        await decide(aqi: lastSettledAQI, mine: mine)
    }

    func dismissCurrent() {
        // Only a SETTLED, shown banner is dismissible — never a pending/held one.
        guard isDismissible, case .show(_, let band, _) = warning else { return }
        generation &+= 1                                   // invalidate any in-flight personalization
        store.recordDismissed(band, now: now(), calendar: calendar)
        clear()
    }

    /// Call when `hg.poorAirWarningsEnabled` changes — synchronous clear + invalidate.
    func onEnabledChanged() {
        generation &+= 1
        if !enabled { clear() }                            // re-enable re-decides on next settle/foreground
    }

    // MARK: - internals

    private func clear() { warning = .none; isDismissible = false }

    /// Base (non-personalized) decision for a SETTLED value; dismissible iff shown.
    private func decideBase(aqi: Int?) {
        let dismissed = store.highestDismissedBandToday(now: now(), calendar: calendar)
        warning = PoorAirWarningDecision.decide(forecastAQI: aqi,
                                                highestDismissedBandToday: dismissed,
                                                personalizedSymptom: nil)
        isDismissible = { if case .show = warning { true } else { false } }()
    }

    /// Settled decision + async personalization, guarded against staleness.
    private func decide(aqi: Int?, mine: Int) async {
        decideBase(aqi: aqi)                               // base first — dismissible if shown
        guard case .show(let a, let band, _) = warning else { return }
        let subtype = await personalizedSymptomSubtype()
        guard mine == generation else { return }          // async-staleness / dismissal / toggle guard
        if let subtype {
            // MUST qualify: the app target has its own top-level `struct SymptomCatalog`
            // (no `displayName`) that shadows the imported one — every app call site qualifies.
            let label = HealthGraphCore.SymptomCatalog.displayName(for: subtype)
            warning = .show(aqi: a, band: band, personalizedSymptom: label)
        }
    }

    /// Tier-specific guidance, matching the AirNow PM2.5 activity table in meaning.
    /// FINALIZED strings — pinned in tests; edit only with a spec change.
    static func guidance(for band: AirQualityIndex.AQICategory) -> String {
        switch band {
        case .unhealthySensitive:
            "Sensitive groups should reduce prolonged or heavy outdoor exertion."
        case .unhealthy:
            "Sensitive groups should avoid prolonged or heavy outdoor exertion; everyone else should reduce it."
        case .veryUnhealthy:
            "Sensitive groups should avoid all outdoor physical activity; everyone else should avoid prolonged or intense outdoor activity."
        case .hazardous:
            "Everyone should avoid all outdoor physical activity; sensitive groups should stay indoors and keep activity low."
        case .good, .moderate:
            ""   // never shown (below threshold); returns empty rather than crashing.
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/PoorAirWarningViewModelTests" -parallel-testing-enabled NO`
Expected: PASS — 12 tests (incl. async-staleness drop, dismiss-during-pending no-op, dismiss-during-personalization, synchronous toggle-off clear, and foreground/day-rollover re-show).

- [ ] **Step 5: Commit**

```bash
git add "Models/PoorAirWarningViewModel.swift" "Food IntolerancesTests/PoorAirWarningViewModelTests.swift"
git commit -m "feat(warnings): Home warning VM — freshness gate, staleness guard, tier copy"
```

---

## Task 7: Banner view + Home wiring + settings toggle + preview injection

**Files:**
- Create: `Views/HealthOS/Home/PoorAirWarningBanner.swift`
- Modify: `Views/HealthOS/Timeline/AQIValueLabel.swift:6` (make `aqiColor(for:)` module-internal — drop `private` — so the banner reuses the SAME tuned 6-band palette)
- Modify: `Views/HealthOS/Home/HomeView.swift` (observe the service, host the banner, drive the VM, foreground/day-rollover + reactive-toggle wiring)
- Modify: `Views/HealthOS/Shell/HealthOSRootView.swift:55-72` (inject `EnvironmentalDataService` into both `#Preview`s)
- Modify: `Views/HealthOS/Health/HealthTabView.swift` (add the `hg.poorAirWarningsEnabled` toggle — the ALWAYS-visible Health surface, near the existing `hg.temperatureUnit`/`hg.measurementSystem` settings)
- Test: `Food IntolerancesTests/PoorAirWarningBannerTests.swift`

**Interfaces:**
- Consumes: `PoorAirWarningViewModel` (`.warning`, `.isDismissible`, `.evaluate(state:)`, `.reevaluateForForeground()`, `.dismissCurrent()`, `.onEnabledChanged()`, `.guidance(for:)`), `PoorAirWarning`, `AirQualityIndex.AQICategory.name`, `AQIValueLabel`, `aqiColor(for:)`, `EnvironmentalDataService.forecastAQIState`, `GRDBRelationshipStore(database:).relationships(status: .active)`, `PoorAirPersonalization.bestSymptomSubtype(from:)`.
- Produces: `PoorAirWarningBanner.title(for:)` (a testable static), and the user-facing surface.

- [ ] **Step 1: Build the banner view (reusing the tuned AQI palette)**

First, in `Views/HealthOS/Timeline/AQIValueLabel.swift:6`, change `private func aqiColor(for category:` to `func aqiColor(for category:` so the banner can reuse the exact same 6-band AirNow palette (do NOT introduce a second orange/red mapping).

Create `Views/HealthOS/Home/PoorAirWarningBanner.swift`:
```swift
import SwiftUI
import HealthGraphCore

/// Dismissible, tier-scaled poor-air warning. NOT a takeover — stays outside the
/// red-flag/crisis interstitial system. Reuses the tuned AirNow palette via
/// `AQIValueLabel` (the value line) and `aqiColor(for:)` (the accent).
struct PoorAirWarningBanner: View {
    let aqi: Int
    let band: AirQualityIndex.AQICategory
    let personalizedSymptom: String?
    let isDismissible: Bool
    let onDismiss: () -> Void

    /// Testable — pins the forecast-oriented copy (spec Decision 2) + the hazardous variant.
    static func title(for band: AirQualityIndex.AQICategory) -> String {
        band == .hazardous ? "Air quality is forecast to be hazardous"
                           : "Air quality is forecast to be unhealthy"
    }
    private var accent: Color { aqiColor(for: band) }   // SAME palette as AQIBadge — all 6 bands distinct

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.title(for: band)).font(.subheadline.weight(.semibold))
                Spacer()
                if isDismissible {   // never during a pending fetch (VM sets isDismissible=false)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.footnote.weight(.bold))
                            .frame(width: 44, height: 44)          // ≥44×44 hit target
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Dismiss air quality warning")
                }
            }
            AQIValueLabel(value: "AQI \(aqi) · \(band.name)", aqi: aqi)   // tuned dot + VoiceOver-combined
                .font(.caption)
            Text(PoorAirWarningViewModel.guidance(for: band)).font(.caption)
            if let personalizedSymptom {
                Text("Poor-air days have been linked to your \(personalizedSymptom).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(band >= .veryUnhealthy ? 0.18 : 0.12),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.4), lineWidth: 1))
    }
}
```

Create `Food IntolerancesTests/PoorAirWarningBannerTests.swift` — pins the forecast title copy (a full SwiftUI render/accessibility test needs ViewInspector, which the project doesn't use; the value line's accessibility is already covered by `AQIValueLabel`'s `.accessibilityElement(children: .combine)`, and end-to-end render is device-gated):
```swift
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct PoorAirWarningBannerTests {
    @Test func titleIsForecastOrientedAndHazardousVariant() {
        #expect(PoorAirWarningBanner.title(for: .unhealthySensitive) == "Air quality is forecast to be unhealthy")
        #expect(PoorAirWarningBanner.title(for: .unhealthy) == "Air quality is forecast to be unhealthy")
        #expect(PoorAirWarningBanner.title(for: .veryUnhealthy) == "Air quality is forecast to be unhealthy")
        #expect(PoorAirWarningBanner.title(for: .hazardous) == "Air quality is forecast to be hazardous")
    }
}
```

- [ ] **Step 2: Wire into `HomeView`**

In `Views/HealthOS/Home/HomeView.swift`:
1. Add the service observation, the toggle binding, and the VM:
```swift
    @EnvironmentObject private var environmentalService: EnvironmentalDataService
    @AppStorage("hg.poorAirWarningsEnabled") private var poorAirEnabled = true
    @StateObject private var poorAir = PoorAirWarningViewModel(
        personalizedSymptomSubtype: {
            let rels = (try? await GRDBRelationshipStore(database: HealthGraphProvider.shared)
                .relationships(status: .active)) ?? []              // failure → [] → base warning
            return PoorAirPersonalization.bestSymptomSubtype(from: rels)
        })
```
2. Render the banner as the FIRST child of the top `VStack` (above `greeting`), passing `isDismissible`:
```swift
                if case .show(let aqi, let band, let symptom) = poorAir.warning {
                    PoorAirWarningBanner(aqi: aqi, band: band, personalizedSymptom: symptom,
                                         isDismissible: poorAir.isDismissible,
                                         onDismiss: { poorAir.dismissCurrent() })
                }
```
3. Wire the three lifecycle triggers (add alongside the existing `.task`/`.onChange`). The scenePhase handler drives the FOREGROUND/day-rollover re-eval; the forecast-state handler drives the SETTLE path; the toggle handler clears synchronously:
```swift
        .task { await poorAir.evaluate(state: environmentalService.forecastAQIState) }
        .onChange(of: environmentalService.forecastAQIState) { _, state in
            Task { await poorAir.evaluate(state: state) }        // settle-driven (incl. pending → non-dismissible hold)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await poorAir.reevaluateForForeground() } }  // day-rollover even if the fetch is cooled-down
        }
        .onChange(of: poorAirEnabled) { _, _ in poorAir.onEnabledChanged() }  // toggle-off clears the mounted banner NOW
```
(`HomeView` already has `@Environment(\.scenePhase)`; reuse it. If it already has a `scenePhase` `.onChange` for `viewModel.refresh()`, add the `poorAir.reevaluateForForeground()` call inside that same handler rather than a second one.)

- [ ] **Step 3: Inject the service into the root previews**

In `Views/HealthOS/Shell/HealthOSRootView.swift`, both `#Preview` blocks now render Home, which requires `EnvironmentalDataService`. Add to each (mirroring the existing `EnvironmentStatusStore` preview injection):
```swift
        .environmentObject(EnvironmentalDataService(locationManager: nil,
            statusStore: EnvironmentStatusStore(defaults: UserDefaults(suiteName: "preview")!)))
```
(If `HomeView` has its own `#Preview`, inject it there too.)

- [ ] **Step 4: Add the settings toggle on the ALWAYS-visible Health surface**

The banner is an **in-app, notification-independent, default-ON** feature, so its toggle must NOT go in `NotificationSettingsView` — its "AI Health Assistant Alerts" `Section` is inside `if notificationsEnabled { … }` (`:51`; `notificationsEnabled == settings.authorizationStatus == .authorized`, `:188`), so a user who denies notifications could never reach it while the banner still shows.

Put it on `Views/HealthOS/Health/HealthTabView.swift`, which is always visible and already hosts the `hg.*` `@AppStorage` settings (`hg.temperatureUnit`, `hg.measurementSystem`, the Temperature/Units pickers ~`:134-156`). Add:
```swift
    @AppStorage("hg.poorAirWarningsEnabled") private var poorAirWarningsEnabled = true
```
and a `Toggle` in that settings area (next to the Temperature/Units controls):
```swift
                    Toggle("Poor air quality warnings", isOn: $poorAirWarningsEnabled)
```
`@AppStorage` writes to `.standard` — the same store `PoorAirWarningViewModel` reads and `HomeView` observes (Step 2's `.onChange(of: poorAirEnabled)`), so flipping it off clears the mounted banner immediately. Leave the legacy notification `enableEnvironmentalAlerts` untouched. Verify the toggle is reachable with notifications denied.

- [ ] **Step 5: Build + verify the whole feature suite**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/PoorAirWarningViewModelTests" -only-testing:"Food IntolerancesTests/PoorAirDismissalStoreTests" -only-testing:"Food IntolerancesTests/ForecastAQIFreshnessTests" -only-testing:"Food IntolerancesTests/PoorAirWarningBannerTests" -parallel-testing-enabled NO`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add "Views/HealthOS/Home/PoorAirWarningBanner.swift" "Views/HealthOS/Home/HomeView.swift" \
        "Views/HealthOS/Timeline/AQIValueLabel.swift" \
        "Views/HealthOS/Shell/HealthOSRootView.swift" "Views/HealthOS/Health/HealthTabView.swift" \
        "Food IntolerancesTests/PoorAirWarningBannerTests.swift"
git commit -m "feat(home): poor-air warning banner + Home lifecycle wiring + Health-tab toggle"
```

---

## Final Verification

- [ ] **Package suite:** `swift test --package-path HealthGraphCore` → green (Tasks 1–3: `AQICategoryOrderingTests`, `PoorAirWarningDecisionTests`, `PoorAirPersonalizationTests` + no regressions).
- [ ] **FULL app suite:** `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO` → the new app suites (`ForecastAQIFreshnessTests`, `PoorAirDismissalStoreTests`, `PoorAirWarningViewModelTests`, `PoorAirWarningBannerTests`) and the existing env suites (`EnvironmentFailureClassificationTests`, `AirQualityHistoryTests`, `EnvironmentalDataServiceDITests`, `InsightsViewModelTests`, …) pass; the ONLY failing entry is the known-unrelated `SwiftDataMigratorTests.migratesObjectsFromAvoidedCabinetAndProtocols()` teardown crash.
- [ ] **Device gate (manual):** on a forecast-unhealthy day (or a stubbed poor forecast), foreground → Home shows the tier-appropriate banner with the tuned AQI color; **dismiss (≥44×44 target) → gone for the local day**; a higher forecast band re-shows; **cross-midnight foreground with the fetch cooled-down → yesterday's dismissal cleared, warning reappears**; while a refresh is pending the banner holds but shows **no Dismiss button**; toggle off on the Health tab → banner clears immediately and never shows; denied location / keyless build → never shows (fail-safe); VoiceOver reads the AQI value line once (via `AQIValueLabel`).
