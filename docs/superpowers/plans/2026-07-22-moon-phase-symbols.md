# Moon-Phase SF Symbols (Timeline) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a small decorative `moonphase.*` SF Symbol next to the moon-phase name at all four Timeline sites, per `docs/superpowers/specs/2026-07-22-moon-phase-symbols-design.md`.

**Architecture:** One new app-side file, `MoonPhaseLabel.swift`, centralizes the pure symbol mapping (`moonPhaseSymbolName(for:)`), the structural event extractor (`moonPhaseName(for event:)`), and the label view (`MoonPhaseLabel`) — mirroring `AQIValueLabel.swift`. The phase flows structurally through `EnvironmentHeadline.moonPhase` and `EnvironmentDetailLine.moonPhase` (exactly how `aqi` was added), and each site becomes a three-way branch: `aqi` → `AQIValueLabel`, `moonPhase` → `MoonPhaseLabel`, else plain `Text`. HealthGraphCore untouched.

**Tech Stack:** Swift / SwiftUI app + HealthGraphCore local SwiftPM package (read-only dependency here). Swift Testing (`@Test`/`#expect`) in the app suite.

## Global Constraints

- **HealthGraphCore untouched** — no symbol names, no model changes in core.
- **Legacy untouched** — Dashboard's `moonPhaseIcon(for:)`, all legacy UI, and Insights evidence cards keep their current look. **No mercury-retrograde graphic.**
- **Structural detection only** — `category == .environment && subtype == "moonPhase"` + decoded `metadata["phase"]`; never label-string or displayed-text matching. The raw search row and detail header use the shared extractor; no view decodes metadata itself.
- **Fail quiet** — unknown/malformed/missing phase → ordinary text-only rendering (no icon, no error).
- **Symbols:** the `moonphase.*` family only (exact names in Task 1); NOT emoji, NOT `.inverse` variants, no semantic coloring — font/color inherit from the caller.
- **Accessibility:** icon `.accessibilityHidden(true)`, element combined — VoiceOver reads the phase exactly once; the phase text is never removed.
- App tests MUST run with `-parallel-testing-enabled NO` (known pre-existing `SwiftDataMigratorTests` teardown crash; "green modulo known crash" is the accepted bar for the FULL suite only — targeted runs must fully succeed). Destination: `platform=iOS Simulator,name=iPhone 17 Pro`.
- Commits: conventional-commit style, trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Working directory: `/Users/leo/dev/FoodIntolerances` (paths below relative to it).

---

### Task 1: `MoonPhaseLabel.swift` — mapping, extractor, label view (+ unit tests)

The single home for everything moon-symbol: two pure internal functions (unit-tested) and the SwiftUI label (build + device gate, like `AQIBadge`). Mirror `Views/HealthOS/Timeline/AQIValueLabel.swift` (read it first — same file layout: helper, view, preview).

**Files:**
- Create: `Views/HealthOS/Timeline/MoonPhaseLabel.swift`
- Test (create): `Food IntolerancesTests/MoonPhaseLabelTests.swift`

**Interfaces:**
- Consumes: `HealthEvent` (core), `AQIValueLabel.swift` as the style template.
- Produces (Tasks 2–3 rely on these exact names): `func moonPhaseSymbolName(for phase: String) -> String?`, `func moonPhaseName(for event: HealthEvent) -> String?` (both internal, file-scope), `struct MoonPhaseLabel: View` with `init(value: String, phase: String)`.

- [ ] **Step 1: Write the failing tests**

Create `Food IntolerancesTests/MoonPhaseLabelTests.swift`:

```swift
import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

struct MoonPhaseLabelTests {
    // Mapping — all eight cleaned canonical names → their exact moonphase.* symbol.
    @Test func mapsAllEightCanonicalPhases() {
        #expect(moonPhaseSymbolName(for: "New Moon") == "moonphase.new.moon")
        #expect(moonPhaseSymbolName(for: "Waxing Crescent") == "moonphase.waxing.crescent")
        #expect(moonPhaseSymbolName(for: "First Quarter") == "moonphase.first.quarter")
        #expect(moonPhaseSymbolName(for: "Waxing Gibbous") == "moonphase.waxing.gibbous")
        #expect(moonPhaseSymbolName(for: "Full Moon") == "moonphase.full.moon")
        #expect(moonPhaseSymbolName(for: "Waning Gibbous") == "moonphase.waning.gibbous")
        #expect(moonPhaseSymbolName(for: "Last Quarter") == "moonphase.last.quarter")
        #expect(moonPhaseSymbolName(for: "Waning Crescent") == "moonphase.waning.crescent")
    }
    @Test func normalizesCaseAndWhitespace() {
        #expect(moonPhaseSymbolName(for: "full moon") == "moonphase.full.moon")
        #expect(moonPhaseSymbolName(for: "FULL MOON") == "moonphase.full.moon")
        #expect(moonPhaseSymbolName(for: "  Full Moon ") == "moonphase.full.moon")
    }
    @Test func unknownPhaseReturnsNil() {
        #expect(moonPhaseSymbolName(for: "Blood Moon") == nil)
        #expect(moonPhaseSymbolName(for: "") == nil)
    }

    // Extractor — structural gate (.environment + "moonPhase") + metadata decode.
    private func event(category: EventCategory = .environment, subtype: String? = "moonPhase",
                       metadata: Data?) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200), category: category,
                    subtype: subtype, source: .weatherAPI, metadata: metadata)
    }
    private func phaseMeta(_ phase: String) -> Data { try! JSONEncoder().encode(["phase": phase]) }

    @Test func extractsPhaseFromWellFormedEvent() {
        #expect(moonPhaseName(for: event(metadata: phaseMeta("Waxing Gibbous"))) == "Waxing Gibbous")
    }
    @Test func wrongSubtypeOrCategoryReturnsNil() {
        #expect(moonPhaseName(for: event(subtype: "season", metadata: phaseMeta("Full Moon"))) == nil)
        #expect(moonPhaseName(for: event(subtype: "airQuality", metadata: phaseMeta("Full Moon"))) == nil)
        #expect(moonPhaseName(for: event(subtype: nil, metadata: phaseMeta("Full Moon"))) == nil)
        #expect(moonPhaseName(for: event(category: .symptom, metadata: phaseMeta("Full Moon"))) == nil)
    }
    @Test func missingOrMalformedMetadataReturnsNil() {
        #expect(moonPhaseName(for: event(metadata: nil)) == nil)
        #expect(moonPhaseName(for: event(metadata: Data([0xFF, 0x00]))) == nil)               // undecodable bytes
        #expect(moonPhaseName(for: event(metadata: try! JSONEncoder().encode(["other": "x"]))) == nil)   // no "phase" key
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run:
```bash
cd /Users/leo/dev/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/MoonPhaseLabelTests" 2>&1 | tail -10
```
Expected: BUILD FAILS — `cannot find 'moonPhaseSymbolName' in scope` (the functions don't exist yet). That is the RED state for a new file.

- [ ] **Step 3: Implement `MoonPhaseLabel.swift`**

Create `Views/HealthOS/Timeline/MoonPhaseLabel.swift`:

```swift
import SwiftUI
import HealthGraphCore

/// The `moonphase.*` SF Symbol for a stored phase name (the factory strips emoji at
/// ingestion, so stored values are e.g. "Full Moon"). Case-insensitive, whitespace-
/// trimmed; anything outside the eight canonical names → nil (the label then renders
/// text-only — fail quiet, never a wrong glyph).
func moonPhaseSymbolName(for phase: String) -> String? {
    switch phase.trimmingCharacters(in: .whitespaces).lowercased() {
    case "new moon":        "moonphase.new.moon"
    case "waxing crescent": "moonphase.waxing.crescent"
    case "first quarter":   "moonphase.first.quarter"
    case "waxing gibbous":  "moonphase.waxing.gibbous"
    case "full moon":       "moonphase.full.moon"
    case "waning gibbous":  "moonphase.waning.gibbous"
    case "last quarter":    "moonphase.last.quarter"
    case "waning crescent": "moonphase.waning.crescent"
    default:                nil
    }
}

/// The stored phase name of a moon-phase event, or nil for anything else. The single
/// structural gate every site goes through — no view decodes metadata itself or infers
/// the phase from displayed text.
func moonPhaseName(for event: HealthEvent) -> String? {
    guard event.category == .environment, event.subtype == "moonPhase",
          let data = event.metadata,
          let meta = try? JSONDecoder().decode([String: String].self, from: data)
    else { return nil }
    return meta["phase"]
}

