# Sleep-Session Summarization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse each night/nap's HealthKit sleep-stage segments into ONE expandable Timeline summary row (bed→wake range, asleep total, Deep/Core/REM/Awake breakdown), placed on the wake-up day — plus restyle the capture quick-log chips so they read as tappable.

**Architecture:** Display-time aggregation only (spec `docs/superpowers/specs/2026-07-15-sleep-sessions-design.md`, Approach A). A pure `SleepSessionBuilder` in HealthGraphCore folds raw `.sleep` duration events into `SleepSession` values; `TimelineDayBuilder` emits days of `TimelineItem` (event-or-session enum). Raw stage events stay in the DB untouched — no schema change, no migration, no ingestion change, no new writes. The app contributes SwiftUI only: an inline-expandable `SleepSessionRow`, `TimelineView`/`TimelineDayHeader` wiring, view-model rebuild fixes, and a shared `QuickLogChip`.

**Tech Stack:** Swift (language mode 5), SwiftUI (iOS 26 SDK), Swift Testing, existing HealthGraphCore stack. GRDB is untouched by this plan.

## Global Constraints

- Repo root: `/Users/leo/dev/FoodIntolerances` (repo moved off Desktop 2026-07-15 — older docs say `~/Desktop`; always use `~/dev`). App project: `Food Intolerances.xcodeproj` (note the space). Scheme: `Food Intolerances`. Deployment floor **iOS 26.0**.
- Work on branch **`sleep-sessions`** (created from `main` before Task 1; the SDD controller creates it).
- App build/test destination: iPhone 17 / iOS 26.5 simulator — `-destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF'`. If that id is stale, run `xcrun simctl list devices available | grep "iPhone 17"` and substitute the UUID.
- App test runs MUST pass `-parallel-testing-enabled NO`. Known pre-existing issue (documented in `SwiftDataMigratorTests.swift`): `migratesObjectsFromAvoidedCabinetAndProtocols` crashes the test process inside Apple's SwiftData teardown. Expected app-suite result: that ONE test crashes, everything else passes. Report per-test results, never a bare "TEST FAILED".
- App-target test module is `Food_Intolerances` (underscore). App tests live under `Food IntolerancesTests/` (folder has a space), `@testable import Food_Intolerances`. Package tests live under `HealthGraphCore/Tests/HealthGraphCoreTests/`, `@testable import HealthGraphCore`.
- Package tests: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test`. Suite entering this plan: **99 tests / 15 suites, all passing**. Swift Testing: plain `struct XTests {}` (no `@Suite`), `@Test func … async throws` only when the body awaits/throws, `#expect(...)`. Deterministic dates only (`Date(timeIntervalSince1970: …)`); never `Date()` in assertions.
- **Migrations are APPEND-ONLY and IMMUTABLE — and this plan adds NO migration and NO schema change.** If you find yourself editing anything under `HealthGraphCore/Sources/HealthGraphCore/Database/`, stop: that's outside this plan.
- **Sessions are display-time values.** Never persisted, never given a DB row, never editable/deletable/navigable. Raw `.sleep` events remain the source of truth; soft-delete/undo/edit semantics of raw events are unchanged.
- **Sessionize browse, never search.** `TimelineDayBuilder.days(…, sessionizeSleep:)` defaults `true`; ONLY `runSearch()` (and search-mode rebuilds) pass `false`. Search results are a filtered subset — sessionizing a subset would display wrong totals.
- **Only duration sleep events sessionize.** A `.sleep` event with `endTimestamp == nil` passes through as a raw row (the existing app test `familyFilterLimitsCategories` seeds exactly such events and must keep passing).
- **Sub-minute sleep segments count toward session totals** (the ≥60s row filter is display-only and must not starve the math).
- **No user-facing causal language.** Copy is descriptive ("Sleep · 7h 32m"), never advisory.
- **Design tokens are law:** every color from `HealthTheme` / `CategoryStyle`. No raw `Color`/`.white` in new views. Accessibility is a merge gate: Dynamic Type (semantic text styles), VoiceOver labels on every interactive element, tap targets ≥ 44pt, the stacked bar is decorative (`accessibilityHidden`) with the data carried by text lines.
- **Privacy:** never log health values, subtypes, names, or note text.
- New app files go under `Views/` (fileSystemSynchronizedGroups — auto-join the target, no pbxproj edits). New package files go under `HealthGraphCore/Sources/HealthGraphCore/`.
- Verification commands pipe through `| tail` for brevity. On ANY failure, rerun without `| tail`.
- Commit after every task with the message given in its final step.

## Frozen semantics (from the spec — do not re-derive)

| Rule | Value |
|---|---|
| Session split | a gap `>= 60 min` between a segment's start and the furthest `endTimestamp` seen so far starts a new session (join iff `gap < 3600s`; 59 min joins, 60 and 61 split). Recorded `awake` segments are data, not gaps — they extend the chain |
| Stage totals | per-subtype sums of `endTimestamp − timestamp` (NOT the stored `value`, which was Int-truncated at ingest). `asleepMinutes = core + deep + rem + unspecified`. `inBed` tracked separately, NEVER added to asleep |
| Nap | `asleepBasis < 180` AND start/end in the same local day AND start ≥ 06:00 AND end ≤ 21:00 (in the passed `timeZone`); else night. `asleepBasis` = `asleepMinutes`, or `inBedMinutes` when `asleepMinutes == 0` (inBed-only session) |
| Day bucket | session → `startOfDay(session.end)` (wake-up day); its within-day sort key is `end` |
| Row title | `"Sleep"` / `"Nap"` (`"In bed"` when `asleepMinutes == 0`) + `" · "` + `EventDisplay.durationString` of `asleepMinutes` (or `inBedMinutes` for inBed-only) — NOT the bed→wake span |
| Right side of row | bed→wake range `"11:24 PM – 7:03 AM"` (start–end, hour+minute) |
| Breakdown order | Deep · Core · REM · Asleep(unspecified) · Awake; stages `< 1 min` omitted; inBed-only sessions have no breakdown and are not expandable |
| Chip restyle | accent label, `HealthTheme.accent.opacity(0.12)` capsule fill, `accent.opacity(0.35)` hairline border, pressed-state dim, `minHeight: 44`, a11y labels preserved verbatim |

## File structure

