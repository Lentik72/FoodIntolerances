# Hide Season (Retire the Season Environment Signal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop emitting the `season` environment event and hide already-stored season rows from every display surface (Environment summary row, search, detail sheet), per `docs/superpowers/specs/2026-07-22-hide-season-design.md`.

**Architecture:** A core retired-subtype policy — `EnvironmentDaySummaryBuilder.retiredSubtypes = ["season"]` — enforced entirely in core: the summary builder filters its own input (it is a public direct entry point), and `TimelineDayBuilder.days` filters raw events for EVERY caller and mode (browse summaries AND `groupEnvironment: false` raw/search rows), so no app-layer caller can leak a retired row. `TimelineViewModel` carries no season-specific code. Emission stops at the source: the `season` field is deleted from `EnvironmentalReading`, the factory's season block (and its inaccurate comment) goes with it, and the now-dead `SeasonService.swift` is removed.

**Tech Stack:** Swift / SwiftUI app + HealthGraphCore local SwiftPM package (GRDB). Swift Testing (`@Test`/`#expect`) in both suites.

## Global Constraints

- **No migration, no data deletion.** Stored season rows (including tombstones) stay in the DB untouched; the frozen v6 migration (`EnvProvenanceMigrationTests` legacy-season seeding) is NOT modified.
- **Legacy seasonal path untouched:** `LogEntry.season`, `LogItemViewModel.determineSeason`, the "Seasonal Changes" category, `UserMemoryService` season patterns, `PersonalAIAssistant` season memories all keep working. Only `SeasonService.swift` (sole consumer: the env emitter) is deleted.
- **`EventDisplay`'s `"season"` title/value mappings are KEPT** (debug view renders raw events; old rows must render sanely).
- **Single source of truth:** the only place the string `"season"` appears as a hiding rule is `EnvironmentDaySummaryBuilder.retiredSubtypes`; `TimelineDayBuilder` references that constant. **No app-layer (TimelineViewModel) season filter.**
- App tests MUST run with `-parallel-testing-enabled NO` (known `SwiftDataMigratorTests` teardown crash under parallel testing). Destination: `platform=iOS Simulator,name=iPhone 17 Pro`.
- Core tests: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test`.
- Commits: conventional-commit style, trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Working directory: `/Users/leo/dev/FoodIntolerances` (all paths below relative to it).

---

### Task 1: Core retired-subtype filter in the summary builder (+ formatter dead-branch removal)

The builder drops retired subtypes **before** grouping (a retired-only day yields NO summary, not an empty one). The formatter's explicit `"{moon} · {season}"` headline branch becomes unreachable and is removed. App formatter tests go red the moment the builder filters (their `day(_:)` helper builds summaries through the real builder), so their updates belong in this task.

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift:24-37`
- Modify: `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift:29-45`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentDaySummaryBuilderTests.swift`
- Test: `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift`

**Interfaces:**
- Consumes: existing `EnvironmentDaySummaryBuilder.summaries(from:timeZone:)`, `EnvironmentSummaryFormatter.headline/headlineResult/detailLines`.
- Produces: `public static let retiredSubtypes: Set<String>` on `EnvironmentDaySummaryBuilder` — **Task 3's search filter references exactly this name**. `subtypeOrder` no longer contains `"season"`.

- [ ] **Step 1: Update the core builder tests (RED first)**

In `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentDaySummaryBuilderTests.swift`:

Replace the canonical-order expectation in `groupsOneDayIntoOneSummaryInCanonicalOrder` (keep `env("season", 0)` in the INPUT — it proves the filter):

```swift
    @Test func groupsOneDayIntoOneSummaryInCanonicalOrder() {
        // REVERSE-canonical input → forces every adjacent pair (incl. temperature vs humidity) through the comparator
        let events = [env("mercuryRetrograde", 0), env("season", 0), env("moonPhase", 0),
                      env("humidity", 0), env("temperature", 0)]
        let summaries = EnvironmentDaySummaryBuilder.summaries(from: events, timeZone: tz)
        #expect(summaries.count == 1)
        #expect(summaries[0].events.map { $0.subtype } ==
                ["temperature", "humidity", "moonPhase", "mercuryRetrograde"])   // canonical; season retired → filtered
        #expect(summaries[0].dayStart == Date(timeIntervalSince1970: 0))
    }
