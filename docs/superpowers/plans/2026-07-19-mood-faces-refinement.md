# Mood Faces Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 5-emoji mood scale with 3 custom-drawn, subtly-colored faces (Rough · Okay · Good), recalibrate the low-mood threshold, and add a display-robustness clamp — with the engine's structure untouched.

**Architecture:** Core (`HealthGraphCore`) keeps `MoodLevel` as pure data (3 cases, labels, a `clamping` initializer) and drops `emoji`; the face *drawing* moves to a new app-layer SwiftUI view `MoodFace`. The two existing capture surfaces swap `Text(level.emoji)` for `MoodFace(level:)`. One engine constant (`lowMoodThreshold`) drops 2→1. No data migration.

**Tech Stack:** Swift, Swift Testing (`import Testing`, `@Test`, `#expect`), SwiftUI, GRDB. Package logic tested via `swift test`; app target via `xcodebuild ... -parallel-testing-enabled NO`.

Design: `docs/superpowers/specs/2026-07-19-mood-faces-refinement-design.md`.

## Global Constraints

- **`MoodLevel` stays pure data** — no SwiftUI, no `Color`, no `emoji`. All drawing/color lives in the app-layer `MoodFace`. (spec §3, §4)
- **Scale is exactly three cases:** `.rough = 1, .okay = 2, .good = 3`; labels `"Rough" / "Okay" / "Good"`. (spec §2)
- **Event shape is unchanged:** mood logs stay `category: .mood`, `subtype: "mood"`, `value: Double(level.rawValue)` (now 1–3), `source: .manual`. No change to `CaptureService.logMood` or `MoodCheckInModel`.
- **`lowMoodThreshold = 1`** — low mood is Rough (1) only; Okay (2) is NOT low. (spec §3)
- **No data migration / remap** of stored mood values; the `clamping` initializer covers orphaned old values at display time. (spec §3, §5)
- **New app files go to the tracked `Views/HealthOS/…` path**, NOT the untracked `Food Intolerances/Views/HealthOS/` decoy tree. `Views` is a `PBXFileSystemSynchronizedRootGroup` — new files are auto-included; no `.pbxproj` edits.
- **App-target tests MUST run with `-parallel-testing-enabled NO`.** The lone `SwiftDataMigratorTests.migratesObjectsFromAvoidedCabinetAndProtocols` `** TEST FAILED **` is a KNOWN pre-existing framework-teardown crash (passes in isolation) — unrelated to this work.
- **Simulator:** iPhone 17 Pro (iOS 26.5).
- **Out of scope:** the positive "what lifts your mood" mining (next round), the Timeline swipe-to-delete gap, the crisis/red-flag flow, the Insights suppression, any engine structural change. (spec §9)
- **Note on intermediate state:** Task 1 removes `MoodLevel.emoji` and the `.awful/.low/.great` cases, which breaks *app-target* compilation until Task 2. That is expected — Task 1's gate is the **core** `swift test` only; the app build is Task 2's gate.

---

### Task 1: Core — 3-level `MoodLevel` + clamping + threshold

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Capture/MoodScale.swift` (whole file)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift:18`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/EventDisplay.swift:34`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/MoodScaleTests.swift` (rewrite)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EventDisplayTests.swift` (rewrite the mood struct)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift` (two mood tests)

**Interfaces:**
- Produces: `MoodLevel { case rough = 1, okay = 2, good = 3 }` with `var label: String` and `init(clamping raw: Int)` (non-failable). `emoji` is removed. Consumed by Task 2 (the views) and by `EventDisplay`.
- Produces: `EvidenceConfig.lowMoodThreshold == 1`.

- [ ] **Step 1: Rewrite the failing tests first.**

Replace the entire body of `MoodScaleTests.swift` with:

```swift
import Foundation
import Testing
@testable import HealthGraphCore

struct MoodScaleTests {
    @Test func levelsAreOrderedOneToThree() {
        #expect(MoodLevel.allCases.map(\.rawValue) == [1, 2, 3])
    }
    @Test func labels() {
        #expect(MoodLevel.rough.label == "Rough")
        #expect(MoodLevel.okay.label == "Okay")
        #expect(MoodLevel.good.label == "Good")
    }
    @Test func clampingMapsAnyIntToNearestLevel() {
        #expect(MoodLevel(clamping: -5) == .rough)
        #expect(MoodLevel(clamping: 0) == .rough)
        #expect(MoodLevel(clamping: 1) == .rough)
        #expect(MoodLevel(clamping: 2) == .okay)
        #expect(MoodLevel(clamping: 3) == .good)
        #expect(MoodLevel(clamping: 4) == .good)
        #expect(MoodLevel(clamping: 99) == .good)
    }
    @Test func logMoodWritesAMoodEvent() async throws {
        let db = try AppDatabase.inMemory()
        let event = try await CaptureService(database: db).logMood(
            level: .good, at: Date(timeIntervalSince1970: 1_700_000_000), note: "sunny walk")
        #expect(event.category == .mood)
        #expect(event.subtype == "mood")
        #expect(event.value == 3)     // Good is 3 on the 1–3 scale
        #expect(event.source == .manual)
        let dict = try JSONDecoder().decode([String: String].self, from: #require(event.metadata))
        #expect(dict["note"] == "sunny walk")   // note round-trips into metadata
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.contains { $0.id == event.id })
    }
}
```

