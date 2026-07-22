# Accessible AQI Badges — Design

**Date:** 2026-07-21
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Add a small, color-coded **dot** next to the AQI value at **every** place it appears, using accessibility-adjusted EPA AirNow category colors — **always** keeping the AQI number + category text. Follow-up #2 after [[measurement-system-control-merged]] (was a deferred item in the air-quality round).

**Not touched:** the AQI math/category model (`AirQualityIndex`, core — stays text-only, no `Color`); AQI ingestion/mining; the AQI value TEXT itself (still produced by `EventDisplay.valueLine` / `EnvironmentSummaryFormatter`).

---

## 1. Problem

AQI renders as plain text (`132 · Unhealthy for sensitive groups`) — no at-a-glance severity signal. We add the official AirNow color coding, but **accessibly**: a small supplementary **dot**, never whole-row color, never color-alone (the number + category text always remain). The dot must appear consistently at all four sites where an AQI value shows, and the colors must be legible in light **and** dark on the app's cream `paper` / dark backgrounds.

## 2. Decisions (Leo, 2026-07-21)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Color fidelity | **Tuned-for-contrast** AirNow colors (dynamic light/dark) + a subtle border — **documented as accessibility-adjusted**, not verbatim official hex. |
| 2 | Coverage | **Badge every site the AQI value appears** — all four (below). |
| 3 | Visual | A small **dot** (not a pill); number + category text always retained. |
| 4 | Reuse | **One** reusable component (`AQIValueLabel` wrapping an `AQIBadge` dot) so the four sites cannot drift. |
| 5 | Detail-line detection | **Typed** detail-line model preserving the event **subtype** — never match the `"Air quality"` label string. |
| 6 | Accessibility | Dot is **decorative** (`.accessibilityHidden`); the category name is already in the adjacent text, so VoiceOver reads the value once. |
| 7 | Core | `AirQualityIndex` stays text-only; **no `Color` in HealthGraphCore**. |

**The four sites** (all confirmed against the code):
1. **Collapsed poor-air Environment headline** — `EnvironmentSummaryRow` (browse; the headline leads with `AQI 132 · …` on days ≥ `poorAirThreshold`).
2. **Expanded "Air quality" detail line** — `EnvironmentSummaryRow` breakdown (browse; shows for **any** AQI value, all six bands).
3. **Raw AQI Timeline search row** — `TimelineEventRow` (search mode builds with `groupEnvironment: false`, so a raw `airQuality` event renders un-collapsed — `TimelineViewModel.swift:129,229`).
4. **Event detail header** — `EventDetailView` (tapping a raw AQI event from search).

## 3. Architecture

### A. Colors (accessibility-adjusted AirNow, dynamic light/dark)

Six **tuned** dynamic `Color`s in `HealthTheme` (via the existing `dyn(light:dark:)` helper, `HealthTheme.swift:47`) — one per `AQICategory` band, adjusted so each reads on both cream and dark (pure AirNow yellow `#FFFF00` is invisible on cream → Moderate becomes a readable gold; maroon lightens for dark). The `AQICategory → Color` switch lives **app-side** in the badge component (which imports HealthGraphCore); `HealthTheme` stays core-free (just six named `Color`s). Proposed values (device-gate-tuned):

| Band (`AQICategory`) | AirNow ref | light | dark |
|---|---|---|---|
| good | green | `0x2E9E4F` | `0x3FD06B` |
| moderate | yellow | `0xB08A00` | `0xE8C33A` |
| unhealthySensitive | orange | `0xD96500` | `0xFF9A3D` |
| unhealthy | red | `0xD42A2A` | `0xFF5C5C` |
| veryUnhealthy | purple | `0x8F3F97` | `0xB667BE` |
| hazardous | maroon | `0x7E0023` | `0xC64B6B` |

Each light variant is chosen to clear roughly **3:1 contrast against the `paper`/`card` surfaces** (the 0.5pt border defines the shape but does not substitute for fill contrast on an 8pt dot — so light Moderate and Orange are darkened from raw AirNow). A doc comment on these records that they are **accessibility-adjusted versions of the official AirNow categories, not verbatim official hex** (link: https://www.airnow.gov/aqi/aqi-basics/). The device gate re-verifies all six against both surfaces in both themes.

### B. `AQIBadge` + `AQIValueLabel` (one reusable component)

New app-side file (`Views/HealthOS/Timeline/AQIValueLabel.swift`):
- **`AQIBadge`** — a small (~8pt) `Circle` filled with `aqiColor(for: AirQualityIndex.category(aqi:))`, plus a hairline border (a `~0.5pt` stroke in a subtle ink) so even light fills (gold) have a defined edge on cream. `.accessibilityHidden(true)`.
- **`AQIValueLabel(value: String, aqi: Int)`** — `HStack(spacing: 6) { AQIBadge(aqi: aqi); Text(value) }`, combined for a11y so VoiceOver reads just the text. The **text is passed in** (from the existing formatter/`EventDisplay`), so the AQI value FORMAT is never duplicated — only the dot is added. The caller applies its own `.font`/`.foregroundStyle` (the dot's fill is explicit, so it's unaffected).

All four sites render `AQIValueLabel(value:, aqi:)` where they currently render a plain `Text` of the AQI value — guaranteeing identical presentation.

### C. Typed detail-line model (no label-string matching)

`EnvironmentSummaryFormatter` changes so the row identifies the AQI line **structurally** and stays correct when a day has duplicate readings:
- `detailLines(...)` returns `[EnvironmentDetailLine]` where `struct EnvironmentDetailLine: Identifiable { let id: UUID; let subtype: String?; let label: String; let value: String?; let aqi: Int? }` (`id` = the source event's id; `aqi` non-nil only for the `airQuality` line — the badge's color input). Replaces the current `(label, value?)` tuple.
- Each line's **value text is formatted from its OWN event** (`WeatherValueFormatter.line(for: e, …) ?? EventDisplay.valueLine(for: e)`), not via a same-subtype lookup — so the dot's `aqi` and the displayed text can never disagree when two same-day AQI events exist.
- The row iterates `ForEach(detailLines)` on the `Identifiable` id (not `id: \.label`), so duplicate subtypes/provenance can't collide on a SwiftUI identifier.
- New `static func poorAirAQI(_ summary:) -> Int?` — the AQI value when the headline leads with AQI (poor-air day), else nil; shares the poor-air check with `headline(...)` so the two can't diverge. (`headline(...)` keeps returning `String` for the row's a11y label.)

