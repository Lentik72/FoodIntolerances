# Environment Timeline Summary Row Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the per-day auto-logged `.environment` events into ONE expandable "Environment" Timeline row, mirroring `SleepSessionRow`, and make environment data read-only (no edit/delete).

**Architecture:** Core groups the day's `.environment` events into an `EnvironmentDaySummary` value type (pure reducer, like `SleepSessionBuilder`) and adds a `TimelineItem.environmentSummary` case that `TimelineDayBuilder.days` emits in browse mode. The app renders it with a stateless `EnvironmentSummaryRow` (parent-owned expand state, swipe-free) whose text comes from a pure `EnvironmentSummaryFormatter` (unit-aware temperature via `WeatherValueFormatter`; everything else via `EventDisplay`). Read-only is enforced by gating the Delete swipe and the detail-sheet Delete button on `category == .environment`.

**Tech Stack:** Swift, Swift Testing, SwiftUI. Display-only — no ingestion/dedup/evidence change.

Design: `docs/superpowers/specs/2026-07-20-environment-timeline-summary-design.md`.

## Global Constraints

- **Display-only.** No change to `EnvironmentalDataService`/`EnvironmentalEventEmitter`/`EnvironmentalEventFactory`, dedup keys, or the evidence engine. This feature reads already-logged events.
- **Read-only rule:** an event is read-only iff `event.category == .environment`. Such events expose NO Delete and NO Edit anywhere (collapsed row is swipe-free; the raw env rows in search get no Delete swipe; the detail sheet hides its Delete button). Edit is already `.manual`-only, so env never showed Edit.
- **Follow the `SleepSessionRow` pattern exactly:** a stateless row (`summary`, `isExpanded`, `onToggle`), parent-owned `Set<String>` expansion state toggled in `withAnimation(.easeOut(duration: 0.2))`, a custom Button + conditional subview (NOT `DisclosureGroup`), swipe-free, and a deterministic value-type `id`.
- **Grouped in browse, raw in search:** env grouping is gated by a new `groupEnvironment: Bool = true` param on `TimelineDayBuilder.days`, which the two search/subset call sites pass as `false` (exactly where they already pass `sessionizeSleep: false`).
- **Unit-aware temperature:** the row/formatter resolve `@AppStorage("hg.temperatureUnit")` → `TemperatureUnit` and format temperature via `WeatherValueFormatter`. `EventDisplay` stays pure/pref-unaware.
- **Row identity:** name **"Environment"**, the `.environment` category icon (`cloud.sun.fill`), headline = temperature range (· humidity) when present, else moon phase (· season), else the single remaining reading. EN DASH inside the temp range is produced by `WeatherValueFormatter` (unchanged).
- **Canonical subtype order:** `temperature, humidity, pressure, pressureDrop, moonPhase, season, mercuryRetrograde`. `pressureDrop` is folded into the Air pressure detail line (not its own row); `mercuryRetrograde` is a label-only presence line (no value).
- **Intermediate state:** Task 3 adds `TimelineItem.environmentSummary`, which makes the app's `switch item` (`TimelineView.swift:116`) non-exhaustive → the app target won't build until Task 4 adds the arm. Expected — Tasks 1/2 keep the app whole and gate independently; Task 3 gates on core `swift test`; the app is rebuilt at Task 4; nothing merges until all four land.
- **App-target tests `-parallel-testing-enabled NO`;** the lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing crash. **Simulator:** iPhone 17 Pro (iOS 26.5). New app files under `Views/HealthOS/Timeline/`. Ignore SourceKit "No such module"/"Cannot find type" diagnostics (stale-index noise); `swift test`/`xcodebuild` are authoritative.

---

