# Mental-Health Crisis Support Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a user deliberately logs "Thoughts of self-harm or suicide," show a warm, non-diagnostic 988 Suicide & Crisis Lifeline support takeover — the tonal opposite of the physical red-flag's 911 screen.

**Architecture:** Extends the merged red-flag system with a `.mentalHealthCrisis` category. Pure core adds the category + one rule + one catalog entry + a `mutableSymptomKeys` accessor (so crisis is never mutable). App layer adds a `CrisisContact` (988 URLs) and a separate warm `CrisisSupportView`; the existing app-level `.fullScreenCover` branches on `match.category`. The capture hook, presenter, and save-first ordering are unchanged.

**Tech Stack:** Swift, SwiftUI, GRDB, Swift Testing. Same pure-core / thin-app split as the red-flag cycle.

**Design doc:** `docs/superpowers/specs/2026-07-18-mental-health-crisis-flow-design.md`.

## Global Constraints

- **Warm, not red.** The crisis screen uses `HealthTheme.accent` (sage), never `HealthTheme.danger`. No alarm, no countdown. The physical red-flag screen is untouched.
- **No diagnostic or minimizing language.** Copy validates the act of logging and affirms support helps / hard moments can pass — never "it gets better," never asserts the person "has" a condition. The crisis copy is used VERBATIM from this plan.
- **988 facts:** the US Suicide & Crisis Lifeline is call **or** text **988**; `tel:988` dials, `sms:988` texts. 911 is the immediate-danger line. `CrisisContact.crisisNumber` is the single 988 regionalization point (never hardcode "988" at a call site).
- **Never mutable.** The crisis symptom is kept out of the Settings "Safety reminders" list (`RedFlagRemindersView` uses `mutableSymptomKeys`, which excludes `.mentalHealthCrisis`). The crisis screen has no "stop reminding me" affordance.
- **Event-driven, no persistent state.** Logging fires the screen once; later days do nothing. No "crisis mode" flag anywhere.
- **Capture-time only.** No text/voice scanning, no proactive detection. The trigger is the deliberate symptom log flowing through the existing `CaptureSheet.logged` → `RedFlagPresenter.consider` hook (unchanged).
- **Qualify `HealthGraphCore.SymptomCatalog`** in app-target source and dual-import tests (the app has a legacy `SymptomCatalog` that shadows it); package-only tests use the bare name.
- **App-target tests MUST run with `-parallel-testing-enabled NO`** (parallel sim clones fail to provision the CoreData container → spurious `failed (0.000s)`). The pre-existing `SwiftDataMigratorTests.migratesObjectsFromAvoidedCabinetAndProtocols` framework crash (passes in isolation) is unrelated.
- **App simulator:** iPhone 17 Pro (iOS 26.5).
- Build: package `cd HealthGraphCore && swift test`; app `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

---

## Verified interfaces (from the codebase, post-red-flag-merge)

- `RedFlagCategory` (`HealthGraphCore/Safety/RedFlagCatalog.swift`): currently `enum RedFlagCategory: Sendable, Equatable { case medicalEmergency }`.
- `RedFlagRule { symptomKeys: [String]; category: RedFlagCategory; extraGuidance: String? }`; `RedFlagMatch { symptomKey; category; extraGuidance }` (`Identifiable`, id == symptomKey).
- `RedFlagCatalog.rules: [RedFlagRule]`, `.rule(forSymptomKey:) -> RedFlagRule?`, `.allSymptomKeys: [String]`; private `key(_:) = SymptomCatalog.canonicalKey(for:)`.
- `RedFlagEvaluator.evaluate(symptomKey: String, mutedKeys: Set<String>) -> RedFlagMatch?` (pure, severity-independent).
- `RedFlagPresenter` (`Views/HealthOS/Safety/RedFlagPresenter.swift`): `@Published var pending: RedFlagMatch?`, `consider(_:)`, `dismiss()`, `mute(_:)`, `init(muteStore:)`. **Unchanged by this plan.**
- `RedFlagRemindersView.swift:13`: `RedFlagCatalog.allSymptomKeys.sorted { ... }` — the Settings list source to change.
- `FoodIntolerancesApp.swift:100-101`: `.fullScreenCover(item: $redFlagPresenter.pending) { match in RedFlagInterstitialView(match: match).environmentObject(redFlagPresenter) }` — the cover to branch.
- `SymptomCatalog` mental symptoms use `regionId "head"` (Anxiety/Stress/Depression at lines 25-29). `canonicalize("Thoughts of self-harm or suicide")` → `"thoughtsOfSelfHarmOrSuicide"`.
- `EmergencyContact.callURL` (`tel:911`) — reuse for the 911 line.
- `HealthTheme`: `accent` (0x2E7D74/0x4FA599), `onAccent` (white), `paper`, `ink`, `inkSecondary`, `cardCornerRadius`. No new token needed (crisis reuses `accent`).
- App test convention: `import Testing; @testable import Food_Intolerances; @MainActor struct` (for the store/presenter tests); isolated `UserDefaults(suiteName:)`.

---

### Task 1: Core — crisis category, rule, catalog entry, mute-exclusion accessor

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Safety/RedFlagCatalog.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomCatalog.swift` (one entry)
- Modify (test): `HealthGraphCore/Tests/HealthGraphCoreTests/SymptomCatalogTests.swift`
- Modify (test): `HealthGraphCore/Tests/HealthGraphCoreTests/RedFlagCatalogTests.swift`
- Modify (test): `HealthGraphCore/Tests/HealthGraphCoreTests/RedFlagEvaluatorTests.swift`

