# Measurement-System Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Health-tab Imperial/Metric segmented control backed by a global `@AppStorage` source of truth (with `UserProfile.unitPreference` mirrored), move Timeline weight resolution onto the global, and reconcile the two stores at every lifecycle.

**Architecture:** A new app-side `UnitSystem` + pure `UnitPreferenceReconciler`; a flash-free `@MainActor`, fail-open bootstrap reconcile in `FoodIntolerancesApp.init()` against the reused `sharedModelContainer` (which also fixes the existing two-container mismatch); the Timeline reads `@AppStorage("hg.measurementSystem")` instead of a profile `@Query`; the Health-tab control + profile-creation/save sites keep the global and `unitPreference` equal.

**Tech Stack:** Swift, SwiftUI, SwiftData (`@Query`, `ModelContainer.mainContext`), Swift Testing. App-side code tested via `xcodebuild … -parallel-testing-enabled NO` (target `Food IntolerancesTests`).

## Global Constraints

- Global key: **`"hg.measurementSystem"`**; its value is only ever `""` (unset → locale), `"imperial"`, or `"metric"`.
- `enum UnitSystem: String { case imperial, metric }` — rawValues **`"imperial"`/`"metric"`**, byte-identical to `UserProfile.unitPreference` and the global.
- The **global is the source of truth**; `UserProfile.unitPreference` is a mirror kept **equal**. **Never create a `UserProfile` to store units.** **Never write an unknown string** to the global or to a profile.
- Bootstrap reconcile is **`@MainActor`**, **fail-open** (fetch/save failure logs + continues launch — never blocks startup), runs in **`App.init()` before the scene renders**, against the **reused `sharedModelContainer`**.
- Timeline weight resolves from **`@AppStorage("hg.measurementSystem")`**, never from a profile `@Query`.
- `EventDisplay` and HealthGraphCore are **untouched**. `BodyMetricValueFormatter.line` + `WeightUnit`'s `{ kilograms, pounds }` + `abbreviation` are unchanged; only the dead `WeightUnit.resolved(preference:)` overload is removed.
- App-target tests run with **`-parallel-testing-enabled NO`**; the lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing teardown crash, not a regression.

---

### Task 1: `UnitSystem` + `UnitPreferenceReconciler` (pure) + tests

**Files:**
- Create: `Models/UnitSystem.swift`
- Test: `Food IntolerancesTests/UnitSystemTests.swift`

**Interfaces:**
- Consumes: `WeightUnit` (app-side, existing — `{ kilograms, pounds }`).
- Produces: `UnitSystem` (`.imperial`/`.metric`, `.localeDefault(for:)`, `.resolved(from:locale:)`, `.weightUnit`); `struct UnitReconciliation: Equatable { globalRaw: String; profileUnitPreference: String? }`; `enum UnitPreferenceReconciler { static func reconcile(globalRaw:profilePref:) -> UnitReconciliation }`.

- [ ] **Step 1: Write the failing tests**

Create `Food IntolerancesTests/UnitSystemTests.swift`:

```swift
import Testing
import Foundation
@testable import Food_Intolerances

struct UnitSystemTests {
    // MARK: UnitSystem resolution + mapping
    @Test func localeDefaultUSisImperialElseMetric() {
        #expect(UnitSystem.localeDefault(for: Locale(identifier: "en_US")) == .imperial)
        #expect(UnitSystem.localeDefault(for: Locale(identifier: "en_GB")) == .metric)
        #expect(UnitSystem.localeDefault(for: Locale(identifier: "de_DE")) == .metric)
    }
    @Test func resolvedExplicitWinsElseLocale() {
        #expect(UnitSystem.resolved(from: "metric", locale: Locale(identifier: "en_US")) == .metric)   // explicit wins
        #expect(UnitSystem.resolved(from: "imperial", locale: Locale(identifier: "de_DE")) == .imperial)
        #expect(UnitSystem.resolved(from: "", locale: Locale(identifier: "en_US")) == .imperial)        // empty → locale
        #expect(UnitSystem.resolved(from: "garbage", locale: Locale(identifier: "de_DE")) == .metric)   // unknown → locale
    }
    @Test func weightUnitMapping() {
        #expect(UnitSystem.imperial.weightUnit == .pounds)
        #expect(UnitSystem.metric.weightUnit == .kilograms)
    }
    @Test func newProfileUnitPreferenceFromResolvedGlobal() {   // rule 4: a new profile inherits the global
        #expect(UnitSystem.newProfileUnitPreference(global: "metric", locale: Locale(identifier: "en_US")) == "metric")     // explicit wins
        #expect(UnitSystem.newProfileUnitPreference(global: "imperial", locale: Locale(identifier: "de_DE")) == "imperial")
        #expect(UnitSystem.newProfileUnitPreference(global: "", locale: Locale(identifier: "en_US")) == "imperial")         // locale fallback
        #expect(UnitSystem.newProfileUnitPreference(global: "", locale: Locale(identifier: "de_DE")) == "metric")
    }

    // MARK: reconciliation truth table (asserts BOTH returned fields)
    private func r(_ g: String, _ p: String?) -> UnitReconciliation {
        UnitPreferenceReconciler.reconcile(globalRaw: g, profilePref: p)
    }
    @Test func validGlobalNoProfile_leftAlone_createsNothing() {          // rule 3
        #expect(r("imperial", nil) == UnitReconciliation(globalRaw: "imperial", profileUnitPreference: nil))
    }
    @Test func validGlobalMatchingProfile_agree() {
        #expect(r("metric", "metric") == UnitReconciliation(globalRaw: "metric", profileUnitPreference: nil))
    }
    @Test func validGlobalDifferentProfile_globalWinsRepairs() {          // rule 2
        #expect(r("imperial", "metric") == UnitReconciliation(globalRaw: "imperial", profileUnitPreference: "imperial"))
    }
    @Test func validGlobalInvalidProfile_repairsProfile() {              // valid global + invalid profile
        #expect(r("metric", "garbage") == UnitReconciliation(globalRaw: "metric", profileUnitPreference: "metric"))
    }
    @Test func emptyGlobalValidProfile_seedsGlobal() {                    // rule 1
        #expect(r("", "metric") == UnitReconciliation(globalRaw: "metric", profileUnitPreference: nil))
    }
    @Test func invalidGlobalValidProfile_seedsGlobal() {                 // invalid global treated as unset
        #expect(r("garbage", "imperial") == UnitReconciliation(globalRaw: "imperial", profileUnitPreference: nil))
    }
    @Test func neitherValid_remainsUnset_neverCopiesUnknown() {
        #expect(r("", "garbage") == UnitReconciliation(globalRaw: "", profileUnitPreference: nil))      // invalid profile NOT copied
        #expect(r("garbage", "garbage") == UnitReconciliation(globalRaw: "", profileUnitPreference: nil))
        #expect(r("", nil) == UnitReconciliation(globalRaw: "", profileUnitPreference: nil))            // no profile, nothing to seed
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/UnitSystemTests" 2>&1 | tail -20
```
Expected: FAILS to compile — `cannot find 'UnitSystem'` / `'UnitPreferenceReconciler'` / `'UnitReconciliation'`.

- [ ] **Step 3: Write the implementation**

Create `Models/UnitSystem.swift`:

```swift
import Foundation

/// The user's measurement system for display. The source of truth is the global
/// `@AppStorage("hg.measurementSystem")`; `UserProfile.unitPreference` mirrors it.
/// Peer to `TemperatureUnit`; rawValues match the strings both stores already use.
enum UnitSystem: String {
    case imperial, metric

    /// Device-locale default: US → imperial, everywhere else → metric.
    static func localeDefault(for locale: Locale = .current) -> UnitSystem {
        locale.measurementSystem == .us ? .imperial : .metric
    }
    /// An explicit stored choice ("imperial"/"metric") wins; empty/unknown → locale default.
    static func resolved(from raw: String, locale: Locale = .current) -> UnitSystem {
        UnitSystem(rawValue: raw) ?? localeDefault(for: locale)
    }
    /// Weight rendering unit for this system.
    var weightUnit: WeightUnit {
        switch self {
        case .imperial: return .pounds
        case .metric: return .kilograms
        }
    }

    /// The `unitPreference` string a newly-created profile should inherit: the
    /// resolved global (explicit choice, else locale). Used by onboarding + the
    /// profile editor so a new profile is born matching the global (invariant §7.4).
    static func newProfileUnitPreference(global raw: String, locale: Locale = .current) -> String {
        resolved(from: raw, locale: locale).rawValue
    }
}

/// Result of reconciling the global measurement setting with a profile's mirror.
struct UnitReconciliation: Equatable {
    /// Value to persist to `@AppStorage("hg.measurementSystem")` ("" = leave unset → locale).
    let globalRaw: String
    /// When non-nil, write to an existing `profile.unitPreference`; nil = no profile write.
    let profileUnitPreference: String?
}

/// Pure reconciliation of the global setting vs a profile mirror. The global is
/// authoritative; an unknown/empty value on either side resolves from locale and
/// is NEVER copied into the other store.
enum UnitPreferenceReconciler {
    /// - Parameter profilePref: nil when NO profile exists; otherwise the profile's
    ///   current `unitPreference` (which may itself be an unrecognized string).
    static func reconcile(globalRaw: String,
                          profilePref: String?) -> UnitReconciliation {
        let global = UnitSystem(rawValue: globalRaw)                    // valid global, else nil
        let profile = profilePref.flatMap(UnitSystem.init(rawValue:))   // valid profile, else nil
        switch (global, profile) {
        case let (.some(g), .some(p)):
            // valid global + valid profile: global wins; repair the profile on mismatch
            return UnitReconciliation(globalRaw: g.rawValue,
                                      profileUnitPreference: g == p ? nil : g.rawValue)
        case let (.some(g), .none):
            // valid global + (no profile | invalid profile)
            if profilePref == nil {
                return UnitReconciliation(globalRaw: g.rawValue, profileUnitPreference: nil)   // rule 3
            }
            return UnitReconciliation(globalRaw: g.rawValue, profileUnitPreference: g.rawValue) // repair invalid profile
        case let (.none, .some(p)):
            // invalid/empty global + valid profile: seed the global from the profile
            return UnitReconciliation(globalRaw: p.rawValue, profileUnitPreference: nil)         // rule 1
        case (.none, .none):
            // neither valid: remain unset (locale at read); never copy an unknown value across
            return UnitReconciliation(globalRaw: "", profileUnitPreference: nil)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command. Expected: `** TEST SUCCEEDED **` — all `UnitSystemTests` pass.

- [ ] **Step 5: Commit**

```bash
git add "Models/UnitSystem.swift" "Food IntolerancesTests/UnitSystemTests.swift"
git commit -m "feat(app): UnitSystem + pure UnitPreferenceReconciler (global source of truth, profile mirror)"
```

---

### Task 2: Timeline reads the global; retire the profile-based resolver

**Files:**
- Modify: `Views/HealthOS/Timeline/TimelineView.swift`
- Modify: `Views/HealthOS/Timeline/EventDetailView.swift`
- Modify: `Views/HealthOS/Insights/InsightDetailView.swift` (remove the 2 preview containers)
- Modify: `Views/HealthOS/Timeline/BodyMetricValueFormatter.swift` (remove the dead resolver)
- Modify: `Food IntolerancesTests/BodyMetricValueFormatterTests.swift` (remove the 2 resolver tests)

**Interfaces:**
- Consumes: `UnitSystem.resolved(from:locale:)`, `UnitSystem.weightUnit` (Task 1).
- Produces: nothing new. `TimelineEventRow`'s `weightUnit: WeightUnit` prop is unchanged (still passed from `TimelineView`).

- [ ] **Step 1: Swap `TimelineView` from `@Query` to `@AppStorage`**

In `Views/HealthOS/Timeline/TimelineView.swift`: delete `import SwiftData` (added in the weight-units round; nothing else here uses it). Replace the query + resolver:
```swift
    @Query private var userProfiles: [UserProfile]
    private var weightUnit: WeightUnit {
        WeightUnit.resolved(preference: userProfiles.first?.unitPreference)
    }