### Task 1: Core — `EnvironmentDaySummary` + pure reducer

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentDaySummaryBuilderTests.swift`

**Interfaces:** Produces `EnvironmentDaySummary` (a `Sendable` value type with a deterministic `id`) and `EnvironmentDaySummaryBuilder.summaries(from:timeZone:)`. Task 3 calls the reducer inside `days()`; the app (Tasks 2/4) reads the summary. Does NOT touch `TimelineItem` yet (keeps the app compiling).

- [ ] **Step 1: Write the failing tests first** in `EnvironmentDaySummaryBuilderTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct EnvironmentDaySummaryBuilderTests {
    private let tz = TimeZone(identifier: "UTC")!
    private func env(_ subtype: String, _ day: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(day) * 86_400 + 43_200),
                    timezoneID: "UTC", category: .environment, subtype: subtype,
                    value: subtype == "pressure" ? 1013 : nil, unit: subtype == "pressure" ? "hPa" : nil,
                    source: .weatherAPI)
    }

    @Test func groupsOneDayIntoOneSummaryInCanonicalOrder() {
        let events = [env("moonPhase", 0), env("temperature", 0), env("humidity", 0)]  // shuffled
        let summaries = EnvironmentDaySummaryBuilder.summaries(from: events, timeZone: tz)
        #expect(summaries.count == 1)
        #expect(summaries[0].events.map { $0.subtype } == ["temperature", "humidity", "moonPhase"])  // canonical
        #expect(summaries[0].dayStart == Date(timeIntervalSince1970: 0))
    }
    @Test func idIsDeterministicPerDayAndDistinctAcrossDays() {
        let a = EnvironmentDaySummaryBuilder.summaries(from: [env("season", 5)], timeZone: tz)[0]
        let a2 = EnvironmentDaySummaryBuilder.summaries(from: [env("season", 5)], timeZone: tz)[0]
        let b = EnvironmentDaySummaryBuilder.summaries(from: [env("season", 6)], timeZone: tz)[0]
        #expect(a.id == a2.id && a.id != b.id)
    }
    @Test func ignoresNonEnvironmentAndEmptyWhenNone() {
        let symptom = HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200), timezoneID: "UTC",
                                  category: .symptom, subtype: "migraine", value: 5, source: .manual)
        #expect(EnvironmentDaySummaryBuilder.summaries(from: [symptom], timeZone: tz).isEmpty)
        #expect(EnvironmentDaySummaryBuilder.summaries(from: [], timeZone: tz).isEmpty)
        let mixed = EnvironmentDaySummaryBuilder.summaries(from: [symptom, env("temperature", 0)], timeZone: tz)
        #expect(mixed.count == 1 && mixed[0].events.count == 1)
    }
    @Test func multipleDaysSortNewestFirst() {
        let s = EnvironmentDaySummaryBuilder.summaries(from: [env("season", 1), env("season", 3)], timeZone: tz)
        #expect(s.map { $0.dayStart } == [Date(timeIntervalSince1970: 3 * 86_400), Date(timeIntervalSince1970: 86_400)])
    }
}
```

- [ ] **Step 2: Run to confirm failure.** `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -20` → FAIL (`EnvironmentDaySummary`/`EnvironmentDaySummaryBuilder` undefined).

- [ ] **Step 3: Implement** `EnvironmentDaySummary.swift`:

```swift
import Foundation

/// One day's auto-logged environment readings, aggregated for a single collapsed
/// Timeline row. A display-time aggregate — the raw `.environment` events stay the
/// source of truth in the graph. Read-only (never editable or deletable).
public struct EnvironmentDaySummary: Equatable, Sendable, Identifiable {
    public let dayStart: Date          // local start-of-day bucket
    public let timestamp: Date         // the shared per-day env timestamp (row sort key)
    public let events: [HealthEvent]   // the day's .environment events, canonical subtype order

    /// Deterministic across rebuilds of the same slice — drives SwiftUI row
    /// identity and the Timeline's expansion state.
    public var id: String { "env-\(Int(dayStart.timeIntervalSince1970))" }

    public init(dayStart: Date, timestamp: Date, events: [HealthEvent]) {
        self.dayStart = dayStart
        self.timestamp = timestamp
        self.events = events
    }
}

public enum EnvironmentDaySummaryBuilder {
    /// Canonical detail/display order. Unknown subtypes sort last (stable).
    public static let subtypeOrder = ["temperature", "humidity", "pressure",
                                      "pressureDrop", "moonPhase", "season", "mercuryRetrograde"]