**Interfaces produced:**
- `RedFlagCategory.mentalHealthCrisis` (new case).
- `RedFlagCatalog.mutableSymptomKeys: [String]` — all red-flag keys whose category is NOT `.mentalHealthCrisis`.
- Catalog entry `"Thoughts of self-harm or suicide"` → key `"thoughtsOfSelfHarmOrSuicide"`, a crisis rule.

- [ ] **Step 1: Add the catalog entry.** In `SymptomCatalog.swift`, near the mental-health symptoms (after `("Cognitive Fog", "head"),` at line ~29), add:

```swift
        ("Thoughts of self-harm or suicide", "head"),
```

Then pin the key in `SymptomCatalogTests.swift` (alongside the existing literal-key assertions):

```swift
    @Test func selfHarmCrisisKeyIsStable() {
        #expect(SymptomCatalog.canonicalKey(for: "Thoughts of self-harm or suicide") == "thoughtsOfSelfHarmOrSuicide")
    }
```

- [ ] **Step 2: Write the failing catalog + evaluator tests.**

Add to `RedFlagCatalogTests.swift`:
```swift
    @Test func selfHarmRuleIsMentalHealthCrisis() {
        let key = SymptomCatalog.canonicalKey(for: "Thoughts of self-harm or suicide")
        let rule = RedFlagCatalog.rule(forSymptomKey: key)
        #expect(rule != nil)
        #expect(rule?.category == .mentalHealthCrisis)
    }

    @Test func crisisKeyIsNotMutableButIsARedFlag() {
        let key = SymptomCatalog.canonicalKey(for: "Thoughts of self-harm or suicide")
        #expect(RedFlagCatalog.allSymptomKeys.contains(key))       // it IS a red flag
        #expect(!RedFlagCatalog.mutableSymptomKeys.contains(key))  // but NEVER offered as a mute toggle
    }

    @Test func medicalKeysStayMutable() {
        let chestPain = SymptomCatalog.canonicalKey(for: "Chest Pain")
        #expect(RedFlagCatalog.mutableSymptomKeys.contains(chestPain))
    }
```

Add to `RedFlagEvaluatorTests.swift`:
```swift
    @Test func selfHarmSymptomIsAMentalHealthCrisisMatch() {
        let key = SymptomCatalog.canonicalKey(for: "Thoughts of self-harm or suicide")
        let match = RedFlagEvaluator.evaluate(symptomKey: key, mutedKeys: [])
        #expect(match?.category == .mentalHealthCrisis)
    }
```