| File | Change | Responsibility |
|---|---|---|
| `HealthGraphCore/Sources/HealthGraphCore/Timeline/SleepSessionBuilder.swift` | create | `SleepSession` value + pure gap-based session detection |
| `HealthGraphCore/Tests/HealthGraphCoreTests/SleepSessionBuilderTests.swift` | create | builder unit tests |
| `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift` | rewrite | `TimelineItem` enum, `TimelineDay.items`, sessionizing `days()` |
| `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift` | modify | re-fixture 2 tests off `.sleep`, add session-integration tests |
| `Views/HealthOS/Timeline/TimelineViewModel.swift` | modify | mode-aware rebuilds (`delete`), `sessionizeSleep: false` in search |
| `Food IntolerancesTests/TimelineViewModelTests.swift` | modify | add session browse/delete tests |
| `Views/HealthOS/Timeline/SleepSessionRow.swift` | create | collapsed/expanded session row (pure presentation) |
| `Views/HealthOS/Timeline/TimelineView.swift` | modify | `ForEach(day.items)` switch + expansion state |
| `Views/HealthOS/Timeline/TimelineDayHeader.swift` | modify | count `items` |
| `Views/HealthOS/Capture/QuickLogChip.swift` | create | shared accent-tinted chip |
| `Views/HealthOS/Capture/SymptomCaptureView.swift` | modify | use `QuickLogChip`, delete private `chip()` |
| `Views/HealthOS/Capture/MealCaptureView.swift` | modify | use `QuickLogChip` |
| `Views/HealthOS/Capture/DoseCaptureView.swift` | modify | use `QuickLogChip` |

Consumers that keep compiling **unchanged** via the `TimelineDay.events` computed accessor: `EventDetailView.swift:15` (`days.flatMap(\.events)` id lookup), `SeveritySparkline` (uses `severityPoints`/`dayStart` only), all existing `flatMap(\.events)` app-test assertions. Nothing outside `TimelineDayBuilder.swift` constructs a `TimelineDay` (verified by grep 2026-07-15).

---

### Task 1: `SleepSession` + `SleepSessionBuilder` (package, TDD)

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Timeline/SleepSessionBuilder.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/SleepSessionBuilderTests.swift`

**Interfaces:**
- Consumes: `HealthEvent` (existing — fields used: `category`, `subtype`, `timestamp`, `endTimestamp`, `id`).
- Produces (Task 2 and Task 4 rely on these exact names):
  - `public struct SleepSession: Equatable, Sendable, Identifiable` with `start`, `end: Date`; `kind: Kind` (`enum Kind { case night, nap }`); `coreMinutes`, `deepMinutes`, `remMinutes`, `unspecifiedMinutes`, `awakeMinutes`, `inBedMinutes: Double`; `segmentCount: Int`; computed `asleepMinutes: Double`; computed `id: String`.
  - `public enum SleepSessionBuilder` with `static func sessions(from events: [HealthEvent], timeZone: TimeZone) -> [SleepSession]` (returns ascending by `end`).

- [ ] **Step 1: Write the failing tests**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/SleepSessionBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import HealthGraphCore

struct SleepSessionBuilderTests {
    let utc = TimeZone(identifier: "UTC")!
    /// 2025-06-15 00:00:00 UTC — a fixed local midnight for offset math.
    let midnight = Date(timeIntervalSince1970: 1_749_945_600)

    /// A sleep-stage segment `startMin` minutes from `midnight` (negative = the
    /// evening before), lasting `durationMin` minutes.
    private func seg(_ subtype: String, startMin: Double, durationMin: Double) -> HealthEvent {
        let start = midnight.addingTimeInterval(startMin * 60)
        return HealthEvent(timestamp: start, endTimestamp: start.addingTimeInterval(durationMin * 60),
                           category: .sleep, subtype: subtype, value: durationMin, unit: "min",
                           source: .healthKit, createdAt: midnight)
    }

    @Test func nightAcrossMidnightIsOneSessionWithExactTotals() {
        // 22:00 core 90m, 23:30 deep 60m, 00:30 awake 15m, 00:45 rem 120m, 02:45 core 180m
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: -120, durationMin: 90),
            seg("asleepDeep", startMin: -30, durationMin: 60),
            seg("awake", startMin: 30, durationMin: 15),
            seg("asleepREM", startMin: 45, durationMin: 120),
            seg("asleepCore", startMin: 165, durationMin: 180),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        let s = sessions[0]
        #expect(s.start == midnight.addingTimeInterval(-120 * 60))
        #expect(s.end == midnight.addingTimeInterval(345 * 60))     // 05:45
        #expect(s.coreMinutes == 270)
        #expect(s.deepMinutes == 60)
        #expect(s.remMinutes == 120)
        #expect(s.awakeMinutes == 15)
        #expect(s.asleepMinutes == 450)
        #expect(s.inBedMinutes == 0)
        #expect(s.kind == .night)
        #expect(s.segmentCount == 5)
    }

    @Test func fiftyNineMinuteHoleKeepsOneSession() {
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 0, durationMin: 60),
            seg("asleepCore", startMin: 60 + 59, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].asleepMinutes == 120)
    }

    @Test func sixtyMinuteHoleSplits() {
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 0, durationMin: 60),
            seg("asleepCore", startMin: 60 + 60, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions.count == 2)
    }

    @Test func sixtyOneMinuteHoleSplits() {
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 0, durationMin: 60),
            seg("asleepCore", startMin: 60 + 61, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions.count == 2)
    }

    @Test func recordedAwakeSegmentNeverSplits() {
        // 45 recorded awake minutes mid-night: data, not a hole -> one session.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 0, durationMin: 60),
            seg("awake", startMin: 60, durationMin: 45),
            seg("asleepCore", startMin: 105, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].awakeMinutes == 45)
    }

    @Test func overlappingSegmentsChainByFurthestEnd() {
        // inBed spans 0-480; a core stage ends at 90. A segment starting at 500
        // is 20m after the FURTHEST end (480), not 410m after the last-seen end.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("inBed", startMin: 0, durationMin: 480),
            seg("asleepCore", startMin: 30, durationMin: 60),
            seg("asleepCore", startMin: 500, durationMin: 30),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].end == midnight.addingTimeInterval(530 * 60))
    }

    @Test func inBedOverlapExcludedFromAsleep() {
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("inBed", startMin: 0, durationMin: 480),
            seg("asleepCore", startMin: 0, durationMin: 240),
            seg("asleepREM", startMin: 240, durationMin: 240),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].asleepMinutes == 480)
        #expect(sessions[0].inBedMinutes == 480)
    }

    @Test func afternoonNapIsNap() {
        // 14:00-15:00, 60 asleep minutes, same local day, inside 06:00-21:00.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepUnspecified", startMin: 14 * 60, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].kind == .nap)
        #expect(sessions[0].unspecifiedMinutes == 60)
    }

    @Test func crashSleepAtOneAMIsNight() {
        // 01:00-03:00 = 120 min (< 180) but starts before 06:00 -> night.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 60, durationMin: 120),
        ], timeZone: utc)
        #expect(sessions[0].kind == .night)
    }

    @Test func longDaytimeSleepIsNight() {
        // 09:00-14:00 = 300 min (>= 180) -> night even in daytime.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 9 * 60, durationMin: 300),
        ], timeZone: utc)
        #expect(sessions[0].kind == .night)
    }

    @Test func eveningNapEndingAfterNinePMIsNight() {
        // 20:30-21:30 ends after 21:00 -> night.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 20 * 60 + 30, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions[0].kind == .night)
    }

    @Test func inBedOnlySessionClassifiesByInBedMinutes() {
        // Phone-only data: 50 inBed minutes at 13:00 -> nap-shaped, no asleep.
        let nap = SleepSessionBuilder.sessions(from: [
            seg("inBed", startMin: 13 * 60, durationMin: 50),
        ], timeZone: utc)
        #expect(nap[0].asleepMinutes == 0)
        #expect(nap[0].inBedMinutes == 50)
        #expect(nap[0].kind == .nap)
        // 8h overnight inBed -> night.
        let night = SleepSessionBuilder.sessions(from: [
            seg("inBed", startMin: -120, durationMin: 480),
        ], timeZone: utc)
        #expect(night[0].kind == .night)
    }

    @Test func subMinuteSegmentsCountTowardTotals() {
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 0, durationMin: 10),
            seg("awake", startMin: 10, durationMin: 0.5),
            seg("asleepCore", startMin: 10.5, durationMin: 10),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].asleepMinutes == 20)
        #expect(sessions[0].awakeMinutes == 0.5)
    }

    @Test func pointSleepEventsAndOtherCategoriesIgnored() {
        let point = HealthEvent(timestamp: midnight, category: .sleep, subtype: "item0",
                                source: .manual, createdAt: midnight)
        let food = HealthEvent(timestamp: midnight, endTimestamp: midnight.addingTimeInterval(600),
                               category: .food, subtype: "dinner", source: .manual, createdAt: midnight)
        #expect(SleepSessionBuilder.sessions(from: [point, food], timeZone: utc).isEmpty)
    }

    @Test func emptyAndSingleSegmentInputs() {
        #expect(SleepSessionBuilder.sessions(from: [], timeZone: utc).isEmpty)
        let one = SleepSessionBuilder.sessions(from: [seg("asleepCore", startMin: 0, durationMin: 90)],
                                               timeZone: utc)
        #expect(one.count == 1)
        #expect(one[0].segmentCount == 1)
    }

    @Test func sessionsSortAscendingByEndAndIdsAreDeterministic() {
        let input = [
            seg("asleepCore", startMin: 14 * 60, durationMin: 60),   // nap, later
            seg("asleepCore", startMin: -120, durationMin: 480),     // night, earlier
        ]
        let a = SleepSessionBuilder.sessions(from: input, timeZone: utc)
        let b = SleepSessionBuilder.sessions(from: input.reversed(), timeZone: utc)
        #expect(a.count == 2)
        #expect(a[0].end < a[1].end)
        #expect(a.map(\.id) == b.map(\.id))     // input order never changes identity
        #expect(a[0].id == "sleep-\(Int(a[0].start.timeIntervalSince1970))-\(Int(a[0].end.timeIntervalSince1970))")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'SleepSessionBuilder' in scope`.