```
with:
```swift
    @AppStorage("hg.measurementSystem") private var rawUnitSystem = ""
    private var weightUnit: WeightUnit {
        UnitSystem.resolved(from: rawUnitSystem).weightUnit
    }
```

- [ ] **Step 2: Swap `EventDetailView` the same way**

In `Views/HealthOS/Timeline/EventDetailView.swift`: delete `import SwiftData`. Replace:
```swift
    @Query private var userProfiles: [UserProfile]
    private var weightUnit: WeightUnit {
        WeightUnit.resolved(preference: userProfiles.first?.unitPreference)
    }
```
with:
```swift
    @AppStorage("hg.measurementSystem") private var rawUnitSystem = ""
    private var weightUnit: WeightUnit {
        UnitSystem.resolved(from: rawUnitSystem).weightUnit
    }
```
(The header's `BodyMetricValueFormatter.line(for: displayEvent, unit: weightUnit) ?? …` chain is unchanged — only the source of `weightUnit` changed.)

- [ ] **Step 3: Remove the now-unnecessary `InsightDetailView` preview containers**

In `Views/HealthOS/Insights/InsightDetailView.swift`, the two `#Preview`s no longer push a `@Query`-backed `EventDetailView`, so drop the container line from each:
```swift
#Preview("Insight Detail — light") {
    NavigationStack { InsightDetailPreviewHost() }
}

#Preview("Insight Detail — dark") {
    NavigationStack { InsightDetailPreviewHost() }
        .preferredColorScheme(.dark)
}
```
(Leave the `HealthOSRootView` preview containers alone — `HealthTabView`, added in Task 4, will host a `@Query` in the shell, so those are still required.)

- [ ] **Step 4: Remove the dead `WeightUnit.resolved(preference:)` overload**

In `Views/HealthOS/Timeline/BodyMetricValueFormatter.swift`, delete the `resolved(preference:locale:)` static method from `WeightUnit` (its only callers were the two views just swapped). `WeightUnit` keeps `{ case kilograms, pounds }` and `var abbreviation`. After the edit the enum is:
```swift
enum WeightUnit {
    case kilograms, pounds

    /// Unit abbreviation as shown in the Timeline.
    var abbreviation: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }
}
```
(`BodyMetricValueFormatter` below it is unchanged.)

- [ ] **Step 5: Remove the two resolver tests**

In `Food IntolerancesTests/BodyMetricValueFormatterTests.swift`, delete the `resolvedFromProfilePreference()` and `resolvedFallsBackToLocaleWhenNoOrUnknownPreference()` `@Test` methods (that behavior now lives in `UnitSystemTests`). The four `line(...)` tests (`kilogramsRenderOneDecimal`, `poundsConvertThenRenderOneDecimal`, `kilogramsRoundsToOneDecimal`, `nonWeightEventReturnsNil`) remain.

- [ ] **Step 6: Build and run the suite**

```bash
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **` (no dangling `WeightUnit.resolved`/`@Query`/`SwiftData` references).
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -25
```
Expected: all pass except the known `SwiftDataMigratorTests` crash. (Intentional intermediate state: with nothing writing the global yet, Timeline weight resolves to the **locale default** — the bootstrap in Task 3 seeds it from the profile.)

- [ ] **Step 7: Commit**

```bash
git add \
  "Views/HealthOS/Timeline/TimelineView.swift" \
  "Views/HealthOS/Timeline/EventDetailView.swift" \
  "Views/HealthOS/Insights/InsightDetailView.swift" \
  "Views/HealthOS/Timeline/BodyMetricValueFormatter.swift" \
  "Food IntolerancesTests/BodyMetricValueFormatterTests.swift"
git commit -m "refactor(app): Timeline weight resolves from the global UnitSystem, not a profile @Query"
```

---

### Task 3: Flash-free launch reconcile + reuse `sharedModelContainer`

**Files:**
- Create: `Models/UnitPreferenceBootstrap.swift`
- Modify: `FoodIntolerancesApp.swift`
- Test: `Food IntolerancesTests/UnitPreferenceBootstrapTests.swift`

**Interfaces:**
- Consumes: `UnitPreferenceReconciler.reconcile` (Task 1); `UserProfile`; `Logger`.
- Produces: `@MainActor enum UnitPreferenceBootstrap { static let globalKey; static func reconcileAtLaunch(container:defaults:) }`.

- [ ] **Step 1: Write the failing bootstrap integration test**

Create `Food IntolerancesTests/UnitPreferenceBootstrapTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Food_Intolerances