- [ ] **Step 3: Run to verify they fail.**

Run: `cd HealthGraphCore && swift test --filter "RedFlag|SymptomCatalog" 2>&1 | tail -6`
Expected: FAIL — `.mentalHealthCrisis` / `mutableSymptomKeys` / the entry don't exist yet.

- [ ] **Step 4: Implement in `RedFlagCatalog.swift`.** Add the enum case:

```swift
public enum RedFlagCategory: Sendable, Equatable {
    case medicalEmergency
    case mentalHealthCrisis
}
```

Add the crisis rule to `rules` (after the anaphylaxis rule):
```swift
        RedFlagRule(
            symptomKeys: [key("Thoughts of self-harm or suicide")],
            category: .mentalHealthCrisis,
            extraGuidance: nil),
```

Add the accessor (next to `allSymptomKeys`):
```swift
    /// Red-flag keys that MAY be muted in Settings — excludes `.mentalHealthCrisis`.
    /// A crisis prompt is never suppressible (design §6); it must not appear as a toggle.
    public static var mutableSymptomKeys: [String] {
        rules.filter { $0.category != .mentalHealthCrisis }.flatMap(\.symptomKeys)
    }
```

- [ ] **Step 5: Run to verify they pass, then the full package suite.**

Run: `cd HealthGraphCore && swift test --filter "RedFlag|SymptomCatalog" 2>&1 | tail -6` → PASS.
Run: `cd HealthGraphCore && swift test 2>&1 | tail -3` → full suite passes (was 213; +4 new).

- [ ] **Step 6: Commit.**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Safety/RedFlagCatalog.swift" \
        "HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomCatalog.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/SymptomCatalogTests.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/RedFlagCatalogTests.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/RedFlagEvaluatorTests.swift"
git commit -m "feat(core): mental-health-crisis red-flag category + self-harm symptom + mutableSymptomKeys"
```

---

### Task 2: CrisisContact (988) + keep crisis out of the mute list

**Files:**
- Create: `Views/HealthOS/Safety/CrisisContact.swift`
- Modify: `Views/HealthOS/Safety/RedFlagRemindersView.swift:13` (`allSymptomKeys` → `mutableSymptomKeys`)
- Test: `Food IntolerancesTests/CrisisContactTests.swift`

**Interfaces:**
- Consumes: `RedFlagCatalog.mutableSymptomKeys` (Task 1).
- Produces: `enum CrisisContact` with `crisisNumber: String`, `call988URL: URL?`, `text988URL: URL?`.

- [ ] **Step 1: Write the failing test.** `CrisisContactTests.swift`:

```swift
import Testing
@testable import Food_Intolerances