- [ ] **Step 3: Write the implementation**

Create `HealthGraphCore/Sources/HealthGraphCore/Timeline/SleepSessionBuilder.swift`:

```swift
import Foundation

/// One night or nap: a display-time aggregation of contiguous raw `.sleep`
/// stage events. Sessions are never persisted — the raw segments stay the
/// source of truth in the graph (spec 2026-07-15, Approach A).
public struct SleepSession: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case night, nap }

    public let start: Date               // earliest segment start (bed time)
    public let end: Date                 // latest segment end (wake time)
    public let kind: Kind
    public let coreMinutes: Double
    public let deepMinutes: Double
    public let remMinutes: Double
    public let unspecifiedMinutes: Double
    public let awakeMinutes: Double
    public let inBedMinutes: Double
    public let segmentCount: Int

    /// Time actually asleep. `inBed` overlaps the stages and is never included.
    public var asleepMinutes: Double { coreMinutes + deepMinutes + remMinutes + unspecifiedMinutes }

    /// Deterministic across rebuilds of the same slice — drives SwiftUI row
    /// identity and the Timeline's expansion state.
    public var id: String { "sleep-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))" }

    public init(start: Date, end: Date, kind: Kind,
                coreMinutes: Double, deepMinutes: Double, remMinutes: Double,
                unspecifiedMinutes: Double, awakeMinutes: Double, inBedMinutes: Double,
                segmentCount: Int) {
        self.start = start; self.end = end; self.kind = kind
        self.coreMinutes = coreMinutes; self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes; self.unspecifiedMinutes = unspecifiedMinutes
        self.awakeMinutes = awakeMinutes; self.inBedMinutes = inBedMinutes
        self.segmentCount = segmentCount
    }
}

public enum SleepSessionBuilder {
    /// A hole in the sleep data of at least this long starts a new session.
    /// Recorded `awake` segments are data, not holes — they extend the chain.
    public static let sessionGap: TimeInterval = 3600

    /// Folds raw `.sleep` duration events into sessions, sorted ascending by
    /// `end`. Point `.sleep` events (no `endTimestamp`) are ignored here and
    /// pass through as raw rows in `TimelineDayBuilder`. Pure; accepts any
    /// unsorted slice; input order never affects the result.
    public static func sessions(from events: [HealthEvent], timeZone: TimeZone) -> [SleepSession] {
        let segments = events
            .filter { $0.category == .sleep && $0.endTimestamp != nil }
            .sorted { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }
        guard !segments.isEmpty else { return [] }

        var groups: [[HealthEvent]] = []
        var current = [segments[0]]
        var furthestEnd = segments[0].endTimestamp!
        for segment in segments.dropFirst() {
            if segment.timestamp.timeIntervalSince(furthestEnd) < sessionGap {
                current.append(segment)
                furthestEnd = max(furthestEnd, segment.endTimestamp!)
            } else {
                groups.append(current)
                current = [segment]
                furthestEnd = segment.endTimestamp!
            }
        }
        groups.append(current)
        return groups.map { session(from: $0, timeZone: timeZone) }.sorted { $0.end < $1.end }
    }

    private static func session(from segments: [HealthEvent], timeZone: TimeZone) -> SleepSession {
        var totals: [String: Double] = [:]
        var start = segments[0].timestamp
        var end = segments[0].endTimestamp!
        for segment in segments {
            let segmentEnd = segment.endTimestamp!
            start = min(start, segment.timestamp)
            end = max(end, segmentEnd)
            // Real interval, not the stored `value` (Int-truncated at ingest).
            totals[segment.subtype ?? "", default: 0] += segmentEnd.timeIntervalSince(segment.timestamp) / 60
        }
        let core = totals["asleepCore"] ?? 0
        let deep = totals["asleepDeep"] ?? 0
        let rem = totals["asleepREM"] ?? 0
        let unspecified = totals["asleepUnspecified"] ?? 0
        let inBed = totals["inBed"] ?? 0
        let asleep = core + deep + rem + unspecified
        return SleepSession(start: start, end: end,
                            kind: kind(start: start, end: end,
                                       asleepBasis: asleep > 0 ? asleep : inBed,
                                       timeZone: timeZone),
                            coreMinutes: core, deepMinutes: deep, remMinutes: rem,
                            unspecifiedMinutes: unspecified,
                            awakeMinutes: totals["awake"] ?? 0,
                            inBedMinutes: inBed,
                            segmentCount: segments.count)
    }

    /// Nap iff short (< 3 h), fully inside one local day, starting 06:00 or
    /// later and ending by 21:00. Everything else — including a 2 h
    /// crash-sleep at 1 AM — is a night (spec §4.4).
    private static func kind(start: Date, end: Date, asleepBasis: Double,
                             timeZone: TimeZone) -> SleepSession.Kind {
        guard asleepBasis < 180 else { return .night }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard calendar.isDate(start, inSameDayAs: end) else { return .night }
        let s = calendar.dateComponents([.hour, .minute], from: start)
        let e = calendar.dateComponents([.hour, .minute], from: end)
        let startMinutes = (s.hour ?? 0) * 60 + (s.minute ?? 0)
        let endMinutes = (e.hour ?? 0) * 60 + (e.minute ?? 0)
        return startMinutes >= 6 * 60 && endMinutes <= 21 * 60 ? .nap : .night
    }
}
```