@MainActor
struct UnitPreferenceBootstrapTests {
    private func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: UserProfile.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "unit-bootstrap-\(UUID().uuidString)")!
        d.removeObject(forKey: UnitPreferenceBootstrap.globalKey)
        return d
    }

    @Test func seedsGlobalFromProfileWhenUnset() throws {
        let c = try inMemoryContainer()
        let p = UserProfile(); p.unitPreference = "metric"; c.mainContext.insert(p)
        let d = freshDefaults()
        UnitPreferenceBootstrap.reconcileAtLaunch(container: c, defaults: d)
        #expect(d.string(forKey: UnitPreferenceBootstrap.globalKey) == "metric")   // seeded
        #expect(p.unitPreference == "metric")                                      // profile untouched
    }
    @Test func globalWinsAndRepairsProfileOnMismatch() throws {
        let c = try inMemoryContainer()
        let p = UserProfile(); p.unitPreference = "metric"; c.mainContext.insert(p)
        let d = freshDefaults(); d.set("imperial", forKey: UnitPreferenceBootstrap.globalKey)
        UnitPreferenceBootstrap.reconcileAtLaunch(container: c, defaults: d)
        #expect(d.string(forKey: UnitPreferenceBootstrap.globalKey) == "imperial")  // global unchanged
        #expect(p.unitPreference == "imperial")                                     // profile repaired
    }
    @Test func noProfileCreatesNothingAndKeepsGlobal() throws {
        let c = try inMemoryContainer()
        let d = freshDefaults(); d.set("metric", forKey: UnitPreferenceBootstrap.globalKey)
        UnitPreferenceBootstrap.reconcileAtLaunch(container: c, defaults: d)
        #expect(d.string(forKey: UnitPreferenceBootstrap.globalKey) == "metric")    // rule 3: left alone
        let count = try c.mainContext.fetch(FetchDescriptor<UserProfile>()).count
        #expect(count == 0)                                                         // nothing created
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/UnitPreferenceBootstrapTests" 2>&1 | tail -20
```
Expected: FAILS to compile — `cannot find 'UnitPreferenceBootstrap'`.

- [ ] **Step 3: Write the bootstrap**

Create `Models/UnitPreferenceBootstrap.swift`:

```swift
import Foundation
import SwiftData

/// Reconciles the global measurement setting with the stored profile at launch —
/// synchronously, before the first render (flash-free), on the main actor, and
/// failing open so a preference repair can never block app startup.
@MainActor
enum UnitPreferenceBootstrap {
    static let globalKey = "hg.measurementSystem"

    static func reconcileAtLaunch(container: ModelContainer,
                                  defaults: UserDefaults = .standard) {
        let current = defaults.string(forKey: globalKey) ?? ""
        do {
            let profiles = try container.mainContext.fetch(FetchDescriptor<UserProfile>())
            let result = UnitPreferenceReconciler.reconcile(
                globalRaw: current, profilePref: profiles.first?.unitPreference)
            if result.globalRaw != current {
                defaults.set(result.globalRaw, forKey: globalKey)
            }
            if let update = result.profileUnitPreference,
               let profile = profiles.first, profile.unitPreference != update {
                profile.unitPreference = update
                try container.mainContext.save()
            }
        } catch {
            // Fail open: a preference repair must never prevent startup.
            Logger.info("Unit preference reconcile skipped (fetch/save failed); using global/locale resolution",
                        category: .data)
        }
    }
}
```

- [ ] **Step 4: Wire it into the app and reuse the shared container**

In `FoodIntolerancesApp.swift`, add the reconcile as the **last line of `init()`** (all stored properties, incl. `sharedModelContainer`, are initialized by then — the existing `setupGlobalErrorHandling()` already relies on that):
```swift
        setupGlobalErrorHandling()

        // Flash-free: reconcile the measurement preference before the scene renders.
        UnitPreferenceBootstrap.reconcileAtLaunch(container: sharedModelContainer)
    }