    /// Folds `.environment` events into one summary per local calendar day, newest
    /// day first. Pure; accepts any unsorted slice; input order never affects the
    /// result. Non-environment events are ignored. (All env events for a day share
    /// one timestamp, so any event's timestamp is the day's row-sort key.)
    public static func summaries(from events: [HealthEvent], timeZone: TimeZone) -> [EnvironmentDaySummary] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let env = events.filter { $0.category == .environment }
        guard !env.isEmpty else { return [] }
        let byDay = Dictionary(grouping: env) { calendar.startOfDay(for: $0.timestamp) }
        return byDay.map { day, evs in
            let sorted = evs.sorted { (orderIndex($0), $0.id.uuidString) < (orderIndex($1), $1.id.uuidString) }
            return EnvironmentDaySummary(dayStart: day, timestamp: sorted.first?.timestamp ?? day, events: sorted)
        }.sorted { $0.dayStart > $1.dayStart }
    }

    private static func orderIndex(_ e: HealthEvent) -> Int {
        subtypeOrder.firstIndex(of: e.subtype ?? "") ?? subtypeOrder.count
    }
}
```

- [ ] **Step 4: Run the core suite.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → all green (the app target is untouched — no `TimelineItem` change yet). Report counts.

- [ ] **Step 5: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Timeline/EnvironmentDaySummary.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentDaySummaryBuilderTests.swift
git commit -m "feat(core): EnvironmentDaySummary + pure per-day reducer (canonical order, deterministic id)"
```

---

### Task 2: App — `EnvironmentSummaryFormatter` (pure text)

**Files:**
- Create: `Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift`
- Test: `Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift`

**Interfaces:** `EnvironmentSummaryFormatter.headline(_:unit:) -> String` and `.detailLines(_:unit:) -> [(label: String, value: String?)]`. Consumes `EnvironmentDaySummary` (Task 1) + `TemperatureUnit`/`WeatherValueFormatter` (existing). Task 4's row renders these. The app target still compiles (no `TimelineItem` change yet), so this task's app tests run.

- [ ] **Step 1: Write the failing tests first** in `EnvironmentSummaryFormatterTests.swift`. Build summaries from `HealthEvent` fixtures (temperature: `value`=high, `metadata`=`["low": String(low)]`, unit `°C`; humidity value+`%`; pressure value+`hPa`; pressureDrop value+`hPa`; moonPhase/season via `metadata` `["phase":…]`/`["season":…]`; mercuryRetrograde bare). Assert:
  - **Headline full day** (temp 12/24 + humidity 69) → `"12–24°C · 69%"` (celsius) and `"54–75°F · 69%"` (fahrenheit).
  - **Headline backfill** (moonPhase "Waxing gibbous" + season "Summer", no temp/humidity) → `"Waxing gibbous · Summer"`.
  - **Headline degenerate** (season only) → `"Season: Summer"`.
  - **detailLines full day** → labels in order `["Temperature","Humidity","Air pressure","Moon phase","Season","Mercury retrograde"]`; the Mercury row's value is `nil`; the Temperature value flips with `unit`.
  - **detailLines pressure+drop folded** → the "Air pressure" row value is `"1013 hPa · ↓7 hPa"` and there is NO separate "Pressure drop" row.

- [ ] **Step 2: Run to confirm failure.** App test build → FAIL (`EnvironmentSummaryFormatter` undefined).

- [ ] **Step 3: Implement** `EnvironmentSummaryFormatter.swift`:

```swift
import Foundation
import HealthGraphCore

/// Builds the collapsed headline and expanded detail lines for an Environment
/// summary row, honoring the user's °C/°F setting for temperature. Pure.
enum EnvironmentSummaryFormatter {
    /// Collapsed one-liner: temperature range (· humidity) when present; else moon
    /// phase (· season); else the single remaining reading.
    static func headline(_ summary: EnvironmentDaySummary, unit: TemperatureUnit) -> String {
        if let temp = value("temperature", summary, unit) {
            if let hum = value("humidity", summary, unit) { return "\(temp) · \(hum)" }
            return temp
        }
        if let moon = value("moonPhase", summary, unit) {
            if let season = value("season", summary, unit) { return "\(moon) · \(season)" }
            return moon
        }
        if let first = detailLines(summary, unit: unit).first {
            return first.value.map { "\(first.label): \($0)" } ?? first.label
        }
        return "Environment"
    }

    /// Ordered (label, value?) rows. `value == nil` → a presence line (mercury).
    /// pressureDrop is folded into the Air pressure line, not its own row.
    static func detailLines(_ summary: EnvironmentDaySummary, unit: TemperatureUnit) -> [(label: String, value: String?)] {
        var rows: [(label: String, value: String?)] = []
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
                rows.append((EventDisplay.title(for: e), v))
            default:
                rows.append((EventDisplay.title(for: e), value(subtype, summary, unit)))
            }
        }
        // Defensive: a lone pressureDrop with no pressure event still shows.
        if !summary.events.contains(where: { $0.subtype == "pressure" }),
           let drop = summary.events.first(where: { $0.subtype == "pressureDrop" }) {
            rows.append((EventDisplay.title(for: drop), EventDisplay.valueLine(for: drop)))
        }
        return rows
    }

    /// Display value for a subtype: temperature/humidity via the unit-aware
    /// WeatherValueFormatter, everything else via EventDisplay.
    private static func value(_ subtype: String, _ summary: EnvironmentDaySummary, _ unit: TemperatureUnit) -> String? {
        guard let e = summary.events.first(where: { $0.subtype == subtype }) else { return nil }
        return WeatherValueFormatter.line(for: e, unit: unit) ?? EventDisplay.valueLine(for: e)
    }
}
```