struct CrisisContactTests {
    @Test func callAndTextUseThe988Constant() {
        #expect(CrisisContact.crisisNumber == "988")
        #expect(CrisisContact.call988URL?.absoluteString == "tel:988")
        #expect(CrisisContact.text988URL?.absoluteString == "sms:988")
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/CrisisContactTests" -parallel-testing-enabled NO 2>&1 | tail -6`
Expected: FAIL (compile error — `CrisisContact` undefined).

- [ ] **Step 3: Implement `CrisisContact.swift`.**

```swift
import Foundation

/// Crisis-line contact for the mental-health support flow. `crisisNumber` is the single
/// place to regionalize later — 988 is the US Suicide & Crisis Lifeline (call or text).
enum CrisisContact {
    static let crisisNumber = "988"                 // US 988 Suicide & Crisis Lifeline. Regionalize here.
    static var call988URL: URL? { URL(string: "tel:\(crisisNumber)") }
    static var text988URL: URL? { URL(string: "sms:\(crisisNumber)") }
}
```

- [ ] **Step 4: Keep crisis out of the mute list.** In `RedFlagRemindersView.swift`, change the key source (line ~13) from `allSymptomKeys` to `mutableSymptomKeys`:

```swift
        RedFlagCatalog.mutableSymptomKeys.sorted {
```

(Everything else in that computed `keys` property stays the same.)

- [ ] **Step 5: Run to verify the test passes + app builds.**

Run the Step 2 command → PASS.
Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -8` → build succeeds (the RedFlagRemindersView change compiles).

- [ ] **Step 6: Commit.**

```bash
git add "Views/HealthOS/Safety/CrisisContact.swift" "Views/HealthOS/Safety/RedFlagRemindersView.swift" \
        "Food IntolerancesTests/CrisisContactTests.swift"
git commit -m "feat(app): CrisisContact (988 call/text) + exclude crisis symptom from mute list"
```

---

### Task 3: CrisisSupportView (the warm 988 screen)

**Files:**
- Create: `Views/HealthOS/Safety/CrisisSupportView.swift`

**Interfaces:**
- Consumes: `RedFlagPresenter` (env object, `dismiss()`), `CrisisContact.call988URL/text988URL` (Task 2), `EmergencyContact.callURL`, `HealthTheme`.
- Produces: `struct CrisisSupportView: View` (no init params; reads `RedFlagPresenter` from the environment).

*View task — build + preview verified (no snapshot infra). Copy is VERBATIM from the plan.*

- [ ] **Step 1: Implement `CrisisSupportView.swift`.**

```swift
import SwiftUI
import UIKit

/// Warm "you're not alone" crisis-support takeover, shown when a self-harm / suicide
/// symptom is logged. Tonal opposite of RedFlagInterstitialView: calm, sage `accent`
/// (never `danger`/red), 988 not 911. Presented from the app anchor via the
/// category-routed `.fullScreenCover` (see FoodIntolerancesApp). No mute affordance.
struct CrisisSupportView: View {
    @EnvironmentObject private var presenter: RedFlagPresenter
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("You're not alone")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(HealthTheme.ink)

                Text("Thank you for noticing this and writing it down — that takes real strength. If you're thinking about harming yourself, talking to someone can help, and hard moments can pass. The **988 Suicide & Crisis Lifeline** has trained counselors, free and confidential, any time.")
                    .font(.body).foregroundStyle(HealthTheme.ink)

                VStack(spacing: 12) {
                    Button { if let url = CrisisContact.call988URL { openURL(url) } } label: {
                        Text("Call 988").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .foregroundStyle(HealthTheme.onAccent)
                    .background(HealthTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius))
                    .accessibilityLabel("Call nine eight eight")

                    Button { if let url = CrisisContact.text988URL { openURL(url) } } label: {
                        Text("Text 988").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .foregroundStyle(HealthTheme.accent)
                    .overlay(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius)
                        .strokeBorder(HealthTheme.accent, lineWidth: 1.5))
                    .accessibilityLabel("Text nine eight eight")
                }

                Button { if let url = EmergencyContact.callURL { openURL(url) } } label: {
                    Text("If you're in immediate danger, call 911")
                        .font(.footnote).foregroundStyle(HealthTheme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(minHeight: 44)
                .accessibilityLabel("If you're in immediate danger, call nine one one")

                Button("I'm okay for now") { presenter.dismiss() }
                    .font(.body).foregroundStyle(HealthTheme.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 4)
            }
            .padding(24)
        }
        .background(HealthTheme.paper.ignoresSafeArea())
        .onAppear {
            UIAccessibility.post(notification: .screenChanged,
                                 argument: "You're not alone. Support is available — call or text 988.")
        }
    }
}

#Preview("Crisis — light") {
    CrisisSupportView()
        .environmentObject(RedFlagPresenter(muteStore: RedFlagMuteStore()))
        .preferredColorScheme(.light)
}

