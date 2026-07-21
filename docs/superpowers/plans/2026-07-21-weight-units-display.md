# Weight Units (Timeline Display) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Timeline body-weight events in the user's chosen unit (kg or lb, reusing the profile's Imperial/Metric preference) instead of the hardcoded `kg`, without touching stored/HealthKit values.

**Architecture:** Mirror the shipped temperature-unit split. A new app-side `WeightUnit` + `BodyMetricValueFormatter` (peer to `WeatherValueFormatter`) render a weight event in the resolved unit; the row/detail prepend it to the existing `WeatherValueFormatter ?? EventDisplay.valueLine` chain. `TimelineView` resolves the unit **once** (a single `@Query userProfiles`) and passes it into each `TimelineEventRow`; `EventDetailView` resolves its own (one query per screen, mirroring its existing `@AppStorage` temp read) so **both** of its entry points work. `EventDisplay` (HealthGraphCore) is unchanged — its `%.1f kg` stays the pure fallback and core gains no `UserProfile` dependency.

**Tech Stack:** Swift, SwiftUI, SwiftData (`@Query UserProfile`), Swift Testing (`import Testing`, `@Test`, `#expect`). Formatter/unit are app-side (test via `xcodebuild … -parallel-testing-enabled NO`, target `Food IntolerancesTests`, same as `WeatherValueFormatterTests`).

## Global Constraints

- Weight is stored **canonically in kilograms** (HealthKit + DB). Convert **only** for display; never write a converted value back.
- Conversion factor: **`2.20462` pounds per kilogram** (matches `UserProfile.weightDisplayString`).
- Precision: **one decimal**, format `"%.1f %@"`. Abbreviations: **`"kg"` / `"lb"`** (singular `lb`, per spec).
- Weight event identity (the only `kg`-unit producer, `HealthKitSampleMapper.swift:63`): `category == .bodyMetric && subtype == "weight" && unit == "kg"`.
- Display chain order at both surfaces: `BodyMetricValueFormatter.line(…) ?? WeatherValueFormatter.line(…) ?? EventDisplay.valueLine(…)`.
- `EventDisplay` (HealthGraphCore) stays **UNCHANGED** — the pure `%.1f kg` is the fallback; **HealthGraphCore gains no `UserProfile` dependency**.
- Preference source: reuse `UserProfile.unitPreference` (`"imperial"` → pounds, `"metric"` → kilograms). **No new setting, no Health-tab picker.** No-profile / unrecognized preference → device locale (US → pounds, else kilograms).
- App-target tests MUST run with **`-parallel-testing-enabled NO`**. The lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing teardown crash — not a regression.

## Deviations from the spec (flagged for the human before execution)

Two refinements discovered while mapping the code. Both are behavior-preserving improvements; if the human prefers the spec's literal wording, revert to it.

1. **Detail screen self-resolves instead of being passed the unit.** The spec said pass `weightUnit` into `EventDetailView` via `TimelineView`'s `navigationDestination`. But `EventDetailView` has a **second** construction site — `InsightDetailView.swift:57` (the Insights evidence drill-down) — with no parent profile lookup. So `EventDetailView` resolves its own unit via its own `@Query userProfiles` (exactly as it already self-reads `@AppStorage("hg.temperatureUnit")`). One query per detail screen (not per row) → both entry points honor the preference, and no call site needs a new argument. The **row** still takes the unit from the single parent resolution (rows are many; a per-row `@Query` is the cost we avoid).
2. **`resolved(preference: String?)` instead of `resolved(from: UserProfile?)`.** Same behavior, but keeps the resolver a pure function of a string — testable without constructing SwiftData `@Model` instances, and it never couples the formatter to `UserProfile`. Call sites pass `userProfiles.first?.unitPreference`.

## File Structure

