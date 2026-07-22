# Moon-Phase SF Symbols (Timeline) — Design

**Date:** 2026-07-22
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Add a small, decorative `moonphase.*` SF Symbol next to the moon-phase name at every Timeline site where the phase name renders — derived structurally from the stored event, never from displayed text. Follow-up #4 (final queued item) after [[hide-season]]. Purely presentational.

**Not touched:** HealthGraphCore (no symbol names in core); the legacy Dashboard `moonPhaseIcon(for:)` mapper and all legacy UI; Insights evidence cards (the "Full moon" card keeps its current look — the greenlit scope is Timeline context only); moon-phase ingestion/mining; mercury retrograde (explicitly NO graphic — novelty tier, a stronger visual would imply more scientific weight than intended).

---

## 1. Problem

Moon phase renders as plain text at four Timeline sites while its sibling environment adornment (AQI) got a visual treatment in the accessible-AQI-badges round. The `moonphase.*` SF Symbol family (fully available — deployment target iOS 26) maps 1:1 onto the eight phase names the pipeline stores, so each phase can carry its actual glyph. The treatment must follow the AQI-badge precedent: decorative, text always kept, VoiceOver reads the phase once, one reusable component so sites cannot drift — plus Leo's refinement: **centralize event extraction as well as symbol mapping**, so no view decodes metadata or infers phase from displayed text.

## 2. Decisions (Leo, 2026-07-22)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Coverage | **All four Timeline phase-name sites** (below) — mirrors the AQI "badge every site the value appears" decision. |
| 2 | Component shape | **Mirror `AQIValueLabel`**, one new app-side file `MoonPhaseLabel.swift` holding the pure symbol mapping, the shared event extractor, AND the label view. |
| 3 | Detection | **Structural only** — `category == .environment && subtype == "moonPhase"` + decoded `metadata["phase"]`; never label-string or displayed-text matching. Phase carried through both presentation models (`EnvironmentHeadline.moonPhase`, `EnvironmentDetailLine.moonPhase`). |
| 4 | Failure mode | **Fail quiet** — unknown/malformed/missing phase → ordinary text-only rendering (mapping returns nil → no icon). |
| 5 | Symbols | The **`moonphase.*` family** (NOT emoji, NOT the mixed `moon.*` set the legacy mapper uses): all eight cleaned canonical names map case-insensitively, whitespace-trimmed. |
| 6 | Accessibility | Icon **decorative** (`.accessibilityHidden`), adjacent text combined — VoiceOver reads the phase exactly once. Text is never removed. |
| 7 | Legacy | Dashboard's inconsistent `moonPhaseIcon(for:)` stays as-is — unifying it would expand the round into legacy UI cleanup. |

