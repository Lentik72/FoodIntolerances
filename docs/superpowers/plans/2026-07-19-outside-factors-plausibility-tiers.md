# Outside Factors + Plausibility Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mine **full moon** and **mercury retrograde** as exposures, and add a **plausibility-tier framework** (established / contested / novelty) so each factor is presented honestly — nothing unproven reads as established science.

**Architecture:** Two new `DerivedExposureKind` cases + two `ExposureSource`s reading the already-emitted `.environment` events, registered in the engine. A pure `PlausibilityCatalog` maps an exposure's `fromCategory` → tier. The Insights feed routes **novelty** edges into a new "Just for fun" section and tags **contested** cards; **established** is unchanged. Gates and phrasing untouched.

**Tech Stack:** Swift, Swift Testing, GRDB, SwiftUI. Core via `swift test`; app via `xcodebuild ... -parallel-testing-enabled NO`.

Design: `docs/superpowers/specs/2026-07-19-outside-factors-plausibility-tiers-design.md`.

## Global Constraints

- **Two new `DerivedExposureKind` cases** (`fullMoon`, `mercuryRetrograde`) are additive. They force updates to every exhaustive `switch` over `DerivedExposureKind` — `EdgeIdentity.fromToken` and `EvidenceConfig.lagWindow(for:)`. Grep to confirm those are the only two; `parseFrom` is an `if`/`switch`-with-default (add cases), and `derivedExposureLabel` keys on a String (not the enum).
- **Exposure detection** (from the events `EnvironmentalEventFactory` already emits): full moon = a `.environment` event `subtype == "moonPhase"` with `metadata["phase"] == "Full Moon"`; mercury = `.environment` `subtype == "mercuryRetrograde"`.
- **Tier is keyed on the exposure's `fromCategory`:** `"fullMoon" → .contested`, `"mercuryRetrograde" → .novelty`, everything else `→ .established`. Orthogonal to the outcome.
- **Presentation:** novelty → a new `InsightSectionKind.justForFun` (rendered LAST); contested → an "unproven mechanism · your pattern" tag on the card; established → unchanged.
- **`InsightCardModel.tier` defaults to `.established`** so existing constructions (previews/tests) compile unchanged.
- **Gates + phrasing rule are unchanged** — a moon/mercury correlation still must clear significance+effect-size+stability; the tier is added honesty, not a new claim template. No causal language.
- **App-target tests MUST run `-parallel-testing-enabled NO`;** the lone `SwiftDataMigratorTests` `** TEST FAILED **` is the KNOWN pre-existing teardown crash.
- **Simulator:** iPhone 17 Pro (iOS 26.5).
- **Out of scope:** weather (temp/humidity) exposures (next round), opt-in toggles, season, any re-sort beyond the new section.
- **Intermediate state:** after Task 1 (mining) but before Task 2 (tiering), moon/mercury would surface as *un-tiered* plain evidence cards against real data. That's fine — nothing merges until all four tasks land; the branch is only reviewed/merged as a whole.

---

