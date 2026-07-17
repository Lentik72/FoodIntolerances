# Red-Flag Safety Interstitial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a user logs a symptom on a fixed red-flag list, take over the screen with a non-diagnostic "seek care now" interstitial instead of the normal save-and-continue flow.

**Architecture:** A pure, deterministic red-flag evaluator in `HealthGraphCore` (a static table + a severity-independent lookup), plus a thin app layer — a full-screen SwiftUI takeover presented from the root, an opt-in per-symptom mute store, and a Settings toggle list. The trigger hooks the single interactive symptom-capture choke point (`CaptureSheet.logged`), never the data layer, so import/backfill/edits can't fire it.

**Tech Stack:** Swift, SwiftUI, GRDB, Swift Testing (`import Testing`). Same pure-core / thin-app split as Phase 2A/2B.

**Design doc:** `docs/superpowers/specs/2026-07-17-red-flag-safety-interstitial-design.md`.

## Global Constraints

- **Swift Testing** everywhere (`import Testing`, `@Test`, `#expect`). Package tests: `@testable import HealthGraphCore`, `try AppDatabase.inMemory()`. App tests (`Food IntolerancesTests/`): `import HealthGraphCore` + `@testable import Food_Intolerances`, `@MainActor struct`, inject an isolated `UserDefaults(suiteName:)` rather than `.standard`.
- **App-target tests MUST run with `-parallel-testing-enabled NO`** (parallel sim clones fail to provision the CoreData container → spurious `failed (0.000s)`; documented in `SwiftDataMigratorTests.swift`). One pre-existing unrelated crash there (`migratesObjectsFromAvoidedCabinetAndProtocols`) is a known framework issue — not this feature.
- **Severity-independent trigger:** the evaluator takes **no** severity parameter. A red-flag symptom fires regardless of the logged 1–10 severity.
- **Physical emergencies only this cycle.** Red-flag set: Chest Pain, Lower Chest Pain, Chest Tightness, Upper Chest Tightness, Breathing Difficulty, Shortness of Breath (already in `SymptomCatalog`) + a **new** "Severe Allergic Reaction" entry. No self-harm / mental-health crisis (its own future round).
- **No causal / diagnostic language.** The interstitial says symptoms "can be" serious and "this isn't a diagnosis." Never asserts the user has a condition.
- **Emergency number is one regionalizable constant** (`EmergencyContact.emergencyNumber = "911"`), never hardcoded at call sites.
- **Fire only on live, interactive symptom logs** — the hook lives in `CaptureSheet.logged(_:)` (UI layer), filtered to `event.category == .symptom`. Never in `EventStore.save` / import / backfill / HealthKit sync / edits.
- **Mute state is app preference (UserDefaults), never health-graph data.** It never enters the event graph, never syncs, never appears in a report.
- **Visual language:** reuse `HealthTheme` tokens + `hgCard()`; the interstitial adds one new `HealthTheme.danger` token (red primary action). 44pt tap targets, Dynamic Type, VoiceOver, light + dark; never color alone.
- **App simulator:** iPhone 17 Pro (iOS 26.5); iPhone 16 Pro is not installed.
- Build: package `cd HealthGraphCore && swift test`; app `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

---

## Verified interfaces (from the codebase)

- `SymptomCatalog` (`HealthGraphCore/.../Capture/SymptomCatalog.swift`): `public static func canonicalKey(for displayName: String) -> String` (lower-camel-cases: "Chest Pain" → `"chestPain"`, "Severe Allergic Reaction" → `"severeAllergicReaction"`); `public static func displayName(for canonicalKey: String) -> String`; `public static let all: [SymptomDefinition]`. `raw: [(String, String)]` is `(displayName, regionId)`; region ids are anatomical, `"torso"` is the catch-all (used for "Fatigue", "Other").
- `HealthEvent` init: `HealthEvent(timestamp:, category:, subtype:, value:, unit:, source:, ...)` — a symptom is `category: .symptom`, `subtype: <canonicalKey>`, `source: .manual` (`EventCategory.symptom`, `EventSource.manual`).
- `CaptureSheet` (`Views/HealthOS/Capture/CaptureSheet.swift`): `@EnvironmentObject private var coordinator: CaptureCoordinator`; `private func logged(_ event: HealthEvent)` is the choke point called by every capture subview via `onLogged`.
- `HealthOSRootView` (`Views/HealthOS/Shell/HealthOSRootView.swift`): tab shell with `@State private var showingCapture`; presents `.sheet(isPresented: $showingCapture) { CaptureSheet() }`. No `.fullScreenCover` exists yet.
- `FoodIntolerancesApp.swift`: `@StateObject`s (incl. `captureCoordinator = CaptureCoordinator()`) injected onto `HealthOSRootView()` via `.environmentObject(...)`.
- `HealthTheme` (`Views/HealthOS/Theme/HealthTheme.swift`): `dyn(light:dark:)`, `paper/card/cardBorder/ink/inkSecondary/accent/onAccent`, `screenTitle()`, `cardCornerRadius`, `hgCard()`. No danger token yet.
- `HealthTabView` (`Views/HealthOS/Health/HealthTabView.swift`): the HealthOS "Health" tab; where the "Health Graph Debug" `NavigationLink` row lives — the home for a new "Safety reminders" row.
- App test convention: `import Testing; import HealthGraphCore; @testable import Food_Intolerances; @MainActor struct ...`.

---

### Task 1: Red-flag catalog + evaluator (pure core) + catalog entry

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Safety/RedFlagCatalog.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Safety/RedFlagEvaluator.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomCatalog.swift` (add one `raw` entry)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/RedFlagEvaluatorTests.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/RedFlagCatalogTests.swift`

**Interfaces produced (later tasks depend on these exact names):**
- `RedFlagCategory` — `enum { case medicalEmergency }`.
- `RedFlagRule { symptomKeys: [String]; category: RedFlagCategory; extraGuidance: String? }`.
- `RedFlagMatch { symptomKey: String; category: RedFlagCategory; extraGuidance: String? }` (`Identifiable`, `id == symptomKey`).
- `RedFlagCatalog.rules: [RedFlagRule]`, `RedFlagCatalog.rule(forSymptomKey:) -> RedFlagRule?`, `RedFlagCatalog.allSymptomKeys: [String]`.
- `RedFlagEvaluator.evaluate(symptomKey: String, mutedKeys: Set<String>) -> RedFlagMatch?`.

- [ ] **Step 1: Add the "Severe Allergic Reaction" catalog entry.** In `SymptomCatalog.swift`, in the `raw` array near the `// Other` entry (`("Other", "torso")`), add:

