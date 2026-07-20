# Environment Timeline Summary Row — Design

**Date:** 2026-07-20
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Collapse the per-day auto-logged `.environment` events (temperature range, humidity, air pressure, pressure drop, moon phase, mercury retrograde, season) into **ONE compact "Environment" summary row per day** in the HealthOS Timeline, expandable to a labeled detail list — mirroring the inline-expandable `SleepSessionRow`. Also make environment data **read-only** (no edit, no delete) everywhere it surfaces. Display-only: ingestion, dedup, and the evidence engine are untouched.

**Not touched:** how weather/moon/season are sourced (existing pipeline), the evidence engine, the tier framework, sleep sessions, manual/other event rows, the °C/°F units feature (reused for the temperature line).

---

## 1. Problem

Every day the environment service auto-logs up to ~7 separate Timeline rows — `pressure`, `pressureDrop`, `moonPhase`, `mercuryRetrograde`, `season`, `temperature`, `humidity` — all sharing one timestamp. On a live day that is 5–7 rows of ambient context the user never entered; on backfilled history days it is 2–3 (moon/season/mercury). This is noise that buries the events the user actually logged. Sleep already solved the analogous problem with an inline-expandable summary row (`SleepSessionRow`); environment is the same shape.

## 2. Decisions (Leo, 2026-07-20)

| # | Decision | Choice |
|---|----------|--------|
| 1 | What collapses | **ALL** auto-logged `.environment` events for a day → one row. (There are no *manual* `.environment` events; the category is exclusively weather-service auto-log.) |
| 2 | Row name | **"Environment"** — not "Weather", since it folds in moon/mercury/season. Matches the `.environment` category and the existing "Environment service" source label. Reuses the category's cloud-sun icon. |
| 3 | Collapsed headline | **Temperature range (· humidity) when present; otherwise moon phase (· season).** Always leads with the most salient available reading; never an empty row. (Weather is location-gated, so backfill/no-permission days fall back to the always-available date-derived moon/season.) |
| 4 | Expand | **Tap-to-expand static labeled lines**, parent-owned expansion state, swipe-free — identical mechanics to `SleepSessionRow`. |
| 5 | Detail nav | The expanded lines are **static / non-navigable**. Tapping the collapsed→expanded row does not open a per-event detail sheet; the expanded row already shows everything that sheet would (source + timestamp are identical across all env events). |
| 6 | Search | **Stays granular** — individual raw `.environment` rows show in search (grouped rows are already suppressed there, exactly like sleep sessions). |
| 7 | Edit / delete | **Environment data is read-only** — no edit, no delete, anywhere it surfaces (collapsed row is swipe-free; the raw env rows shown in search lose their Delete swipe; the detail sheet hides its Delete button for env). Consistent with sleep sessions ("never editable or deletable") and the immutable crisis-flow precedent. |

## 3. Architecture

The split follows the established convention: **core groups & identifies; the app formats & displays** (unit-aware temperature is app-side, `EventDisplay` stays pure/pref-unaware).

### A. Core — group `.environment` into a daily summary (`HealthGraphCore`)