### Task 1: Core — full-moon & mercury exposures

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift` (`DerivedExposureKind`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/DerivedEventExposureSources.swift` (two new sources)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift` (register the sources, ~line 32-37)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EdgeIdentity.swift` (`fromToken`, `parseFrom`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift` (`lagWindow` + a lag field)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPhrasing.swift` (`derivedExposureLabel`)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift`, `EdgeIdentityTests.swift`, `InsightPhrasingTests.swift`

**Interfaces:** Produces `DerivedExposureKind.fullMoon` / `.mercuryRetrograde`, mined by the engine; edge tokens `"derived:fullMoon"` / `"derived:mercuryRetrograde"`; labels "Full moon" / "Mercury retrograde". Task 2 tiers them via `fromCategory`.

- [ ] **Step 1: Write the failing tests first.**

In `ExposureSourceTests.swift`, add (mirroring the pressure-drop tests — construct `.environment` events):

```swift
struct OutsideFactorExposureSourceTests {
    private func env(_ subtype: String, phase: String? = nil) -> HealthEvent {
        let meta = phase.map { try? JSONEncoder().encode(["phase": $0]) } ?? nil
        return HealthEvent(timestamp: Date(timeIntervalSince1970: 100), timezoneID: "UTC",
                           category: .environment, subtype: subtype, source: .weatherAPI, metadata: meta ?? nil)
    }
    @Test func fullMoonExtractsOnlyFullMoonPhase() {
        let occ = FullMoonExposureSource().occurrences(from: [
            env("moonPhase", phase: "Full Moon"), env("moonPhase", phase: "Waning Gibbous"),
            env("mercuryRetrograde")])
        #expect(occ.map(\.key) == [.derived(.fullMoon)])
    }
    @Test func mercuryExtractsRetrogradeEvents() {
        let occ = MercuryRetrogradeExposureSource().occurrences(from: [
            env("mercuryRetrograde"), env("moonPhase", phase: "Full Moon")])
        #expect(occ.map(\.key) == [.derived(.mercuryRetrograde)])
    }
}
```

In `EdgeIdentityTests.swift`, extend `derivedExposuresRoundTrip`:

```swift
        roundTrip(.derived(.fullMoon), .symptom("headache"))
        roundTrip(.derived(.mercuryRetrograde), .lowMood)
```

In `InsightPhrasingTests.swift`, extend `derivedLabels`:

```swift
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "fullMoon") == "Full moon")
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "mercuryRetrograde") == "Mercury retrograde")
```

In `ExposureSourceTests.swift`, extend `EvidenceConfigTests.lagWindowsByExposureKind` (pins the lag wiring — the exhaustive switch forces a *case*, but only a test catches a wrong *value*, e.g. copy-pasting `pressureLagHours`):

```swift
        #expect(c.lagWindow(for: .derived(.fullMoon)) == 0...24)
        #expect(c.lagWindow(for: .derived(.mercuryRetrograde)) == 0...24)