```swift
        ("Severe Allergic Reaction", "torso"),
```

(Use `"torso"` — the existing catch-all region for whole-body symptoms like "Fatigue"/"Other"; no new region id, so the body-map UI needs no changes.)

- [ ] **Step 2: Write the failing evaluator + catalog tests.**

`RedFlagCatalogTests.swift`:
```swift
import Testing
@testable import HealthGraphCore

struct RedFlagCatalogTests {
    @Test func everyRuleKeyResolvesToARealSymptom() {
        // Drift guard: if a display name is renamed, its derived key must still exist in the catalog.
        let catalogKeys = Set(SymptomCatalog.all.map(\.canonicalKey))
        for key in RedFlagCatalog.allSymptomKeys {
            #expect(catalogKeys.contains(key), "red-flag key \(key) is not in SymptomCatalog")
        }
    }

    @Test func severeAllergicReactionExistsWithEpinephrineGuidance() {
        let key = SymptomCatalog.canonicalKey(for: "Severe Allergic Reaction")
        #expect(SymptomCatalog.all.contains { $0.canonicalKey == key })
        let rule = RedFlagCatalog.rule(forSymptomKey: key)
        #expect(rule?.extraGuidance?.contains("epinephrine") == true)
    }

    @Test func cardiacRespiratoryRulesHaveNoExtraGuidance() {
        let key = SymptomCatalog.canonicalKey(for: "Chest Pain")
        #expect(RedFlagCatalog.rule(forSymptomKey: key)?.extraGuidance == nil)
    }
}
```

`RedFlagEvaluatorTests.swift`:
```swift
import Testing
@testable import HealthGraphCore

struct RedFlagEvaluatorTests {
    private var chestPain: String { SymptomCatalog.canonicalKey(for: "Chest Pain") }

    @Test func redFlagKeyMatches() {
        let match = RedFlagEvaluator.evaluate(symptomKey: chestPain, mutedKeys: [])
        #expect(match?.symptomKey == chestPain)
        #expect(match?.category == .medicalEmergency)
    }

    @Test func nonRedFlagKeyDoesNotMatch() {
        let headache = SymptomCatalog.canonicalKey(for: "Headache")
        #expect(RedFlagEvaluator.evaluate(symptomKey: headache, mutedKeys: []) == nil)
    }

    @Test func mutedKeyDoesNotMatch() {
        #expect(RedFlagEvaluator.evaluate(symptomKey: chestPain, mutedKeys: [chestPain]) == nil)
    }

    @Test func anaphylaxisCarriesEpinephrineGuidance() {
        let key = SymptomCatalog.canonicalKey(for: "Severe Allergic Reaction")
        #expect(RedFlagEvaluator.evaluate(symptomKey: key, mutedKeys: [])?.extraGuidance?.contains("EpiPen") == true)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail.**

Run: `cd HealthGraphCore && swift test --filter RedFlag 2>&1 | tail -5`
Expected: FAIL — `RedFlagCatalog` / `RedFlagEvaluator` don't exist yet (compile error).

- [ ] **Step 4: Implement `RedFlagCatalog.swift`.**

```swift
import Foundation