```

Swap the retired subtype out of the two tests that only need "any env event" (season events now produce no summary, so `[0]` would trap):

```swift
    @Test func idIsDeterministicPerDayAndDistinctAcrossDays() {
        let a = EnvironmentDaySummaryBuilder.summaries(from: [env("moonPhase", 5)], timeZone: tz)[0]
        let a2 = EnvironmentDaySummaryBuilder.summaries(from: [env("moonPhase", 5)], timeZone: tz)[0]
        let b = EnvironmentDaySummaryBuilder.summaries(from: [env("moonPhase", 6)], timeZone: tz)[0]
        #expect(a.id == a2.id && a.id != b.id)
    }
```

```swift
    @Test func multipleDaysSortNewestFirst() {
        let s = EnvironmentDaySummaryBuilder.summaries(from: [env("moonPhase", 1), env("moonPhase", 3)], timeZone: tz)
        #expect(s.map { $0.dayStart } == [Date(timeIntervalSince1970: 3 * 86_400), Date(timeIntervalSince1970: 86_400)])
    }
```

Add a new test after `multipleDaysSortNewestFirst`:

```swift
    @Test func retiredSubtypeOnlyDayProducesNoSummary() {
        // Filter runs BEFORE grouping — a stored-season-only day yields no row, not an empty row.
        #expect(EnvironmentDaySummaryBuilder.summaries(from: [env("season", 0)], timeZone: tz).isEmpty)
    }
```

- [ ] **Step 2: Run core tests to verify they fail**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test --filter EnvironmentDaySummaryBuilderTests 2>&1 | tail -10`
Expected: FAIL — `groupsOneDayIntoOneSummaryInCanonicalOrder` (order still contains `"season"`) and `retiredSubtypeOnlyDayProducesNoSummary` (summary produced). The two moonPhase-swapped tests PASS.

- [ ] **Step 3: Implement the builder filter**

In `HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift`, replace the `subtypeOrder` declaration (lines 24-25) with:

```swift
    /// Canonical detail/display order. Unknown subtypes sort last (stable).
    public static let subtypeOrder = ["temperature", "humidity", "airQuality", "pressure",
                                      "pressureDrop", "moonPhase", "mercuryRetrograde"]

    /// Subtypes that may still exist as stored rows but must never display.
    /// `season` is retired: it was never mined (no exposure source exists) and its
    /// calculation was Northern-Hemisphere-only. It is a pure date-fact, so a future
    /// hemisphere-aware exposure could regenerate the history via backfill.
    public static let retiredSubtypes: Set<String> = ["season"]
```

And in `summaries(from:timeZone:)`, replace the env filter line

```swift
        let env = events.filter { $0.category == .environment }
```

with:

```swift
        let env = events.filter { $0.category == .environment
            && !retiredSubtypes.contains($0.subtype ?? "") }
```