- [ ] **Step 4: Run the new suite, then the full package suite**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test --filter SleepSessionBuilderTests 2>&1 | tail -5`
Expected: 16 tests pass.
Run: `swift test 2>&1 | tail -5`
Expected: 115 tests pass (99 entering + 16 new), 16 suites, zero warnings.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/dev/FoodIntolerances
git add HealthGraphCore/Sources/HealthGraphCore/Timeline/SleepSessionBuilder.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/SleepSessionBuilderTests.swift
git commit -m "feat(core): SleepSessionBuilder — gap-based night/nap detection with exact stage totals"
```

---

### Task 2: `TimelineItem` + sessionizing `TimelineDayBuilder` (package, TDD)

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift` (full rewrite below)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift`

**Interfaces:**
- Consumes: `SleepSessionBuilder.sessions(from:timeZone:)`, `SleepSession` (Task 1).
- Produces (Tasks 3–4 rely on these exact names):
  - `public enum TimelineItem: Identifiable, Equatable, Sendable` — `case event(HealthEvent)`, `case sleepSession(SleepSession)`; `var id: String`; `var sortDate: Date`.
  - `TimelineDay` — `items: [TimelineItem]` (stored), `events: [HealthEvent]` (computed: `.event` payloads only), `severityPoints`, `dayStart` unchanged. Init becomes `init(dayStart:items:severityPoints:)`.
  - `TimelineDayBuilder.days(from:timeZone:sessionizeSleep: Bool = true) -> [TimelineDay]`.

- [ ] **Step 1: Update two existing tests off `.sleep` fixtures and add the failing session tests**

In `TimelineDayBuilderTests.swift`, the two duration-filter tests currently use `.sleep` fixtures, which now sessionize; their intent is the *generic* duration-row filter, so re-fixture to `.exercise`. Replace `dropsSubMinuteDurationMicroSegments` and `keepsExactlySixtySecondDuration` with:

```swift
    @Test func dropsSubMinuteDurationMicroSegments() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let micro = HealthEvent(timestamp: base, endTimestamp: base.addingTimeInterval(20),
                                category: .exercise, subtype: "walking", value: 0, unit: "min",
                                source: .healthKit, createdAt: base)
        let real = HealthEvent(timestamp: base.addingTimeInterval(100), endTimestamp: base.addingTimeInterval(100 + 600),
                               category: .exercise, subtype: "running", value: 10, unit: "min",
                               source: .healthKit, createdAt: base)
        let days = TimelineDayBuilder.days(from: [real, micro], timeZone: TimeZone(identifier: "UTC")!)
        #expect(days.flatMap(\.events).map(\.subtype) == ["running"])   // micro dropped
    }

    @Test func keepsExactlySixtySecondDuration() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let sixty = HealthEvent(timestamp: base, endTimestamp: base.addingTimeInterval(60),
                                category: .exercise, subtype: "walking", value: 1, unit: "min",
                                source: .healthKit, createdAt: base)
        let days = TimelineDayBuilder.days(from: [sixty], timeZone: TimeZone(identifier: "UTC")!)
        #expect(days.flatMap(\.events).count == 1)
    }
```

Then append these new tests inside the same struct (they use the existing `tz` / `lateNight` / `nextMorning` fixtures):