/// The category of a red flag — determines the guidance surfaced. This cycle is
/// physical medical emergencies only; the enum leaves room for `.mentalHealthCrisis`.
public enum RedFlagCategory: Sendable, Equatable {
    case medicalEmergency
}

public struct RedFlagRule: Sendable, Equatable {
    public let symptomKeys: [String]      // SymptomCatalog canonicalKeys
    public let category: RedFlagCategory
    public let extraGuidance: String?     // e.g. anaphylaxis epinephrine line; nil otherwise
    public init(symptomKeys: [String], category: RedFlagCategory, extraGuidance: String?) {
        self.symptomKeys = symptomKeys
        self.category = category
        self.extraGuidance = extraGuidance
    }
}

public struct RedFlagMatch: Sendable, Equatable, Identifiable {
    public let symptomKey: String
    public let category: RedFlagCategory
    public let extraGuidance: String?
    public var id: String { symptomKey }
    public init(symptomKey: String, category: RedFlagCategory, extraGuidance: String?) {
        self.symptomKey = symptomKey
        self.category = category
        self.extraGuidance = extraGuidance
    }
}

/// The static red-flag table. Keys are DERIVED from SymptomCatalog display names
/// (single source of truth) so a rename can't silently drift a rule out of sync —
/// RedFlagCatalogTests.everyRuleKeyResolvesToARealSymptom guards that.
public enum RedFlagCatalog {
    private static func key(_ displayName: String) -> String {
        SymptomCatalog.canonicalKey(for: displayName)
    }

    public static let rules: [RedFlagRule] = [
        RedFlagRule(
            symptomKeys: ["Chest Pain", "Lower Chest Pain", "Chest Tightness",
                          "Upper Chest Tightness", "Breathing Difficulty", "Shortness of Breath"].map(key),
            category: .medicalEmergency,
            extraGuidance: nil),
        RedFlagRule(
            symptomKeys: [key("Severe Allergic Reaction")],
            category: .medicalEmergency,
            extraGuidance: "If you have an epinephrine auto-injector (EpiPen), use it now, then call 911."),
    ]

    public static func rule(forSymptomKey symptomKey: String) -> RedFlagRule? {
        rules.first { $0.symptomKeys.contains(symptomKey) }
    }

    /// Every red-flag symptom key, across all rules — used by the Settings list.
    public static var allSymptomKeys: [String] { rules.flatMap(\.symptomKeys) }
}
```

- [ ] **Step 5: Implement `RedFlagEvaluator.swift`.**

```swift
import Foundation