The row then renders the dot exactly when: `poorAirAQI != nil` (headline, site 1) or `line.aqi != nil` (detail line, site 2).

### D. Site wiring

- **`EnvironmentSummaryRow`**: collapsed headline — if `poorAirAQI(summary)` is non-nil, render `AQIValueLabel(value: headline, aqi:)` in place of `Text(headline)`; else unchanged. Breakdown — for a line with `aqi != nil`, render `AQIValueLabel(value: line.value ?? "", aqi:)` in place of `Text(value)`.
- **`TimelineEventRow`** (site 3): when `event.category == .environment && event.subtype == "airQuality"` and it has a value, render `AQIValueLabel(value: displayValueLine, aqi: Int(value))` instead of the plain value `Text`.
- **`EventDetailView`** (site 4): same structural check on `displayEvent`, in the header value-line.

## 4. Files

- **Create** `Views/HealthOS/Timeline/AQIValueLabel.swift` — `AQIBadge`, `AQIValueLabel`, the `aqiColor(for: AirQualityIndex.AQICategory) -> Color` switch.
- **Modify** `Views/HealthOS/Theme/HealthTheme.swift` — six tuned dynamic AQI `Color`s (+ the adjusted-AirNow doc comment).
- **Modify** `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift` — `EnvironmentDetailLine` typed model; `poorAirAQI(_:)`.
- **Modify** `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift` — dot on the poor-air headline + the AQI detail line; `ForEach` over the typed model.
- **Modify** `Views/HealthOS/Timeline/TimelineEventRow.swift` — AQI badge on a raw airQuality row.
- **Modify** `Views/HealthOS/Timeline/EventDetailView.swift` — AQI badge in the header.
- **Modify** `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift` — update for the typed model; add `poorAirAQI` + air-line-carries-subtype/aqi cases.

## 5. Testing

- **`EnvironmentSummaryFormatter` (pure, app tests):**
  - `detailLines` returns typed `EnvironmentDetailLine`s: the air-quality line has `subtype == "airQuality"` and `aqi == <event value>`; other lines carry their own subtype and `aqi == nil`. (Update existing assertions to the struct.)
  - `poorAirAQI`: returns the AQI Int on a poor-air day (≥ `poorAirThreshold`), `nil` on a clean-air day (< threshold), and `nil` when no `airQuality` event exists — mirroring exactly when the headline leads with AQI (pin the 101/100 boundary).
  - A good-air detail line still carries its `aqi` (the detail line badges ALL bands, not only poor air).
  - Two same-day AQI events: each line's `aqi` matches its OWN displayed text (value formatted per-event, never by a same-subtype lookup).
- **Device (visual):** all four sites show the dot in the correct band color; **light and dark** both legible (esp. Moderate gold on cream, maroon on dark); the number + category text are always present; VoiceOver reads the value once (dot silent). Tune any color that reads poorly.
- (The SwiftUI `AQIBadge`/`AQIValueLabel`/color-switch are view code — verified by build + the device gate, not a unit test; `Color` equality isn't reliably assertable and the category bands are already covered by `AirQualityIndexTests`.)

## 6. Out of scope

- Whole-row / whole-cell AQI coloring (rejected — dot only, text always).
- Coloring any non-AQI environment reading.
- A `Color` in HealthGraphCore (`AirQualityIndex` stays text-only).
- Changing the AQI value text format, thresholds, or the poor-air headline rule.
- Badging AQI anywhere it does not currently render a value.

## 7. Accessibility summary (for the reviewer)

- The dot is **supplementary and decorative** — every site keeps the full `<number> · <category>` text; color is never the sole signal.
- Colors are **contrast-tuned** for both themes and carry a hairline border for shape definition regardless of fill.
- VoiceOver output is unchanged (dot `.accessibilityHidden`); the value text reads exactly as today.