```swift
    /// A cross-midnight night collapses to ONE session item on the WAKE-UP day.
    @Test func sleepCollapsesIntoWakeDaySession() {
        // 22:00 EDT core (60m) + 23:00 EDT rem (420m, ends 06:00 EDT July 5).
        let core = HealthEvent(timestamp: lateNight, endTimestamp: lateNight.addingTimeInterval(3600),
                               category: .sleep, subtype: "asleepCore", value: 60, unit: "min",
                               source: .healthKit, createdAt: lateNight)
        let rem = HealthEvent(timestamp: lateNight.addingTimeInterval(3600), endTimestamp: nextMorning,
                              category: .sleep, subtype: "asleepREM", value: 420, unit: "min",
                              source: .healthKit, createdAt: lateNight)
        let dinner = HealthEvent(timestamp: lateNight, category: .food, subtype: "dinner",
                                 source: .manual, createdAt: lateNight)
        let days = TimelineDayBuilder.days(from: [rem, core, dinner], timeZone: tz)
        #expect(days.count == 2)
        // Newest day (July 5) holds ONLY the session; no raw sleep rows anywhere.
        #expect(days[0].items.count == 1)
        guard case .sleepSession(let s) = days[0].items[0] else {
            Issue.record("expected a sleepSession item"); return
        }
        #expect(s.asleepMinutes == 480)
        #expect(s.end == nextMorning)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        #expect(days[0].dayStart == cal.startOfDay(for: nextMorning))
        // Older day (July 4) holds the dinner only.
        #expect(days[1].events.map(\.subtype) == ["dinner"])
        #expect(days.flatMap(\.events).allSatisfy { $0.category != .sleep })
    }

    /// Search mode keeps raw stage rows (a filtered subset must not sessionize).
    @Test func searchModeKeepsRawSleepRows() {
        let core = HealthEvent(timestamp: lateNight, endTimestamp: lateNight.addingTimeInterval(3600),
                               category: .sleep, subtype: "asleepCore", value: 60, unit: "min",
                               source: .healthKit, createdAt: lateNight)
        let rem = HealthEvent(timestamp: lateNight.addingTimeInterval(3600), endTimestamp: nextMorning,
                              category: .sleep, subtype: "asleepREM", value: 420, unit: "min",
                              source: .healthKit, createdAt: lateNight)
        let days = TimelineDayBuilder.days(from: [rem, core], timeZone: tz, sessionizeSleep: false)
        // Both group by START day (July 4), as raw rows.
        #expect(days.count == 1)
        #expect(days[0].events.count == 2)
        #expect(days[0].items.allSatisfy { if case .event = $0 { true } else { false } })
    }

    /// A session sorts within its day by wake time, between neighboring events.
    @Test func sessionRowInterleavesByWakeTime() {
        let sleep = HealthEvent(timestamp: nextMorning.addingTimeInterval(-7 * 3600),
                                endTimestamp: nextMorning,   // 23:00 -> 06:00
                                category: .sleep, subtype: "asleepCore", value: 420, unit: "min",
                                source: .healthKit, createdAt: nextMorning)
        let earlier = HealthEvent(timestamp: nextMorning.addingTimeInterval(-600),  // 05:50
                                  category: .symptom, subtype: "headache", value: 4, unit: "severity",
                                  source: .manual, createdAt: nextMorning)
        let later = HealthEvent(timestamp: nextMorning.addingTimeInterval(600),     // 06:10
                                category: .food, subtype: "coffee", source: .manual, createdAt: nextMorning)
        let days = TimelineDayBuilder.days(from: [later, earlier, sleep], timeZone: tz)
        #expect(days.count == 1)
        let kinds = days[0].items.map { item -> String in
            switch item {
            case .event(let e): e.subtype ?? ""
            case .sleepSession: "session"
            }
        }
        #expect(kinds == ["coffee", "session", "headache"])   // 06:10 > 06:00 > 05:50
    }

    /// Defensive: a point .sleep event (no endTimestamp) stays a raw row.
    @Test func pointSleepEventsPassThroughAsRawRows() {
        let point = HealthEvent(timestamp: nextMorning, category: .sleep, subtype: "item0",
                                source: .healthKit, createdAt: nextMorning)
        let days = TimelineDayBuilder.days(from: [point], timeZone: tz)
        #expect(days.count == 1)
        #expect(days[0].events.map(\.id) == [point.id])
    }
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test --filter TimelineDayBuilderTests 2>&1 | tail -5`
Expected: compile FAILURE — `TimelineDay` has no member `items`, no `sessionizeSleep:` parameter.

- [ ] **Step 3: Rewrite `TimelineDayBuilder.swift`**

Replace the entire file `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift` with:

```swift
import Foundation

public struct SeverityPoint: Equatable, Sendable {
    public let time: Date
    public let value: Double
    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

/// One visible Timeline row: a raw event or an aggregated sleep session.
public enum TimelineItem: Identifiable, Equatable, Sendable {
    case event(HealthEvent)
    case sleepSession(SleepSession)

    public var id: String {
        switch self {
        case .event(let e): e.id.uuidString
        case .sleepSession(let s): s.id
        }
    }

    /// Where the row sorts within its day: events by start, sessions by wake.
    public var sortDate: Date {
        switch self {
        case .event(let e): e.timestamp
        case .sleepSession(let s): s.end
        }
    }
}

public struct TimelineDay: Identifiable, Equatable, Sendable {
    public let dayStart: Date
    public let items: [TimelineItem]
    public let severityPoints: [SeverityPoint]
    public var id: Date { dayStart }

    /// The raw events among `items` (sessions excluded) — the accessor most
    /// existing consumers (detail lookup by id, tests) still want.
    public var events: [HealthEvent] {
        items.compactMap { if case .event(let e) = $0 { e } else { nil } }
    }

    public init(dayStart: Date, items: [TimelineItem], severityPoints: [SeverityPoint]) {
        self.dayStart = dayStart
        self.items = items
        self.severityPoints = severityPoints
    }
}

public enum TimelineDayBuilder {
    /// Groups a slice of events into local-calendar days, newest day first.
    ///
    /// With `sessionizeSleep` (browse mode, the default) `.sleep` DURATION
    /// events leave the row stream and come back as ONE `SleepSession` item
    /// bucketed under the wake-up day (`startOfDay(session.end)`) — so a
    /// session row can live in a different day bucket than some of its
    /// segments started in. Point `.sleep` events pass through as raw rows.
    /// Search passes `false`: results are a filtered subset, and sessionizing
    /// a subset would display wrong totals.
    public static func days(from events: [HealthEvent], timeZone: TimeZone,
                            sessionizeSleep: Bool = true) -> [TimelineDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        // Sleep duration events feed the session builder INCLUDING sub-minute
        // fragments — totals must be exact even though such rows never render.
        let isSessionizable: (HealthEvent) -> Bool = { $0.category == .sleep && $0.endTimestamp != nil }
        let sessions = sessionizeSleep
            ? SleepSessionBuilder.sessions(from: events.filter(isSessionizable), timeZone: timeZone)
            : []
        let rowEvents = sessionizeSleep ? events.filter { !isSessionizable($0) } : events

        // HealthKit emits sub-30-second stages that would otherwise render as
        // cluttering "0m" rows; drop those while keeping all point-in-time events.
        let kept = rowEvents.filter { e in
            guard let end = e.endTimestamp else { return true }        // point events kept
            return end.timeIntervalSince(e.timestamp) >= 60            // duration >= 1 min
        }

        var buckets: [Date: [TimelineItem]] = [:]
        for event in kept {
            buckets[calendar.startOfDay(for: event.timestamp), default: []].append(.event(event))
        }
        for session in sessions {
            buckets[calendar.startOfDay(for: session.end), default: []].append(.sleepSession(session))
        }

        return buckets.keys.sorted(by: >).map { day in
            let items = buckets[day]!.sorted { ($0.sortDate, $0.id) > ($1.sortDate, $1.id) }
            let points = items
                .compactMap { item -> SeverityPoint? in
                    guard case .event(let e) = item, e.category == .symptom, let v = e.value else { return nil }
                    return SeverityPoint(time: e.timestamp, value: v)
                }
                .sorted { $0.time < $1.time }
            return TimelineDay(dayStart: day, items: items, severityPoints: points)
        }
    }
}
```