Replace the `EventDisplayMoodTests` struct in `EventDisplayTests.swift` with:

```swift
struct EventDisplayMoodTests {
    private func mood(_ v: Double) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .mood,
                    subtype: "mood", value: v, source: .manual)
    }
    @Test func moodTitleShowsTheLevel() {
        #expect(EventDisplay.title(for: mood(1)) == "Mood: Rough")
        #expect(EventDisplay.title(for: mood(2)) == "Mood: Okay")
        #expect(EventDisplay.title(for: mood(3)) == "Mood: Good")
    }
    @Test func moodTitleClampsOutOfRangeValues() {
        #expect(EventDisplay.title(for: mood(0)) == "Mood: Rough")   // guards orphaned/garbage
        #expect(EventDisplay.title(for: mood(4)) == "Mood: Good")    // old "Good"
        #expect(EventDisplay.title(for: mood(5)) == "Mood: Good")    // old "Great"
    }
    @Test func moodValueLineIsNilBecauseTitleCarriesIt() {
        #expect(EventDisplay.valueLine(for: mood(2)) == nil)
    }
}
```

In `ExposureSourceTests.swift`, update the low-mood sample in `extractsSymptomsAndLowMood` — change the two mood events (currently value `2` "≤2 → low mood" and value `8` "high → skipped") to:

```swift
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .mood,
                        subtype: "mood", value: 1, source: .manual),           // Rough (≤1) → low mood
            HealthEvent(timestamp: Date(timeIntervalSince1970: 300), category: .mood,
                        subtype: "mood", value: 3, source: .manual),           // Good → skipped
```

And replace the whole `moodThresholdIsTwo` test with:

```swift
    @Test func moodThresholdIsOne() {
        let low = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .mood,
                              subtype: "mood", value: 1, source: .manual)   // Rough → low mood
        let okay = HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .mood,
                               subtype: "mood", value: 2, source: .manual)  // Okay → NOT low
        let occ = OutcomeSource(config: .default).occurrences(from: [low, okay])
        #expect(occ.filter { $0.key == .lowMood }.count == 1)
    }
```