/// The single moon-phase presentation used at every site: the phase glyph followed by
/// the caller-provided value text (e.g. "Waxing Gibbous"). The caller applies its own
/// `.font`/`.foregroundStyle`; hierarchical rendering keeps the lit/shadow segments
/// legible at footnote size. Combined for VoiceOver so it reads the text once, icon
/// silent. An unmappable phase renders text-only.
struct MoonPhaseLabel: View {
    let value: String
    let phase: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol = moonPhaseSymbolName(for: phase) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
            }
            Text(value)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Moon phases — all eight") {
    VStack(alignment: .leading, spacing: 10) {
        MoonPhaseLabel(value: "New Moon", phase: "New Moon")
        MoonPhaseLabel(value: "Waxing Crescent", phase: "Waxing Crescent")
        MoonPhaseLabel(value: "First Quarter", phase: "First Quarter")
        MoonPhaseLabel(value: "Waxing Gibbous", phase: "Waxing Gibbous")
        MoonPhaseLabel(value: "Full Moon", phase: "Full Moon")
        MoonPhaseLabel(value: "Waning Gibbous", phase: "Waning Gibbous")
        MoonPhaseLabel(value: "Last Quarter", phase: "Last Quarter")
        MoonPhaseLabel(value: "Waning Crescent", phase: "Waning Crescent")
        MoonPhaseLabel(value: "Unmappable", phase: "Blood Moon")
    }
    .font(.footnote)
    .padding()
    .background(HealthTheme.paper)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: the same command as Step 2.
Expected: `** TEST SUCCEEDED **` — all 6 `@Test` cases pass.

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Timeline/MoonPhaseLabel.swift" "Food IntolerancesTests/MoonPhaseLabelTests.swift"
git commit -m "feat(app): MoonPhaseLabel — moonphase.* symbol mapping + structural event extractor + label view

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Formatter plumbing — `moonPhase` on both presentation models

`EnvironmentDetailLine` and `EnvironmentHeadline` (both in `EnvironmentSummaryFormatter.swift`) each gain `let moonPhase: String?` with **no default value**, so the compiler forces every construction site to decide — all constructions live in this one file. The phase comes from `moonPhaseName(for:)` on the branch's OWN event (the per-event rule from the AQI round).

**Files:**
- Modify: `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift:4-51`
- Test: `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift`

**Interfaces:**
- Consumes: `moonPhaseName(for: HealthEvent) -> String?` (Task 1).
- Produces (Task 3 relies on these exact names): `EnvironmentDetailLine.moonPhase: String?`, `EnvironmentHeadline.moonPhase: String?`.

- [ ] **Step 1: Write the failing tests**

In `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift`, add at the end of the struct (the existing `moon(_:)` helper builds `ev("moonPhase", meta: ["phase": s])` — use realistic title-case names):

```swift
    // Structural moon-phase plumbing — the label's input, never inferred from display text.
    @Test func moonDetailLineCarriesPhaseOthersNil() {
        let rows = EnvironmentSummaryFormatter.detailLines(day([temp(24, 12), moon("Waxing Gibbous"), mercury()]), unit: c)
        let moonLine = rows.first { $0.subtype == "moonPhase" }
        #expect(moonLine?.moonPhase == "Waxing Gibbous")   // from the line's own event metadata
        #expect(moonLine?.value == "Waxing Gibbous")       // display text unchanged
        #expect(rows.first { $0.subtype == "temperature" }?.moonPhase == nil)
        #expect(rows.first { $0.subtype == "mercuryRetrograde" }?.moonPhase == nil)
    }
    @Test func headlineCarriesMoonPhaseOnlyWhenMoonLeads() {
        // Backfill fallback: moon leads → phase set, aqi nil.
        let moonLead = EnvironmentSummaryFormatter.headlineResult(day([moon("Full Moon")]), unit: c)
        #expect(moonLead.text == "Full Moon")
        #expect(moonLead.moonPhase == "Full Moon")
        #expect(moonLead.aqi == nil)
        // Temperature leads → no moon phase on the headline.
        #expect(EnvironmentSummaryFormatter.headlineResult(day([temp(24, 12), moon("Full Moon")]), unit: c).moonPhase == nil)
        // Poor air leads → no moon phase on the headline.
        #expect(EnvironmentSummaryFormatter.headlineResult(day([moon("Full Moon"), airQuality(132)]), unit: c).moonPhase == nil)
    }
```

- [ ] **Step 2: Run the formatter tests to verify the new ones fail to compile**

Run:
```bash
cd /Users/leo/dev/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/EnvironmentSummaryFormatterTests" 2>&1 | tail -10
```
Expected: BUILD FAILS — `value of type 'EnvironmentDetailLine' has no member 'moonPhase'` (RED for a model change).

- [ ] **Step 3: Implement the model fields and branches**

In `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift`:

Replace the two model declarations (lines 4-24) with:

```swift
/// One expanded environment reading. `id` is the source event's id — stable SwiftUI
/// identity even when a day has duplicate subtypes/provenance (avoids duplicate
/// `ForEach` ids). `subtype` lets the row identify the AQI line structurally; `aqi` is
/// set ONLY for the airQuality line — the badge's color input. `moonPhase` is set ONLY
/// for the moonPhase line (from its own event's metadata) — the glyph's input.
/// `value == nil` → a presence line (mercury).
struct EnvironmentDetailLine: Identifiable {
    let id: UUID
    let subtype: String?
    let label: String
    let value: String?
    let aqi: Int?
    let moonPhase: String?
}

/// The collapsed headline plus the adornment it displays, if any. `aqi` is non-nil
/// whenever the SELECTED headline actually shows an AQI value — a poor-air lead OR a
/// good-air degenerate "Air quality: …" fallback. `moonPhase` is non-nil whenever the
/// SELECTED headline shows a moon phase — the moon fallback or a degenerate moon line.
struct EnvironmentHeadline {
    let text: String
    let aqi: Int?
    let moonPhase: String?
}
```

Replace `headlineResult` (lines 29-51) with:

```swift
    /// Collapsed one-liner + the adornment it displays (if any). Temperature range
    /// (· humidity) when present; else moon phase; else the single remaining reading. A
    /// poor-air day leads with the AQI; a day whose only/first reading is airQuality shows
    /// it via the degenerate fallback — `aqi`/`moonPhase` mark what the headline shows so
    /// the row can badge it.
    static func headlineResult(_ summary: EnvironmentDaySummary, unit: TemperatureUnit) -> EnvironmentHeadline {
        // Poor-air days lead with the AQI — the most health-salient signal that day.
        if let aqi = poorAirAQI(summary) {
            return EnvironmentHeadline(text: "AQI \(aqi) · \(AirQualityIndex.category(aqi: aqi).name)", aqi: aqi, moonPhase: nil)
        }
        if let temp = value("temperature", summary, unit) {
            if let hum = value("humidity", summary, unit) { return EnvironmentHeadline(text: "\(temp) · \(hum)", aqi: nil, moonPhase: nil) }
            return EnvironmentHeadline(text: temp, aqi: nil, moonPhase: nil)
        }
        // Fetch the event once so the displayed text and the structural phase can never
        // come from different same-subtype events.
        if let e = summary.events.first(where: { $0.subtype == "moonPhase" }),
           let moon = WeatherValueFormatter.line(for: e, unit: unit) ?? EventDisplay.valueLine(for: e) {
            return EnvironmentHeadline(text: moon, aqi: nil, moonPhase: moonPhaseName(for: e))
        }
        if let first = detailLines(summary, unit: unit).first {
            // The degenerate lead carries an adornment only when that first line has one.
            let text = first.value.map { "\(first.label): \($0)" } ?? first.label
            return EnvironmentHeadline(text: text, aqi: first.aqi, moonPhase: first.moonPhase)
        }
        return EnvironmentHeadline(text: "Environment", aqi: nil, moonPhase: nil)
    }
```

In `detailLines(...)`, update the three `EnvironmentDetailLine(` constructions inside the `switch` and the defensive one below it:

```swift
            case "pressure":
                var v = text
                if let drop = summary.events.first(where: { $0.subtype == "pressureDrop" }), let d = drop.value {
                    v = [v, "↓\(Int(d.rounded())) hPa"].compactMap { $0 }.joined(separator: " · ")
                }
                rows.append(EnvironmentDetailLine(id: e.id, subtype: subtype, label: EventDisplay.title(for: e), value: v, aqi: nil, moonPhase: nil))
            case "airQuality":
                rows.append(EnvironmentDetailLine(id: e.id, subtype: subtype, label: EventDisplay.title(for: e), value: text, aqi: e.value.map { Int($0) }, moonPhase: nil))
            default:
                rows.append(EnvironmentDetailLine(id: e.id, subtype: subtype, label: EventDisplay.title(for: e), value: text, aqi: nil, moonPhase: moonPhaseName(for: e)))
```

(The `default` branch covers the moonPhase subtype; `moonPhaseName(for:)` returns nil for every other subtype that lands there, so no extra case is needed.) And the defensive lone-pressureDrop row:

```swift
            rows.append(EnvironmentDetailLine(id: drop.id, subtype: drop.subtype, label: EventDisplay.title(for: drop),
                                              value: EventDisplay.valueLine(for: drop), aqi: nil, moonPhase: nil))
```

- [ ] **Step 4: Run the formatter tests to verify they pass**