Note the day ordering now comes from sorting bucket keys descending (the old first-seen `order` array can't work — session buckets are keyed by wake day, not first-seen input order). Behavior for callers is identical: newest day first.

- [ ] **Step 4: Run the full package suite**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: 119 tests pass (115 + 4 new; the 2 re-fixtured tests replace themselves), 16 suites, zero warnings.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/dev/FoodIntolerances
git add HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift
git commit -m "feat(core): TimelineItem enum + wake-day sleep sessionization in TimelineDayBuilder"
```

---

### Task 3: Session-aware `TimelineViewModel` rebuilds (app, TDD)

**Files:**
- Modify: `Views/HealthOS/Timeline/TimelineViewModel.swift` (two changes: `delete()` rebuild, `runSearch()` flag)
- Test: `Food IntolerancesTests/TimelineViewModelTests.swift`

**Interfaces:**
- Consumes: `TimelineDayBuilder.days(from:timeZone:sessionizeSleep:)`, `TimelineItem`, `SleepSession` (Tasks 1–2).
- Produces: no new API — behavior only. `TimelineView` (Task 4) relies on `viewModel.days[*].items` containing `.sleepSession` items in browse mode and only `.event` items in search mode.

Everything else in the view model keeps compiling untouched: `loadPage()`, `undoDelete()`, and `searchTextChanged()`'s empty branch already call `TimelineDayBuilder.days(from:timeZone:)`, which now sessionizes by default — which is exactly what browse mode wants.

- [ ] **Step 1: Add the failing app tests**

Append inside `struct TimelineViewModelTests` in `Food IntolerancesTests/TimelineViewModelTests.swift`:

```swift
    private func seedNight(_ store: GRDBEventStore, endingAt wake: Date) async throws {
        // Two contiguous stage segments ending at `wake`: core 4h then rem 4h.
        let core = HealthEvent(timestamp: wake.addingTimeInterval(-8 * 3600),
                               endTimestamp: wake.addingTimeInterval(-4 * 3600),
                               category: .sleep, subtype: "asleepCore", value: 240, unit: "min",
                               source: .healthKit, createdAt: wake)
        let rem = HealthEvent(timestamp: wake.addingTimeInterval(-4 * 3600), endTimestamp: wake,
                              category: .sleep, subtype: "asleepREM", value: 240, unit: "min",
                              source: .healthKit, createdAt: wake)
        try await store.save([core, rem])
    }

    @Test func browseCollapsesSleepIntoOneSessionItem() async throws {
        let (_, store) = try makeStore()
        let wake = Date(timeIntervalSince1970: 1_750_000_000)
        try await seedNight(store, endingAt: wake)
        try await store.save(HealthEvent(timestamp: wake.addingTimeInterval(600),
                                         category: .food, subtype: "coffee",
                                         source: .manual, createdAt: wake))
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        await vm.loadInitial()
        let sessions = vm.days.flatMap(\.items).compactMap { item -> SleepSession? in
            if case .sleepSession(let s) = item { s } else { nil }
        }
        #expect(sessions.count == 1)
        #expect(sessions[0].asleepMinutes == 480)
        #expect(vm.days.flatMap(\.events).allSatisfy { $0.category != .sleep })
    }

    @Test func deletingEventOnSessionDayKeepsTheSession() async throws {
        let (_, store) = try makeStore()
        let wake = Date(timeIntervalSince1970: 1_750_000_000)
        try await seedNight(store, endingAt: wake)
        let coffee = HealthEvent(timestamp: wake.addingTimeInterval(600),
                                 category: .food, subtype: "coffee",
                                 source: .manual, createdAt: wake)
        try await store.save(coffee)
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        await vm.loadInitial()
        await vm.delete(coffee)
        // The raw event is gone; the session row survives the rebuild.
        #expect(vm.days.flatMap(\.events).isEmpty)
        let sessions = vm.days.flatMap(\.items).compactMap { item -> SleepSession? in
            if case .sleepSession(let s) = item { s } else { nil }
        }
        #expect(sessions.count == 1)
        await vm.undoDelete()
        #expect(vm.days.flatMap(\.events).map(\.subtype) == ["coffee"])
        #expect(vm.days.flatMap(\.items).count == 2)   // session + coffee
    }
```

- [ ] **Step 2: Build the tests to verify current behavior fails**

Run the two tests:

```bash
cd /Users/leo/dev/FoodIntolerances
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' \
  -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/TimelineViewModelTests" 2>&1 | tail -20
```

Expected: `browseCollapsesSleepIntoOneSessionItem` PASSES already (Task 2's default covers the browse path — this test pins it at the view-model level), `deletingEventOnSessionDayKeepsTheSession` FAILS deterministically at `#expect(sessions.count == 1)`: the old surgical rebuild sees `day.events == [coffee]` (the computed accessor excludes the session), `remaining` is empty, so it drops the whole day — session included.

- [ ] **Step 3: Apply the two view-model changes**

In `Views/HealthOS/Timeline/TimelineViewModel.swift`, replace the body of `delete(_:)`'s day-rebuild block. Current code (lines ~119–126):

```swift
        let wasInBrowseSlice = browseEvents.contains { $0.id == event.id }
        browseEvents.removeAll { $0.id == event.id }
        days = days.compactMap { day in
            guard day.events.contains(where: { $0.id == event.id }) else { return day }
            let remaining = day.events.filter { $0.id != event.id }
            guard !remaining.isEmpty else { return nil }
            return TimelineDayBuilder.days(from: remaining, timeZone: timeZone).first
        }
```

becomes:

```swift
        let wasInBrowseSlice = browseEvents.contains { $0.id == event.id }
        browseEvents.removeAll { $0.id == event.id }
        if isSearchActive {
            // Search days hold raw rows only (sessionizeSleep: false), so a
            // surgical per-day rebuild is still valid here.
            days = days.compactMap { day in
                guard day.events.contains(where: { $0.id == event.id }) else { return day }
                let remaining = day.events.filter { $0.id != event.id }
                guard !remaining.isEmpty else { return nil }
                return TimelineDayBuilder.days(from: remaining, timeZone: timeZone,
                                               sessionizeSleep: false).first
            }
        } else {
            // Browse days contain sleep sessions whose segments can span day
            // buckets — rebuild from the full remaining slice instead.
            days = TimelineDayBuilder.days(from: browseEvents, timeZone: timeZone)
        }
```

In `runSearch()`, the grouping line

```swift
            days = TimelineDayBuilder.days(from: results, timeZone: timeZone)
```

becomes:

```swift
            days = TimelineDayBuilder.days(from: results, timeZone: timeZone, sessionizeSleep: false)
```

No other lines change.

- [ ] **Step 4: Run the app suite**

```bash
cd /Users/leo/dev/FoodIntolerances
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' \
  -parallel-testing-enabled NO 2>&1 | tail -30
```

Expected: all `TimelineViewModelTests` pass including the two new ones; the documented app-suite pattern (only the known `SwiftDataMigratorTests` teardown crash). `familyFilterLimitsCategories` must still pass — it seeds POINT sleep events, which pass through as raw rows.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/dev/FoodIntolerances
git add Views/HealthOS/Timeline/TimelineViewModel.swift "Food IntolerancesTests/TimelineViewModelTests.swift"
git commit -m "feat(app): session-aware Timeline rebuilds — sessionize browse, raw search, slice-wide delete rebuild"
```

---

### Task 4: `SleepSessionRow` + Timeline wiring (app)

**Files:**
- Create: `Views/HealthOS/Timeline/SleepSessionRow.swift`
- Modify: `Views/HealthOS/Timeline/TimelineView.swift` (feed `ForEach`, expansion state)
- Modify: `Views/HealthOS/Timeline/TimelineDayHeader.swift` (count `items`)

**Interfaces:**
- Consumes: `TimelineItem`, `SleepSession`, `EventDisplay.durationString`, `CategoryStyle.style(for: .sleep)`, `HealthTheme` tokens.
- Produces: `SleepSessionRow(session:isExpanded:onToggle:)` — presentation only, no store access, no navigation.

- [ ] **Step 1: Create `Views/HealthOS/Timeline/SleepSessionRow.swift`**

```swift
import SwiftUI
import HealthGraphCore

/// One expandable night/nap row. Collapsed: "Sleep · 7h 32m" + bed→wake range.
/// Expanded: stacked stage-proportion bar + per-stage duration lines.
/// Sessions are display-time aggregates — never navigable, editable, or deletable.
struct SleepSessionRow: View {
    let session: SleepSession
    let isExpanded: Bool
    let onToggle: () -> Void

    private var style: CategoryStyle { .style(for: .sleep) }

    /// inBed-only sessions (phone-only data) have no stage breakdown.
    private var kindLabel: String {
        session.asleepMinutes > 0 ? (session.kind == .nap ? "Nap" : "Sleep") : "In bed"
    }
    private var displayMinutes: Double {
        session.asleepMinutes > 0 ? session.asleepMinutes : session.inBedMinutes
    }
    private var rangeText: String {
        "\(session.start.formatted(.dateTime.hour().minute())) – \(session.end.formatted(.dateTime.hour().minute()))"
    }

    /// Breakdown rows, spec order, stages under a minute omitted. The colors
    /// are an opacity ramp of the sleep family color; Awake is neutral.
    private var stages: [(label: String, minutes: Double, color: Color)] {
        [("Deep", session.deepMinutes, style.color),
         ("Core", session.coreMinutes, style.color.opacity(0.7)),
         ("REM", session.remMinutes, style.color.opacity(0.45)),
         ("Asleep", session.unspecifiedMinutes, style.color.opacity(0.55)),
         ("Awake", session.awakeMinutes, HealthTheme.inkMuted.opacity(0.5))]
            .filter { $0.minutes >= 1 }
    }
    private var isExpandable: Bool { !stages.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpandable { onToggle() }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    // day spine gutter + duration tick (same anatomy as TimelineEventRow)
                    ZStack {
                        Rectangle()
                            .fill(HealthTheme.cardBorder)
                            .frame(width: 1)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(style.color)
                            .frame(width: 3, height: 28)
                    }
                    .frame(width: 20)
                    Image(systemName: style.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(style.color)
                        .frame(width: 24)
                    Text("\(kindLabel) · \(EventDisplay.durationString(minutes: displayMinutes))")
                        .font(.body)
                        .foregroundStyle(HealthTheme.ink)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(rangeText)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkMuted)
                    if isExpandable {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HealthTheme.inkMuted)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(.trailing, 16)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(kindLabel), \(EventDisplay.durationString(minutes: displayMinutes)), \(rangeText)")
            .accessibilityHint(isExpandable
                               ? (isExpanded ? "Collapses stage breakdown" : "Expands stage breakdown")
                               : "")
            .accessibilityAddTraits(.isButton)

            if isExpanded && isExpandable {
                breakdown
                    .padding(.leading, 56)   // aligns under the title column
                    .padding(.trailing, 16)
                    .padding(.bottom, 10)
            }
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            stackedBar
                .frame(height: 6)
                .clipShape(Capsule())
                .accessibilityHidden(true)   // decorative — the lines carry the data
            ForEach(stages, id: \.label) { stage in
                HStack(spacing: 8) {
                    Circle().fill(stage.color).frame(width: 8, height: 8)
                    Text(stage.label)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkSecondary)
                    Spacer()
                    Text(EventDisplay.durationString(minutes: stage.minutes))
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            let total = stages.reduce(0) { $0 + $1.minutes }
            HStack(spacing: 0) {
                ForEach(stages, id: \.label) { stage in
                    Rectangle()
                        .fill(stage.color)
                        .frame(width: total > 0 ? geo.size.width * stage.minutes / total : 0)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Wire `TimelineView`**

In `Views/HealthOS/Timeline/TimelineView.swift`:

Add the expansion state below the existing `@State` properties (after `@State private var path = NavigationPath()`):

```swift
    @State private var expandedSessions: Set<String> = []
```

Replace the feed's inner `ForEach` (currently):

```swift
                    ForEach(day.events) { event in
                        TimelineEventRow(event: event) { tapped in
                            path.append(tapped)
                        }
                        .padding(.leading, 16)
                    }
```

with:

```swift
                    ForEach(day.items) { item in
                        switch item {
                        case .event(let event):
                            TimelineEventRow(event: event) { tapped in
                                path.append(tapped)
                            }
                            .padding(.leading, 16)
                        case .sleepSession(let session):
                            SleepSessionRow(session: session,
                                            isExpanded: expandedSessions.contains(session.id)) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if expandedSessions.contains(session.id) {
                                        expandedSessions.remove(session.id)
                                    } else {
                                        expandedSessions.insert(session.id)
                                    }
                                }
                            }
                            .padding(.leading, 16)
                        }
                    }
```

- [ ] **Step 3: Update `TimelineDayHeader`**

In `Views/HealthOS/Timeline/TimelineDayHeader.swift`, the count badge (currently `day.events.count` twice) becomes `day.items.count`, and since a session row aggregates many events the a11y noun changes to "entries":

```swift
            Text("\(day.items.count)")
                .font(.caption)
                .foregroundStyle(HealthTheme.inkMuted)
                .accessibilityLabel("\(day.items.count) entries")
```

- [ ] **Step 4: Build and run the app suite**

```bash
cd /Users/leo/dev/FoodIntolerances
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`, zero warnings in the new/modified files.

```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' \
  -parallel-testing-enabled NO 2>&1 | tail -30
```

Expected: documented app-suite pattern (only the known `SwiftDataMigratorTests` teardown crash).

- [ ] **Step 5: Token/a11y self-check**

Run: `grep -n "Color(\|\.white\|\.black\|\.gray\|\.red\|\.blue" Views/HealthOS/Timeline/SleepSessionRow.swift`
Expected: no matches (every color goes through `HealthTheme`/`CategoryStyle`; `.black.opacity` appears only in the theme's own `hgCard`, not here).

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/dev/FoodIntolerances
git add Views/HealthOS/Timeline/SleepSessionRow.swift Views/HealthOS/Timeline/TimelineView.swift \
        Views/HealthOS/Timeline/TimelineDayHeader.swift
git commit -m "feat(app): inline-expandable SleepSessionRow — wake-day night/nap summary in the Timeline"
```

---

### Task 5: `QuickLogChip` — shared accent-tinted capture chip (app)

**Files:**
- Create: `Views/HealthOS/Capture/QuickLogChip.swift`
- Modify: `Views/HealthOS/Capture/SymptomCaptureView.swift` (use it; delete private `chip()`)
- Modify: `Views/HealthOS/Capture/MealCaptureView.swift` (use it)
- Modify: `Views/HealthOS/Capture/DoseCaptureView.swift` (use it)

**Interfaces:**
- Produces: `QuickLogChip(label:accessibilityLabel:action:)` — `accessibilityLabel` defaults to `label`.
- Behavior, chip ranking, and callbacks are UNCHANGED — this is a pure restyle + de-duplication. The three capture views currently carry three verbatim copies of the neutral capsule styling.

- [ ] **Step 1: Create `Views/HealthOS/Capture/QuickLogChip.swift`**

```swift
import SwiftUI

/// Quick-log chip. 1C on-device checkpoint: the neutral capsules read as
/// static tags, not buttons — so chips are accent-tinted (the same visual
/// language as the Log button, quieter) with a pressed-state dim.
struct QuickLogChip: View {
    let label: String
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(HealthTheme.accent.opacity(0.12)))
                .overlay(Capsule().strokeBorder(HealthTheme.accent.opacity(0.35), lineWidth: 1))
                .foregroundStyle(HealthTheme.accent)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(QuickLogChipPressStyle())
        .accessibilityLabel(accessibilityLabel ?? label)
    }
}

private struct QuickLogChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}
```

- [ ] **Step 2: Use it in `SymptomCaptureView.swift`**

Replace the `chipRow` body's chip call (line ~73):

```swift
                    chip(HealthGraphCore.SymptomCatalog.displayName(for: key)) { model.pendingKey = key }
```

with:

```swift
                    QuickLogChip(label: HealthGraphCore.SymptomCatalog.displayName(for: key)) {
                        model.pendingKey = key
                    }
```

and DELETE the whole private helper (lines ~155–165):

```swift
    private func chip(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.footnote)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(HealthTheme.card))
                .overlay(Capsule().strokeBorder(HealthTheme.cardBorder, lineWidth: 1))
                .foregroundStyle(HealthTheme.inkSecondary)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
```

- [ ] **Step 3: Use it in `MealCaptureView.swift`**

Replace the chip `Button` block inside the `ForEach(model.chips, …)` (lines ~38–48):

```swift
                                Button {            // chip tap logs immediately
                                    Task { if let e = await model.log(name: food, at: timestamp) { onLogged(e) } }
                                } label: {
                                    Text(food).font(.footnote)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(HealthTheme.card))
                                        .overlay(Capsule().strokeBorder(HealthTheme.cardBorder, lineWidth: 1))
                                        .foregroundStyle(HealthTheme.inkSecondary)
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .accessibilityLabel("Log \(food)")
```

with:

```swift
                                QuickLogChip(label: food, accessibilityLabel: "Log \(food)") {
                                    // chip tap logs immediately
                                    Task { if let e = await model.log(name: food, at: timestamp) { onLogged(e) } }
                                }
```

- [ ] **Step 4: Use it in `DoseCaptureView.swift`**

Replace the chip `Button` block inside `ForEach(model.chips, …)` (lines ~67–75):

```swift
                                Button {            // chip tap logs at the last-used amount/unit
                                    Task { if let e = await model.logChip(substance: s, at: timestamp) { onLogged(e) } }
                                } label: {
                                    Text(s).font(.footnote).padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(HealthTheme.card))
                                        .overlay(Capsule().strokeBorder(HealthTheme.cardBorder, lineWidth: 1))
                                        .foregroundStyle(HealthTheme.inkSecondary)
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }.accessibilityLabel("Log \(s)")
```

with:

```swift
                                QuickLogChip(label: s, accessibilityLabel: "Log \(s)") {
                                    // chip tap logs at the last-used amount/unit
                                    Task { if let e = await model.logChip(substance: s, at: timestamp) { onLogged(e) } }
                                }
```

- [ ] **Step 5: Verify no neutral chip styling remains, build, run capture tests**

Run: `grep -rn "Capsule().fill(HealthTheme.card)" Views/HealthOS/Capture/`
Expected: no matches.

```bash
cd /Users/leo/dev/FoodIntolerances
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' \
  -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/CaptureFlowTests" 2>&1 | tail -10
```

Expected: CaptureFlowTests all pass (behavior untouched).

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/dev/FoodIntolerances
git add Views/HealthOS/Capture/QuickLogChip.swift Views/HealthOS/Capture/SymptomCaptureView.swift \
        Views/HealthOS/Capture/MealCaptureView.swift Views/HealthOS/Capture/DoseCaptureView.swift
git commit -m "refine(app): QuickLogChip — shared accent-tinted capture chips that read as tappable"
```

---

### Task 6: Final verification

**Files:** none (verification only; fix anything found and note it).

- [ ] **Step 1: Full package suite**

Run: `cd /Users/leo/dev/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: 119 tests / 16 suites, all pass, zero warnings.

- [ ] **Step 2: Full app suite**

```bash
cd /Users/leo/dev/FoodIntolerances
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' \
  -parallel-testing-enabled NO 2>&1 | tail -40
```

Expected: documented pattern — every test passes except the ONE known `SwiftDataMigratorTests.migratesObjectsFromAvoidedCabinetAndProtocols` teardown crash. Report per-test results.

- [ ] **Step 3: Discipline greps**

```bash
cd /Users/leo/dev/FoodIntolerances
grep -rn "sessionizeSleep" Views/
grep -rn "eraseDatabaseOnSchemaChange" HealthGraphCore/Sources/
git diff main --stat -- HealthGraphCore/Sources/HealthGraphCore/Database/
```

Expected: exactly 2 `sessionizeSleep` matches, both `false` and both in `TimelineViewModel.swift` (`runSearch()` and `delete()`'s search branch — every other call site relies on the sessionizing default); zero `eraseDatabaseOnSchemaChange` matches; empty Database/ diff.

- [ ] **Step 4: Report**

No commit (nothing should have changed). Summarize suite results for the human on-device checkpoint that follows this plan: nights render as single rows on wake days; expansion breakdown sane vs. Apple Health; naps labeled; search still shows raw stages; chips read as tappable; delete/undo on a session day behaves.

---

## Execution notes (SDD controller)

- Suggested implementer models: Tasks 1–2 sonnet (net-new logic + rewrite with exact code given), Tasks 3–5 sonnet, Task 6 haiku. Task reviewers: sonnet. Whole-branch review: fable.
- After Task 6: whole-branch review over `main..HEAD`, then Leo's on-device checkpoint, then superpowers:finishing-a-development-branch.
- Expected artifact sizes: ~2 new package files (~230 lines), ~1 rewritten package file, 3 new/modified view files, 3 chip call sites. Nothing touches Database/, migrations, or ingestion.
