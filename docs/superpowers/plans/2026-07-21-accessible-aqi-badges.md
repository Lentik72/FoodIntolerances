# Accessible AQI Badges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a small, color-coded AQI dot (accessibility-adjusted AirNow colors) next to the AQI value at all four places it appears, always keeping the number + category text.

**Architecture:** Six tuned dynamic light/dark `Color`s in `HealthTheme`; an app-side `AQICategory → Color` switch + a reusable `AQIBadge`/`AQIValueLabel` used at every site; a typed `EnvironmentDetailLine` model + `poorAirAQI(_:)` helper so the row identifies the AQI line structurally. `HealthGraphCore` gains no `Color`.

**Tech Stack:** Swift, SwiftUI, Swift Testing. App-side; tested via `xcodebuild … -parallel-testing-enabled NO` (target `Food IntolerancesTests`).

## Global Constraints

- `HealthGraphCore` / `AirQualityIndex` are **untouched** — no `Color` in core; the category **bands** stay the single source (the app switch keys on `AirQualityIndex.AQICategory`, never re-derives thresholds).
- The dot is **supplementary and decorative** (`.accessibilityHidden(true)`); the **number + category text is always present**. Never whole-row color, never color-alone.
- **One** component (`AQIValueLabel(value:aqi:)` wrapping `AQIBadge(aqi:)`) at **all four** sites — they cannot drift. The AQI value **text is passed in** (from the existing formatter/`EventDisplay`); only the dot is new.
- The AQI detail line is found by the **typed model's `subtype`/`aqi`**, never by matching the `"Air quality"` label string.
- Colors are **accessibility-adjusted** AirNow (dynamic light/dark via `HealthTheme.dyn`), documented as **not verbatim** official hex, each with a hairline border.
- App-target tests run with **`-parallel-testing-enabled NO`**; the lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing teardown crash.

## The four AQI value sites
1. Collapsed poor-air Environment headline — `EnvironmentSummaryRow` (Task 3).
2. Expanded "Air quality" detail line — `EnvironmentSummaryRow` (Task 3).
3. Raw AQI Timeline search row — `TimelineEventRow` (Task 4).
4. Event detail header — `EventDetailView` (Task 4).

---

### Task 1: Colors + `AQIBadge` + `AQIValueLabel`

**Files:**
- Modify: `Views/HealthOS/Theme/HealthTheme.swift`
- Create: `Views/HealthOS/Timeline/AQIValueLabel.swift`

**Interfaces:**
- Consumes: `HealthTheme.dyn` (existing, private — the six colors live IN `HealthTheme.swift`); `AirQualityIndex.AQICategory`, `AirQualityIndex.category(aqi:)` (core).
- Produces: `HealthTheme.aqiGood/aqiModerate/aqiUnhealthySensitive/aqiUnhealthy/aqiVeryUnhealthy/aqiHazardous: Color`; `struct AQIBadge: View` (`init(aqi: Int)`); `struct AQIValueLabel: View` (`init(value: String, aqi: Int)`).

- [ ] **Step 1: Add the six tuned AQI colors to `HealthTheme`**

In `Views/HealthOS/Theme/HealthTheme.swift`, after the `danger`/`onDanger` block (around line 27), add:
```swift
    /// EPA AirNow AQI category colors, **accessibility-adjusted** for legibility on
    /// the cream/dark surfaces (NOT verbatim official hex — pure AirNow yellow is
    /// invisible on cream, maroon is lightened for dark). Ref: airnow.gov/aqi/aqi-basics.
    /// Rendered as a small dot beside the always-present AQI number + category text.
    static let aqiGood               = dyn(light: 0x2E9E4F, dark: 0x3FD06B)   // green
    static let aqiModerate           = dyn(light: 0xC9A200, dark: 0xE8C33A)   // yellow → readable gold
    static let aqiUnhealthySensitive = dyn(light: 0xE8730C, dark: 0xFF9A3D)   // orange
    static let aqiUnhealthy          = dyn(light: 0xD42A2A, dark: 0xFF5C5C)   // red
    static let aqiVeryUnhealthy      = dyn(light: 0x8F3F97, dark: 0xB667BE)   // purple
    static let aqiHazardous          = dyn(light: 0x7E0023, dark: 0xC64B6B)   // maroon
```

