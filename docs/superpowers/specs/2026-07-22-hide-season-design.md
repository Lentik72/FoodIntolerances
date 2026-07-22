# Hide Season (Retire the Season Environment Signal) — Design

**Date:** 2026-07-22
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Stop emitting the `season` environment event and hide the already-stored season rows from every display surface (Environment summary row, search, detail sheet). Follow-up #3 after the accessible-AQI-badges round. No migration; stored rows are untouched.

**Not touched:** the legacy food-intolerance seasonal path (`LogEntry.season`, `LogItemViewModel.determineSeason`, the "Seasonal Changes" category, seasonal-allergy alerts, `UserMemoryService` season patterns, `PersonalAIAssistant` season memories) — it has its own season calculation and keeps working as-is. Also untouched: the evidence engine, all other environment subtypes, ingestion provenance/dedup, the frozen v6 migration, tombstone semantics.

---

## 1. Problem

The environment pipeline emits a `season` event every day (plus backfilled history), but nothing consumes it: there is no `SeasonExposureSource`, so the evidence engine never mines it. It is pure display — a "Season: Summer" detail line in the Environment row, a "{moon} · {season}" headline fallback on backfill days, and raw rows in search. Worse, the calculation (`SeasonService.getCurrentSeason`) is Northern-Hemisphere-specific, so it is actively wrong for southern-hemisphere users. And the factory comment at `EnvironmentalEventFactory.swift:84` falsely claims "the engine correlates against season presence" — it doesn't.

Season is derivable from the date, so retiring it loses nothing: a future hemisphere-aware season exposure could regenerate the entire history via backfill.