/// Pure, deterministic, severity-independent. Returns a match iff `symptomKey`
/// is a red flag AND not in `mutedKeys`. No Date(), no I/O, no severity input.
public enum RedFlagEvaluator {
    public static func evaluate(symptomKey: String, mutedKeys: Set<String>) -> RedFlagMatch? {
        guard !mutedKeys.contains(symptomKey),
              let rule = RedFlagCatalog.rule(forSymptomKey: symptomKey) else { return nil }
        return RedFlagMatch(symptomKey: symptomKey, category: rule.category, extraGuidance: rule.extraGuidance)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass, then the full package suite.**

Run: `cd HealthGraphCore && swift test --filter RedFlag 2>&1 | tail -5` → PASS.
Run: `cd HealthGraphCore && swift test 2>&1 | tail -3` → the full suite passes (existing + new).

- [ ] **Step 7: Commit.**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Safety/RedFlagCatalog.swift" \
        "HealthGraphCore/Sources/HealthGraphCore/Safety/RedFlagEvaluator.swift" \
        "HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomCatalog.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/RedFlagEvaluatorTests.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/RedFlagCatalogTests.swift"
git commit -m "feat(core): red-flag catalog + severity-independent evaluator + anaphylaxis symptom"
```

---

### Task 2: RedFlagMuteStore (app persistence primitive)

**Files:**
- Create: `Views/HealthOS/Safety/RedFlagMuteStore.swift`
- Test: `Food IntolerancesTests/RedFlagMuteStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `protocol RedFlagMuteStoring` (`var mutedKeys: Set<String> { get }`, `mute(_:)`, `unmute(_:)`, `isMuted(_:) -> Bool`); `final class RedFlagMuteStore: RedFlagMuteStoring, ObservableObject` with `@Published private(set) var mutedKeys`, `init(defaults: UserDefaults = .standard)`.

- [ ] **Step 1: Write the failing test.** `RedFlagMuteStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Food_Intolerances

@MainActor
struct RedFlagMuteStoreTests {
    private func isolatedStore() -> RedFlagMuteStore {
        let suite = "redflag-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return RedFlagMuteStore(defaults: defaults)
    }

    @Test func muteThenUnmute() {
        let store = isolatedStore()
        #expect(store.isMuted("chestPain") == false)
        store.mute("chestPain")
        #expect(store.isMuted("chestPain") == true)
        #expect(store.mutedKeys == ["chestPain"])
        store.unmute("chestPain")
        #expect(store.isMuted("chestPain") == false)
    }

    @Test func persistsAcrossInstances() {
        let suite = "redflag-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        RedFlagMuteStore(defaults: defaults).mute("shortnessOfBreath")
        let reloaded = RedFlagMuteStore(defaults: defaults)
        #expect(reloaded.isMuted("shortnessOfBreath") == true)
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/RedFlagMuteStoreTests" -parallel-testing-enabled NO 2>&1 | tail -8`
Expected: FAIL (compile error — `RedFlagMuteStore` undefined).

- [ ] **Step 3: Implement `RedFlagMuteStore.swift`.**

```swift
import Foundation

/// Which red-flag reminders the user has turned off. App preference state — never
/// health-graph data, never synced, never in a report.
protocol RedFlagMuteStoring: AnyObject {
    var mutedKeys: Set<String> { get }
    func mute(_ key: String)
    func unmute(_ key: String)
    func isMuted(_ key: String) -> Bool
}

@MainActor
final class RedFlagMuteStore: RedFlagMuteStoring, ObservableObject {
    @Published private(set) var mutedKeys: Set<String>
    private let defaults: UserDefaults
    private let storageKey = "redflag.mutedKeys"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mutedKeys = Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    func mute(_ key: String) { mutedKeys.insert(key); persist() }
    func unmute(_ key: String) { mutedKeys.remove(key); persist() }
    func isMuted(_ key: String) -> Bool { mutedKeys.contains(key) }

    private func persist() { defaults.set(Array(mutedKeys), forKey: storageKey) }
}
```

- [ ] **Step 4: Run to verify it passes.**

Run the Step 2 command → PASS (both tests).

- [ ] **Step 5: Commit.**

```bash
git add "Views/HealthOS/Safety/RedFlagMuteStore.swift" "Food IntolerancesTests/RedFlagMuteStoreTests.swift"
git commit -m "feat(app): RedFlagMuteStore — per-symptom mute persistence (UserDefaults)"
```

---

### Task 3: RedFlagPresenter (app — the hook decision + presentation state)

**Files:**
- Create: `Views/HealthOS/Safety/RedFlagPresenter.swift`
- Test: `Food IntolerancesTests/RedFlagPresenterTests.swift`

**Interfaces:**
- Consumes: `RedFlagEvaluator.evaluate(symptomKey:mutedKeys:)` (Task 1), `RedFlagMuteStore` / `RedFlagMuteStoring` (Task 2), `HealthEvent` / `RedFlagMatch`.
- Produces: `final class RedFlagPresenter: ObservableObject` (`@MainActor`), `@Published var pending: RedFlagMatch?`, `let muteStore: RedFlagMuteStore`, `init(muteStore:)`, `func consider(_ event: HealthEvent)`, `func dismiss()`, `func mute(_ key: String)`.

- [ ] **Step 1: Write the failing test.** `RedFlagPresenterTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct RedFlagPresenterTests {
    private func presenter(mutedKeys: [String] = []) -> RedFlagPresenter {
        let store = RedFlagMuteStore(defaults: UserDefaults(suiteName: "rf-\(UUID().uuidString)")!)
        mutedKeys.forEach(store.mute)
        return RedFlagPresenter(muteStore: store)
    }
    private func symptom(_ displayName: String) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                    category: .symptom, subtype: SymptomCatalog.canonicalKey(for: displayName),
                    source: .manual)
    }

    @Test func redFlagSymptomSetsPending() {
        let p = presenter()
        p.consider(symptom("Chest Pain"))
        #expect(p.pending?.symptomKey == SymptomCatalog.canonicalKey(for: "Chest Pain"))
    }

    @Test func nonRedFlagSymptomLeavesPendingNil() {
        let p = presenter()
        p.consider(symptom("Headache"))
        #expect(p.pending == nil)
    }

    @Test func mutedRedFlagLeavesPendingNil() {
        let p = presenter(mutedKeys: [SymptomCatalog.canonicalKey(for: "Chest Pain")])
        p.consider(symptom("Chest Pain"))
        #expect(p.pending == nil)
    }

    @Test func nonSymptomEventIgnored() {
        let p = presenter()
        p.consider(HealthEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                               category: .food, subtype: "dairy", source: .manual))
        #expect(p.pending == nil)
    }

    @Test func muteClearsPendingAndPersists() {
        let p = presenter()
        p.consider(symptom("Chest Pain"))
        p.mute(SymptomCatalog.canonicalKey(for: "Chest Pain"))
        #expect(p.pending == nil)
        #expect(p.muteStore.isMuted(SymptomCatalog.canonicalKey(for: "Chest Pain")) == true)
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/RedFlagPresenterTests" -parallel-testing-enabled NO 2>&1 | tail -8`
Expected: FAIL (compile error — `RedFlagPresenter` undefined).

- [ ] **Step 3: Implement `RedFlagPresenter.swift`.**

```swift
import Foundation
import HealthGraphCore

/// Holds the pending red-flag takeover and bridges a just-saved symptom to the
/// interstitial. Owns nothing but the presentation decision; the pure evaluator
/// decides, the mute store persists.
@MainActor
final class RedFlagPresenter: ObservableObject {
    @Published var pending: RedFlagMatch?
    let muteStore: RedFlagMuteStore

    init(muteStore: RedFlagMuteStore) { self.muteStore = muteStore }

    /// Evaluate a just-saved event. Sets `pending` only on a fresh, unmuted red-flag
    /// symptom; never clears an already-showing takeover.
    func consider(_ event: HealthEvent) {
        guard event.category == .symptom, let key = event.subtype else { return }
        if let match = RedFlagEvaluator.evaluate(symptomKey: key, mutedKeys: muteStore.mutedKeys) {
            pending = match
        }
    }

    func dismiss() { pending = nil }

    func mute(_ key: String) { muteStore.mute(key); pending = nil }
}
```

- [ ] **Step 4: Run to verify it passes.** Step 2 command → PASS (all 5 tests).

- [ ] **Step 5: Commit.**

```bash
git add "Views/HealthOS/Safety/RedFlagPresenter.swift" "Food IntolerancesTests/RedFlagPresenterTests.swift"
git commit -m "feat(app): RedFlagPresenter — symptom→takeover decision + mute/dismiss"
```

---

### Task 4: EmergencyContact + HealthTheme danger token (app view primitives)

**Files:**
- Create: `Views/HealthOS/Safety/EmergencyContact.swift`
- Modify: `Views/HealthOS/Theme/HealthTheme.swift` (add `danger` / `onDanger`)
- Test: `Food IntolerancesTests/EmergencyContactTests.swift`

**Interfaces:**
- Produces: `enum EmergencyContact` with `static let emergencyNumber: String`, `static var callURL: URL?`, `static var nearestERURL: URL?`; `HealthTheme.danger`, `HealthTheme.onDanger`.

- [ ] **Step 1: Write the failing test.** `EmergencyContactTests.swift`:

```swift
import Testing
@testable import Food_Intolerances

struct EmergencyContactTests {
    @Test func callURLUsesTheEmergencyNumberConstant() {
        #expect(EmergencyContact.callURL?.absoluteString == "tel://\(EmergencyContact.emergencyNumber)")
        #expect(EmergencyContact.emergencyNumber == "911")
    }

    @Test func nearestERSearchesMaps() {
        let s = EmergencyContact.nearestERURL?.absoluteString ?? ""
        #expect(s.contains("maps.apple.com"))
        #expect(s.contains("emergency"))
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/EmergencyContactTests" -parallel-testing-enabled NO 2>&1 | tail -8`
Expected: FAIL (compile error — `EmergencyContact` undefined).

- [ ] **Step 3: Implement `EmergencyContact.swift`.**

```swift
import Foundation

/// Emergency dialing + nearest-ER lookup. `emergencyNumber` is the single place to
/// regionalize later — never hardcode a number at a call site.
enum EmergencyContact {
    static let emergencyNumber = "911"          // US. Regionalize here.
    static var callURL: URL? { URL(string: "tel://\(emergencyNumber)") }
    static var nearestERURL: URL? { URL(string: "https://maps.apple.com/?q=emergency+room") }
}
```

- [ ] **Step 4: Add the danger token.** In `HealthTheme.swift`, right after the `onAccent` line (`static let onAccent = dyn(light: 0xFFFFFF, dark: 0xFFFFFF)`), add:

```swift
    /// Urgent/emergency action fill — the red-flag "Call 911" primary. Reuses the
    /// severe-severity terracotta for palette consistency. Emergencies ONLY.
    static let danger   = dyn(light: 0xC0442E, dark: 0xD65C44)
    static let onDanger = dyn(light: 0xFFFFFF, dark: 0xFFFFFF)
```

- [ ] **Step 5: Run to verify it passes + app still builds.**

Run the Step 2 command → PASS.
Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -10` → build succeeds.

- [ ] **Step 6: Commit.**

```bash
git add "Views/HealthOS/Safety/EmergencyContact.swift" "Views/HealthOS/Theme/HealthTheme.swift" \
        "Food IntolerancesTests/EmergencyContactTests.swift"
git commit -m "feat(app): EmergencyContact (tel/maps URLs) + HealthTheme.danger token"
```

---

### Task 5: RedFlagInterstitialView (the takeover UI)

**Files:**
- Create: `Views/HealthOS/Safety/RedFlagInterstitialView.swift`

**Interfaces:**
- Consumes: `RedFlagMatch` (Task 1), `RedFlagPresenter` (Task 3), `EmergencyContact` + `HealthTheme.danger/onDanger` (Task 4), `SymptomCatalog.displayName(for:)`.
- Produces: `struct RedFlagInterstitialView: View` taking `let match: RedFlagMatch` and reading `@EnvironmentObject var presenter: RedFlagPresenter`.

*This is a view — no unit test (no snapshot infra, same as Phase 2B). Verified by build + previews.*

- [ ] **Step 1: Implement `RedFlagInterstitialView.swift`.**

```swift
import SwiftUI
import HealthGraphCore

/// Full-screen "seek care now" takeover. Non-diagnostic. Presented from the root
/// via .fullScreenCover so it sits above every tab and sheet (see HealthOSRootView).
struct RedFlagInterstitialView: View {
    let match: RedFlagMatch
    @EnvironmentObject private var presenter: RedFlagPresenter
    @Environment(\.openURL) private var openURL
    @State private var confirmingMute = false

    private var symptomName: String { SymptomCatalog.displayName(for: match.symptomKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("This could be serious")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(HealthTheme.ink)

                Text("You just logged **\(symptomName)**. Symptoms like this can be a medical emergency. If it's severe, came on suddenly, or is getting worse, call 911 or get emergency care now.")
                    .font(.body).foregroundStyle(HealthTheme.ink)

                if let guidance = match.extraGuidance {
                    Text(guidance)
                        .font(.headline).foregroundStyle(HealthTheme.danger)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HealthTheme.danger.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius))
                }

                Text("This isn't medical advice or a diagnosis — when in doubt, get checked.")
                    .font(.footnote).foregroundStyle(HealthTheme.inkSecondary)

                VStack(spacing: 12) {
                    Button { if let url = EmergencyContact.callURL { openURL(url) } } label: {
                        Text("Call 911").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .foregroundStyle(HealthTheme.onDanger)
                    .background(HealthTheme.danger)
                    .clipShape(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius))
                    .accessibilityLabel("Call nine one one")

                    Button { if let url = EmergencyContact.nearestERURL { openURL(url) } } label: {
                        Text("Find nearest ER").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .foregroundStyle(HealthTheme.accent)
                    .overlay(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius)
                        .strokeBorder(HealthTheme.accent, lineWidth: 1.5))

                    Button("I'm okay — dismiss") { presenter.dismiss() }
                        .font(.body).foregroundStyle(HealthTheme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }

                Button("Stop reminding me about \(symptomName)") { confirmingMute = true }
                    .font(.footnote).foregroundStyle(HealthTheme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .background(HealthTheme.paper.ignoresSafeArea())
        .alert("Turn off the seek-care reminder for \(symptomName)?", isPresented: $confirmingMute) {
            Button("Turn it off", role: .destructive) { presenter.mute(match.symptomKey) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll still be able to log it — you just won't see this screen. You can turn it back on anytime in Settings → Safety reminders.")
        }
    }
}

#Preview("Cardiac — light") {
    RedFlagInterstitialView(match: RedFlagMatch(symptomKey: SymptomCatalog.canonicalKey(for: "Chest Pain"),
                                                category: .medicalEmergency, extraGuidance: nil))
        .environmentObject(RedFlagPresenter(muteStore: RedFlagMuteStore()))
        .preferredColorScheme(.light)
}

#Preview("Anaphylaxis — dark") {
    RedFlagInterstitialView(match: RedFlagMatch(symptomKey: SymptomCatalog.canonicalKey(for: "Severe Allergic Reaction"),
                                                category: .medicalEmergency,
                                                extraGuidance: "If you have an epinephrine auto-injector (EpiPen), use it now, then call 911."))
        .environmentObject(RedFlagPresenter(muteStore: RedFlagMuteStore()))
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and confirm previews.**

Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -10`
Expected: build succeeds. Confirm both previews render (Call 911 red primary, Find ER outline, dismiss; the anaphylaxis preview shows the epinephrine line).

- [ ] **Step 3: Commit.**

```bash
git add "Views/HealthOS/Safety/RedFlagInterstitialView.swift"
git commit -m "feat(app): RedFlagInterstitialView — seek-care-now takeover (Call 911 / Find ER / dismiss + guarded mute)"
```

---

### Task 6: RedFlagRemindersView (Settings list) + "Safety reminders" row

**Files:**
- Create: `Views/HealthOS/Safety/RedFlagRemindersView.swift`
- Modify: `Views/HealthOS/Health/HealthTabView.swift` (add a "Safety reminders" `NavigationLink` row)

**Interfaces:**
- Consumes: `RedFlagCatalog.allSymptomKeys` (Task 1), `RedFlagMuteStore` (Task 2), `SymptomCatalog.displayName(for:)`.
- Produces: `struct RedFlagRemindersView: View` reading `@EnvironmentObject var muteStore: RedFlagMuteStore`.

*View — verified by build + preview.*

- [ ] **Step 1: Implement `RedFlagRemindersView.swift`.**

```swift
import SwiftUI
import HealthGraphCore

/// Settings: per-symptom toggles for the seek-care reminders. ON = you'll be
/// reminded; OFF = muted. Full list so the feature is discoverable and re-enabling
/// is one tap.
struct RedFlagRemindersView: View {
    @EnvironmentObject private var muteStore: RedFlagMuteStore

    private var keys: [String] {
        RedFlagCatalog.allSymptomKeys.sorted {
            SymptomCatalog.displayName(for: $0).localizedCaseInsensitiveCompare(SymptomCatalog.displayName(for: $1)) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(keys, id: \.self) { key in
                    Toggle(SymptomCatalog.displayName(for: key), isOn: Binding(
                        get: { !muteStore.isMuted(key) },
                        set: { on in on ? muteStore.unmute(key) : muteStore.mute(key) }
                    ))
                }
            } header: {
                Text("When you log one of these symptoms, the app reminds you to consider urgent care. These aren't diagnoses. Turn any off if the reminder isn't useful for you — you can turn it back on here anytime.")
            }
        }
        .navigationTitle("Safety reminders")
    }
}

#Preview {
    NavigationStack { RedFlagRemindersView().environmentObject(RedFlagMuteStore()) }
}
```

- [ ] **Step 2: Add the "Safety reminders" row to `HealthTabView.swift`.** Read the file first; add, next to the existing "Open legacy app" / "Health Graph Debug" rows (a normal, non-`#if DEBUG` row), matching the file's existing row style:

```swift
NavigationLink(destination: RedFlagRemindersView()) {
    Label("Safety reminders", systemImage: "exclamationmark.shield")
}
```

(If the file's rows use a different wrapper — e.g. a custom row view — match that instead; the goal is a tapping row that pushes `RedFlagRemindersView`.)

- [ ] **Step 3: Build and confirm.**

Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -10` → succeeds. Confirm the preview shows all red-flag symptoms with toggles.

- [ ] **Step 4: Commit.**

```bash
git add "Views/HealthOS/Safety/RedFlagRemindersView.swift" "Views/HealthOS/Health/HealthTabView.swift"
git commit -m "feat(app): Safety reminders settings — per-symptom red-flag mute toggles"
```

---

### Task 7: Wire it up (root injection + capture hook + full-screen takeover)

**Files:**
- Modify: `FoodIntolerancesApp.swift` (share one `RedFlagMuteStore`, create `RedFlagPresenter`, inject both)
- Modify: `Views/HealthOS/Capture/CaptureSheet.swift` (hook `logged` → `presenter.consider`)
- Modify: `Views/HealthOS/Shell/HealthOSRootView.swift` (dismiss capture sheet on red-flag + `.fullScreenCover`)

**Interfaces:**
- Consumes: `RedFlagMuteStore` (Task 2), `RedFlagPresenter` (Task 3), `RedFlagInterstitialView` (Task 5).

*Integration — no new unit test (behavior verified end-to-end in Task 8). Build-verified here.*

> **Voice note (spec §5):** there is no voice-parsed symptom-capture pipeline today — the only voice code is a legacy dictation-to-notes field (`VoiceInputView.swift`), unused by the HealthOS capture flow. All interactive symptom entry funnels through `CaptureSheet.logged` (this hook) and `CaptureService.logSymptom`, so the single hook covers every present modality. The spec's "voice" firing is therefore covered vacuously; any future voice symptom capture must route through this same choke point to inherit the check. Not a gap.

- [ ] **Step 1: Inject at the app root.** In `FoodIntolerancesApp.swift`, add an `init()` that constructs one shared `RedFlagMuteStore` and hands it to a `RedFlagPresenter` (so Settings and the presenter mutate the same instance). Add the two `@StateObject` declarations (without inline initializers) alongside the existing ones, and add an `init`:

```swift
    @StateObject private var redFlagMuteStore: RedFlagMuteStore
    @StateObject private var redFlagPresenter: RedFlagPresenter

    init() {
        let muteStore = RedFlagMuteStore()
        _redFlagMuteStore = StateObject(wrappedValue: muteStore)
        _redFlagPresenter = StateObject(wrappedValue: RedFlagPresenter(muteStore: muteStore))
    }
```

Then add both into the existing `.environmentObject(...)` chain on `HealthOSRootView()` (next to `.environmentObject(captureCoordinator)`):

```swift
                    .environmentObject(redFlagMuteStore)
                    .environmentObject(redFlagPresenter)
```

(The other `@StateObject`s keep their inline initializers; only the two new ones are set in `init`.)

- [ ] **Step 2: Hook the capture choke point.** In `CaptureSheet.swift`, add the presenter env object next to the coordinator:

```swift
    @EnvironmentObject private var redFlagPresenter: RedFlagPresenter
```

and call it at the end of `logged(_:)` (after `coordinator.saveCompleted()`):

```swift
    private func logged(_ event: HealthEvent) {
        coordinator.saveCompleted()
        redFlagPresenter.consider(event)     // fires the takeover iff a red-flag symptom
        lastLogged = event
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(for: .seconds(4)); guard !Task.isCancelled else { return }; lastLogged = nil }
    }
```

- [ ] **Step 3: Present the takeover from the root.** In `HealthOSRootView.swift`, add the presenter env object:

```swift
    @EnvironmentObject private var redFlagPresenter: RedFlagPresenter
```

and, on the body's `VStack` (beside the existing `.sheet` modifier), dismiss the capture sheet when a red flag arrives, then present the cover above everything:

```swift
        .onChange(of: redFlagPresenter.pending) { _, match in
            if match != nil { showingCapture = false }   // let the sheet close, then the cover shows
        }
        .fullScreenCover(item: $redFlagPresenter.pending) { match in
            RedFlagInterstitialView(match: match)
        }
```

(`RedFlagInterstitialView` reads `RedFlagPresenter` from the environment, which the cover inherits.)

- [ ] **Step 4: Build.**

Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -12`
Expected: build succeeds, no errors/warnings.

- [ ] **Step 5: Confirm the package + app suites still pass.**

Run: `cd HealthGraphCore && swift test 2>&1 | tail -3`
Run: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/RedFlagMuteStoreTests" -only-testing:"Food IntolerancesTests/RedFlagPresenterTests" -only-testing:"Food IntolerancesTests/EmergencyContactTests" -parallel-testing-enabled NO 2>&1 | grep -E "Test run with|TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: all green.

- [ ] **Step 6: Commit.**

```bash
git add "FoodIntolerancesApp.swift" "Views/HealthOS/Capture/CaptureSheet.swift" "Views/HealthOS/Shell/HealthOSRootView.swift"
git commit -m "feat(app): wire red-flag takeover — root injection + capture hook + fullScreenCover"
```

---

### Task 8: End-to-end verification (device) + regression

**Files:** none (verification).

- [ ] **Step 1: Full regression.**
  - `cd HealthGraphCore && swift test 2>&1 | tail -3` → all green (incl. `RedFlag*`).
  - App target: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "✔ Suite|✘|Test run with|TEST (SUCCEEDED|FAILED)"` → every suite green except the pre-existing known `SwiftDataMigratorTests.migratesObjectsFromAvoidedCabinetAndProtocols` framework crash (unrelated).
  - App build succeeds.

- [ ] **Step 2: On-device / simulator behavior check** (device preferred, given simulator gesture-automation limits). Drive the capture flow and confirm:
  - Log **Chest Pain** (any severity) → the "seek care now" takeover appears above the tab bar; **Call 911** is the red primary; **Find nearest ER** opens Maps; **Dismiss** returns to the app. The symptom was still saved (visible in Timeline).
  - Log **Severe Allergic Reaction** → takeover shows the epinephrine line.
  - Log **Headache** → no takeover (saves normally).
  - On the takeover, **Stop reminding me about Chest Pain** → confirm → dismiss; log Chest Pain again → **no** takeover.
  - **Settings → Safety reminders** → Chest Pain toggle is OFF; turn it back ON → log Chest Pain → takeover returns.
  - Light + dark both correct; XXL Dynamic Type doesn't clip (actions scroll).

- [ ] **Step 3: Record observed behavior** in the review notes / ledger.

---

## Definition of Done

- Logging a red-flag symptom (severity-independent) via live capture triggers a full-screen, non-diagnostic "seek care now" takeover above all UI, with **Call 911** (regionalizable constant), **Find nearest ER**, and **Dismiss**; the symptom is saved first.
- Anaphylaxis ("Severe Allergic Reaction," a new catalog entry) adds the epinephrine-first guidance line.
- Opt-in per-symptom muting: guarded from the interstitial, directly toggleable in **Settings → Safety reminders**; muted symptoms don't fire; one shared source of truth (`RedFlagMuteStore`, UserDefaults, never health-graph data).
- Fires only on interactive symptom capture — never import/backfill/HealthKit sync/edits.
- Pure evaluator + catalog unit-tested (incl. the rename drift guard); mute store + presenter unit-tested; views build + preview verified; end-to-end confirmed on device.
- No self-harm/mental-health crisis flow (future round); no telemetry; no changes to the evidence engine, extraction, scoring, migrations, or the Insights surface.
