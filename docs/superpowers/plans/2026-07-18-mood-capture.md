# Mood Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user log how they feel on a five-level scale — via a prominent ambient Home quick-check and a capture-sheet Mood tab — producing the `.mood` events the evidence engine already mines.

**Architecture:** A `MoodLevel` scale + `CaptureService.logMood` in HealthGraphCore, a one-line low-mood-threshold calibration, and `EventDisplay` mood rendering. App layer adds a Mood capture tab (`MoodCaptureView`) and a Home quick-check card (`MoodCheckInView` + model). Mood edges are suppressed from the Insights feed this cycle (their reading experience is the next round).

**Tech Stack:** Swift, SwiftUI, GRDB, Swift Testing. Same pure-core / thin-app split as prior cycles.

**Design doc:** `docs/superpowers/specs/2026-07-18-mood-capture-design.md`.

## Global Constraints

- **Five-level scale** (😖 Awful=1 · 🙁 Low=2 · 😐 Okay=3 · 🙂 Good=4 · 😄 Great=5), stored as the `HealthEvent.value` (1–5). `MoodLevel` in HealthGraphCore is the single source of truth for values/labels/emoji.
- Mood event shape: `category: .mood`, `subtype: "mood"`, `value: Double(level.rawValue)`, `source: .manual`, optional note in metadata (matches the existing `OutcomeSource`/`ExposureSourceTests` convention — `.mood` events key off category + value, not subtype).
- **Low-mood cutoff = 2** (Awful/Low): calibrate `EvidenceConfig.lowMoodThreshold` from 3 → 2. This is the only engine touch.
- **No prediction / pre-fill** of mood, ever. **No forced check-ins / streaks / nagging.** **No stored "don't know"** value (Okay=3 means neutral, not unknown).
- **No red-flag interaction:** mood events are `.mood`, and the crisis/red-flag check only fires on `.symptom` — logging "Awful" must never trigger a crisis takeover.
- **Mood Insights are deferred (next round):** suppress `low-mood` relationships (`toCategory == "mood"`) from the Insights feed this cycle. The engine still mines + stores them.
- **Qualify `HealthGraphCore.SymptomCatalog`** if referenced in app-target files (legacy shadow); this feature mostly doesn't touch it. Package tests use bare names.
- **App-target tests MUST run with `-parallel-testing-enabled NO`** (the pre-existing `SwiftDataMigratorTests.migratesObjectsFromAvoidedCabinetAndProtocols` framework crash is unrelated).
- **Directory hazard:** new app files go to the tracked `Views/HealthOS/...` — never a `Food Intolerances/Views/...` decoy tree.
- **App simulator:** iPhone 17 Pro (iOS 26.5). Build: package `cd HealthGraphCore && swift test`; app `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

---

## Verified interfaces (from the codebase)

- `CaptureService` (`HealthGraphCore/.../Capture/CaptureService.swift`): `public init(database: AppDatabase)`, private `eventStore`, `private static func metadata(_ pairs:[String:String]) -> Data?`. `logSymptom(canonicalKey:severity:at:note:)` is the pattern for `logMood`.
- `HealthEvent(timestamp:category:subtype:value:unit:source:metadata:dedupKey:...)` — a symptom uses `.symptom`/subtype/value/unit "severity"/`.manual`.
- `EvidenceConfig.lowMoodThreshold: Double = 3` (`.../Evidence/EvidenceConfig.swift:18`). `OutcomeSource` maps `.mood` events with `value <= lowMoodThreshold` → `.lowMood`.
- `ExposureSourceTests.extractsSymptomsAndLowMood` (`.../Tests/.../ExposureSourceTests.swift:40-54`): mood value 2 → low, value 8 → skipped; asserts `occ.count == 2`.
- `EventDisplay.title(for:)` / `valueLine(for:)` (`.../Timeline/EventDisplay.swift:31-81`): `title` humanizes subtype; has a `.note` special-case at the top; never reads `value`. `valueLine` switches on `unit`.
- `CaptureType` (`Views/HealthOS/Capture/CaptureType.swift`): `symptom, meal, dose, note` + `label`/`icon`.
- `CaptureSheet.swift`: shared `@State timestamp`, `switch type { case .symptom: SymptomCaptureView(timestamp:$timestamp, onLogged: logged) ...}`, `logged(_:)` (calls `coordinator.saveCompleted()` + `redFlagPresenter.consider(event)` + undo toast).
- `SymptomCaptureView`: `struct …View { @Binding var timestamp: Date; let onLogged: (HealthEvent)->Void; @StateObject model = SymptomCaptureModel(database: HealthGraphProvider.shared) }`; model wraps `CaptureService`.
- `HomeView.swift`: `@StateObject viewModel = HomeViewModel(store: GRDBEventStore(database: HealthGraphProvider.shared))`, `@EnvironmentObject captureCoordinator: CaptureCoordinator`; body = `VStack(spacing:16){ greeting; passiveStrip; if backfill {backfillCard}; whatsNext }`. A mood card slots between `greeting` and `passiveStrip`.
- `InsightsFeed.build(_ resolved:[ResolvedRelationship], now:, config:)` (`HealthGraphCore/.../Insights/InsightsFeed.swift:4-8`): sections `resolved` by `relationship.status`. `ResolvedRelationship.relationship: Relationship`; `Relationship.toCategory: String?` — a low-mood edge has `toCategory == "mood"` (per `EdgeIdentity.columns`).
- `HealthTheme`: `paper/card/cardBorder/ink/inkSecondary/inkMuted/accent/onAccent`, `hgCard()`, `screenTitle()`, `sectionHeader()`, `cardCornerRadius`. No mood/emoji token needed (emoji carry the scale).
- `EventStore.events(in: DateInterval, category: EventCategory?)` exists (used by `EvidenceEngine`); `GRDBEventStore.softDelete(id:)` exists (used by `CaptureSheet.undo`).
- App test convention: `import Testing; import HealthGraphCore; @testable import Food_Intolerances; @MainActor struct`; `AppDatabase.inMemory()`; isolated `UserDefaults(suiteName:)`.

---

### Task 1: Core — `MoodLevel` scale + `CaptureService.logMood` + threshold calibration

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Capture/MoodScale.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Capture/CaptureService.swift` (add `logMood`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift:18` (3 → 2, comment)
- Modify (test): `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift` (boundary case + stale comment)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/MoodScaleTests.swift`

**Interfaces produced:**
- `enum MoodLevel: Int, CaseIterable, Sendable { case awful=1, low=2, okay=3, good=4, great=5; var label: String; var emoji: String }`.
- `CaptureService.logMood(level: MoodLevel, at timestamp: Date, note: String?) async throws -> HealthEvent` (writes `.mood`/`"mood"`/value 1–5).

- [ ] **Step 1: Write the failing tests.** `MoodScaleTests.swift`:

```swift
import Foundation
import Testing
@testable import HealthGraphCore

struct MoodScaleTests {
    @Test func levelsAreOrderedOneToFive() {
        #expect(MoodLevel.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
    }
    @Test func labelsAndEmoji() {
        #expect(MoodLevel.awful.label == "Awful")
        #expect(MoodLevel.great.label == "Great")
        #expect(MoodLevel.okay.emoji == "😐")
        #expect(MoodLevel(rawValue: 4)?.label == "Good")
    }
}
```

Add a `logMood` test to `MoodScaleTests.swift` (package, in-memory DB):
```swift
    @Test func logMoodWritesAMoodEvent() async throws {
        let db = try AppDatabase.inMemory()
        let event = try await CaptureService(database: db).logMood(
            level: .good, at: Date(timeIntervalSince1970: 1_700_000_000), note: "sunny walk")
        #expect(event.category == .mood)
        #expect(event.subtype == "mood")
        #expect(event.value == 4)
        #expect(event.source == .manual)
        let dict = try JSONDecoder().decode([String: String].self, from: #require(event.metadata))
        #expect(dict["note"] == "sunny walk")   // note round-trips into metadata
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.contains { $0.id == event.id })
    }
```

Add the threshold-boundary case to `ExposureSourceTests.swift`:
```swift
    @Test func moodThresholdIsTwo() {
        let low = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .mood,
                              subtype: "mood", value: 2, source: .manual)   // Low → low mood
        let okay = HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .mood,
                               subtype: "mood", value: 3, source: .manual)  // Okay → NOT low
        let occ = OutcomeSource(config: .default).occurrences(from: [low, okay])
        #expect(occ.filter { $0.key == .lowMood }.count == 1)
    }
```

- [ ] **Step 2: Run to verify they fail.**

Run: `cd HealthGraphCore && swift test --filter "MoodScale|OutcomeSource" 2>&1 | tail -6`
Expected: FAIL — `MoodLevel`/`logMood` undefined; `moodThresholdIsTwo` fails (threshold still 3, so Okay=3 counts as low → count 2).

- [ ] **Step 3: Implement `MoodScale.swift`.**

```swift
import Foundation

/// The single source of truth for the mood scale (1–5). Every surface reads
/// values/labels/emoji from here.
public enum MoodLevel: Int, CaseIterable, Sendable {
    case awful = 1, low = 2, okay = 3, good = 4, great = 5

    public var label: String {
        switch self {
        case .awful: "Awful"
        case .low:   "Low"
        case .okay:  "Okay"
        case .good:  "Good"
        case .great: "Great"
        }
    }

    public var emoji: String {
        switch self {
        case .awful: "😖"
        case .low:   "🙁"
        case .okay:  "😐"
        case .good:  "🙂"
        case .great: "😄"
        }
    }
}
```

- [ ] **Step 4: Implement `logMood`** in `CaptureService.swift` (after `logSymptom`):

```swift
    @discardableResult
    public func logMood(level: MoodLevel, at timestamp: Date, note: String?) async throws -> HealthEvent {
        var meta: [String: String] = [:]
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meta["note"] = note
        }
        let event = HealthEvent(
            timestamp: timestamp, category: .mood,
            subtype: "mood",
            value: Double(level.rawValue),
            source: .manual, metadata: Self.metadata(meta), dedupKey: nil)
        try await eventStore.save(event)
        return event
    }
```

- [ ] **Step 5: Calibrate the threshold.** In `EvidenceConfig.swift:18`, change:

```swift
    public var lowMoodThreshold: Double = 2               // mood value ≤ 2 (Awful/Low on the 1–5 scale) → low mood
```

And update the now-stale comment on the existing `ExposureSourceTests` low sample (the `value: 2` line comment `// ≤3 → low mood` → `// ≤2 → low mood`).

- [ ] **Step 6: Run to verify pass + full suite.**

Run: `cd HealthGraphCore && swift test --filter "MoodScale|OutcomeSource" 2>&1 | tail -6` → PASS (incl. the unchanged `extractsSymptomsAndLowMood`: 2≤2 low, 8>2 skipped).
Run: `cd HealthGraphCore && swift test 2>&1 | tail -3` → full suite passes.

- [ ] **Step 7: Commit.**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Capture/MoodScale.swift" \
        "HealthGraphCore/Sources/HealthGraphCore/Capture/CaptureService.swift" \
        "HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/MoodScaleTests.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift"
git commit -m "feat(core): MoodLevel scale + CaptureService.logMood + low-mood threshold calibration (3→2)"
```

---

### Task 2: Timeline display — `EventDisplay` renders mood as "Mood: Good"

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/EventDisplay.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EventDisplayTests.swift` (create if absent; else add cases)

**Interfaces:**
- Consumes: `MoodLevel` (Task 1).

- [ ] **Step 1: Write the failing test.** In `EventDisplayTests.swift`:

```swift
import Testing
@testable import HealthGraphCore

struct EventDisplayMoodTests {
    private func mood(_ v: Double) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .mood,
                    subtype: "mood", value: v, source: .manual)
    }
    @Test func moodTitleShowsTheLevel() {
        #expect(EventDisplay.title(for: mood(4)) == "Mood: Good")
        #expect(EventDisplay.title(for: mood(1)) == "Mood: Awful")
    }
    @Test func moodValueLineIsNilBecauseTitleCarriesIt() {
        #expect(EventDisplay.valueLine(for: mood(4)) == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `cd HealthGraphCore && swift test --filter "EventDisplay" 2>&1 | tail -6`
Expected: FAIL — `title` returns "Mood" (no level); `valueLine` returns "4".

- [ ] **Step 3: Implement.** In `EventDisplay.title(for:)`, add a `.mood` branch right after the `.note` special-case (line ~33):

```swift
        if event.category == .mood, let v = event.value, let level = MoodLevel(rawValue: Int(v)) {
            return "Mood: \(level.label)"
        }
```

And at the top of `EventDisplay.valueLine(for:)` (after the `.environment` block, before the `guard let value`), add:

```swift
        if event.category == .mood { return nil }   // the level is already in the title
```

- [ ] **Step 4: Run to verify pass.**

Run: `cd HealthGraphCore && swift test --filter "EventDisplay" 2>&1 | tail -6` → PASS.

- [ ] **Step 5: Commit.**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Timeline/EventDisplay.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/EventDisplayTests.swift"
git commit -m "feat(core): EventDisplay renders mood events as 'Mood: <level>'"
```

---

### Task 3: Capture-sheet Mood tab — `CaptureType.mood` + `MoodCaptureView`

**Files:**
- Modify: `Views/HealthOS/Capture/CaptureType.swift` (add `.mood`)
- Modify: `Views/HealthOS/Capture/CaptureSheet.swift` (add the `.mood` switch arm)
- Create: `Views/HealthOS/Capture/MoodCaptureView.swift`
- Modify (test): `Food IntolerancesTests/RedFlagPresenterTests.swift` (lock mood ≠ red-flag)

**Interfaces:**
- Consumes: `MoodLevel`, `CaptureService.logMood` (Task 1); the sheet's `onLogged`/`$timestamp`.

*View task — build + preview verified.*

- [ ] **Step 1: Add `.mood` to `CaptureType.swift`.** Add `mood` to the case list and both switches:

```swift
    case symptom, meal, dose, note, mood
```
label: `case .mood: "Mood"` · icon: `case .mood: "face.smiling"`.

- [ ] **Step 2: Implement `MoodCaptureView.swift`.**

```swift
import SwiftUI
import HealthGraphCore

@MainActor
final class MoodCaptureModel: ObservableObject {
    @Published var note: String = ""
    private let capture: CaptureService
    init(database: AppDatabase) { self.capture = CaptureService(database: database) }
    @discardableResult
    func log(_ level: MoodLevel, at timestamp: Date, note: String?) async -> HealthEvent? {
        do { return try await capture.logMood(level: level, at: timestamp, note: note) }
        catch { return nil }
    }
}

/// Capture-sheet Mood tab: tap one of five faces (+ optional note); back-dated via the
/// sheet's shared "When" picker. The Home quick-check is the fast path; this is the
/// "with note / earlier time" path.
struct MoodCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    @StateObject private var model = MoodCaptureModel(database: HealthGraphProvider.shared)

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(MoodLevel.allCases, id: \.rawValue) { level in
                    Button {
                        Task {
                            let note = model.note.isEmpty ? nil : model.note
                            if let e = await model.log(level, at: timestamp, note: note) {
                                onLogged(e); model.note = ""
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(level.emoji).font(.largeTitle)
                            Text(level.label).font(.caption).foregroundStyle(HealthTheme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64).contentShape(Rectangle())
                    }
                    .accessibilityLabel(level.label)
                }
            }
            .padding(.horizontal, 16)

            TextField("Add a note (optional)", text: $model.note, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3).padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

#Preview {
    MoodCaptureView(timestamp: .constant(Date()), onLogged: { _ in })
}
```

- [ ] **Step 3: Wire the tab in `CaptureSheet.swift`.** Add to the `switch type` block:

```swift
                case .mood: MoodCaptureView(timestamp: $timestamp, onLogged: logged)
```

- [ ] **Step 4: Lock the "mood never fires a red flag" guarantee.** The Mood tab routes through `CaptureSheet.logged`, which calls `redFlagPresenter.consider(event)` for every capture type. `consider` guards on `event.category == .symptom`, so a mood event is a no-op — add a regression test to the existing `Food IntolerancesTests/RedFlagPresenterTests.swift` (reuses its `presenter()` helper) locking that:

```swift
    @Test func moodEventNeverTriggersRedFlag() {
        let p = presenter()
        p.consider(HealthEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                               category: .mood, subtype: "mood", value: 1, source: .manual))
        #expect(p.pending == nil)
    }
```

It passes immediately (regression lock — a future `consider` change can't route "Awful" mood to a crisis screen).

- [ ] **Step 5: Build + confirm.**

Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -8`
Expected: build succeeds; the sheet now has a Mood tab; the preview renders five faces + note field.
Run the safety test: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/RedFlagPresenterTests" -parallel-testing-enabled NO 2>&1 | grep -E "Test run with|TEST (SUCCEEDED|FAILED)" | tail -3` → all pass (incl. the new mood case).

- [ ] **Step 6: Commit.**

```bash
git add "Views/HealthOS/Capture/CaptureType.swift" "Views/HealthOS/Capture/CaptureSheet.swift" \
        "Views/HealthOS/Capture/MoodCaptureView.swift" "Food IntolerancesTests/RedFlagPresenterTests.swift"
git commit -m "feat(app): Mood capture-sheet tab — five-level picker + optional note (+ mood≠red-flag lock)"
```

---

### Task 4: Home quick-check — `MoodCheckInView` + model + Home wiring

**Files:**
- Create: `Views/HealthOS/Home/MoodCheckInView.swift` (view + `MoodCheckInModel`)
- Modify: `Views/HealthOS/Home/HomeView.swift` (embed the card)
- Test: `Food IntolerancesTests/MoodCheckInModelTests.swift`

**Interfaces:**
- Consumes: `MoodLevel`, `CaptureService.logMood` (Task 1); `EventStore.events(in:category:)`, `GRDBEventStore.softDelete(id:)`; `CaptureCoordinator` (env, `saveCompleted()`); `HealthGraphProvider.shared`.
- Produces: `MoodCheckInModel` (`@MainActor ObservableObject`) with `todaysMood: (level: MoodLevel, at: Date)?`, `dismissedToday: Bool`, `load() async`, `log(_ level:) async`, `undo() async`, `dismissForToday()`; `struct MoodCheckInView: View`.

- [ ] **Step 1: Write the failing model test.** `MoodCheckInModelTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct MoodCheckInModelTests {
    private var utcCal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    // A fixed "today" at 12:00 UTC — the +1h/+2h offsets below stay within the same UTC day.
    private var noon: Date { utcCal.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 12))! }
    private func model(_ db: AppDatabase, at t: Date) -> MoodCheckInModel {
        MoodCheckInModel(database: db,
                         defaults: UserDefaults(suiteName: "mood-\(UUID().uuidString)")!,
                         calendar: utcCal, now: { t })
    }

    @Test func logThenLoadShowsTodaysMood() async throws {
        let db = try AppDatabase.inMemory()
        let m = model(db, at: noon)
        await m.log(.good)
        #expect(m.todaysMood?.level == .good)
        let m2 = model(db, at: noon)         // a fresh model on the same DB/day loads it back
        await m2.load()
        #expect(m2.todaysMood?.level == .good)
    }

    @Test func latestOfMultipleLogsTodayWins() async throws {
        let db = try AppDatabase.inMemory()
        await model(db, at: noon).log(.awful)
        await model(db, at: noon.addingTimeInterval(3600)).log(.good)   // later, same day
        let fresh = model(db, at: noon.addingTimeInterval(7200))
        await fresh.load()
        #expect(fresh.todaysMood?.level == .good)   // latest by timestamp, not first-logged
    }

    @Test func previousDaysMoodDoesNotCountAsToday() async throws {
        let db = try AppDatabase.inMemory()
        await model(db, at: noon).log(.good)
        let tomorrow = model(db, at: noon.addingTimeInterval(24 * 3600))
        await tomorrow.load()
        #expect(tomorrow.todaysMood == nil)
    }

    @Test func undoRemovesTodaysMood() async throws {
        let db = try AppDatabase.inMemory()
        let m = model(db, at: noon)
        await m.log(.awful)
        await m.undo()
        #expect(m.todaysMood == nil)
    }

    @Test func dismissForTodayPersistsPerDay() {
        let db = try AppDatabase.inMemory()
        let defaults = UserDefaults(suiteName: "mood-\(UUID().uuidString)")!
        func mk(_ t: Date) -> MoodCheckInModel {
            MoodCheckInModel(database: db, defaults: defaults, calendar: utcCal, now: { t })
        }
        let m = mk(noon)
        #expect(m.dismissedToday == false)
        m.dismissForToday()
        #expect(m.dismissedToday == true)
        #expect(mk(noon).dismissedToday == true)                                // same day sees it
        #expect(mk(noon.addingTimeInterval(24 * 3600)).dismissedToday == false)  // next day cleared
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/MoodCheckInModelTests" -parallel-testing-enabled NO 2>&1 | tail -8`
Expected: FAIL (compile — `MoodCheckInModel` undefined).

- [ ] **Step 3: Implement `MoodCheckInView.swift`** (model + view).

```swift
import SwiftUI
import HealthGraphCore

@MainActor
final class MoodCheckInModel: ObservableObject {
    @Published private(set) var todaysMood: (level: MoodLevel, at: Date)?
    @Published private(set) var dismissedToday: Bool

    private let capture: CaptureService
    private let store: GRDBEventStore
    private let defaults: UserDefaults
    private let calendar: Calendar   // injectable so "today" is timezone-deterministic in tests
    private let now: () -> Date
    private var lastLoggedID: UUID?
    private static let dismissKey = "hg.home.moodDismissedDay"

    init(database: AppDatabase, defaults: UserDefaults = .standard,
         calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.capture = CaptureService(database: database)
        self.store = GRDBEventStore(database: database)
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.dismissedToday = (defaults.string(forKey: Self.dismissKey) == Self.dayKey(now(), calendar))
    }

    // Static (takes the calendar) so it's callable while `self` is still initializing.
    private static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    private var todayInterval: DateInterval {
        let start = calendar.startOfDay(for: now())
        return DateInterval(start: start, end: start.addingTimeInterval(24 * 3600))
    }

    /// Load the latest mood logged today (so the confirmed state survives app relaunch within the day).
    func load() async {
        dismissedToday = (defaults.string(forKey: Self.dismissKey) == Self.dayKey(now(), calendar))
        let events = (try? await store.events(in: todayInterval, category: .mood)) ?? []
        if let latest = events.max(by: { $0.timestamp < $1.timestamp }),
           let v = latest.value, let level = MoodLevel(rawValue: Int(v)) {
            todaysMood = (level, latest.timestamp)
            lastLoggedID = latest.id
        } else {
            todaysMood = nil; lastLoggedID = nil
        }
    }

    func log(_ level: MoodLevel) async {
        guard let e = try? await capture.logMood(level: level, at: now(), note: nil) else { return }
        todaysMood = (level, e.timestamp)
        lastLoggedID = e.id
    }

    func undo() async {
        guard let id = lastLoggedID else { return }
        try? await store.softDelete(id: id)
        lastLoggedID = nil
        await load()
    }

    func dismissForToday() {
        defaults.set(Self.dayKey(now(), calendar), forKey: Self.dismissKey)
        dismissedToday = true
    }
}

/// Ambient Home "How are you feeling?" quick-check — the primary, low-friction mood surface.
/// One tap logs; never nags; "not now" tucks it away for the day.
struct MoodCheckInView: View {
    @StateObject private var model = MoodCheckInModel(database: HealthGraphProvider.shared)
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator

    var body: some View {
        Group {
            if !model.dismissedToday {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("How are you feeling?")
                            .font(HealthTheme.sectionHeader()).foregroundStyle(HealthTheme.ink)
                        Spacer()
                        Button { model.dismissForToday() } label: {
                            Image(systemName: "xmark").font(.footnote).foregroundStyle(HealthTheme.inkMuted)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Not now")
                    }
                    if let today = model.todaysMood {
                        HStack {
                            Text("Felt \(today.level.label) \(today.at.formatted(date: .omitted, time: .shortened)) — tap to update")
                                .font(.subheadline).foregroundStyle(HealthTheme.inkSecondary)
                            Spacer()
                            Button("Undo") { Task { await model.undo(); captureCoordinator.saveCompleted() } }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(HealthTheme.accent)
                                .frame(minHeight: 44)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(MoodLevel.allCases, id: \.rawValue) { level in
                            Button {
                                Task { await model.log(level); captureCoordinator.saveCompleted() }
                            } label: {
                                Text(level.emoji).font(.largeTitle)
                                    .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                            }
                            .accessibilityLabel(level.label)
                        }
                    }
                }
                .padding(16).hgCard()
                .task { await model.load() }
            }
        }
    }
}

#Preview {
    MoodCheckInView().environmentObject(CaptureCoordinator())
        .padding().background(HealthTheme.paper)
}
```

- [ ] **Step 4: Run the model test to verify pass.**

Run the Step 2 command → `** TEST SUCCEEDED **`, all three model tests pass.

- [ ] **Step 5: Embed the card in `HomeView.swift`.** In the body `VStack` (line ~12), insert between `greeting` and `passiveStrip`:

```swift
                greeting
                MoodCheckInView()
                passiveStrip
```

(`MoodCheckInView` reaches `CaptureCoordinator` via `@EnvironmentObject`, already injected at the app root.)

- [ ] **Step 6: Build.**

Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -8` → build succeeds. Confirm the preview renders the card (title, ×, five faces).

- [ ] **Step 7: Commit.**

```bash
git add "Views/HealthOS/Home/MoodCheckInView.swift" "Views/HealthOS/Home/HomeView.swift" \
        "Food IntolerancesTests/MoodCheckInModelTests.swift"
git commit -m "feat(app): Home 'How are you feeling?' quick-check — one-tap mood, per-day dismiss, undo"
```

---

### Task 5: Suppress mood edges from the Insights feed (this cycle)

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightsFeed.swift` (filter in `build`)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/InsightsFeedTests.swift` (add a case)

**Interfaces:**
- Consumes: `ResolvedRelationship.relationship.toCategory` (a low-mood edge has `toCategory == "mood"`).

- [ ] **Step 1: Write the failing test.** Add to `InsightsFeedTests.swift` (read the file first to reuse its `ResolvedRelationship` fixture helper; construct one symptom edge + one mood edge):

The existing `rr()` helper in `InsightsFeedTests.swift` **hardcodes** `toCategory: "symptom"` / `exposureLabel: "Food"`, so it can't produce a mood edge — construct the two edges **inline** (both types have public inits). One symptom edge (survives) + one mood edge (`toCategory: "mood"`, suppressed), with distinct exposure labels so cards are identifiable (a low-mood claim renders its subtype "low", never the word "mood"):

```swift
    @Test func moodOutcomeEdgesAreSuppressed() {
        let refNow = Date(timeIntervalSince1970: 1_700_000_000)
        func rel(toCategory: String, toSubtype: String, key: String) -> Relationship {
            Relationship(fromCategory: "food", toCategory: toCategory, type: .possibleTrigger,
                         evidenceCount: 6, contradictionCount: 2, confidence: 0.6, strength: 5, lagHours: 12,
                         firstSeen: refNow.addingTimeInterval(-5 * 86_400), lastSeen: refNow,
                         lastRecomputed: refNow, status: .active, edgeKey: key, toSubtype: toSubtype)
        }
        let dairy = ResolvedRelationship(
            relationship: rel(toCategory: "symptom", toSubtype: "bloating", key: "k-dairy"),
            exposureLabel: "Dairy", outcomeLabel: "bloating", exposureCategory: .food, recentOutcomes: [])
        let coffeeMood = ResolvedRelationship(
            relationship: rel(toCategory: "mood", toSubtype: "low", key: "k-coffee-mood"),
            exposureLabel: "Coffee", outcomeLabel: "low", exposureCategory: .food, recentOutcomes: [])
        let claims = InsightsFeed.build([dairy, coffeeMood], now: refNow)
            .sections.flatMap(\.cards).map { $0.claim.lowercased() }
        #expect(claims.contains { $0.contains("dairy") })    // the symptom edge survives
        #expect(!claims.contains { $0.contains("coffee") })  // the mood edge is suppressed
        #expect(claims.count == 1)                           // exactly one card (guards vacuity)
    }
```

(Verify the `Relationship`/`ResolvedRelationship` init argument labels against the real types before running — the integration audit confirmed both have public inits and `InsightCardModel.claim` is public. Match any label/order differences you find, and drop `recentOutcomes:` if that field isn't on the init.)

- [ ] **Step 2: Run to verify it fails.**

Run: `cd HealthGraphCore && swift test --filter InsightsFeed 2>&1 | tail -6`
Expected: FAIL — the mood edge currently appears (no filter).

- [ ] **Step 3: Implement the filter** in `InsightsFeed.build` — filter `resolved` before sectioning (at the top of `build`, before the `active`/`noEffect`/`archive` splits):

```swift
        // Mood-outcome edges (toCategory == "mood") are mined + stored but not surfaced this
        // cycle — their reading experience ("what lifts your mood") is the next round.
        let resolved = resolved.filter { $0.relationship.toCategory != "mood" }
```

- [ ] **Step 4: Run to verify pass + full suite.**

Run: `cd HealthGraphCore && swift test --filter InsightsFeed 2>&1 | tail -6` → PASS.
Run: `cd HealthGraphCore && swift test 2>&1 | tail -3` → full suite green.

- [ ] **Step 5: Commit.**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Insights/InsightsFeed.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/InsightsFeedTests.swift"
git commit -m "feat(core): suppress mood-outcome edges from the Insights feed (deferred to next round)"
```

---

### Task 6: End-to-end verification + regression

**Files:** none (verification).

- [ ] **Step 1: Full regression.**
  - `cd HealthGraphCore && swift test 2>&1 | tail -3` → all green (incl. Mood/EventDisplay/OutcomeSource/InsightsFeed additions).
  - App target: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "✔ Suite|✘|Test run with|\*\* TEST"` → every suite green except the known pre-existing `SwiftDataMigratorTests.migratesObjectsFromAvoidedCabinetAndProtocols` crash (passes in isolation).
  - App build succeeds.

- [ ] **Step 2: On-device / simulator behavior check** (device preferred). Confirm:
  - Home shows the **"How are you feeling?"** card near the top; tapping a face logs it and the card flips to "Felt Good … — tap to update" with **Undo**; **Undo** removes it.
  - **"Not now" (×)** hides the card for the rest of the day; it returns the next day.
  - Capture ➕ → **Mood** tab → tap a face (+ optional note, back-dated via "When") → logs.
  - Both paths appear in the **Timeline** as **"Mood: Good"** and are deletable.
  - Logging **Awful** shows **no** crisis takeover; no red-flag interaction.
  - Mood edges do **NOT** appear in the **Insights** tab this cycle (seed via debug view + recompute to confirm a mined mood edge stays hidden; symptom edges still show).
  - Light + dark; XXL Dynamic Type.

- [ ] **Step 3: Record observed behavior** in the review notes / ledger.

---

## Definition of Done

- A user can log mood on a five-level scale from a prominent ambient Home quick-check (one tap, per-day "not now", undo) and a capture-sheet Mood tab (with note + back-dating); both write `.mood` events (value 1–5).
- Mood events render as "Mood: <level>" in the Timeline and are deletable; logging never triggers the crisis/red-flag flow.
- The engine's low-mood mining is calibrated to the 1–5 scale (threshold 2) and mines mood from day one; mood-outcome edges are suppressed from the Insights feed (deferred to next round) but stored.
- Core (`MoodLevel`, `logMood`, threshold, `EventDisplay`, feed filter) unit-tested; the Home model (log/load/undo/dismiss) unit-tested; views build + preview; verified end-to-end.
- No prediction/pre-fill, no forced check-ins/streaks, no stored "don't know"; no changes to the engine's structure, migrations, the crisis/red-flag flow, or other extractors. The positive "what lifts your mood" mining + mood Insights presentation remain the committed next round.