- [ ] **Step 4: Run core tests to verify they pass**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: PASS (full core suite — nothing else in core consumes `subtypeOrder`'s season entry).

- [ ] **Step 5: Update the app formatter tests**

In `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift` (keep the `season(_:)` helper — the filter-proof tests still use it):

Replace `headlineBackfillMoonAndSeason`:

```swift
    @Test func headlineBackfillMoonWithStoredSeasonFiltered() {
        // A stored legacy season event is retired by the builder → the backfill headline is the moon alone.
        #expect(EnvironmentSummaryFormatter.headline(day([moon("Waxing gibbous"), season("Summer")]), unit: c) == "Waxing gibbous")
    }
```

Replace `headlineDegenerateSeasonOnly` (the labeled-degenerate branch needs a value-ful subtype that still displays):

```swift
    @Test func headlineDegeneratePressureOnlyIsLabeled() {
        #expect(EnvironmentSummaryFormatter.headline(day([pressure(1013)]), unit: c) == "Air pressure: 1013 hPa")
    }
```

In `detailLinesOrderedLabeledAndFolded`, keep `season("Summer")` in the input and drop `"Season"` from the expected labels:

```swift
        #expect(rows.map(\.label) == ["Temperature", "Humidity", "Air pressure", "Moon phase", "Mercury retrograde"])   // Season retired → filtered by the builder
```

In `detailLineCountDrivesExpandability`, swap the season-only line (would trap on `[0]`) for mercury:

```swift
        #expect(EnvironmentSummaryFormatter.detailLines(day([mercury()]), unit: c).count == 1)          // one line → not expandable
```

- [ ] **Step 6: Remove the formatter's now-unreachable season branch**

In `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift`, replace the moon branch of `headlineResult` (lines 42-45)

```swift
        if let moon = value("moonPhase", summary, unit) {
            if let season = value("season", summary, unit) { return EnvironmentHeadline(text: "\(moon) · \(season)", aqi: nil) }
            return EnvironmentHeadline(text: moon, aqi: nil)
        }
```

with:

```swift
        if let moon = value("moonPhase", summary, unit) {
            return EnvironmentHeadline(text: moon, aqi: nil)
        }
```

And update the two doc comments that mention season — line 30 (`else moon phase (· season); else the single remaining reading`) becomes `else moon phase; else the single remaining reading`, and the `headlineResult` doc line 29-32 loses its `(· season)`.

- [ ] **Step 7: Run the app formatter tests to verify they pass**

Run:
```bash
cd /Users/leo/dev/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/EnvironmentSummaryFormatterTests" 2>&1 | tail -10
```
Expected: `** TEST SUCCEEDED **` — all formatter cases pass.

- [ ] **Step 8: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentDaySummaryBuilderTests.swift \
        "Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift" \
        "Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift"
git commit -m "feat(core): retiredSubtypes display filter — season dropped from Environment summaries (+ dead moon·season headline branch)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Stop emitting season (factory field removal, emitter, SeasonService deletion, debug seed)

Delete the `season` field from `EnvironmentalReading` — the compiler then enforces every call-site update. The factory's season block (with its inaccurate "the engine correlates against season presence" comment) is deleted; `SeasonService.swift` (sole consumer: the emitter) is removed from disk AND from `project.pbxproj`; the debug WEATHER seed stops seeding a season row.

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift:9,18,26,83-88`
- Modify: `Models/EnvironmentalEventEmitter.swift:44,93,135,163,181`
- Delete: `SeasonService.swift` (+ its 4 references in `Food Intolerances.xcodeproj/project.pbxproj` lines 94, 219, 380, 661)
- Modify: `Views/HealthGraphDebugView.swift:513,533-538`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EnvProvenanceMigrationTests.swift:125-128`

**Interfaces:**
- Consumes: nothing from Task 1 (independent; core builds either order).
- Produces: `EnvironmentalReading` WITHOUT a `season` property/parameter — signature becomes `init(date:pressureHPa:previousPressureHPa:moonPhaseName:isMercuryRetrograde:timezoneID:temperatureHighC:temperatureLowC:humidityPct:airQualityAQI:)`. `EnvironmentalEventFactory.events(for:)` never returns a `subtype == "season"` event.

- [ ] **Step 1: Make the factory tests demand no season (RED first, compile-compatible)**

In `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift` — behavioral assertions only for now (the `season:` constructor arguments stay until Step 3, so the file still compiles):

Replace `emitsPressureMoonAndSeasonOnAQuietDay` with:

```swift
    @Test func emitsPressureAndMoonOnAQuietDay() throws {
        let events = EnvironmentalEventFactory.events(for: reading())
        #expect(events.count == 2) // pressure + moonPhase; no drop, no retrograde
        #expect(!events.contains { $0.subtype == "season" })   // season retired — never emitted
        #expect(events.allSatisfy { $0.category == .environment })
        #expect(events.allSatisfy { $0.source == .weatherAPI })
        #expect(events.allSatisfy { $0.dedupKey != nil })
        let pressure = events.first { $0.subtype == "pressure" }
        #expect(pressure?.value == 1013)
        #expect(pressure?.unit == "hPa")
        let moon = try #require(events.first { $0.subtype == "moonPhase" })
        let moonMeta = try JSONDecoder().decode([String: String].self, from: moon.metadata ?? Data())
        #expect(moonMeta["phase"] == "Full Moon") // emoji stripped
    }
```

In `nilPressureSkipsPressureEventsOnly`, delete the line `#expect(events.contains { $0.subtype == "season" })`.

In `dailyKeysMakeReemissionIdempotent`, change the count expectation:

```swift
        #expect(try await store.count() == 3) // same day: updated, not duplicated
```
becomes
```swift
        #expect(try await store.count() == 2) // same day: updated, not duplicated (pressure + moonPhase)
```

In `emitsAirQualityWhenAQIPresent`, update the count comment: `// no pressure/moon/season/temp/humidity this day` → `// no pressure/moon/temp/humidity this day`.

In `stampsPerSignalProvenanceOnEveryEvent`, delete the line `#expect(provenance("season") == .observedCompletedDay)`.

- [ ] **Step 2: Run core tests to verify the new expectations fail**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test --filter EnvironmentalEventFactoryTests 2>&1 | tail -10`
Expected: FAIL — `emitsPressureAndMoonOnAQuietDay` (count is 3 and a season event exists) and `dailyKeysMakeReemissionIdempotent` (count is 3).

- [ ] **Step 3: Remove the season field and block from the factory, then fix test call sites**

In `HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift`:
- Delete line 9 (`public let season: String?`).
- In the init: delete `season: String?,` from the signature (line 18) and `self.season = season` (line 26).
- Delete the whole season block (lines 83-88) — including the inaccurate comment:

```swift
        if let season = r.season {
            // Daily exposure — the engine correlates against season presence,
            // not just the four transition days a year.
            events.append(event("season", metadata: ["season": season],
                                provenance: .observedCompletedDay))
        }
```

Then fix the core test call sites (compiler-enforced):
- `EnvironmentalEventFactoryTests.swift`: the `reading(...)` helper becomes

```swift
    func reading(date: Date? = nil, pressure: Double? = 1013, previous: Double? = 1015,
                 moon: String? = "Full Moon 🌕", retrograde: Bool = false) -> EnvironmentalReading {
        EnvironmentalReading(
            date: date ?? noon, pressureHPa: pressure, previousPressureHPa: previous,
            moonPhaseName: moon,
            isMercuryRetrograde: retrograde, timezoneID: "UTC")
    }
```

  and the six inline `EnvironmentalReading(` constructions (lines ~79, ~87, ~102, ~114, ~126, ~137) drop their `season: nil,` / `season: "Summer",` argument.
- `EnvProvenanceMigrationTests.swift:125-128`: `moonPhaseName: "Full Moon", season: nil,` → `moonPhaseName: "Full Moon",`. Do NOT touch that file's legacy-season row seeding (lines 58, 67) — the frozen migration still classifies stored legacy season rows, by design.

- [ ] **Step 4: Run core tests to verify they pass**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: PASS (full core suite).

- [ ] **Step 5: Update the app emitter, delete SeasonService, remove the debug seed**

In `Models/EnvironmentalEventEmitter.swift`:
- Line 44 doc comment: `deterministic date-facts (moon/season/mercury)` → `deterministic date-facts (moon/mercury)`.
- Today's reading (line ~93): delete `season: getCurrentSeason(for: today),`.
- The AQI-only reading (line ~135): `moonPhaseName: nil, season: nil, isMercuryRetrograde: false,` → `moonPhaseName: nil, isMercuryRetrograde: false,`.
- `backfillDerived` doc (line ~163): `date-derived signals (moon phase, season, Mercury retrograde)` → `date-derived signals (moon phase, Mercury retrograde)`.
- Backfill reading (line ~181): delete `season: getCurrentSeason(for: date),`.

Delete the dead service file and its project references:

```bash
git rm SeasonService.swift
```

In `Food Intolerances.xcodeproj/project.pbxproj`, delete these four lines (exact content):
- Line 94: `B3D487BB2D56397F00F7E3BA /* SeasonService.swift in Sources */ = {isa = PBXBuildFile; fileRef = B3D487BA2D56397F00F7E3BA /* SeasonService.swift */; };`
- Line 219: `B3D487BA2D56397F00F7E3BA /* SeasonService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SeasonService.swift; sourceTree = "<group>"; };`
- Line 380: `B3D487BA2D56397F00F7E3BA /* SeasonService.swift */,`
- Line 661: `B3D487BB2D56397F00F7E3BA /* SeasonService.swift in Sources */,`

In `Views/HealthGraphDebugView.swift`:
- Comment line ~513: `Air pressure (with the pressure-drop fold) / Moon phase / Season /` → `Air pressure (with the pressure-drop fold) / Moon phase /`.
- Delete the season seed block (lines ~533-538):

```swift
                events.append(HealthEvent(
                    timestamp: stamp, timezoneID: tz, category: .environment, subtype: "season",
                    source: .weatherAPI, metadata: try? JSONEncoder().encode(
                        ["season": "Summer", "provenance": TemporalProvenance.observedCompletedDay.rawValue]),
                    dedupKey: DedupKey.daily(.environment, "season", dayStart: dayStart,
                                             provenance: .observedCompletedDay)))
```

- [ ] **Step 6: Run the app test suite to verify everything passes**

Run:
```bash
cd /Users/leo/dev/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -25
```
Expected: `** TEST SUCCEEDED **`. (Emitter/orchestration tests assert per-subtype, not totals — they don't reference season. The legacy `determineSeason` in `LogItemViewModel` is untouched, so legacy seasonal tests are unaffected.)

- [ ] **Step 7: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EnvProvenanceMigrationTests.swift \
        Models/EnvironmentalEventEmitter.swift \
        Views/HealthGraphDebugView.swift \
        "Food Intolerances.xcodeproj/project.pbxproj"
git commit -m "feat: stop emitting the season env event — field deleted from EnvironmentalReading, SeasonService removed, seed dropped

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(`git rm SeasonService.swift` already staged the deletion.)

---

### Task 3: Raw-row retired filter in TimelineDayBuilder (+ VM integration test, full verification)

Filtering in `TimelineViewModel` would make visibility policy dependent on one caller — `TimelineDayBuilder.days(..., groupEnvironment: false)` would still surface retired season events to any current or future raw-row caller. So the filter lives in `TimelineDayBuilder.days` itself, feeding sessions, summaries, and `rowEvents` from one filtered slice. The summary builder KEEPS its own filter (Task 1) because `EnvironmentDaySummaryBuilder.summaries` is also a public direct entry point. **`TimelineViewModel` gets NO season-specific code** — its search test is an integration check that the core filter reaches the search surface (search flows through `runSearch()` → `TimelineDayBuilder.days(..., groupEnvironment: false)`; note the store fetch + category/source filters live in the private `runSearch()`, which `searchTextChanged()` delegates to).

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift:74-90`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift`
- Test: `Food IntolerancesTests/TimelineViewModelTests.swift` (integration only — no `TimelineViewModel` source change)

**Interfaces:**
- Consumes: `EnvironmentDaySummaryBuilder.retiredSubtypes` (Task 1; same module).
- Produces: nothing new — behavior only. `TimelineDayBuilder.days` signature unchanged.

- [ ] **Step 1: Write the failing core test**

In `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift`, add after `searchLeavesEnvironmentRaw` (same local-`env` idiom):

```swift
    /// Retired env subtypes are invisible in RAW mode too — the filter lives in
    /// days(), not in any one caller (search or otherwise).
    @Test func rawModeFiltersRetiredEnvironmentSubtypes() {
        let tz = TimeZone(identifier: "UTC")!
        func env(_ s: String, value: Double? = nil) -> HealthEvent { HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200),
            timezoneID: "UTC", category: .environment, subtype: s, value: value, source: .weatherAPI) }
        let days = TimelineDayBuilder.days(from: [env("season"), env("airQuality", value: 42)], timeZone: tz,
                                           sessionizeSleep: false, groupEnvironment: false)
        #expect(days.flatMap(\.events).map(\.subtype) == ["airQuality"])   // season removed, airQuality remains
        // A retired-only slice yields no day at all, not an empty day.
        #expect(TimelineDayBuilder.days(from: [env("season")], timeZone: tz,
                                        sessionizeSleep: false, groupEnvironment: false).isEmpty)
    }