(The construction call `OutcomeSource(config: .default).occurrences(from:)` above is verbatim from the current test — only the two sample values, the test name, and the comments change. Do NOT touch `extractsSymptomsAndLowMood`'s `#expect(occ.count == 2)` line: with Rough=1 → low and Good=3 → skipped, the count is still 2.)

- [ ] **Step 2: Run the tests to confirm they fail.**

Run: `cd HealthGraphCore && swift test 2>&1 | tail -20`
Expected: FAIL — `MoodLevel` still has 5 cases / `.rough` etc. don't exist / `init(clamping:)` undefined / `EventDisplay` still says "Awful".

- [ ] **Step 3: Rewrite `MoodScale.swift` (whole file).**

```swift
import Foundation

/// The single source of truth for the mood scale (1–3). Pure data — labels and
/// values only; the face *drawing* (custom SwiftUI) lives in the app layer.
public enum MoodLevel: Int, CaseIterable, Sendable {
    case rough = 1, okay = 2, good = 3

    public var label: String {
        switch self {
        case .rough: "Rough"
        case .okay:  "Okay"
        case .good:  "Good"
        }
    }

    /// Nearest valid level for any Int — so display/mining never break on an
    /// out-of-range value (an orphaned pre-refinement 4/5 log, or future drift).
    public init(clamping raw: Int) {
        self = raw <= 1 ? .rough : (raw >= 3 ? .good : .okay)
    }
}
```

- [ ] **Step 4: Lower the threshold.** In `EvidenceConfig.swift:18`, replace:

```swift
    public var lowMoodThreshold: Double = 2               // mood value ≤ 2 (Awful/Low on the 1–5 scale) → low mood
```

with:

```swift
    public var lowMoodThreshold: Double = 1               // mood value ≤ 1 (Rough on the 1–3 scale) → low mood
```

- [ ] **Step 5: Use the clamp in `EventDisplay`.** In `EventDisplay.swift`, replace the mood branch (line 34-36):

```swift
        if event.category == .mood, let v = event.value, let level = MoodLevel(rawValue: Int(v)) {
            return "Mood: \(level.label)"
        }
```

with (note: `init(clamping:)` is non-failable, so drop the `let level =` optional-bind):

```swift
        if event.category == .mood, let v = event.value {
            return "Mood: \(MoodLevel(clamping: Int(v)).label)"
        }
```

- [ ] **Step 6: Run the full core suite to confirm green.**

Run: `cd HealthGraphCore && swift test 2>&1 | tail -20`
Expected: all pass (the whole suite, incl. the rewritten `MoodScaleTests`, `EventDisplayMoodTests`, and `ExposureSourceTests`). Report the pass/suite counts.

- [ ] **Step 7: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Capture/MoodScale.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Sources/HealthGraphCore/Timeline/EventDisplay.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/MoodScaleTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EventDisplayTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "feat(core): 3-level MoodLevel (Rough/Okay/Good) + clamping init + lowMoodThreshold 2→1"
```

---

### Task 2: App — `MoodFace` view + wire both surfaces

**Files:**
- Create: `Views/HealthOS/Capture/MoodFace.swift`
- Modify: `Views/HealthOS/Theme/HealthTheme.swift` (add three mood color tokens)
- Modify: `Views/HealthOS/Capture/MoodCaptureView.swift:37`
- Modify: `Views/HealthOS/Home/MoodCheckInView.swift:106`
- Modify: `Food IntolerancesTests/MoodCheckInModelTests.swift:33,51` (`.awful` → `.rough`)

**Interfaces:**
- Consumes: `MoodLevel` (3 cases) from Task 1.
- Produces: `struct MoodFace: View { let level: MoodLevel; var size: CGFloat = 56 }` — a self-contained tinted face; no bindings, `accessibilityHidden` (the enclosing button carries the VoiceOver label).

- [ ] **Step 1: Add mood color tokens to `HealthTheme`.** In `HealthTheme.swift`, immediately after the `accent` token (`static let accent = dyn(light: 0x2E7D74, dark: 0x4FA599)`), add:

```swift
    // Mood faces (starting values — tunable live in MoodFace previews)
    static let moodRough = dyn(light: 0xC46A72, dark: 0xD08A90)   // muted rose
    static let moodOkay  = dyn(light: 0x8F8A7B, dark: 0x9A9488)   // warm neutral
    static let moodGood  = dyn(light: 0x2E7D74, dark: 0x4FA599)   // sage (matches accent)
```

- [ ] **Step 2: Create `MoodFace.swift`** at `Views/HealthOS/Capture/MoodFace.swift` (verify with `git status` it is NOT under `Food Intolerances/Views/…`):

```swift
import SwiftUI
import HealthGraphCore

/// The single place a mood is drawn. A tinted round face whose mouth curve is
/// driven by the level: frown (Rough) → flat (Okay) → smile (Good). Custom-drawn
/// (not emoji) so it renders identically on every device and tints to the palette.
struct MoodFace: View {
    let level: MoodLevel
    var size: CGFloat = 56

    private var tint: Color {
        switch level {
        case .rough: HealthTheme.moodRough
        case .okay:  HealthTheme.moodOkay
        case .good:  HealthTheme.moodGood
        }
    }
    /// Mouth control-point offset as a fraction of the mouth rect height:
    /// +ve dips the middle down → smile; -ve raises it → frown; 0 → flat.
    private var smile: CGFloat {
        switch level {
        case .rough: -0.7
        case .okay:   0
        case .good:   0.7
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.16))
            Circle().stroke(tint, lineWidth: size * 0.055)
            HStack(spacing: size * 0.26) {
                Circle().fill(tint).frame(width: size * 0.1, height: size * 0.1)
                Circle().fill(tint).frame(width: size * 0.1, height: size * 0.1)
            }
            .offset(y: -size * 0.12)
            MouthShape(smile: smile)
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                .frame(width: size * 0.44, height: size * 0.26)
                .offset(y: size * 0.15)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)   // the enclosing button carries the label
    }
}

/// A quadratic mouth curve. `smile` moves the control point vertically as a
/// fraction of height: +ve → smile, 0 → flat line, -ve → frown.
private struct MouthShape: Shape {
    var smile: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                       control: CGPoint(x: rect.midX, y: rect.midY + smile * rect.height))
        return p
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 16) {
            ForEach(MoodLevel.allCases, id: \.rawValue) { MoodFace(level: $0, size: 76) }
        }
    }
    .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HealthTheme.paper)
}
```

- [ ] **Step 3: Wire the capture-sheet tab.** In `MoodCaptureView.swift`, in the face `VStack`, replace line 37:

```swift
                            Text(level.emoji).font(.largeTitle)