## 2. Decisions (Leo, 2026-07-22)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Depth | **Stop emitting + hide** — emitter stops producing season events; existing stored rows stay in the DB (immutable, tombstone rules untouched, no migration) but are filtered from every display site. Rejected: UI-only hiding (keeps writing dead data) and a purge migration (churn/risk for zero user-visible gain). |
| 2 | Where hiding lives | **Core retired-subtype policy** — one constant (`EnvironmentDaySummaryBuilder.retiredSubtypes`) consumed by the summary builder (a public direct entry point) and by `TimelineDayBuilder.days` (which covers browse AND raw/search mode for every current and future caller — Leo's review moved this out of `TimelineViewModel` so visibility policy never depends on one caller). Rejected: app-side-only filters (rule duplicated, future core consumers resurface season) and SQL-level exclusion (subtype policy inside generic query code). |
| 3 | Emission removal | **Delete the `season` field from `EnvironmentalReading` entirely** (not pass-nil) — the factory's season block dies with it, taking the inaccurate comment along. |
| 4 | Dead code | Delete `SeasonService.swift` — `getCurrentSeason` has exactly one consumer (the emitter); legacy uses its own `determineSeason`. |
| 5 | `EventDisplay` | **Keep** the `"season"` title/value mappings — the debug view shows raw events, and old rows should still render sanely anywhere they might leak. |
| 6 | Debug seed | Stop seeding the season event in the WEATHER demo (`HealthGraphDebugView`). |

## 3. Architecture

### A. Emission retirement

- **`EnvironmentalEventFactory` (core):** remove `season` from `EnvironmentalReading` (property + init) and delete the season event block (`EnvironmentalEventFactory.swift:83–88`), including the inaccurate "engine correlates against season presence" comment.
- **`EnvironmentalEventEmitter` (app):** update the three `EnvironmentalReading(` call sites (today's reading at line 88, the weather-less reading at 133, backfill at 178) to drop the `season:` argument; the backfill doc comment ("moon phase, season, mercury") updates to match.
- **`SeasonService.swift` (app):** delete the file.
- **`HealthGraphDebugView` (app):** remove the seeded season `HealthEvent` (~line 534) and update the adjacent seed-content comment.

No migration. Existing season rows (including tombstones) are untouched; dedup keys for other subtypes are unaffected. Since no new season events are ever created, stopping emission has no dedup or provenance interaction.

### B. Display policy (core, single source of truth)

In `EnvironmentDaySummaryBuilder`:

- New `public static let retiredSubtypes: Set<String> = ["season"]` — subtypes that still exist as stored rows but must never display. A doc comment records why season is retired (never mined, Northern-Hemisphere-only calc) and that it is date-derivable if ever wanted back.
- `summaries(from:)` filters retired subtypes **before** grouping (alongside the existing `.environment` category filter), so a hypothetical season-only day produces **no Environment row at all**, not an empty one.
- `"season"` is removed from `subtypeOrder` (unreachable after the filter).

`EnvironmentSummaryFormatter` needs one small cleanup: its detail lines are generic (driven by the summary's events + `EventDisplay`), so the "Season: …" line disappears on its own — but the headline fallback has an explicit season branch (`EnvironmentSummaryFormatter.swift:43`, `"{moon} · {season}"`) that becomes unreachable once the builder filters season. Remove that branch (the fallback returns the moon phase alone) rather than leaving dead code.

Browse cannot leak a raw season row: `TimelineDayBuilder.days` strips **all** `.environment` events from the row stream in browse mode unconditionally (`TimelineDayBuilder.swift:90`) — the summary is the only browse surface, and it is now filtered.

### C. Raw-row filter (core, all callers)

In `TimelineDayBuilder.days(from:timeZone:sessionizeSleep:groupEnvironment:)`, filter the input once at the top and use it consistently for sessions, summaries, and `rowEvents`:

```swift
let visibleEvents = events.filter {
    !($0.category == .environment &&
      EnvironmentDaySummaryBuilder.retiredSubtypes.contains($0.subtype ?? ""))
}
```

This covers browse (`groupEnvironment: true`) and — critically — raw/search mode (`groupEnvironment: false`), where the previous design would have filtered only inside `TimelineViewModel.runSearch()` (note: `runSearch()`, the private worker `searchTextChanged()` delegates to) and left any other current or future raw-row caller exposed. The summary builder KEEPS its own filter because `EnvironmentDaySummaryBuilder.summaries` is also a public direct entry point. `TimelineViewModel` gets **no season-specific code**; its search test remains as an integration check. Search is the only path to raw environment rows, and `EventDetailView` is reachable only by tapping a search row — so the core filter also closes off the detail sheet. No `EventDetailView` change.

## 4. Files

- **Delete** `SeasonService.swift`.
- **Modify** `HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift` — drop the `season` field + event block (+ inaccurate comment).
- **Modify** `HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift` — `retiredSubtypes`, pre-grouping filter, `subtypeOrder` without `"season"`.
- **Modify** `Models/EnvironmentalEventEmitter.swift` — three call sites + doc comments.
- **Modify** `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift` — remove the unreachable `"{moon} · {season}"` headline branch.
- **Modify** `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift` — `visibleEvents` retired-subtype filter feeding sessions/summaries/rowEvents.
- **Modify** `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift` — see Testing.
- **Modify** `Views/HealthGraphDebugView.swift` — remove the season seed.
- **Modify** `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift`, `EnvironmentDaySummaryBuilderTests.swift` — see Testing.
- **Modify** `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift` — see Testing.

## 5. Testing

- **Factory (core):** a reading produces **no** season event; the event-count/subtype assertions update accordingly. (The `season` parameter no longer exists, so the compiler enforces call-site updates.)
- **Builder (core):**
  - A day containing a stored season event (retired subtype) folds into a summary **without** it; the other subtypes keep canonical order.
  - A day whose only env event is a retired subtype produces **no summary** (not an empty one).
- **Formatter (app):** the moon-phase headline fallback returns the moon phase alone (season branch removed); existing "moon · season" expectations update to moon-only, and season detail-line expectations are removed from fixtures.
- **Raw-row filter (core):** a `TimelineDayBuilder.days(..., groupEnvironment: false)` call with a stored season event and an `airQuality` event yields only the `airQuality` row (season removed in raw mode, not just in summaries).
- **Search integration (VM/app):** searching for the stored season event via `TimelineViewModel` (which exercises `runSearch()` → `TimelineDayBuilder.days`) renders nothing; other environment subtypes (e.g. `airQuality`) still pass through. No season-specific code in `TimelineViewModel` itself.
- **Migration tests:** untouched — the frozen v6 migration may keep classifying legacy season rows; that is correct (they're stored, just never displayed).
- **Device pass:** Environment row (live + backfilled days) shows no Season line; a backfill day's headline reads "Full moon" (no "· Summer"); searching "season"/"summer" surfaces no environment rows; legacy seasonal-allergy features still work.

## 6. Out of scope

- Deleting or migrating stored season rows (they stay, hidden).
- Any change to the legacy seasonal-analysis path.
- A hemisphere-aware season exposure (possible future round; backfill can regenerate history from dates).
- Removing `EventDisplay`'s season mappings (kept for debug/leak robustness).
- Moon-phase SF Symbols (follow-up #4, next round).