```

- [ ] **Step 2: Run the core tests to verify the new one fails**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test --filter TimelineDayBuilderTests 2>&1 | tail -10`
Expected: FAIL — `rawModeFiltersRetiredEnvironmentSubtypes`: raw mode currently passes the season row straight through to `rowEvents`. All pre-existing builder tests PASS.

- [ ] **Step 3: Implement the raw-event filter in days()**

In `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift`, at the top of `days(from:timeZone:sessionizeSleep:groupEnvironment:)` (after the calendar setup, before the sleep-session block), add:

```swift
        // Stored rows of retired env subtypes (season) must never display, in ANY
        // mode — raw/search rows included. Filtered here so no caller can leak
        // them; the summary builder re-filters for its own public callers.
        let visibleEvents = events.filter {
            !($0.category == .environment &&
              EnvironmentDaySummaryBuilder.retiredSubtypes.contains($0.subtype ?? ""))
        }
```

Then use `visibleEvents` consistently in the three places that read `events`:

```swift
        let sessions = sessionizeSleep
            ? SleepSessionBuilder.sessions(from: visibleEvents.filter(isSessionizable), timeZone: timeZone)
```

```swift
        let summaries = groupEnvironment
            ? EnvironmentDaySummaryBuilder.summaries(from: visibleEvents, timeZone: timeZone)
            : []
        var rowEvents = sessionizeSleep ? visibleEvents.filter { !isSessionizable($0) } : visibleEvents
```