- [ ] **Step 2: Create the badge + label component**

Create `Views/HealthOS/Timeline/AQIValueLabel.swift`:
```swift
import SwiftUI
import HealthGraphCore

/// The accessibility-adjusted AirNow color for an AQI category. Keys on the core
/// category (single source of the band thresholds); the six colors live in HealthTheme.
private func aqiColor(for category: AirQualityIndex.AQICategory) -> Color {
    switch category {
    case .good:               HealthTheme.aqiGood
    case .moderate:           HealthTheme.aqiModerate
    case .unhealthySensitive: HealthTheme.aqiUnhealthySensitive
    case .unhealthy:          HealthTheme.aqiUnhealthy
    case .veryUnhealthy:      HealthTheme.aqiVeryUnhealthy
    case .hazardous:          HealthTheme.aqiHazardous
    }
}

/// A small, decorative AQI severity dot (AirNow color for the value's band) with a
/// hairline border so light fills still read on cream. Never the sole signal — the
/// AQI number + category text always accompany it (see `AQIValueLabel`).
struct AQIBadge: View {
    let aqi: Int
    var body: some View {
        Circle()
            .fill(aqiColor(for: AirQualityIndex.category(aqi: aqi)))
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(HealthTheme.inkSecondary.opacity(0.35), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The single AQI-value presentation used at every site: the severity dot followed
/// by the caller-provided value text (e.g. "132 · Unhealthy for sensitive groups").
/// The caller applies its own `.font`/`.foregroundStyle` (the dot's fill is explicit,
/// so it is unaffected). Combined for VoiceOver so it reads the text once, dot silent.
struct AQIValueLabel: View {
    let value: String
    let aqi: Int
    var body: some View {
        HStack(spacing: 6) {
            AQIBadge(aqi: aqi)
            Text(value)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("AQI badges — all bands") {
    VStack(alignment: .leading, spacing: 10) {
        AQIValueLabel(value: "25 · Good", aqi: 25)
        AQIValueLabel(value: "75 · Moderate", aqi: 75)
        AQIValueLabel(value: "132 · Unhealthy for sensitive groups", aqi: 132)
        AQIValueLabel(value: "175 · Unhealthy", aqi: 175)
        AQIValueLabel(value: "250 · Very unhealthy", aqi: 250)
        AQIValueLabel(value: "350 · Hazardous", aqi: 350)
    }
    .font(.footnote)
    .padding()
    .background(HealthTheme.paper)
}
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -12
```
Expected: `** BUILD SUCCEEDED **`. (View + color code — no unit test; `Color` equality isn't reliably assertable and the category bands are already covered by `AirQualityIndexTests`. Visual correctness is the device gate.)

- [ ] **Step 4: Commit**

```bash
git add "Views/HealthOS/Theme/HealthTheme.swift" "Views/HealthOS/Timeline/AQIValueLabel.swift"
git commit -m "feat(app): AQIBadge/AQIValueLabel + tuned AirNow AQI colors (accessibility-adjusted, app-side)"
```

---

### Task 2: Typed detail-line model + `poorAirAQI` (formatter)

**Files:**
- Modify: `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift`
- Modify: `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift` (retype the bridging `detailLines` property only — so the app compiles; the badge wiring is Task 3)
- Test: `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift`

**Interfaces:**
- Produces: `struct EnvironmentDetailLine { let subtype: String?; let label: String; let value: String?; let aqi: Int? }`; `EnvironmentSummaryFormatter.detailLines(...) -> [EnvironmentDetailLine]` (was a `(label, value?)` tuple); `static func poorAirAQI(_ summary:) -> Int?`.

- [ ] **Step 1: Add the failing tests**

In `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift`, add these `@Test`s (the existing tuple-style tests keep compiling — `EnvironmentDetailLine` has `.label`/`.value`):
```swift
    // Typed detail-line model — subtype preserved; AQI line carries the value for the badge.
    @Test func airQualityDetailLineCarriesSubtypeAndAQI() {
        let rows = EnvironmentSummaryFormatter.detailLines(day([temp(24, 12), airQuality(132)]), unit: c)
        let air = rows.first { $0.subtype == "airQuality" }
        #expect(air?.aqi == 132)                     // the badge's color input, structural (not label-matched)
        #expect(air?.value == "132 · Unhealthy for sensitive groups")
        let tempLine = rows.first { $0.subtype == "temperature" }
        #expect(tempLine?.aqi == nil)                // non-AQI lines carry no aqi
        #expect(tempLine?.subtype == "temperature")  // subtype preserved for every line
        // The detail line badges ALL bands, not just poor air — a good-air line still carries its aqi.
        let good = EnvironmentSummaryFormatter.detailLines(day([temp(24, 12), airQuality(42)]), unit: c)
        #expect(good.first { $0.subtype == "airQuality" }?.aqi == 42)   // guards against gating detail aqi to poor-air only
    }
    // poorAirAQI — mirrors exactly when the collapsed headline leads with AQI.
    @Test func poorAirAQIReturnsValueOnlyOnPoorAirDays() {
        #expect(EnvironmentSummaryFormatter.poorAirAQI(day([temp(24, 12), airQuality(132)])) == 132)   // >= 101 → poor
        #expect(EnvironmentSummaryFormatter.poorAirAQI(day([temp(24, 12), airQuality(42)])) == nil)    // < 101 → nil (temp leads)
        #expect(EnvironmentSummaryFormatter.poorAirAQI(day([temp(24, 12)])) == nil)                    // no AQI event → nil
        #expect(EnvironmentSummaryFormatter.poorAirAQI(day([airQuality(101)])) == 101)                 // == threshold → poor (pins >=, not >)
        #expect(EnvironmentSummaryFormatter.poorAirAQI(day([airQuality(100)])) == nil)                 // one below → nil
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/EnvironmentSummaryFormatterTests" 2>&1 | tail -20
```
Expected: FAILS to compile — `value of type '...' has no member 'subtype'` / `no member 'aqi'` / `cannot find 'poorAirAQI'`.

- [ ] **Step 3: Convert `detailLines` to the typed model + add `poorAirAQI`**

In `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift`, add the model at the top of the file (after the imports):
```swift
/// One expanded environment reading. `subtype` is the source event's subtype (so the
/// row can identify the AQI line structurally); `aqi` is set ONLY for the airQuality
/// line — the badge's color input. `value == nil` → a presence line (mercury).
struct EnvironmentDetailLine {
    let subtype: String?
    let label: String
    let value: String?
    let aqi: Int?
}
```
Replace the `headline`'s poor-air branch (lines ~10-14) so it shares the check with `poorAirAQI`:
```swift
        // Poor-air days lead with the AQI — the most health-salient signal that day.
        if let aqi = poorAirAQI(summary) {
            return "AQI \(aqi) · \(AirQualityIndex.category(aqi: aqi).name)"
        }
```
Add the helper (near `headline`):
```swift
    /// The AQI value when the collapsed headline leads with AQI (a poor-air day, AQI
    /// >= poorAirThreshold), else nil. Shares the poor-air check with `headline` so the
    /// dot appears exactly when the headline shows the AQI.
    static func poorAirAQI(_ summary: EnvironmentDaySummary) -> Int? {
        guard let aq = summary.events.first(where: { $0.subtype == "airQuality" }),
              let v = aq.value, Int(v) >= AirQualityIndex.poorAirThreshold else { return nil }
        return Int(v)
    }
```
Replace `detailLines`'s signature + body to build `EnvironmentDetailLine`s (keep the pressure-fold, the mercury presence line, and the defensive lone-pressureDrop exactly as before, now carrying `subtype`, and set `aqi` on the airQuality line):
```swift
    static func detailLines(_ summary: EnvironmentDaySummary, unit: TemperatureUnit) -> [EnvironmentDetailLine] {
        var rows: [EnvironmentDetailLine] = []
        for e in summary.events {
            guard let subtype = e.subtype else { continue }
            switch subtype {
            case "pressureDrop":
                continue   // folded into the pressure line
            case "pressure":
                var v = EventDisplay.valueLine(for: e)
                if let drop = summary.events.first(where: { $0.subtype == "pressureDrop" }), let d = drop.value {
                    v = [v, "↓\(Int(d.rounded())) hPa"].compactMap { $0 }.joined(separator: " · ")
                }
                rows.append(EnvironmentDetailLine(subtype: subtype, label: EventDisplay.title(for: e), value: v, aqi: nil))
            case "airQuality":
                rows.append(EnvironmentDetailLine(subtype: subtype, label: EventDisplay.title(for: e),
                                                  value: value(subtype, summary, unit), aqi: e.value.map { Int($0) }))
            default:
                rows.append(EnvironmentDetailLine(subtype: subtype, label: EventDisplay.title(for: e),
                                                  value: value(subtype, summary, unit), aqi: nil))
            }
        }
        // Defensive: a lone pressureDrop with no pressure event still shows.
        if !summary.events.contains(where: { $0.subtype == "pressure" }),
           let drop = summary.events.first(where: { $0.subtype == "pressureDrop" }) {
            rows.append(EnvironmentDetailLine(subtype: drop.subtype, label: EventDisplay.title(for: drop),
                                              value: EventDisplay.valueLine(for: drop), aqi: nil))
        }
        return rows
    }
```
(`value(_:_:_:)` private helper is unchanged.)

Then, in `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift`, **retype the bridging computed property** (line 19) — its explicit tuple annotation no longer matches the formatter's new return type, so the app target won't compile (which the Step 4 test run needs) until this changes. The badge wiring itself is Task 3; this is only the type:
```swift
    private var detailLines: [EnvironmentDetailLine] {
        EnvironmentSummaryFormatter.detailLines(summary, unit: unit)
    }
```
(`ForEach(detailLines, id: \.label)`, `line.label`/`line.value`, and `detailLines.count >= 2` all keep compiling — `EnvironmentDetailLine` provides `.label`/`.value`, and `\.label` is still a `String` keypath.)

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **` — the two new tests pass and all pre-existing `EnvironmentSummaryFormatterTests` still pass (they read `.label`/`.value`, which the struct provides).

- [ ] **Step 5: Commit**

```bash
git add \
  "Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift" \
  "Views/HealthOS/Timeline/EnvironmentSummaryRow.swift" \
  "Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift"
git commit -m "feat(app): typed EnvironmentDetailLine (subtype/aqi) + poorAirAQI helper"
```

---

### Task 3: Badge the Environment row (headline + detail line)

**Files:**
- Modify: `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift`

**Interfaces:**
- Consumes: `AQIValueLabel` (Task 1); `EnvironmentSummaryFormatter.poorAirAQI` + `EnvironmentDetailLine.aqi` (Task 2).

- [ ] **Step 1: Badge the collapsed headline on poor-air days**

In `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift`, replace the headline `Text` (currently lines ~49-52):
```swift
                    Text(headline)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkMuted)
                        .multilineTextAlignment(.trailing)