```

- [ ] **Step 2: Run to confirm failure.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → FAIL to compile (`.fullMoon`/`FullMoonExposureSource` undefined).

- [ ] **Step 3: Add the enum cases.** In `ExposureModel.swift`:

```swift
public enum DerivedExposureKind: Sendable, Equatable, Hashable {
    case shortSleep, highStress, pressureDrop
    case cyclePhase(CyclePhase)
    case fullMoon, mercuryRetrograde
}
```

- [ ] **Step 4: Add the two sources.** Append to `DerivedEventExposureSources.swift`:

```swift
/// Mercury-retrograde exposures. EnvironmentalEventFactory emits a
/// `subtype: "mercuryRetrograde"` event on retrograde days.
public struct MercuryRetrogradeExposureSource: ExposureSource {
    public init() {}
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .environment, e.subtype == "mercuryRetrograde" else { return nil }
            return ExposureOccurrence(key: .derived(.mercuryRetrograde), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}

/// Full-moon exposures. The factory emits a daily `subtype: "moonPhase"` event with
/// the cleaned phase name in metadata; the "Full Moon" bucket spans ~2 days/cycle.
public struct FullMoonExposureSource: ExposureSource {
    public init() {}
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .environment, e.subtype == "moonPhase", let data = e.metadata,
                  let meta = try? JSONDecoder().decode([String: String].self, from: data),
                  meta["phase"] == "Full Moon" else { return nil }
            return ExposureOccurrence(key: .derived(.fullMoon), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
```

- [ ] **Step 5: Register the sources.** In `EvidenceEngine.swift`, add to the `sources` array (after `CyclePhaseExposureSource(...)`):

```swift
            FullMoonExposureSource(),
            MercuryRetrogradeExposureSource(),
```

- [ ] **Step 6: Edge identity.** In `EdgeIdentity.swift`:
  - `fromToken`, in the `.derived(kind)` switch, add: `case .fullMoon: return "derived:fullMoon"` and `case .mercuryRetrograde: return "derived:mercuryRetrograde"`.
  - `parseFrom`, in the `derived:` `switch kind`, add: `case "fullMoon": return .derived(.fullMoon)` and `case "mercuryRetrograde": return .derived(.mercuryRetrograde)`.

- [ ] **Step 7: Lag windows.** In `EvidenceConfig.swift`, add a field near the other lag ranges:

```swift
    public var outsideFactorLagHours: ClosedRange<Double> = 0...24   // moon/mercury: same-day
```

and in `lagWindow(for:)`'s `.derived(kind)` switch, add: `case .fullMoon, .mercuryRetrograde: return outsideFactorLagHours`.

- [ ] **Step 8: Phrasing labels.** In `InsightPhrasing.derivedExposureLabel`, add before `default`:

```swift
        case "fullMoon": return "Full moon"
        case "mercuryRetrograde": return "Mercury retrograde"
```

- [ ] **Step 9: Run the full core suite.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → all green. Report counts.

- [ ] **Step 10: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/DerivedEventExposureSources.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EdgeIdentity.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPhrasing.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EdgeIdentityTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/InsightPhrasingTests.swift
git commit -m "feat(core): mine full moon + mercury retrograde as exposures (outside factors)"
```

---

### Task 2: Core — plausibility-tier framework + feed routing

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Insights/PlausibilityCatalog.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPresentation.swift` (`InsightCardModel.tier`, `InsightSectionKind.justForFun`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightsFeed.swift` (tier + routing)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/PlausibilityCatalogTests.swift` (new), `InsightsFeedTests.swift`

**Interfaces:** Consumes `fromCategory` (Task 1's tokens). Produces `PlausibilityTier`, `PlausibilityCatalog.tier(forExposureCategory:)`, `InsightCardModel.tier`, `InsightSectionKind.justForFun`; novelty edges routed out of `.active` into `.justForFun`. Task 3's views read `card.tier` + the new section.

- [ ] **Step 1: Write the failing tests first.**

`PlausibilityCatalogTests.swift` (new):

```swift
import Testing
@testable import HealthGraphCore

struct PlausibilityCatalogTests {
    @Test func tiers() {
        #expect(PlausibilityCatalog.tier(forExposureCategory: "fullMoon") == .contested)
        #expect(PlausibilityCatalog.tier(forExposureCategory: "mercuryRetrograde") == .novelty)
        #expect(PlausibilityCatalog.tier(forExposureCategory: "food") == .established)
        #expect(PlausibilityCatalog.tier(forExposureCategory: "shortSleep") == .established)
        #expect(PlausibilityCatalog.tier(forExposureCategory: nil) == .established)
    }
}
```

In `InsightsFeedTests.swift`, add (build three active edges — food/symptom = established, fullMoon = contested, mercuryRetrograde = novelty — assert routing + tier):

```swift
    @Test func tiersRouteNoveltyToJustForFunAndTagContested() {
        let refNow = Date(timeIntervalSince1970: 1_700_000_000)
        func rel(from: String, key: String, daysAgo: Double = 30) -> Relationship {
            Relationship(fromCategory: from, toCategory: "symptom", type: .possibleTrigger,
                         evidenceCount: 6, contradictionCount: 2, confidence: 0.6, strength: 5, lagHours: 12,
                         firstSeen: refNow.addingTimeInterval(-daysAgo * 86_400), lastSeen: refNow,
                         lastRecomputed: refNow, status: .active, edgeKey: key, toSubtype: "headache")
        }
        func rr(_ r: Relationship, _ label: String) -> ResolvedRelationship {
            ResolvedRelationship(relationship: r, exposureLabel: label, outcomeLabel: "headache",
                                 exposureCategory: .food, recentOutcomes: [])
        }
        let feed = InsightsFeed.build([
            rr(rel(from: "food", key: "k-food"), "Dairy"),
            rr(rel(from: "fullMoon", key: "k-moon"), "Full moon"),
            rr(rel(from: "mercuryRetrograde", key: "k-merc", daysAgo: 1), "Mercury retrograde"),  // recent
        ], now: refNow)
        let active = feed.sections.first { $0.kind == .active }
        let fun = feed.sections.first { $0.kind == .justForFun }
        #expect(active?.cards.first { $0.claim.contains("Dairy") }?.tier == .established)
        #expect(active?.cards.first { $0.claim.contains("Full moon") }?.tier == .contested)
        #expect(active?.cards.contains { $0.claim.contains("Mercury") } == false)   // NOT in evidence feed
        #expect(fun?.cards.contains { $0.claim.contains("Mercury") } == true)        // in Just for fun
        #expect(fun?.cards.first?.isNew == false)   // recent novelty must NOT take a "New" slot
    }
    @Test func noJustForFunSectionWithoutNoveltyEdges() {
        let refNow = Date(timeIntervalSince1970: 1_700_000_000)
        let r = Relationship(fromCategory: "food", toCategory: "symptom", type: .possibleTrigger,
                             evidenceCount: 6, contradictionCount: 2, confidence: 0.6, strength: 5, lagHours: 12,
                             firstSeen: refNow.addingTimeInterval(-30 * 86_400), lastSeen: refNow,
                             lastRecomputed: refNow, status: .active, edgeKey: "k", toSubtype: "headache")
        let feed = InsightsFeed.build([ResolvedRelationship(
            relationship: r, exposureLabel: "Dairy", outcomeLabel: "headache",
            exposureCategory: .food, recentOutcomes: [])], now: refNow)
        #expect(feed.sections.contains { $0.kind == .justForFun } == false)   // no empty section
    }
```

- [ ] **Step 2: Run to confirm failure.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → FAIL to compile (`PlausibilityCatalog`/`.justForFun`/`.tier` undefined).

- [ ] **Step 3: Add the catalog.** `PlausibilityCatalog.swift`:

```swift
import Foundation

/// How plausible a *causal* link from this exposure is — the honesty layer over
/// the evidence gates. Established = known mechanism; contested = plausible but
/// weak/mixed evidence; novelty = no known mechanism (a curious coincidence).
public enum PlausibilityTier: Sendable, Equatable { case established, contested, novelty }

public enum PlausibilityCatalog {
    /// Keyed on the resolved `fromCategory` token (object categories like "food",
    /// or derived tokens like "fullMoon"). Everything not listed is established.
    public static func tier(forExposureCategory category: String?) -> PlausibilityTier {
        switch category {
        case "fullMoon":          return .contested
        case "mercuryRetrograde": return .novelty
        default:                  return .established
        }
    }
}
```

- [ ] **Step 4: Extend the presentation model.** In `InsightPresentation.swift`:
  - `InsightSectionKind`: `public enum InsightSectionKind: Sendable, Equatable { case active, noEffect, archive, justForFun }`.
  - `InsightCardModel`: add `public let tier: PlausibilityTier`, and add `tier: PlausibilityTier = .established` (with default) to its `public init`, setting `self.tier = tier`.

- [ ] **Step 5: Route + tag in the feed.** In `InsightsFeed.build`:
  - Add a helper: `func tier(_ rr: ResolvedRelationship) -> PlausibilityTier { PlausibilityCatalog.tier(forExposureCategory: rr.relationship.fromCategory) }`.
  - In `card(_:)`, pass `tier: tier(rr)` to `InsightCardModel(...)`.
  - Partition active: **delete** the existing line `let active = resolved.filter { $0.relationship.status == .active }` and replace it with the three lines below (`active` is redefined to the evidence-only set; the existing `recent`/`newIDs`/`activeCards` code then references this narrowed `active` unchanged):

```swift
        let activeAll = resolved.filter { $0.relationship.status == .active }
        let active = activeAll.filter { tier($0) != .novelty }        // evidence feed
        let justForFun = activeAll.filter { tier($0) == .novelty }    // curiosities
```

  (Leave `noEffect`/`archive` as-is. Compute `recent`/`newIDs` from `active` — i.e. the evidence set — so novelty edges don't take "New" slots.)
  - After building `activeCards`/`noEffectCards`/`archiveCards`, add:

```swift
        let justForFunCards = justForFun.sorted {
            $0.relationship.confidence != $1.relationship.confidence
                ? $0.relationship.confidence > $1.relationship.confidence : idTiebreak($0, $1) }.map(card)
```

  - Append the section LAST (after archive):

```swift
        if !justForFunCards.isEmpty { sections.append(InsightSection(kind: .justForFun, cards: justForFunCards)) }
```

- [ ] **Step 6: Run the full core suite.** `cd HealthGraphCore && swift test 2>&1 | tail -20` → all green (incl. the new catalog + routing tests; existing feed tests still pass). Report counts.

- [ ] **Step 7: Commit.**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Insights/PlausibilityCatalog.swift \
        HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPresentation.swift \
        HealthGraphCore/Sources/HealthGraphCore/Insights/InsightsFeed.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/PlausibilityCatalogTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/InsightsFeedTests.swift
git commit -m "feat(core): plausibility tiers — route novelty to 'Just for fun', tag contested edges"
```

---

### Task 3: App — "Just for fun" section + contested tag

**Files:**
- Modify: `Views/HealthOS/Insights/InsightsView.swift` (`sectionView` — add `.justForFun`)
- Modify: `Views/HealthOS/Insights/InsightCardView.swift` (contested tag)
- Modify: `Views/HealthOS/Insights/InsightsViewModel.swift` (`exposure(for:)` — map the new tokens to the `.environment` icon)
- Test: `Food IntolerancesTests/InsightsViewModelTests.swift` (novelty → justForFun; contested → active + tag)

**Interfaces:** Consumes `InsightSectionKind.justForFun` + `card.tier` from Task 2.

- [ ] **Step 1: Write the failing VM test first.** In `InsightsViewModelTests.swift`, add (seeds a mercury edge → asserts it lands in the `.justForFun` section, not `.active`):

```swift
    @Test func mercuryEdgeSurfacesUnderJustForFun() async throws {
        let refNow = Date(timeIntervalSince1970: 1_713_000_000)
        let db = try AppDatabase.inMemory()
        let merc = Relationship(
            fromCategory: "mercuryRetrograde", toCategory: "symptom", type: .possibleTrigger,
            evidenceCount: 6, contradictionCount: 2, confidence: 0.6, strength: 5, lagHours: 12,
            firstSeen: refNow.addingTimeInterval(-30 * 86_400), lastSeen: refNow, lastRecomputed: refNow,
            status: .active, edgeKey: "derived:mercuryRetrograde|symptom:headache|possibleTrigger",
            toSubtype: "headache")
        try await GRDBRelationshipStore(database: db).save(merc)
        let vm = InsightsViewModel(database: db, now: { refNow })
        await vm.load()
        #expect(vm.feed.sections.contains { $0.kind == .justForFun } == true)
        #expect(vm.feed.sections.first { $0.kind == .active } == nil)   // no evidence card for a novelty edge
    }
    @Test func fullMoonEdgeSurfacesInActiveWithContestedTier() async throws {
        let refNow = Date(timeIntervalSince1970: 1_713_000_000)
        let db = try AppDatabase.inMemory()
        let moon = Relationship(
            fromCategory: "fullMoon", toCategory: "symptom", type: .possibleTrigger,
            evidenceCount: 6, contradictionCount: 2, confidence: 0.6, strength: 5, lagHours: 12,
            firstSeen: refNow.addingTimeInterval(-30 * 86_400), lastSeen: refNow, lastRecomputed: refNow,
            status: .active, edgeKey: "derived:fullMoon|symptom:headache|possibleTrigger", toSubtype: "headache")
        try await GRDBRelationshipStore(database: db).save(moon)
        let vm = InsightsViewModel(database: db, now: { refNow })
        await vm.load()
        let card = vm.feed.sections.first { $0.kind == .active }?.cards.first
        #expect(card?.tier == .contested)                              // contested stays in the evidence feed…
        #expect(card?.claim.contains("Full moon") == true)             // …phrased + labeled via exposure(for:)
    }
```

- [ ] **Step 2: Add the section view.** In `InsightsView.sectionView`, add a case before the closing brace (the `switch` is currently `.active`/`.noEffect`/`.archive`):

```swift
        case .justForFun:
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Just for fun")
                        .font(HealthTheme.sectionHeader())
                        .foregroundStyle(HealthTheme.ink)
                    Text("Curious coincidences from your data — correlation isn't causation, and there's no known mechanism.")
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkSecondary)
                }
                cardsStack(section.cards, dismissable: false)
            }
```

- [ ] **Step 3: Add the contested tag.** In `InsightCardView`, inside the `NavigationLink`'s `VStack`, immediately after the claim `HStack` (the one with the icon + `card.claim`), add:

```swift
                    if card.tier == .contested {
                        Text("unproven mechanism · your pattern")
                            .font(.caption)
                            .foregroundStyle(HealthTheme.inkMuted)
                    }
```

- [ ] **Step 3b: Fix the card icon for the new factors.** In `InsightsViewModel.swift`'s `exposure(for:)`, the derived-`fromCategory` → representative-`EventCategory` mapping (used for the card icon) sends `"pressureDrop"` → `.environment` but has no branch for the two new tokens, so `"fullMoon"`/`"mercuryRetrograde"` fall through to `.note` (a generic "Context" icon). Add both to the **`.environment`** branch (they're `.environment` events too), mirroring `"pressureDrop"`.

- [ ] **Step 4: Build + VM tests.**

Run: `xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -8` → `** BUILD SUCCEEDED **`.

Run: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests/InsightsViewModelTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "Test run with|✔ Test|✘ Test|TEST (SUCCEEDED|FAILED)" | tail -10` → `** TEST SUCCEEDED **` (existing tests + `mercuryEdgeSurfacesUnderJustForFun` + `fullMoonEdgeSurfacesInActiveWithContestedTier`).

- [ ] **Step 5: Commit.**

```bash
git add "Views/HealthOS/Insights/InsightsView.swift" \
        "Views/HealthOS/Insights/InsightCardView.swift" \
        "Views/HealthOS/Insights/InsightsViewModel.swift" \
        "Food IntolerancesTests/InsightsViewModelTests.swift"
git commit -m "feat(app): 'Just for fun' section + 'unproven mechanism' tag + environment icon for moon/mercury"
```

---

### Task 4: Debug demo seed + end-to-end verification

**Files:**
- Modify: `Views/HealthGraphDebugView.swift` (a "Load OUTSIDE-FACTORS demo" button + seed)

**Interfaces:** Consumes the exposure sources (Task 1) + tier routing (Task 2). Reuses `EvidenceEngine(database:).recompute(asOf:)` (public, already used in the debug view).

- [ ] **Step 1: Add the demo seed.** In `HealthGraphDebugView.swift`, add a button next to "Load MOOD demo data" and a `loadOutsideFactorsDemo()` that hand-generates ~200 days of `.environment` events with a correlated symptom, then recomputes. Emit, over the range: a `moonPhase` event each day (metadata `["phase": ...]`, "Full Moon" on ~2 days per ~29.5-day cycle, other phases otherwise); a `mercuryRetrograde` event on a few multi-week windows; and a correlated `.symptom` "headache" following full-moon days (~70%) and retrograde days (~70%), with light baseline noise. Then `try await EvidenceEngine(database: database).recompute(asOf: Date())` and `await refresh()`. Reuse `loadMoodDemo()`'s `isWorking`/`defer`/`do-catch` shell, but **hand-build a `[HealthEvent]` array and save via `GRDBEventStore(database: database).save(_:)`** (public) — `loadMoodDemo` itself seeds via `SyntheticDataGenerator.insert`, but the generator can't emit moon/mercury `.environment` events, so build them directly here. Keep it DEBUG-only, APPENDS (reset first).

  (Implementer: pick the exact day-marking logic; the goal is enough full-moon days [~14] and retrograde days [~40] with a ~70% headache follow-rate to clear the gates so both a contested "Full moon → headache" card and a novelty "Mercury retrograde → headache" card appear after recompute.)

- [ ] **Step 2: Build + full regression.**
  - App build succeeds.
  - Core: `cd HealthGraphCore && swift test 2>&1 | tail -3` → all green.
  - App target: `xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -only-testing:"Food IntolerancesTests" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "✔ Suite|✘|Test run with|\*\* TEST"` → every suite green except the known `SwiftDataMigratorTests` crash.

- [ ] **Step 3: On-device / simulator check** (device preferred). Health tab → Health Graph Debug → Reset → **"Load OUTSIDE-FACTORS demo"** → Insights:
  - **"Full moon is linked to more headaches"** (or similar) appears in the evidence feed with an **"unproven mechanism · your pattern"** tag.
  - **"Mercury retrograde …"** appears ONLY under a **"Just for fun"** section at the bottom, with the coincidence subtext — never as an evidence card.
  - Established factors (if seeded) carry no tag.
  - Phrasing stays tentative ("seems to"/"is linked to"); light + dark; XXL Dynamic Type.

- [ ] **Step 4: Record observed behavior** in the review notes / ledger.

---

## Definition of Done

- The engine mines **full moon** and **mercury retrograde** as exposures (from the already-emitted environmental events); both round-trip through edge identity and have labels + lag windows.
- Every insight carries a **plausibility tier** (keyed on the exposure): established (plain), contested (evidence feed + "unproven mechanism" tag), novelty (a separate **"Just for fun"** section, never an evidence card).
- The evidence gates + tentative phrasing rule are unchanged; no causal language; no re-sort beyond the added section.
- Core (exposures, identity, labels, `PlausibilityCatalog`, feed routing) unit-tested; the app section + tag wired + VM-tested; a debug demo seed for device verification.
- Out of scope (unchanged commitments): weather (temp/humidity) exposures = next round; no opt-in toggles; season not added.