(The `.filter { $0.end.timeIntervalSince($0.start) >= 60 }` line under `sessions` and everything below `rowEvents` are unchanged.)

- [ ] **Step 4: Run the core tests to verify they pass**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: PASS (full core suite).

- [ ] **Step 5: Add the VM search integration test**

In `Food IntolerancesTests/TimelineViewModelTests.swift`, add after `searchModeGroupsMatchesAndClearingReturnsToBrowse` (NO change to `TimelineViewModel` itself — this proves the core filter reaches the search surface end-to-end):

```swift
    /// Integration: the core retired-subtype filter (TimelineDayBuilder) reaches the
    /// search surface — no season-specific code exists in TimelineViewModel.
    @Test func searchNeverShowsRetiredEnvironmentSubtypes() async throws {
        let (_, store) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save([
            HealthEvent(timestamp: base, category: .environment, subtype: "season",
                        source: .weatherAPI, createdAt: base),
            HealthEvent(timestamp: base.addingTimeInterval(60), category: .environment, subtype: "airQuality",
                        value: 42, source: .weatherAPI, createdAt: base),
        ])
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        vm.searchText = "season"
        await vm.searchTextChanged()
        #expect(vm.isSearchActive)
        #expect(vm.days.flatMap(\.events).isEmpty)   // the stored season row must never display
        vm.searchText = "airquality"
        await vm.searchTextChanged()
        #expect(vm.days.flatMap(\.events).map(\.subtype) == ["airQuality"])   // other env subtypes still pass
    }
```

- [ ] **Step 6: Run the VM tests to verify they pass**

Run:
```bash
cd /Users/leo/dev/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/TimelineViewModelTests" 2>&1 | tail -10
```
Expected: `** TEST SUCCEEDED **` — the new integration test passes on the strength of the Step 3 core filter alone (it exercises `runSearch()` → `TimelineDayBuilder.days(..., groupEnvironment: false)`).

- [ ] **Step 7: Full-suite verification (both packages)**

Run:
```bash
cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3
cd /Users/leo/dev/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -5
```
Expected: core suite all pass; app suite `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift \
        "Food IntolerancesTests/TimelineViewModelTests.swift"
git commit -m "feat(core): TimelineDayBuilder filters retired env subtypes in every mode — raw season rows hidden for all callers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Device gate (Leo, after Task 3)

Not a plan task — the round's final verification, per the spec's Testing section:
1. Environment row on a live day and a backfilled day: no "Season" line; backfill headline reads e.g. "Full moon" with no "· Summer".
2. Search "season" and "summer": no environment rows surface.
3. Debug "Load WEATHER demo": Environment row renders every remaining detail line (no Season).
4. Legacy seasonal-allergy features still work (capture-side season tracking untouched).