- **Create** `Views/HealthOS/Timeline/BodyMetricValueFormatter.swift` — `WeightUnit` enum (+ `abbreviation`, `resolved(preference:locale:)`) and `BodyMetricValueFormatter.line(for:unit:)`. Peer to `WeatherValueFormatter.swift`, same directory.
- **Create** `Food IntolerancesTests/BodyMetricValueFormatterTests.swift` — unit tests (peer to `WeatherValueFormatterTests.swift`).
- **Modify** `Views/HealthOS/Timeline/TimelineView.swift` — `import SwiftData`, `@Query userProfiles`, resolve `weightUnit` once, pass into `TimelineEventRow` (2 call sites: feed + `#Preview`).
- **Modify** `Views/HealthOS/Timeline/TimelineEventRow.swift` — new `weightUnit: WeightUnit` property; prepend the weight formatter to `displayValueLine`.
- **Modify** `Views/HealthOS/Timeline/EventDetailView.swift` — `import SwiftData`, `@Query userProfiles`, self-resolve `weightUnit`, prepend the weight formatter to the header value line. No signature change (both call sites unaffected).

---

### Task 1: `WeightUnit` + `BodyMetricValueFormatter` (pure, app-side)

**Files:**
- Create: `Views/HealthOS/Timeline/BodyMetricValueFormatter.swift`
- Test: `Food IntolerancesTests/BodyMetricValueFormatterTests.swift`

**Interfaces:**
- Consumes: `HealthGraphCore.HealthEvent` (`.category: EventCategory`, `.subtype: String?`, `.value: Double?`, `.unit: String?`), `EventCategory.bodyMetric`.
- Produces (later tasks rely on these exact signatures):
  - `enum WeightUnit { case kilograms, pounds }`
  - `WeightUnit.abbreviation: String` → `"kg"` / `"lb"`
  - `static WeightUnit.resolved(preference: String?, locale: Locale = .current) -> WeightUnit`
  - `enum BodyMetricValueFormatter { static func line(for event: HealthEvent, unit: WeightUnit) -> String? }`

- [ ] **Step 1: Write the failing tests**

Create `Food IntolerancesTests/BodyMetricValueFormatterTests.swift`:

```swift
import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

struct BodyMetricValueFormatterTests {
    /// A canonical body-weight event: category .bodyMetric, subtype "weight",
    /// unit "kg", value in kilograms (mirrors HealthKitSampleMapper's bodyMass row).
    private func weight(_ kg: Double?) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .bodyMetric,
                    subtype: "weight", value: kg, unit: "kg", source: .healthKit)
    }

    @Test func kilogramsRenderOneDecimal() {
        #expect(BodyMetricValueFormatter.line(for: weight(81.4), unit: .kilograms) == "81.4 kg")
        // A whole-number kg keeps its trailing ".0" — guards against an Int-style "90 kg"
        // regression (cf. UserProfile.weightDisplayString, which does render Int kg).
        #expect(BodyMetricValueFormatter.line(for: weight(90), unit: .kilograms) == "90.0 kg")
    }
    @Test func poundsConvertThenRenderOneDecimal() {
        // 81.4 × 2.20462 = 179.456… → "%.1f" → 179.5
        #expect(BodyMetricValueFormatter.line(for: weight(81.4), unit: .pounds) == "179.5 lb")
        // 90.0 × 2.20462 = 198.4158 → 198.4  (pins conversion + rounding direction)
        #expect(BodyMetricValueFormatter.line(for: weight(90), unit: .pounds) == "198.4 lb")
    }
    @Test func kilogramsRoundsToOneDecimal() {
        // The nearest double to 81.45 is >81.45 (NOT a half-tie), so "%.1f" rounds up to 81.5
        // under any rounding mode — deterministic, not platform-fragile. Discriminates round
        // vs truncate (truncation would give 81.4).
        #expect(BodyMetricValueFormatter.line(for: weight(81.45), unit: .kilograms) == "81.5 kg")
    }
    @Test func nonWeightEventReturnsNil() {   // caller falls back to WeatherValueFormatter / EventDisplay
        let symptom = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .symptom,
                                  subtype: "migraine", value: 5, source: .manual)
        #expect(BodyMetricValueFormatter.line(for: symptom, unit: .pounds) == nil)
        // bodyMetric but not the weight subtype → nil (defensive: only "weight" converts)
        let bodyFat = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .bodyMetric,
                                  subtype: "bodyFat", value: 20, unit: "%", source: .healthKit)
        #expect(BodyMetricValueFormatter.line(for: bodyFat, unit: .pounds) == nil)
        // A future kg-unit bodyMetric that ISN'T weight (e.g. HealthKit lean body mass, also kg)
        // must still return nil — isolates the subtype guard from the unit guard.
        let leanMass = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .bodyMetric,
                                   subtype: "leanBodyMass", value: 80, unit: "kg", source: .healthKit)
        #expect(BodyMetricValueFormatter.line(for: leanMass, unit: .pounds) == nil)
        // weight subtype but a non-kg unit → nil (guard pins the canonical-unit assumption)
        let oddUnit = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .bodyMetric,
                                  subtype: "weight", value: 81.4, unit: "lb", source: .healthKit)
        #expect(BodyMetricValueFormatter.line(for: oddUnit, unit: .pounds) == nil)
        #expect(BodyMetricValueFormatter.line(for: weight(nil), unit: .kilograms) == nil)   // no value → nil
    }
    @Test func resolvedFromProfilePreference() {
        #expect(WeightUnit.resolved(preference: "imperial", locale: Locale(identifier: "de_DE")) == .pounds)   // explicit wins over locale
        #expect(WeightUnit.resolved(preference: "metric", locale: Locale(identifier: "en_US")) == .kilograms)  // explicit wins over locale
    }
    @Test func resolvedFallsBackToLocaleWhenNoOrUnknownPreference() {
        #expect(WeightUnit.resolved(preference: nil, locale: Locale(identifier: "en_US")) == .pounds)
        #expect(WeightUnit.resolved(preference: nil, locale: Locale(identifier: "en_GB")) == .kilograms)
        #expect(WeightUnit.resolved(preference: nil, locale: Locale(identifier: "de_DE")) == .kilograms)
        #expect(WeightUnit.resolved(preference: "garbage", locale: Locale(identifier: "en_US")) == .pounds)     // unknown → locale
        #expect(WeightUnit.resolved(preference: "garbage", locale: Locale(identifier: "de_DE")) == .kilograms)  // unknown → locale
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/BodyMetricValueFormatterTests" 2>&1 | tail -20
```
Expected: FAILS to compile — `cannot find 'BodyMetricValueFormatter'` / `cannot find type 'WeightUnit'`.

- [ ] **Step 3: Write the implementation**

Create `Views/HealthOS/Timeline/BodyMetricValueFormatter.swift`:

```swift
import Foundation
import HealthGraphCore

/// The user's weight unit for Timeline display. Body mass is stored canonically
/// in kilograms (HealthKit + DB); this only affects how it's shown.
enum WeightUnit {
    case kilograms, pounds

    /// Unit abbreviation as shown in the Timeline.
    var abbreviation: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }

    /// Resolve the display unit from the profile's stored `unitPreference`
    /// ("imperial" → pounds, "metric" → kilograms). A nil preference (no profile)
    /// — or any unrecognized value — falls back to the device locale: US → pounds,
    /// everywhere else → kilograms. Locale is injectable for testability (mirrors
    /// `TemperatureUnit.localeDefault`).
    static func resolved(preference: String?, locale: Locale = .current) -> WeightUnit {
        switch preference {
        case "imperial": return .pounds
        case "metric": return .kilograms
        default: return locale.measurementSystem == .us ? .pounds : .kilograms
        }
    }
}

/// The Timeline value line for a body-weight event, in the user's unit, to one
/// decimal place. Returns nil for any non-weight event (caller falls back to the
/// weather formatter, then `EventDisplay.valueLine`). Stored weight is canonical kg.
enum BodyMetricValueFormatter {
    private static let poundsPerKilogram = 2.20462

    static func line(for event: HealthEvent, unit: WeightUnit) -> String? {
        guard event.category == .bodyMetric,
              event.subtype == "weight",
              event.unit == "kg",
              let kg = event.value else { return nil }
        let shown = unit == .pounds ? kg * poundsPerKilogram : kg
        return String(format: "%.1f %@", shown, unit.abbreviation)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/BodyMetricValueFormatterTests" 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` — all 6 `@Test` cases pass.

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Timeline/BodyMetricValueFormatter.swift" "Food IntolerancesTests/BodyMetricValueFormatterTests.swift"
git commit -m "feat(app): WeightUnit + BodyMetricValueFormatter — profile-aware kg/lb weight display"
```

---

### Task 2: Route the resolved unit into the Timeline row

**Files:**
- Modify: `Views/HealthOS/Timeline/TimelineView.swift` (add SwiftData query + resolution; 2 `TimelineEventRow(` call sites at `:119` and `:237`)
- Modify: `Views/HealthOS/Timeline/TimelineEventRow.swift` (new property + chain)
- Modify: `Views/HealthOS/Shell/HealthOSRootView.swift` (give the 2 `#Preview`s an in-memory container, now that `TimelineView` hosts a `@Query`)

**Interfaces:**
- Consumes: `WeightUnit`, `WeightUnit.resolved(preference:locale:)`, `BodyMetricValueFormatter.line(for:unit:)` (Task 1); `UserProfile.unitPreference: String`.
- Produces: `TimelineEventRow(event:weightUnit:onTap:)` — the new required `weightUnit: WeightUnit` label sits between `event` and the trailing `onTap` closure.

- [ ] **Step 1: Add the `weightUnit` property and extend the display chain in `TimelineEventRow`**

In `Views/HealthOS/Timeline/TimelineEventRow.swift`, add the property directly under `let onTap`:

```swift
struct TimelineEventRow: View {
    let event: HealthEvent
    let weightUnit: WeightUnit
    let onTap: (HealthEvent) -> Void
```

Replace `displayValueLine` (currently lines 18-20) with the weight formatter first in the chain:

```swift
    private var displayValueLine: String? {
        BodyMetricValueFormatter.line(for: event, unit: weightUnit)
            ?? WeatherValueFormatter.line(for: event, unit: TemperatureUnit.resolved(from: rawTempUnit))
            ?? EventDisplay.valueLine(for: event)
    }
```

(No a11y change needed — `accessibilitySummary` already reads `displayValueLine`.)

- [ ] **Step 2: Wire `TimelineView` to resolve once and pass it down**

In `Views/HealthOS/Timeline/TimelineView.swift`:

Add the SwiftData import at the top (after `import SwiftUI`):
```swift
import SwiftData
```

Add the query + resolver among the other `@State`/`@Environment` properties. The `@StateObject private var viewModel = …` declaration spans two lines (`:5-6`); insert **after** line 6:
```swift
    @Query private var userProfiles: [UserProfile]
    private var weightUnit: WeightUnit {
        WeightUnit.resolved(preference: userProfiles.first?.unitPreference)
    }
```

Update the feed call site (currently `:119`) to pass the unit — note the label goes before the trailing closure:
```swift
                        case .event(let event):
                            TimelineEventRow(event: event, weightUnit: weightUnit) { tapped in
                                path.append(tapped)
                            }
```

Update the `#Preview` call site (currently `:237`) so the preview still compiles (no profile in a preview → a fixed unit is fine):
```swift
                    if case .event(let e) = item {
                        TimelineEventRow(event: e, weightUnit: .kilograms) { _ in }
```

Then, because `TimelineView` now hosts a `@Query`, give the two `HealthOSRootView` `#Preview`s a `ModelContainer` (they mount `TimelineView()` directly and currently supply none, so the canvas would warn/fault). In `Views/HealthOS/Shell/HealthOSRootView.swift`, add one line to **both** previews (`:55-60` and `:62-68`), after the existing `.environmentObject(...)` modifiers:
```swift
        .modelContainer(for: UserProfile.self, inMemory: true)
```
(The dark preview keeps its trailing `.preferredColorScheme(.dark)` after this line. This is preview-only — the shipping app already provides the container at the root, `FoodIntolerancesApp.swift:110`.)

- [ ] **Step 3: Build the app target to verify it compiles**

Run:
```bash
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`. (This wiring is a thin `??` chain over the Task-1 formatter, which is already unit-tested; there is no separate view unit test — the visual check is the device gate at the end.)

- [ ] **Step 4: Run the app test suite to confirm no regressions**

Run:
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -25
```
Expected: all suites pass **except** the known `SwiftDataMigratorTests` teardown crash (pre-existing; not caused by this change). `BodyMetricValueFormatterTests` is green.

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Timeline/TimelineView.swift" "Views/HealthOS/Timeline/TimelineEventRow.swift"
git commit -m "feat(app): Timeline weight rows honor the profile's kg/lb preference (single parent lookup)"
```

---

### Task 3: Weight-aware value line in `EventDetailView`

**Files:**
- Modify: `Views/HealthOS/Timeline/EventDetailView.swift`

**Interfaces:**
- Consumes: `WeightUnit`, `WeightUnit.resolved(preference:locale:)`, `BodyMetricValueFormatter.line(for:unit:)` (Task 1); `UserProfile.unitPreference`.
- Produces: nothing new — `EventDetailView`'s initializer is unchanged, so both call sites (`TimelineView.swift:24`, `InsightDetailView.swift:57`) are unaffected.

- [ ] **Step 1: Add the SwiftData query + self-resolution**

In `Views/HealthOS/Timeline/EventDetailView.swift`:

Add the import at the top (after `import SwiftUI`):
```swift
import SwiftData
```

Add the query + resolver next to the existing `@AppStorage("hg.temperatureUnit")` (mirrors how temperature is self-read here):
```swift
    @AppStorage("hg.temperatureUnit") private var rawTempUnit = ""
    @Query private var userProfiles: [UserProfile]
    private var weightUnit: WeightUnit {
        WeightUnit.resolved(preference: userProfiles.first?.unitPreference)
    }
```

- [ ] **Step 2: Prepend the weight formatter to the header value line**

In the `header` computed property, replace the existing value-line resolution (currently `:73`):
```swift
                    if let line = WeatherValueFormatter.line(for: displayEvent, unit: TemperatureUnit.resolved(from: rawTempUnit)) ?? EventDisplay.valueLine(for: displayEvent) {
```
with:
```swift
                    if let line = BodyMetricValueFormatter.line(for: displayEvent, unit: weightUnit) ?? WeatherValueFormatter.line(for: displayEvent, unit: TemperatureUnit.resolved(from: rawTempUnit)) ?? EventDisplay.valueLine(for: displayEvent) {
```

- [ ] **Step 3: Build the app target to verify it compiles**

Run:
```bash
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **` (both `EventDetailView` call sites still compile — no signature change).

- [ ] **Step 4: Run the app test suite to confirm no regressions**

Run:
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -25
```
Expected: all suites pass except the known `SwiftDataMigratorTests` teardown crash.

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Timeline/EventDetailView.swift"
git commit -m "feat(app): EventDetailView shows weight in the profile's unit (self-resolved; covers Insights drill-down too)"
```

---

## Device verification (finishing gate, after all tasks)

On the booted iPhone 17 Pro, with a body-weight event in the Timeline (seed via HealthKit or a demo weight event):
1. Profile **Imperial** → Timeline row **and** detail show `lb`; Profile **Metric** → both show `kg`.
2. No profile on a US-locale device → `lb`; the same weight reached from the **Insights** evidence drill-down also shows the profile unit.
3. VoiceOver on the row reads the same value string.
4. Light + dark render unchanged otherwise.

## Self-Review (completed)

- **Spec coverage:** §3A `WeightUnit`/`BodyMetricValueFormatter` → Task 1. §3B single parent resolution → Task 2. §3C row + detail wiring → Tasks 2/3. §5 formatter + `resolved` tests → Task 1; device checks → finishing gate. §2 decisions (reuse `unitPreference`, kg canonical, one decimal, core independence, no new picker) → Global Constraints. The two spec deviations are flagged above.
- **Placeholder scan:** none — every step carries full code/commands.
- **Type consistency:** `WeightUnit`, `abbreviation`, `resolved(preference:locale:)`, `BodyMetricValueFormatter.line(for:unit:)`, and `TimelineEventRow(event:weightUnit:onTap:)` are used identically across tasks.