- [ ] **Step 4: Run app tests.** `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:"Food IntolerancesTests/EnvironmentSummaryFormatterTests" -parallel-testing-enabled NO 2>&1 | tail -30` → green.

- [ ] **Step 5: Commit.**

```bash
git add "Views/HealthOS/Timeline/EnvironmentSummaryFormatter.swift" \
        "Food IntolerancesTests/EnvironmentSummaryFormatterTests.swift"
git commit -m "feat(app): EnvironmentSummaryFormatter — headline + detail lines (unit-aware, pressureDrop folded)"
```

---

### Task 3: Core — `TimelineItem.environmentSummary` + grouping in `days()`

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift`

**Interfaces:** `TimelineItem` gains `.environmentSummary(EnvironmentDaySummary)` (its `id`/`sortDate`); `days(...)` gains `groupEnvironment: Bool = true`. Browse emits one `.environmentSummary` item per day (env events excluded from `.event` rows); search (`groupEnvironment: false`) leaves env raw. **This breaks the app build** (`TimelineView.swift:116` switch) — fixed in Task 4.

- [ ] **Step 1: Write the failing tests first** — add to `TimelineDayBuilderTests.swift`:

```swift
    @Test func environmentEventsCollapseIntoOneSummaryInBrowse() {
        let tz = TimeZone(identifier: "UTC")!
        func env(_ s: String) -> HealthEvent { HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200),
            timezoneID: "UTC", category: .environment, subtype: s, source: .weatherAPI) }
        let symptom = HealthEvent(timestamp: Date(timeIntervalSince1970: 40_000), timezoneID: "UTC",
                                  category: .symptom, subtype: "migraine", value: 5, source: .manual)
        let days = TimelineDayBuilder.days(from: [env("temperature"), env("humidity"), env("moonPhase"), symptom],
                                           timeZone: tz)
        let envItems = days[0].items.filter { if case .environmentSummary = $0 { true } else { false } }
        #expect(envItems.count == 1)                                   // one collapsed row
        #expect(days[0].events.map { $0.subtype } == ["migraine"])     // env excluded from raw .event rows
    }
    @Test func searchLeavesEnvironmentRaw() {
        let tz = TimeZone(identifier: "UTC")!
        func env(_ s: String) -> HealthEvent { HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200),
            timezoneID: "UTC", category: .environment, subtype: s, source: .weatherAPI) }
        let days = TimelineDayBuilder.days(from: [env("temperature"), env("humidity")], timeZone: tz,
                                           sessionizeSleep: false, groupEnvironment: false)
        #expect(days[0].items.allSatisfy { if case .event = $0 { true } else { false } })   // raw rows, no summary
        #expect(days[0].events.count == 2)
    }
```

- [ ] **Step 2: Run to confirm failure.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → FAIL (`.environmentSummary` undefined; `groupEnvironment:` unknown).

- [ ] **Step 3: Extend `TimelineItem`** in `TimelineDayBuilder.swift`:
  - Add case: `case environmentSummary(EnvironmentDaySummary)`.
  - `id` switch: add `case .environmentSummary(let s): s.id`.
  - `sortDate` switch: add `case .environmentSummary(let s): s.timestamp`.
  (The `events` accessor and the severity-points `compactMap` use `if case .event`, so they correctly exclude summaries — no change.)

- [ ] **Step 4: Add grouping to `days(...)`.** Add the parameter and the filter/reduce/bucket:

```swift
    public static func days(from events: [HealthEvent], timeZone: TimeZone,
                            sessionizeSleep: Bool = true,
                            groupEnvironment: Bool = true) -> [TimelineDay] {
        // ... calendar, isSessionizable, sessions unchanged ...
        let summaries = groupEnvironment
            ? EnvironmentDaySummaryBuilder.summaries(from: events, timeZone: timeZone)
            : []
        var rowEvents = sessionizeSleep ? events.filter { !isSessionizable($0) } : events
        if groupEnvironment { rowEvents = rowEvents.filter { $0.category != .environment } }
        // ... `kept` filter unchanged (operates on rowEvents) ...
        // ... bucket `kept` and `sessions` unchanged ...
        for summary in summaries {
            buckets[summary.dayStart, default: []].append(.environmentSummary(summary))
        }
        // ... sort + severityPoints + return unchanged ...
    }