**The four sites** (all confirmed against the code):
1. **Expanded "Moon phase" detail line** — `EnvironmentSummaryRow` breakdown (`ForEach(detailLines)`).
2. **Collapsed headline when moon leads** — `EnvironmentSummaryRow`; the backfill fallback (`EnvironmentSummaryFormatter.headlineResult`'s moon branch) AND the degenerate moon-only day (`"Moon phase: Full Moon"` labeled form via the first-detail-line branch).
3. **Raw moon Timeline search row** — `TimelineEventRow` (search builds with `groupEnvironment: false`).
4. **Event detail header** — `EventDetailView` (tapping a raw moon row from search).

## 3. Architecture

### A. `MoonPhaseLabel.swift` (new app-side file — the single home)

Peer of `Views/HealthOS/Timeline/AQIValueLabel.swift`, three units:

- **`moonPhaseSymbolName(for phase: String) -> String?`** — pure. Trims whitespace, lowercases, and switches over the eight cleaned canonical names (the factory strips emoji at ingestion, so stored values are e.g. `"Full Moon"`, `"Waxing Gibbous"`):

  | Stored phase | SF Symbol |
  |---|---|
  | New Moon | `moonphase.new.moon` |
  | Waxing Crescent | `moonphase.waxing.crescent` |
  | First Quarter | `moonphase.first.quarter` |
  | Waxing Gibbous | `moonphase.waxing.gibbous` |
  | Full Moon | `moonphase.full.moon` |
  | Waning Gibbous | `moonphase.waning.gibbous` |
  | Last Quarter | `moonphase.last.quarter` |
  | Waning Crescent | `moonphase.waning.crescent` |

  Anything else → `nil`.

- **`moonPhaseName(for event: HealthEvent) -> String?`** — the shared structural extractor. Requires `event.category == .environment && event.subtype == "moonPhase"`; decodes the event's JSON metadata and returns `metadata["phase"]`. Wrong subtype, missing metadata, or undecodable metadata → `nil`. **The raw search row and the detail header call this** — no view decodes metadata itself or infers the phase from displayed text.

- **`MoonPhaseLabel(value: String, phase: String)`** — `HStack(spacing: 6)`: `Image(systemName:)` (rendered only when `moonPhaseSymbolName(for: phase)` resolves; otherwise the stack is just the text) + `Text(value)`. Icon `.accessibilityHidden(true)`, `.symbolRenderingMode(.hierarchical)` (the lit/shadow segments read at footnote size); element combined so VoiceOver reads the text once. Font and color inherit from the caller, exactly like `AQIValueLabel` (headline: `inkMuted`; detail line: `ink`).

### B. Structural plumbing (formatter models)

In `EnvironmentSummaryFormatter.swift`:
- **`EnvironmentDetailLine`** gains `let moonPhase: String?` — set in `detailLines(...)` for the `"moonPhase"` subtype via `moonPhaseName(for: e)` (the line's OWN event, matching the per-event AQI rule); `nil` for every other subtype.
- **`EnvironmentHeadline`** gains `let moonPhase: String?` — set by the moon-fallback branch (extracted from the summary's moonPhase event, not from the display string) and carried from `first.moonPhase` in the degenerate first-line branch (symmetric with how `first.aqi` flows); `nil` when temperature or AQI leads. `aqi` and `moonPhase` are mutually exclusive in practice (a headline shows one reading), but the model does not need to enforce that.

### C. Site wiring

Each site becomes a three-way branch — `aqi` → `AQIValueLabel`, `moonPhase` → `MoonPhaseLabel`, else plain `Text`:
- **`EnvironmentSummaryRow`** — collapsed headline: `headlineResult.moonPhase` branch renders `MoonPhaseLabel(value: headline, phase:)`. Breakdown: `line.moonPhase` branch renders `MoonPhaseLabel(value: line.value ?? "", phase:)`.
- **`TimelineEventRow`** — after the existing airQuality branch: `else if let phase = moonPhaseName(for: event)` → `MoonPhaseLabel(value: displayValueLine, phase: phase)`.
- **`EventDetailView`** — same extractor-gated branch in the header value line.

Styling (font/color/alignment modifiers) is preserved identically across all three branches at every site, as the AQI round did.

## 4. Files

- **Create** `Views/HealthOS/Timeline/MoonPhaseLabel.swift` — `moonPhaseSymbolName(for:)`, `moonPhaseName(for:)`, `MoonPhaseLabel`.
- **Modify** `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift` — `moonPhase` on both models + the two headline branches + the detail-line branch.
- **Modify** `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift` — three-way branches (headline + breakdown).
- **Modify** `Views/HealthOS/Timeline/TimelineEventRow.swift` — moon branch on the raw row.
- **Modify** `Views/HealthOS/Timeline/EventDetailView.swift` — moon branch in the header.
- **Create** `Food IntolerancesTests/MoonPhaseLabelTests.swift` — see Testing.
- **Modify** `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift` — see Testing.

## 5. Testing

- **`MoonPhaseLabelTests` (pure, app tests):**
  - All eight canonical names map to their exact `moonphase.*` symbol.
  - Case-insensitivity (`"full moon"`, `"FULL MOON"`) and whitespace trimming (`"  Full Moon "`) resolve.
  - Unknown phase (`"Blood Moon"`, `""`) → nil.
  - Extractor: a well-formed moonPhase event → its phase; wrong subtype (e.g. `"season"`, `"airQuality"`) → nil; non-environment category → nil; missing metadata → nil; undecodable metadata bytes → nil.
- **`EnvironmentSummaryFormatterTests`:**
  - The moonPhase detail line carries `moonPhase == "<stored phase>"`; temperature/AQI/mercury lines carry nil.
  - Headline: moon-fallback day → `moonPhase` set (and `aqi` nil); degenerate moon-only day → set; temperature-led and poor-air-led days → nil.
- **Device (visual):** all four sites show the correct glyph per phase; light + dark legible; hierarchical rendering reads at footnote size; VoiceOver reads the phase once at every site; text always present. (SwiftUI view code is build + device gate, per the AQI precedent.)

## 6. Out of scope

- Any change to HealthGraphCore (no symbol names in core).
- The legacy Dashboard `moonPhaseIcon(for:)` mapper and every legacy surface.
- Insights evidence cards (the "Full moon" card's look is unchanged).
- A mercury-retrograde graphic (explicitly rejected — novelty tier).
- Emoji, `.inverse` symbol variants, or semantic coloring of the moon icon.
- Changing the phase value text, `EventDisplay`, or ingestion.