- **`EnvironmentDaySummary`** — a new `Sendable` value type (mirrors `SleepSession`): `dayStart: Date`, `timestamp: Date` (the shared per-day env timestamp), `events: [HealthEvent]` (the day's `.environment` events, in a stable canonical subtype order), and a **deterministic string `id`** derived from `dayStart` (drives SwiftUI row identity + the parent's expansion `Set`). It carries the raw events, not pre-formatted strings, so the app row can apply unit conversion.
- **`TimelineItem`** (`TimelineDayBuilder.swift`) — add a `.environmentSummary(EnvironmentDaySummary)` case, with its `id` and `sortDate` (= the env `timestamp`, so it sorts among the day's items by time like any row).
- **`TimelineDayBuilder.days(...)`** — add a filter→reduce→re-bucket arm mirroring the sleep block: pull `.environment` events out of `rowEvents`, fold each day's set into one `EnvironmentDaySummary`, and append it as a `.environmentSummary` item under `startOfDay(timestamp)`. Grouping is gated to **browse mode only** (the same condition that sessionizes sleep); in search the env events stay raw. A day with a single env subtype still yields a summary item (see §D expandability).
- **`EnvironmentDaySummaryBuilder`** (optional, or a private helper) — the pure reducer that sorts a day's env events into canonical order and mints the id. Order-independent, deterministic.

### B. App — the summary row (`Views/HealthOS/Timeline/`)

- **`EnvironmentSummaryRow`** — a new stateless row mirroring `SleepSessionRow`: props `summary: EnvironmentDaySummary`, `isExpanded: Bool`, `onToggle: () -> Void`. Same visual spine/gutter as the other rows, the category cloud-sun icon, a collapsed **headline** (§3C), a right-aligned timestamp, and a chevron that rotates when expanded. Expanded → a `VStack` of labeled lines.
- **`EnvironmentSummaryFormatter`** — an app-side helper (peer to `WeatherValueFormatter`) that turns the summary's events into (a) the collapsed **headline** per Decision 3, and (b) the ordered **detail lines** `[(label, value)]`. Temperature uses `WeatherValueFormatter` (unit-aware, `@AppStorage("hg.temperatureUnit")`); other subtypes use `EventDisplay.title` + `EventDisplay.valueLine` (pressure "1013 hPa", pressureDrop "↓7 hPa" / shown with the pressure line, moonPhase/season/mercuryRetrograde their metadata/label). Canonical detail order: Temperature, Humidity, Air pressure (with drop annotation), Moon phase, Season, Mercury retrograde.
- **`TimelineView`** — add a `switch` arm for `.environmentSummary` → `EnvironmentSummaryRow`, with **no `.swipeActions`** (swipe-free), and a parent-owned `@State private var expandedEnvironment: Set<String>` (mirrors `expandedSessions`), toggled inside `withAnimation(.easeOut(duration: 0.2))`. Same `.listRowInsets/.listRowSeparator/.listRowBackground` treatment as the other rows.

### C. Collapsed headline (Decision 3, precise)

- If the day has a `temperature` event → `"{lowConv}–{highConv}°{unit}"` (via `WeatherValueFormatter`), append `" · {humidity}%"` when a `humidity` event exists.
- Else if a `moonPhase` event exists → the moon phase name, append `" · {season}"` when a `season` event exists.
- Else (degenerate single-subtype day; e.g. season-only or mercury-only) → the first detail line rendered as `"{label}: {value}"`, or the bare `"{label}"` when that reading has no value (e.g. mercury retrograde). The labeled form guarantees a non-empty headline even for a value-less reading.

### D. Expandability

- The row is **expandable when it has ≥2 detail lines** — i.e. more than the single-line headline conveys. Because `pressureDrop` folds into the Air pressure line (§3B), a pressure-only day is one line and is not expandable; backfill days (moon + season, often + mercury) and live days have ≥2 and always qualify. A one-line day renders a **non-expandable** row (no chevron) — parity with `SleepSessionRow`'s `isExpandable` guard. Implemented as `detailLines(...).count >= 2`.

### E. Read-only enforcement (Decision 7)

Environment data must expose no edit or delete affordance on any surface:
- **Collapsed row** — swipe-free (§3B). ✓ by construction.
- **Search raw rows** — in `TimelineView`'s `.swipeActions` for `.event` rows, the destructive **Delete** button is currently attached to *every* event. Gate it so it is **not** attached when `event.category == .environment`. (Edit is already `.manual`-only, so env never showed Edit.) An env row in search thus has no swipe actions.
- **Detail sheet** — `EventDetailView` currently shows its `deleteButton` unconditionally. Gate it to **hide for `.environment`** events (reachable only by tapping a raw env row in search). Edit is already `.manual`-gated.

## 4. Reused / unchanged

- The **`SleepSessionRow` pattern** end to end: stateless row, parent-owned `Set<String>` expansion, custom button + conditional subview (not `DisclosureGroup`), swipe-free, deterministic value-type id.
- The **browse-vs-search grouping distinction** already in `TimelineDayBuilder` / `TimelineViewModel` (grouped in browse, raw in search; delete triggers the full slice rebuild).
- **`WeatherValueFormatter`** (unit-aware temperature range) and **`EventDisplay`** (titles/value lines) — reused as-is; `EventDisplay` stays pure.
- **Ingestion** (`EnvironmentalDataService`/`EnvironmentalEventEmitter`/`EnvironmentalEventFactory`), dedup keys, and the **evidence engine** — untouched. This feature reads already-logged events.

## 5. Testing

- **Core (`swift test`):**
  - `TimelineDayBuilderTests` — a day's `.environment` events collapse into exactly one `.environmentSummary` item and are excluded from that day's `.event` rows; non-environment events on the same day are unaffected and still sort correctly by time; the summary's `id` is deterministic and stable across rebuilds; distinct days produce distinct ids; a day with a single env subtype still yields a summary item.
  - Search path (grouping off) — the builder leaves `.environment` events as raw `.event` rows (no `.environmentSummary`), mirroring the sleep `sessionizeSleep: false` behavior.
  - `EnvironmentDaySummary` canonical event order is deterministic regardless of input order.
- **App (`-parallel-testing-enabled NO`):**
  - `EnvironmentSummaryFormatter` — headline is temp-range·humidity on a full day; **falls back to moon·season on a backfill day** (no temp/humidity); detail lines are complete, correctly labeled, in canonical order; temperature honors the °C/°F setting (range flips units); pressureDrop is annotated on the pressure line.
  - Read-only — a `.environment` event yields **no Delete swipe** in the search row path, and `EventDetailView` renders **no delete button** for an `.environment` event (while still showing it for a `.manual` one).
- **Device:** Timeline browse shows one "Environment" row per day (collapsed headline correct for both a live day and a backfilled day); tap expands to the labeled list and collapses; no swipe actions on the row; search shows individual env rows again with no Delete swipe; light + dark; XXL Dynamic Type.

## 6. Out of scope

- Any change to how weather/moon/mercury/season are sourced or computed (location services, endpoints, the northern-hemisphere season assumption).
- Any change to the evidence engine, tiers, dedup, or the units picker.
- Per-event detail navigation for environment from browse (intentionally dropped — the expanded row is the detail).
- Collapsing any non-`.environment` category; changing sleep or manual rows.
- Making other auto-logged sources (e.g. HealthKit imports) read-only — this feature scopes read-only to `.environment` only.

## 7. Next / future

- If the expanded list wants richer treatment (e.g. a small pressure trend), it can grow later; v1 is a static labeled list.
- A future "why is this here?" affordance linking an env reading to its Insights tier, if users ask where the data comes from.