```
Then replace the scene's container modifier so the UI, recovery, and this reconcile share one container. Change:
```swift
                .modelContainer(for: [
                    LogEntry.self,
                    TrackedItem.self,
                    Symptom.self,
                    TherapyProtocol.self,
                    TherapyProtocolItem.self,
                    CabinetItem.self,
                    AvoidedItem.self,
                    OngoingSymptom.self,
                    SymptomCheckIn.self,
                    MoodEntry.self,
                    ProtocolRequirement.self,
                    // AI Assistant Models
                    UserProfile.self,
                    UserAllergy.self,
                    AIMemory.self,
                    HealthTestResult.self,
                    HealthScreeningSchedule.self
                ])
```
to:
```swift
                .modelContainer(sharedModelContainer)
```

- [ ] **Step 5: Run the bootstrap tests, then build + full suite**

```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
  -only-testing:"Food IntolerancesTests/UnitPreferenceBootstrapTests" 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` (3/3).
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -25
```
Expected: all pass except the known `SwiftDataMigratorTests` crash.

- [ ] **Step 6: Commit**

```bash
git add "Models/UnitPreferenceBootstrap.swift" "FoodIntolerancesApp.swift" \
  "Food IntolerancesTests/UnitPreferenceBootstrapTests.swift"
git commit -m "feat(app): flash-free launch reconcile of measurement preference; reuse sharedModelContainer"
```

---

### Task 4: Health-tab Imperial/Metric control

**Files:**
- Modify: `Views/HealthOS/Health/HealthTabView.swift`

**Interfaces:**
- Consumes: `UnitSystem` (Task 1); `UserProfile.unitPreference`; `Logger`.
- Produces: nothing external.

- [ ] **Step 1: Add the query, environment, storage, and binding**

In `Views/HealthOS/Health/HealthTabView.swift`, add `import SwiftData` under `import SwiftUI`. Add these properties next to the existing `@AppStorage("hg.temperatureUnit")`:
```swift
    @AppStorage("hg.measurementSystem") private var rawUnitSystem = ""
    @Query private var userProfiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
```
Add this binding next to `tempUnitBinding` (rule 6 — global first; mirror an existing profile; a profile-save failure does not roll back the global; never creates a profile):
```swift
    private var unitSystemBinding: Binding<UnitSystem> {
        Binding(get: { UnitSystem.resolved(from: rawUnitSystem) },
                set: { newValue in
                    rawUnitSystem = newValue.rawValue                      // global is the source of truth
                    if let profile = userProfiles.first {                  // mirror; never create one
                        profile.unitPreference = newValue.rawValue
                        do { try modelContext.save() }
                        catch { Logger.error(error, message: "Failed to mirror units to profile", category: .data) }
                    }
                })
    }
```

- [ ] **Step 2: Add the segmented control after Temperature**

Insert this block immediately after the Temperature `HStack`'s closing `.padding(16)` and before the `#if DEBUG` "Open legacy app" block:
```swift
                    .padding(16)
                    Divider().padding(.leading, 16)
                    HStack {
                        Image(systemName: "ruler")
                            .foregroundStyle(HealthTheme.accent)
                        Text("Units")
                            .foregroundStyle(HealthTheme.ink)
                        Spacer()
                        Picker("Measurement system", selection: unitSystemBinding) {
                            Text("Imperial").tag(UnitSystem.imperial)
                            Text("Metric").tag(UnitSystem.metric)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("Measurement system")
                        .frame(width: 160)
                    }
                    .padding(16)
                    #if DEBUG
```
(The first `.padding(16)` and `#if DEBUG` lines are the existing anchor — the new `Divider()` + `HStack` + `.padding(16)` go between them.)

- [ ] **Step 3: Build and run the suite**

```bash
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -25
```
Expected: all pass except the known `SwiftDataMigratorTests` crash.

- [ ] **Step 4: Commit**

```bash
git add "Views/HealthOS/Health/HealthTabView.swift"
git commit -m "feat(app): Health-tab Imperial/Metric control (writes global, mirrors an existing profile)"
```

