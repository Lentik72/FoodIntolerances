# Measurement-System Control (Health tab) — Design

**Date:** 2026-07-21
**Status:** Approved (decisions made interactively with Leo)
**Scope:** Surface the Imperial/Metric preference as a **segmented control in the Health tab** (beside Temperature), backed by a **global `@AppStorage` setting** that is the source of truth, with `UserProfile.unitPreference` kept **mirrored**. Move the Timeline weight resolution off the profile `@Query` onto the global (so it works for no-profile users), and reconcile the two stores at every lifecycle. Follow-up #1 after [[weight-units-merged]].

**Not touched:** the Temperature control (`hg.temperatureUnit`, independent °C/°F); the weight *formatting* (`WeightUnit`/`BodyMetricValueFormatter`, unchanged); `EventDisplay` (still the pure kg fallback); HealthGraphCore (no `UserProfile`/units dependency).

---

## 1. Problem

Weight units shipped reusing `UserProfile.unitPreference`, but that preference's only UI is **buried in the legacy app** (Health → *Open legacy app* → More → Profile → Units), while Temperature has a control right in the Health tab. And resolving weight off the profile means a **no-profile user can't choose units at all**. We add a Health-tab Imperial/Metric control and move the preference into a **global setting** so it works with or without a profile — matching how Temperature already works — while keeping `unitPreference` in sync so the legacy profile screen is unaffected.

**Binding constraint (Leo):** never silently create a blank `UserProfile` to store units — `UserProfile` also drives onboarding + AI settings, so creating one has side effects.