```
  Also update the `days` doc comment to note `groupEnvironment` collapses `.environment` events into one `EnvironmentDaySummary` per day (browse), off in search.

- [ ] **Step 5: Fix the one exhaustive test switch.** In `TimelineDayBuilderTests.swift` around line 179 (`items.map { switch $0 { case .event…; case .sleepSession… } }`), add `case .environmentSummary: "env"` so the switch stays exhaustive.

- [ ] **Step 6: Run the core suite.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → all green. Report counts. (The app target is now broken — expected; Task 4 fixes it.)

- [ ] **Step 7: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift
git commit -m "feat(core): TimelineItem.environmentSummary + browse-only grouping in days()"
```

---

### Task 4: App — the row, the wiring, and read-only enforcement

**Files:**
- Create: `Views/HealthOS/Timeline/EnvironmentSummaryRow.swift`
- Create: `Views/HealthOS/Timeline/EnvironmentReadOnly.swift` (the testable read-only predicate)
- Modify: `Views/HealthOS/Timeline/TimelineView.swift` (switch arm + expand state + gated Delete swipe)
- Modify: `Views/HealthOS/Timeline/TimelineViewModel.swift` (`groupEnvironment: false` at the 2 search sites)
- Modify: `Views/HealthOS/Timeline/EventDetailView.swift` (hide Delete button for env)
- Test: `Food IntolerancesTests/EnvironmentReadOnlyTests.swift`

**Interfaces:** Consumes `EnvironmentDaySummary` (Task 1), `EnvironmentSummaryFormatter` (Task 2), and `TimelineItem.environmentSummary` (Task 3). Rebuilds the app (fixes the Task 3 break) and delivers the visible feature.

- [ ] **Step 1: Write the failing read-only test first** in `EnvironmentReadOnlyTests.swift`:

```swift
import Testing
import HealthGraphCore
@testable import Food_Intolerances

struct EnvironmentReadOnlyTests {
    private func event(_ cat: EventCategory, _ source: EventSource) -> HealthEvent {
        HealthEvent(timestamp: .init(timeIntervalSince1970: 0), timezoneID: "UTC",
                    category: cat, subtype: "x", value: 1, source: source)
    }
    @Test func environmentIsReadOnlyOthersAreNot() {
        #expect(event(.environment, .weatherAPI).isReadOnlyEnvironment)
        #expect(!event(.symptom, .manual).isReadOnlyEnvironment)
        #expect(!event(.sleep, .healthKit).isReadOnlyEnvironment)   // scoped to .environment only
    }
}
```
  (Use whatever the real `EventSource` cases are — `.weatherAPI`, `.manual`, and any HealthKit case; the point is only `.environment` is read-only.)

- [ ] **Step 2: Run to confirm failure.** App test build → FAIL (`isReadOnlyEnvironment` undefined).

- [ ] **Step 3: Add the predicate** `EnvironmentReadOnly.swift`:

```swift
import HealthGraphCore

extension HealthEvent {
    /// Auto-logged environment readings are immutable in the UI: no edit, no
    /// delete, anywhere they surface. Single source of truth for the swipe and
    /// the detail-sheet Delete gating.
    var isReadOnlyEnvironment: Bool { category == .environment }
}
```

- [ ] **Step 4: Build `EnvironmentSummaryRow.swift`** (mirror `SleepSessionRow`): stateless (`summary`, `isExpanded`, `onToggle`), `@AppStorage("hg.temperatureUnit") private var rawTempUnit = ""` resolved via `TemperatureUnit.resolved(from: rawTempUnit)`, `style = .style(for: .environment)`. Collapsed header = the same spine gutter + tick + `style.icon` + `Text("Environment")` + `Spacer` + right-aligned `Text(EnvironmentSummaryFormatter.headline(summary, unit: unit))` + a chevron when `isExpandable`. `isExpandable = EnvironmentSummaryFormatter.detailLines(summary, unit: unit).count >= 2`. `onToggle()` fires only when expandable. Expanded → a `VStack` of the detail lines (label left, value right; value-less lines show just the label), padded `.leading, 56` / `.trailing, 16` / `.bottom, 10` like `SleepSessionRow.breakdown`. Add the same accessibility treatment (`.accessibilityElement(children: .ignore)`, a label combining "Environment" + the headline, an expand/collapse hint, `.isButton` trait only when expandable).