---

### Task 5: Profile-creation & legacy-save lifecycles (rules 4–5)

**Files:**
- Modify: `Views/Onboarding/OnboardingContainerView.swift`
- Modify: `Views/Profile/UserProfileView.swift`

**Interfaces:**
- Consumes: `UnitSystem.resolved(from:)` (Task 1).
- Produces: nothing external.

- [ ] **Step 1: New onboarding profile inherits the global (rule 4)**

In `Views/Onboarding/OnboardingContainerView.swift`, add `@AppStorage("hg.measurementSystem") private var rawUnitSystem = ""` among the view's properties. In `completeOnboarding()`, after `profile.onboardingStepsCompleted = 7`, set the unit from the resolved global:
```swift
        profile.onboardingStepsCompleted = 7
        profile.unitPreference = UnitSystem.newProfileUnitPreference(global: rawUnitSystem)   // rule 4: match the global
```

- [ ] **Step 2: Profile editor — init picker from global when no profile (rule 4)**

In `Views/Profile/UserProfileView.swift`, add `@AppStorage("hg.measurementSystem") private var rawUnitSystem = ""` among the properties (near the existing `@State private var unitPreference`). In the load function, **replace the one-line early-return** `guard let profile = profile else { return }` (at `~:300`) so a missing profile initializes the picker from the resolved global instead of the hardcoded `"imperial"`:
```swift
        guard let profile = profile else {
            unitPreference = UnitSystem.newProfileUnitPreference(global: rawUnitSystem)
            return
        }
```

- [ ] **Step 3: Legacy save propagates to the global on success (rule 5)**

In `saveChanges()`, after a successful `try modelContext.save()`, set the global from the saved preference (only on success):
```swift
        do {
            try modelContext.save()
            hasChanges = false
            rawUnitSystem = unitPreference                 // rule 5: propagate to the global only on a successful save
            Logger.info("Profile saved successfully", category: .data)
        } catch {
            Logger.error(error, message: "Failed to save profile", category: .data)
        }
```

- [ ] **Step 4: Build and run the suite**

```bash
xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.
```bash
xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | tail -25
```
Expected: all pass except the known `SwiftDataMigratorTests` crash.

- [ ] **Step 5: Commit**

```bash
git add "Views/Onboarding/OnboardingContainerView.swift" "Views/Profile/UserProfileView.swift"
git commit -m "feat(app): onboarding + profile editor keep unitPreference in sync with the global measurement setting"
```

---

## Device verification (finishing gate, after all tasks)

On the booted iPhone 17 Pro, with a weight event in the Timeline:
1. **Health-tab control:** flip Imperial ↔ Metric → the Timeline **row and detail** both switch `lb` ↔ `kg` live.
2. **No profile:** with zero `UserProfile` rows, the control still works and changes the weight unit — and **no profile row is created** (check the debug event/DB inspector).
3. **No flash:** set the profile/global to **Metric**, relaunch → the weight shows **kg immediately** on first paint (never a momentary `lb`).
4. **Legacy agreement:** change units in the legacy profile picker → the Health-tab control and Timeline agree; change in the Health-tab control → the legacy picker agrees.
5. **Onboarding:** a fresh onboarding creates a profile whose units match the current control.
6. VoiceOver reads the control; light/dark unchanged.

## Self-Review (completed)

- **Spec coverage:** §3A `UnitSystem`/reconciler → Task 1. §3C Timeline→global + retire resolver → Task 2. §3D bootstrap + container reuse → Task 3. §3B Health-tab control → Task 4. §3D rules 4–5 → Task 5 (rule 6 is in Task 4). §5 tests → Tasks 1/3 + device gate. Invariants §7 map to the Global Constraints.
- **Placeholder scan:** none — every step carries full code/commands.
- **Type consistency:** `UnitSystem` (`resolved(from:)`, `weightUnit`, rawValues), `UnitReconciliation` fields, `UnitPreferenceReconciler.reconcile`, `UnitPreferenceBootstrap.reconcileAtLaunch`/`globalKey`, and the `@AppStorage("hg.measurementSystem")` key are used identically across tasks.