## 2. Decisions (Leo, 2026-07-21)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Where units live | **Global `@AppStorage("hg.measurementSystem")`** is the source of truth; `UserProfile.unitPreference` is a **mirror** kept equal. (Not: keep it profile-only.) |
| 2 | Timeline source | Reads the **global**, not a profile `@Query` (so no-profile users' choice applies). |
| 3 | Legacy profile screen | Keeps reading its own `unitPreference` (mirrored) — display logic unchanged. |
| 4 | Sync model | **Reconciliation** (runs every launch, repairs disagreements), not a one-time seed. |
| 5 | Bootstrap timing | **Flash-free:** reconcile synchronously in `FoodIntolerancesApp.init()` before the scene renders, using the **reused `sharedModelContainer`** (also fixes the existing two-container mismatch). |
| 6 | Profile creation | Never auto-created for units. Every genuine profile-creation site initializes `unitPreference` from the **resolved global**. |
| 7 | Control style | **Segmented `Imperial / Metric` Picker** (not a switch), mirroring the Temperature control. |

## 3. Architecture

### A. `UnitSystem` + global setting (app-side, new)

- **`enum UnitSystem: String { case imperial, metric }`** — rawValues `"imperial"`/`"metric"`, byte-identical to what `unitPreference` and the global already store, so `resolved(...).rawValue` writes straight into either. Peer to `TemperatureUnit`.
  - `static func localeDefault(for locale: Locale = .current) -> UnitSystem` — `locale.measurementSystem == .us ? .imperial : .metric`.
  - `static func resolved(from raw: String, locale: Locale = .current) -> UnitSystem` — `UnitSystem(rawValue: raw) ?? localeDefault(for: locale)` (unknown/empty → locale).
  - `var weightUnit: WeightUnit` — `.imperial → .pounds`, `.metric → .kilograms`.
- **Global:** `@AppStorage("hg.measurementSystem")` raw string (empty = unset → locale at read). Exactly the `hg.temperatureUnit` pattern.

### B. Health-tab control (`HealthTabView`)

A segmented `Imperial / Metric` `Picker` in a new `HStack` **directly after the Temperature `HStack`** (a `Divider().padding(.leading, 16)` between), bound to a `UnitSystem` binding over the `@AppStorage` (mirrors `tempUnitBinding`). `.pickerStyle(.segmented)`, `.labelsHidden()`, `.accessibilityLabel("Measurement system")`. Label text "Units", icon e.g. `ruler`.

**Rule 6 (write on change):** the binding's setter (1) writes the global **immediately**; (2) if a profile exists, sets `profile.unitPreference` and saves; (3) a profile-save failure is **logged but does not roll back the global** (global is the source of truth). Never creates a profile. `HealthTabView` gains `@Query private var userProfiles: [UserProfile]` + `@Environment(\.modelContext)` for the mirror.

### C. Timeline reads the global (refactor of just-merged code)

- **`TimelineView`** and **`EventDetailView`**: replace `@Query userProfiles` + `WeightUnit.resolved(preference: userProfiles.first?.unitPreference)` with `@AppStorage("hg.measurementSystem") rawUnitSystem` + `UnitSystem.resolved(from: rawUnitSystem).weightUnit`. Remove the now-unused `@Query` and the `import SwiftData` from both (if not otherwise used). `TimelineEventRow` is unchanged — it still receives `weightUnit: WeightUnit` from `TimelineView`.
- **Preview accounting:** `HealthOSRootView`'s two `#Preview` containers **stay** — `HealthTabView` (mounted in the shell) now hosts a `@Query`, so they're still required. `InsightDetailView`'s two `#Preview` containers are **removed** — `EventDetailView` no longer has a `@Query`, so nothing in that path needs one. Any `HealthTabView` own `#Preview` **gains** `.modelContainer(for: UserProfile.self, inMemory: true)`.
- `WeightUnit.resolved(preference:)` (the String? overload from the weight-units round) becomes unused once callers move to `UnitSystem`; **remove it** (and its tests) to avoid a dead second resolver, keeping `WeightUnit` as just `{ kilograms, pounds }` + `abbreviation`. `BodyMetricValueFormatter` is unchanged.

### D. Reconciliation + write lifecycles

**Invariant:** the global (`hg.measurementSystem`) and `profile.unitPreference` (when a profile exists) stay **equal**, with the global authoritative. An unknown/empty value on either side resolves from locale and is never copied into the other.

**Pure reconciler** (unit-tested; returns both the resulting global and any requested profile write):

```swift
struct UnitReconciliation: Equatable {
    let globalRaw: String            // store to @AppStorage("hg.measurementSystem")
    let profileUnitPreference: String?  // non-nil → write to existing profile.unitPreference; nil → no profile write
}

enum UnitPreferenceReconciler {
    /// profilePref: nil when NO profile exists; otherwise the profile's current unitPreference (which may be invalid).
    static func reconcile(globalRaw: String, profilePref: String?, locale: Locale = .current) -> UnitReconciliation
}
```

| global | profile | → result global | → profile update | rule |
|---|---|---|---|---|
| valid `G` | none | `G` | — | 3: leave, create nothing |
| valid `G` | valid `P == G` | `G` | — | agree |
| valid `G` | valid `P ≠ G` | `G` | `G` | 2: global wins, repair |
| valid `G` | **invalid** | `G` | `G` | valid global + invalid profile → repair |
| **invalid/empty** | valid `P` | `P` | — | 1: seed from profile |
| invalid/empty | **invalid** (profile exists) | locale default | locale default | neither valid + profile → repair BOTH to the locale default (never leave "garbage" in the profile; `locale` is used here) |
| invalid/empty | none | `""` (unset → locale) | — | nothing to seed, create nothing |

"Valid" = `UnitSystem(rawValue:) != nil`. The reconciler never returns a non-`{imperial,metric}` value in `globalRaw` except `""` (unset), and never puts an unknown string in `profileUnitPreference`.

**Bootstrap (rule: mount at app init, flash-free, main-actor, fail-open):**

```swift
@MainActor
enum UnitPreferenceBootstrap {
    static func reconcileAtLaunch(container: ModelContainer,
                                  defaults: UserDefaults = .standard,
                                  locale: Locale = .current)
}
```

- Reads the current global from `defaults`, fetches the first `UserProfile` from `container.mainContext`, runs `UnitPreferenceReconciler.reconcile`, then persists: writes the global if changed, and (only if a profile exists and an update is requested) sets `profile.unitPreference` + saves.
- **Fail open:** the fetch + apply are wrapped in `do/catch`; any error is logged and swallowed — a preference repair must never prevent startup.
- **Main-actor:** `@MainActor` (App `init` is main-actor-isolated; `mainContext` is main-actor-bound).
- Called from `FoodIntolerancesApp.init()` (after the existing setup), against the **reused `sharedModelContainer`**. Because `init` runs before the scene body, the global `@AppStorage` is correct on first paint — an existing Metric user never flashes pounds.

**Container reuse (folds in a real bug fix):** `FoodIntolerancesApp` currently builds `sharedModelContainer` (which the 2-second SwiftData recovery saves into) but the scene injects a **separate** container via `.modelContainer(for: [array])`. Replace that modifier with **`.modelContainer(sharedModelContainer)`** so the UI, the recovery path, and the bootstrap reconcile all use the **same** container. Same schema + default store → behavior-identical data, one instance instead of two.

**Write lifecycles (rules 4–6):**
- **Rule 4 — profile creation.** `OnboardingContainerView.swift:111` (`UserProfile(...)`) and `UserProfileView`'s create-on-save (`:343`) initialize the new `unitPreference` from `UnitSystem.resolved(from: global, locale).rawValue`. `UserProfileView` also initializes its picker `@State unitPreference` from the resolved global when **no** profile exists (instead of the hardcoded `"imperial"` at `:26`/`:311`).
- **Rule 5 — legacy profile save.** In `UserProfileView.saveChanges()`, after `try modelContext.save()` **succeeds** (`:388`), set the global from the saved `unitPreference`. On save failure, the global is left untouched.
- **Rule 6 — Health-tab change.** As in §B: global first, then mirror an existing profile; profile-save failure does not invalidate the global.

## 4. Files

- **Create** `Models/UnitSystem.swift` — `UnitSystem` enum, `UnitReconciliation`, `UnitPreferenceReconciler.reconcile`, `@MainActor UnitPreferenceBootstrap.reconcileAtLaunch`.
- **Create** `Food IntolerancesTests/UnitSystemTests.swift` — `UnitSystem` resolution/mapping + the reconciler truth table (incl. invalid-global and invalid-profile cases).
- **Modify** `FoodIntolerancesApp.swift` — call the bootstrap in `init()`; replace `.modelContainer(for: [array])` with `.modelContainer(sharedModelContainer)`.
- **Modify** `Views/HealthOS/Health/HealthTabView.swift` — the segmented control + `@Query` + `@AppStorage` + `modelContext` mirror; its `#Preview` gets an in-memory container if it has one.
- **Modify** `Views/HealthOS/Timeline/TimelineView.swift`, `Views/HealthOS/Timeline/EventDetailView.swift` — `@Query`→`@AppStorage` swap; drop `import SwiftData`.
- **Modify** `Views/HealthOS/Insights/InsightDetailView.swift` — remove the two `#Preview` `.modelContainer` lines.
- **Modify** `Views/Onboarding/OnboardingContainerView.swift` — new-profile `unitPreference` from resolved global.
- **Modify** `Views/Profile/UserProfileView.swift` — picker init-from-global when no profile; set global after a successful save.
- **Modify** `Views/HealthOS/Timeline/BodyMetricValueFormatter.swift` + its test — remove the now-dead `WeightUnit.resolved(preference:)` overload (and its tests).

## 5. Testing

- **`UnitSystem`** (pure): `localeDefault` (US→imperial, en_GB/de_DE→metric), `resolved(from:)` (explicit wins; empty/garbage→locale), `weightUnit` mapping.
- **`UnitPreferenceReconciler.reconcile`** (pure): every row of the §D table asserting **both** returned fields — including **valid-global + invalid-profile → repair**, **invalid-global + valid-profile → seed**, **invalid-global + invalid-profile → unset (never copy unknown)**, and both no-profile rows.
- **Rule 4** helper: new-profile `unitPreference` derives from the resolved global (imperial/metric/locale-fallback).
- **Regression:** the `BodyMetricValueFormatter` weight tests still pass; Timeline/detail still resolve the right `WeightUnit` after the `@AppStorage` swap (build + suite).
- **Device:** Health-tab Imperial/Metric flips row **and** detail live; works with **no** profile (and creates none — verify via the debug event list / no new profile row); an existing Metric user sees **kg immediately on launch** (no pounds flash); the legacy profile picker and the Health-tab control agree after either is changed; onboarding creates a profile matching the current global. VoiceOver reads the control.

## 6. Out of scope

- Merging Temperature into this control (stays an independent °C/°F setting, per Leo — the new control sits *beside* it).
- Height display anywhere on the Timeline (no height events); the legacy profile's height/weight *rendering* logic (unchanged — it reads the mirrored `unitPreference`).
- Fixing `UserProfile.unitPreference`'s `"imperial"` default for *existing untouched* profiles (reconciliation seeds the global from whatever the profile holds — consistent with the shipped behavior; not a units-default rewrite).
- Any HealthGraphCore change.

## 7. Invariants (for the reviewer)

1. No code path creates a `UserProfile` solely to store units.
2. The global is only ever `""`, `"imperial"`, or `"metric"`; an unknown string is never written to the global or to a profile.
3. The Timeline weight unit derives from the **global**, never from a profile `@Query`.
4. After launch (and after any control change), the global and an existing `profile.unitPreference` are equal.
5. A failed profile fetch/save never blocks startup and never invalidates the global.