- [ ] **Step 5: Wire into `TimelineView`.**
  - Add `@State private var expandedEnvironment: Set<String> = []` next to `expandedSessions`.
  - Add the switch arm after `.sleepSession`:

```swift
                        case .environmentSummary(let summary):
                            EnvironmentSummaryRow(summary: summary,
                                                  isExpanded: expandedEnvironment.contains(summary.id)) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if expandedEnvironment.contains(summary.id) { expandedEnvironment.remove(summary.id) }
                                    else { expandedEnvironment.insert(summary.id) }
                                }
                            }
                            .padding(.leading, 16)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            // no .swipeActions — environment is read-only
```
  - Gate the Delete swipe on the `.event` arm (env appears there only in search): wrap the destructive Delete `Button` in `if !event.isReadOnlyEnvironment { … }`. (Leave the `if event.source == .manual { Edit }` block as-is — env is never `.manual`, so an env row ends with an empty `.swipeActions` → no actions.)

- [ ] **Step 6: Keep env raw in search** — in `TimelineViewModel.swift`, add `groupEnvironment: false` to the two `days(...)` calls that already pass `sessionizeSleep: false` (the search-delete rebuild ~line 128 and `runSearch` ~line 229).

- [ ] **Step 7: Hide the detail-sheet Delete for env** — in `EventDetailView.swift`, wrap the `deleteButton` and its adjacent `deleteFailed` message in `if !displayEvent.isReadOnlyEnvironment { … }`. (Edit is already `.manual`-gated.)

- [ ] **Step 8: Build + regression.**
  - App build succeeds (this task re-fixes the `switch` break from Task 3).
  - `xcodebuild test … -only-testing:"Food IntolerancesTests" … -parallel-testing-enabled NO` → every suite green except the known `SwiftDataMigratorTests` crash (incl. `EnvironmentReadOnlyTests` + the Task 2 formatter tests).
  - Core still green: `cd HealthGraphCore && swift test 2>&1 | tail -3`.

- [ ] **Step 9: Commit.**

```bash
git add "Views/HealthOS/Timeline/EnvironmentSummaryRow.swift" \
        "Views/HealthOS/Timeline/EnvironmentReadOnly.swift" \
        "Views/HealthOS/Timeline/TimelineView.swift" \
        "Views/HealthOS/Timeline/TimelineViewModel.swift" \
        "Views/HealthOS/Timeline/EventDetailView.swift" \
        "Food IntolerancesTests/EnvironmentReadOnlyTests.swift"
git commit -m "feat(app): collapsed Environment Timeline row (expandable, swipe-free) + read-only env"
```

- [ ] **Step 10: Device / simulator check** (device preferred; this step is the human's gate). Timeline browse:
  - One **"Environment"** row per day; collapsed headline correct on a **live** day (`12–24°C · 69%`, flips with the °C/°F picker) and a **backfilled** day (`Waxing gibbous · Summer`).
  - Tap expands to the labeled list (Temperature / Humidity / Air pressure (· ↓N) / Moon phase / Season / Mercury retrograde) and collapses; **no swipe actions** on the row.
  - **Search** for a weather term → individual env rows appear again, and they have **no Delete swipe**; opening one shows the detail sheet with **no Delete button**.
  - Light + dark; XXL Dynamic Type.

---

## Definition of Done

- Each day shows ONE expandable **"Environment"** Timeline row (browse) instead of ~2–7 auto-logged rows; the collapsed headline leads with weather and falls back to moon·season; expanding shows the full labeled list; it is swipe-free.
- Environment data is **read-only** — no Delete swipe (browse row or search raw rows), no detail-sheet Delete, no Edit — enforced by a single `isReadOnlyEnvironment` predicate.
- Search stays granular (raw env rows). Core reducer + grouping unit-tested; the formatter + read-only predicate unit-tested; the app wired + device-verified.
- Ingestion, dedup, the evidence engine, sleep/other rows, and the units picker are unchanged.