```
with a poor-air branch (the row's own `.accessibilityLabel("Environment, \(headline)")` already carries the text, so VoiceOver is unchanged):
```swift
                    if let aqi = EnvironmentSummaryFormatter.poorAirAQI(summary) {
                        AQIValueLabel(value: headline, aqi: aqi)
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.inkMuted)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(headline)
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.inkMuted)
                            .multilineTextAlignment(.trailing)
                    }
```

- [ ] **Step 2: Badge the "Air quality" detail line**

In the `breakdown` view, replace the value `Text` (currently lines ~89-93):
```swift
                    if let value = line.value {
                        Text(value)
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.ink)
                    }
```
with a branch keyed on the typed model's `aqi` (structural, not the label string):
```swift
                    if let value = line.value {
                        if let aqi = line.aqi {
                            AQIValueLabel(value: value, aqi: aqi)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.ink)
                        } else {
                            Text(value)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.ink)
                        }
                    }
```
(The `detailLines` property was already retyped to `[EnvironmentDetailLine]` in Task 2; `ForEach(…, id: \.label)` and `detailLines.count` are otherwise unchanged. This step only adds the `line.aqi` badge branch.)

- [ ] **Step 3: Build and run the suite**

```bash
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -12
```
Expected: `** BUILD SUCCEEDED **`.
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -25
```
Expected: all pass except the known `SwiftDataMigratorTests` crash.