Run: the same command as Step 2.
Expected: `** TEST SUCCEEDED **` — the 2 new tests and all pre-existing formatter tests pass. (`EnvironmentSummaryRow` only reads existing members, so the app still compiles before Task 3.)

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift" "Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift"
git commit -m "feat(app): EnvironmentHeadline/EnvironmentDetailLine carry moonPhase structurally (own-event extraction)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Site wiring — three-way branches at all four sites (+ full verification)

Pure view wiring: `aqi` → `AQIValueLabel`, `moonPhase` → `MoonPhaseLabel`, else `Text`, with the existing font/color/alignment modifiers repeated identically on every branch (the AQI round's rule). No formatter or core changes. Verified by build + full suites + device gate (no new unit tests — SwiftUI view code, per the spec's Testing section).

**Files:**
- Modify: `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift:50-60,97-107`
- Modify: `Views/HealthOS/Timeline/TimelineEventRow.swift:49-59`
- Modify: `Views/HealthOS/Timeline/EventDetailView.swift:77-88`

**Interfaces:**
- Consumes: `MoonPhaseLabel(value:phase:)` + `moonPhaseName(for:)` (Task 1); `headlineResult.moonPhase` + `line.moonPhase` (Task 2).
- Produces: nothing new — behavior only.

- [ ] **Step 1: Wire `EnvironmentSummaryRow` (headline + breakdown)**

Collapsed headline — replace the current two-way branch (`if let aqi = headlineResult.aqi { AQIValueLabel(...) } else { Text(headline) }`, lines ~50-60) with:

```swift
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
```

Breakdown — replace the inner two-way branch (`if let aqi = line.aqi { AQIValueLabel(...) } else { Text(value) }`, lines ~97-107) with:

```swift
                    if let value = line.value {
                        if let aqi = line.aqi {
                            AQIValueLabel(value: value, aqi: aqi)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.ink)
                        } else if let phase = line.moonPhase {
                            MoonPhaseLabel(value: value, phase: phase)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.ink)
                        } else {
                            Text(value)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.ink)
                        }
                    }
```

- [ ] **Step 2: Wire `TimelineEventRow` (raw search row)**

Replace the value-line branch (lines ~49-59) with (the moon branch uses the shared extractor — never metadata decoding or title matching in the view):

```swift
                    if let line = displayValueLine {
                        if event.category == .environment, event.subtype == "airQuality", let v = event.value {
                            AQIValueLabel(value: line, aqi: Int(v))
                                .font(.footnote)
                                .foregroundStyle(valueLineColor)
                        } else if let phase = moonPhaseName(for: event) {
                            MoonPhaseLabel(value: line, phase: phase)
                                .font(.footnote)
                                .foregroundStyle(valueLineColor)
                        } else {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(valueLineColor)
                        }
                    }
```

- [ ] **Step 3: Wire `EventDetailView` (header value line)**

Replace the header value-line branch (lines ~79-88, inside the `if let line = …` block after the `Text("·")` separator) with:

```swift
                        if displayEvent.category == .environment, displayEvent.subtype == "airQuality", let v = displayEvent.value {
                            AQIValueLabel(value: line, aqi: Int(v))
                                .font(.footnote)
                                .foregroundStyle(valueLineColor)
                        } else if let phase = moonPhaseName(for: displayEvent) {
                            MoonPhaseLabel(value: line, phase: phase)
                                .font(.footnote)
                                .foregroundStyle(valueLineColor)
                        } else {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(valueLineColor)
                        }
```

- [ ] **Step 4: Full-suite verification**

Run:
```bash
cd /Users/leo/dev/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -10
```
Expected: green modulo the ONE known pre-existing `SwiftDataMigratorTests` teardown crash. (No core changes this round, so the core suite is untouched; running it is optional: `cd HealthGraphCore && swift test` → all pass.)

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Timeline/EnvironmentSummaryRow.swift" "Views/HealthOS/Timeline/TimelineEventRow.swift" "Views/HealthOS/Timeline/EventDetailView.swift"
git commit -m "feat(app): moonphase.* glyph at all 4 Timeline phase-name sites (three-way aqi/moon/text branches)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Device gate (Leo, after Task 3)

Not a plan task — the round's final verification, per the spec's Testing section:
1. All four sites show the correct glyph per phase (browse a backfill day for the headline; expand the Environment row for the detail line; search "moon" for the raw row; tap it for the detail header).
2. Light + dark both legible; hierarchical rendering reads at footnote size.
3. VoiceOver reads the phase name exactly once at every site (icon silent); the text is always present.
4. Legacy Dashboard moon icon unchanged; Insights "Full moon" card unchanged.