#Preview("Crisis — dark") {
    CrisisSupportView()
        .environmentObject(RedFlagPresenter(muteStore: RedFlagMuteStore()))
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build + confirm previews.**

Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -8`
Expected: build succeeds. Confirm both previews render — warm sage "Call 988" (NOT red), outlined "Text 988", the quiet 911 line, the gentle "I'm okay for now".

- [ ] **Step 3: Commit.**

```bash
git add "Views/HealthOS/Safety/CrisisSupportView.swift"
git commit -m "feat(app): CrisisSupportView — warm 988 crisis-support takeover"
```

---

### Task 4: Route the cover on category

**Files:**
- Modify: `FoodIntolerancesApp.swift:100-101`

**Interfaces:**
- Consumes: `RedFlagInterstitialView` (existing), `CrisisSupportView` (Task 3), `RedFlagMatch.category`.

*Integration — build + regression verified; behavior in Task 5.*

- [ ] **Step 1: Branch the app-level cover on `match.category`.** Replace the current cover closure (`FoodIntolerancesApp.swift:100-103`):

```swift
                .fullScreenCover(item: $redFlagPresenter.pending) { match in
                    switch match.category {
                    case .medicalEmergency:
                        RedFlagInterstitialView(match: match)
                            .environmentObject(redFlagPresenter)
                    case .mentalHealthCrisis:
                        CrisisSupportView()
                            .environmentObject(redFlagPresenter)
                    }
                }
```

- [ ] **Step 2: Build.**

Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -8`
Expected: build succeeds (the `switch` is now exhaustive over both categories).

- [ ] **Step 3: Confirm no regression.**

Run: `cd HealthGraphCore && swift test 2>&1 | tail -3` → package suite green.
Run: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/RedFlagPresenterTests" -only-testing:"Food IntolerancesTests/RedFlagMuteStoreTests" -only-testing:"Food IntolerancesTests/CrisisContactTests" -parallel-testing-enabled NO 2>&1 | grep -E "Test run with|TEST (SUCCEEDED|FAILED)" | tail -3` → all green.

- [ ] **Step 4: Commit.**

```bash
git add "FoodIntolerancesApp.swift"
git commit -m "feat(app): route red-flag cover on category — crisis → CrisisSupportView"
```

---

### Task 5: End-to-end verification + regression

**Files:** none (verification).

- [ ] **Step 1: Full regression.**
  - `cd HealthGraphCore && swift test 2>&1 | tail -3` → all green (incl. the new crisis tests).
  - App target: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "✔ Suite|✘|Test run with|\*\* TEST"` → every suite green except the known pre-existing `SwiftDataMigratorTests.migratesObjectsFromAvoidedCabinetAndProtocols` crash (passes in isolation).
  - App build succeeds.

- [ ] **Step 2: On-device / simulator behavior check** (device preferred). Drive it and confirm:
  - Capture ➕ → Symptom → search "self" / "harm" → **Thoughts of self-harm or suicide** → set severity → the **warm "You're not alone" screen** appears (sage, NOT red).
  - **Call 988** opens the dialer to 988; **Text 988** opens Messages to 988; the **911** line opens the dialer to 911; **"I'm okay for now"** returns to the app.
  - The symptom is **saved** (visible in Timeline) and **deletable**.
  - **Health → Safety reminders** does **NOT** list the crisis symptom (only the medical red-flags have toggles).
  - Log it **again** → the screen shows again (not mutable, no lingering state); a normal Headache log shows no crisis screen.
  - Logging **Chest Pain** still shows the **red** medical screen (the medical branch is unregressed).
  - VoiceOver announces the crisis screen on appear; light + dark correct; XXL Dynamic Type scrolls without clipping.

- [ ] **Step 3: Record observed behavior** in the review notes / ledger.

---

## Definition of Done

- Logging "Thoughts of self-harm or suicide" (severity-independent, capture-time) shows a warm, non-diagnostic 988 support takeover — Call 988 / Text 988 / the 911 line / a gentle close — visually distinct from the red medical screen.
- The crisis symptom is a normal saved (deletable) event; it never appears in the Settings mute list and has no mute affordance; it always shows; no persistent state.
- The physical red-flag flow is unchanged and unregressed; the cover routes correctly on category.
- Core (category/rule/entry/mutableSymptomKeys) unit-tested; `CrisisContact` unit-tested; views build + preview; verified end-to-end on device.
- No text/voice scanning, no proactive detection, no harm-to-others, no evidence-engine/migration changes. Mood/recovery tracking remains the committed next round.