- [ ] **Step 4: Commit**

```bash
git add "Views/HealthOS/Timeline/EnvironmentSummaryRow.swift"
git commit -m "feat(app): AQI dot on the Environment poor-air headline + air-quality detail line"
```

---

### Task 4: Badge the raw AQI search row + the detail header

**Files:**
- Modify: `Views/HealthOS/Timeline/TimelineEventRow.swift`
- Modify: `Views/HealthOS/Timeline/EventDetailView.swift`

**Interfaces:**
- Consumes: `AQIValueLabel` (Task 1).

- [ ] **Step 1: Badge the raw airQuality row (`TimelineEventRow`)**

In `Views/HealthOS/Timeline/TimelineEventRow.swift`, replace the value-line `Text` (currently lines ~46-50):
```swift
                    if let line = displayValueLine {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(valueLineColor)
                    }
```
with an AQI branch (structural check on the event, not the text):
```swift
                    if let line = displayValueLine {
                        if event.category == .environment, event.subtype == "airQuality", let v = event.value {
                            AQIValueLabel(value: line, aqi: Int(v))
                                .font(.footnote)
                                .foregroundStyle(valueLineColor)
                        } else {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(valueLineColor)
                        }
                    }
```
(The row's `accessibilitySummary` already includes `displayValueLine`, and the row is `.accessibilityElement(children: .ignore)` with its own label — so the inner label is ignored; VoiceOver reads the value once.)

- [ ] **Step 2: Badge the detail header (`EventDetailView`)**

In `Views/HealthOS/Timeline/EventDetailView.swift` `header`, replace the value `Text` (currently ~line 75):
```swift
                        Text("·").foregroundStyle(HealthTheme.inkMuted)
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(valueLineColor)
```
with:
```swift
                        Text("·").foregroundStyle(HealthTheme.inkMuted)
                        if displayEvent.category == .environment, displayEvent.subtype == "airQuality", let v = displayEvent.value {
                            AQIValueLabel(value: line, aqi: Int(v))
                                .font(.footnote)
                                .foregroundStyle(valueLineColor)
                        } else {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(valueLineColor)
                        }
```

- [ ] **Step 3: Build and run the suite**

```bash
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -12
```
Expected: `** BUILD SUCCEEDED **`.
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -25
```
Expected: all pass except the known `SwiftDataMigratorTests` crash.

- [ ] **Step 4: Commit**

```bash
git add "Views/HealthOS/Timeline/TimelineEventRow.swift" "Views/HealthOS/Timeline/EventDetailView.swift"
git commit -m "feat(app): AQI dot on the raw search row + event detail header"
```

---

## Device verification (finishing gate, after all tasks)

On the booted iPhone 17 Pro, with AQI data (a poor-air demo day + a good-air day; the WEATHER demo seeds observed AQI):
1. All four sites show a dot in the **correct band color**: collapsed poor-air Environment headline, the expanded **Air quality** detail line (any band), the **raw AQI row** in search (type "air"), and the **event detail** header (tap that row).
2. **Light and dark** both legible — especially **Moderate gold** on cream and **maroon** on dark; tune any color in `HealthTheme` that reads poorly.
3. The **number + category text** are always present next to the dot.
4. **VoiceOver** reads the value once (e.g. "132 · Unhealthy for sensitive groups"); the dot is silent.

## Self-Review (completed)

- **Spec coverage:** §3A colors → Task 1 (HealthTheme) + the app switch; §3B `AQIBadge`/`AQIValueLabel` → Task 1; §3C typed model + `poorAirAQI` → Task 2; §3D four sites → Tasks 3 (headline + detail line) & 4 (raw row + detail header). §5 formatter tests → Task 2; device checks → finishing gate.
- **Placeholder scan:** none — every step carries full code/commands.
- **Type consistency:** `AQIValueLabel(value:aqi:)`, `AQIBadge(aqi:)`, `EnvironmentDetailLine.{subtype,label,value,aqi}`, `poorAirAQI(_:)`, and the six `HealthTheme.aqi*` colors are used identically across tasks.