```

with:

```swift
                            MoodFace(level: level, size: 52)
```

(Leave the `Text(level.label)` caption, the `.frame(maxWidth: .infinity, minHeight: 64)`, and the note field unchanged.)

- [ ] **Step 4: Wire the Home quick-check.** In `MoodCheckInView.swift`, replace line 106:

```swift
                                Text(level.emoji).font(.largeTitle)
```

with:

```swift
                                MoodFace(level: level, size: 56)
```

(Leave the `.frame(maxWidth: .infinity, minHeight: 48)` and `.accessibilityLabel(level.label)` unchanged.)

- [ ] **Step 5: Fix the app-test fixtures.** In `MoodCheckInModelTests.swift`, the case `.awful` no longer exists. Replace `.log(.awful)` with `.log(.rough)` at line 33 and line 51. (No assertion depends on the level value at those sites — one logs-then-logs-good and asserts "good wins"; the other logs-then-undoes and asserts nil.)

- [ ] **Step 6: Build the app + run the app mood tests.**

Run:
```
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **` (all `level.emoji` references resolved to `MoodFace`; `.awful` removed).

Run:
```
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests/MoodCheckInModelTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "Test run with|✔ Test|✘ Test|TEST (SUCCEEDED|FAILED)" | tail -10
```
Expected: `** TEST SUCCEEDED **`, all 5 tests pass. Confirm the `MoodFace` `#Preview` compiles.

- [ ] **Step 7: Commit.**

```bash
git add "Views/HealthOS/Capture/MoodFace.swift" \
        "Views/HealthOS/Theme/HealthTheme.swift" \
        "Views/HealthOS/Capture/MoodCaptureView.swift" \
        "Views/HealthOS/Home/MoodCheckInView.swift" \
        "Food IntolerancesTests/MoodCheckInModelTests.swift"
git commit -m "feat(app): custom-drawn MoodFace (Rough/Okay/Good) replaces emoji on both mood surfaces"
```

---

### Task 3: End-to-end verification + regression

**Files:** none (verification).

- [ ] **Step 1: Full regression.**
  - Core: `cd HealthGraphCore && swift test 2>&1 | tail -3` → all green.
  - App target: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "✔ Suite|✘|Test run with|\*\* TEST"` → every suite green except the known pre-existing `SwiftDataMigratorTests.migratesObjectsFromAvoidedCabinetAndProtocols` teardown crash.
  - App build succeeds.

- [ ] **Step 2: On-device / simulator behavior check** (device preferred). Confirm:
  - Home **"How are you feeling?"** card shows **three** custom faces (frown / flat / smile), noticeably larger than before; tapping one logs it and the card flips to "Felt Rough/Okay/Good … — tap to update" with **Undo**; **Undo** removes it.
  - Capture ➕ → **Mood** tab → three faces + labels (Rough/Okay/Good) + optional note + back-date → logs.
  - Both appear in the **Timeline** as **"Mood: Rough/Okay/Good"** and are deletable.
  - Logging **Rough** shows **no** crisis takeover; no red-flag interaction.
  - Faces read well in **light + dark** and at **XXL Dynamic Type** (faces don't clip; labels legible).
  - (If seeded) mood edges still do **NOT** appear in **Insights** (unchanged suppression).

- [ ] **Step 3: Record observed behavior** in the review notes / ledger.

---

## Definition of Done

- The mood scale is three custom-drawn, subtly-colored faces (Rough · Okay · Good) on both surfaces (Home quick-check + capture-sheet tab); the system emoji are gone and `MoodLevel` carries no drawing/color.
- Mood events still write `category: .mood`, `subtype: "mood"`, `value: 1–3`; they render "Mood: Rough/Okay/Good" in the Timeline (with any out-of-range/orphaned value clamped, never a bare "Mood") and are deletable; logging never triggers the crisis/red-flag flow.
- The engine's low-mood mining is recalibrated to the 1–3 scale (`lowMoodThreshold = 1`: Rough is low, Okay is not); mood-outcome edges remain suppressed from Insights but stored.
- Core (`MoodLevel`, `clamping`, `EventDisplay`, threshold + `ExposureSourceTests`) unit-tested; the Home model tests stay green; `MoodFace` builds + previews; verified end-to-end.
- No data migration; no prediction/pre-fill, no forced check-ins/streaks, no stored "don't know"; no changes to the engine's structure, the crisis/red-flag flow, other extractors, or the Insights suppression. The positive "what lifts your mood" mining remains the committed next round.
