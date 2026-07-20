# Temperature Units + Display Rounding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Round temperature/humidity in the Timeline to whole numbers, and add a °C/°F unit setting (default °F in the US, locale-based). Display-only — stored °C and the engine are untouched.

**Architecture:** A pure app-layer `TemperatureUnit` (with a locale-aware resolver) + `WeatherValueFormatter` that converts stored °C → the chosen unit and rounds *after* conversion. `TimelineEventRow` + `EventDetailView` use it with a fallback to the existing `EventDisplay.valueLine` for non-weather events. A segmented °C/°F picker in the Health tab binds to the same `@AppStorage`.

**Tech Stack:** SwiftUI, Swift Testing, `@AppStorage`, `Locale.measurementSystem` (iOS 16+; deployment 26.5).

Design: `docs/superpowers/specs/2026-07-20-temperature-units-design.md`.

## Global Constraints

- **Display-only.** No change to stored values, the evidence engine, or `EventDisplay` (core, pref-unaware). °C stays the canonical stored unit; conversion + rounding happen at render.
- **Round AFTER converting** (`°C → °F` then round), never before — else the °C→°F math loses precision.
- **Locale default via an injectable `Locale`** (so it's testable): `localeDefault(for: Locale = .current)` → `.us` measurement system → °F, else °C. `resolved(from raw:locale:)` — explicit "C"/"F" wins; empty/unknown → locale default.
- **Format:** `20°C` / `68°F` / `69%` (unit/degree attached, no space).
- **New app files** go under the tracked `Views/HealthOS/…` path (NOT the decoy `Food Intolerances/Views/…`).
- **App-target tests MUST run `-parallel-testing-enabled NO`;** the lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing teardown crash.
- **Simulator:** iPhone 17 Pro (iOS 26.5).
- **Out of scope:** weight/other unit prefs, a unit choice for humidity/pressure, any data migration.

---

### Task 1: `TemperatureUnit` + `WeatherValueFormatter` (+ tests)

**Files:**
- Create: `Views/HealthOS/Timeline/WeatherValueFormatter.swift`
- Test: `Food IntolerancesTests/WeatherValueFormatterTests.swift`

**Interfaces:** Produces `TemperatureUnit` (`.celsius`/`.fahrenheit`, `rawValue` "C"/"F") + `localeDefault(for:)` + `resolved(from:locale:)`, and `WeatherValueFormatter.line(for:unit:) -> String?`. Task 2's views consume both.

- [ ] **Step 1: Write the failing tests first.** `WeatherValueFormatterTests.swift`:

```swift
import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

struct WeatherValueFormatterTests {
    private func env(_ subtype: String, _ v: Double) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .environment,
                    subtype: subtype, value: v, source: .weatherAPI)
    }
    @Test func temperatureCelsiusRoundsWhole() {
        #expect(WeatherValueFormatter.line(for: env("temperature", 20), unit: .celsius) == "20°C")
        #expect(WeatherValueFormatter.line(for: env("temperature", 19.6372), unit: .celsius) == "20°C")
    }
    @Test func temperatureFahrenheitConvertsThenRounds() {
        #expect(WeatherValueFormatter.line(for: env("temperature", 20), unit: .fahrenheit) == "68°F")       // 20·9/5+32
        #expect(WeatherValueFormatter.line(for: env("temperature", 19.6372), unit: .fahrenheit) == "67°F")  // 67.35 → 67
        #expect(WeatherValueFormatter.line(for: env("temperature", 0), unit: .fahrenheit) == "32°F")
        #expect(WeatherValueFormatter.line(for: env("temperature", -5), unit: .fahrenheit) == "23°F")       // -5·9/5+32
    }
    @Test func humidityRoundsWholePercentRegardlessOfUnit() {
        #expect(WeatherValueFormatter.line(for: env("humidity", 69.3915), unit: .fahrenheit) == "69%")
        #expect(WeatherValueFormatter.line(for: env("humidity", 69.3915), unit: .celsius) == "69%")
    }
    @Test func nonWeatherEventReturnsNil() {   // caller falls back to EventDisplay.valueLine
        let symptom = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .symptom,
                                  subtype: "migraine", value: 5, source: .manual)
        #expect(WeatherValueFormatter.line(for: symptom, unit: .fahrenheit) == nil)
        #expect(WeatherValueFormatter.line(for: env("pressure", 1013), unit: .fahrenheit) == nil)   // env but not temp/humidity
    }
    @Test func localeDefaultAndResolution() {
        #expect(TemperatureUnit.localeDefault(for: Locale(identifier: "en_US")) == .fahrenheit)
        #expect(TemperatureUnit.localeDefault(for: Locale(identifier: "en_GB")) == .celsius)
        #expect(TemperatureUnit.localeDefault(for: Locale(identifier: "de_DE")) == .celsius)
        #expect(TemperatureUnit.resolved(from: "F", locale: Locale(identifier: "de_DE")) == .fahrenheit)  // explicit wins
        #expect(TemperatureUnit.resolved(from: "C", locale: Locale(identifier: "en_US")) == .celsius)
        #expect(TemperatureUnit.resolved(from: "", locale: Locale(identifier: "en_US")) == .fahrenheit)   // empty → locale
        #expect(TemperatureUnit.resolved(from: "garbage", locale: Locale(identifier: "de_DE")) == .celsius)
    }
}
```

- [ ] **Step 2: Run to confirm failure.** `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests/WeatherValueFormatterTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -8` → FAIL to compile (`TemperatureUnit`/`WeatherValueFormatter` undefined).

- [ ] **Step 3: Create `WeatherValueFormatter.swift`:**

```swift
import Foundation
import HealthGraphCore

enum TemperatureUnit: String, CaseIterable {
    case celsius = "C", fahrenheit = "F"

    /// Device-locale default: US (imperial) → °F, everywhere else → °C. Locale is
    /// injectable for testability.
    static func localeDefault(for locale: Locale = .current) -> TemperatureUnit {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }
    /// An explicit stored choice ("C"/"F") wins; empty/unknown → locale default.
    static func resolved(from raw: String, locale: Locale = .current) -> TemperatureUnit {
        TemperatureUnit(rawValue: raw) ?? localeDefault(for: locale)
    }
}

/// The Timeline value line for a weather event, in the user's unit, rounded to a
/// whole number. Returns nil for non-weather events (caller falls back to
/// EventDisplay.valueLine). Stored temperature is canonical °C.
enum WeatherValueFormatter {
    static func line(for event: HealthEvent, unit: TemperatureUnit) -> String? {
        guard event.category == .environment, let v = event.value else { return nil }
        switch event.subtype {
        case "temperature":
            let shown = unit == .fahrenheit ? v * 9 / 5 + 32 : v
            return "\(Int(shown.rounded()))°\(unit.rawValue)"     // rawValue is "C"/"F"
        case "humidity":
            return "\(Int(v.rounded()))%"
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run the tests.** Same command as Step 2 → `** TEST SUCCEEDED **` (all 5 tests pass). Also confirm the app still builds: `xcodebuild build … -quiet 2>&1 | tail -6` → `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
git add "Views/HealthOS/Timeline/WeatherValueFormatter.swift" \
        "Food IntolerancesTests/WeatherValueFormatterTests.swift"
git commit -m "feat(app): TemperatureUnit (locale-default) + WeatherValueFormatter (round-after-convert)"
```

---

### Task 2: Wire the Timeline/detail rendering + the Health-tab picker

**Files:**
- Modify: `Views/HealthOS/Timeline/TimelineEventRow.swift` (value line + a11y)
- Modify: `Views/HealthOS/Timeline/EventDetailView.swift` (value line)
- Modify: `Views/HealthOS/Health/HealthTabView.swift` (the °C/°F picker row)

**Interfaces:** Consumes `TemperatureUnit`/`WeatherValueFormatter` from Task 1, plus `@AppStorage("hg.temperatureUnit")`.

- [ ] **Step 1: Wire `TimelineEventRow`.** Add the pref + a shared computed line, and use it in BOTH the visible value line and the accessibility string:
  - Add near the top of the struct: `@AppStorage("hg.temperatureUnit") private var rawTempUnit = ""`.
  - Add a computed helper: `private var displayValueLine: String? { WeatherValueFormatter.line(for: event, unit: TemperatureUnit.resolved(from: rawTempUnit)) ?? EventDisplay.valueLine(for: event) }`.
  - In `body` (~line 40), replace `if let line = EventDisplay.valueLine(for: event) {` with `if let line = displayValueLine {`.
  - In `accessibilitySummary` (~line 63), replace `if let line = EventDisplay.valueLine(for: event) { parts.append(line) }` with `if let line = displayValueLine { parts.append(line) }`.

- [ ] **Step 2: Wire `EventDetailView`.** Add `@AppStorage("hg.temperatureUnit") private var rawTempUnit = ""` near the other `@State`s, and at ~line 70 replace `if let line = EventDisplay.valueLine(for: displayEvent) {` with:

```swift
                    if let line = WeatherValueFormatter.line(for: displayEvent, unit: TemperatureUnit.resolved(from: rawTempUnit)) ?? EventDisplay.valueLine(for: displayEvent) {
```

- [ ] **Step 3: Add the °C/°F picker row.** In `HealthTabView.swift`:
  - Add near the top of the struct: `@AppStorage("hg.temperatureUnit") private var rawTempUnit = ""` and a resolving binding:

```swift
    private var tempUnitBinding: Binding<TemperatureUnit> {
        Binding(get: { TemperatureUnit.resolved(from: rawTempUnit) },
                set: { rawTempUnit = $0.rawValue })
    }
```

  - Inside the settings card (the `VStack(spacing: 0) { … }.hgCard()`), immediately AFTER the "Safety reminders" `NavigationLink { RedFlagRemindersView() } label: { … }` closing brace and BEFORE the `#if DEBUG` block, insert a units row (a non-DEBUG row, so it ships):

```swift
                    Divider().padding(.leading, 16)
                    HStack {
                        Image(systemName: "thermometer.medium")
                            .foregroundStyle(HealthTheme.accent)
                        Text("Temperature")
                            .foregroundStyle(HealthTheme.ink)
                        Spacer()
                        Picker("Temperature unit", selection: tempUnitBinding) {
                            Text("°C").tag(TemperatureUnit.celsius)
                            Text("°F").tag(TemperatureUnit.fahrenheit)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 116)
                    }
                    .padding(16)
                    .accessibilityElement(children: .combine)
```

  (The `get` resolves an empty stored value to the locale default, so the segment shows the resolved unit on first open rather than blank.)

- [ ] **Step 4: Build + regression.**

Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -6` → `** BUILD SUCCEEDED **`.

Run: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "✔ Suite|✘|Test run with|\*\* TEST"` → every suite green except the known `SwiftDataMigratorTests` teardown crash (incl. the new `WeatherValueFormatterTests`).

- [ ] **Step 5: On-device / simulator check** (device preferred):
  - The Timeline shows temperature as a whole number in the resolved unit (e.g. `68°F` on a US device) and humidity as `69%` — no decimals.
  - Health tab → the **Temperature** row's **°C / °F** segmented picker: toggling it flips every temperature value in the Timeline live (humidity unchanged).
  - Tapping a temperature event → the detail view shows the same formatted value.
  - Light + dark; XXL Dynamic Type (the picker + row don't clip).

- [ ] **Step 6: Commit.**

```bash
git add "Views/HealthOS/Timeline/TimelineEventRow.swift" \
        "Views/HealthOS/Timeline/EventDetailView.swift" \
        "Views/HealthOS/Health/HealthTabView.swift"
git commit -m "feat(app): Timeline/detail render weather in the chosen unit (rounded) + Health-tab °C/°F picker"
```

---

## Definition of Done

- Temperature and humidity render as whole numbers in the Timeline + detail view (`20°C`/`68°F`/`69%`), never with decimals.
- A °C/°F picker in the Health tab flips the temperature unit live; it defaults to °F on a US device (locale-based) and °C elsewhere; an explicit choice persists.
- The formatter is unit-tested (conversion, rounding-after-convert, negative °C, humidity, the nil non-weather fallback, and the locale-default resolver); the wiring builds + is device-verified.
- Stored values, the evidence engine, and `EventDisplay` (core) are unchanged — display-only, no migration.
