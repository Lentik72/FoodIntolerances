# Phase 2B — Insights Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Turn 2A's mined `relationships` into the Insights tab — sectioned cards with word-scale badges + per-exposure dots, an `evidence(for:)` drill-down, deterministic phrasing, dismiss, an honest empty state — and schedule recompute via a single debounced coordinator.

**Architecture:** Pure phrasing / feed / surfacing / recompute-policy logic in `HealthGraphCore` (unit-tested); a thin `@MainActor` `InsightsViewModel` + SwiftUI views + one `InsightsRefreshCoordinator` in the app. Read-only over `relationships` (plus the dismiss status write).

**Tech Stack:** Swift 5.9+, SwiftUI, GRDB, Swift Testing. Package `HealthGraphCore`; app target `Food_Intolerances`.

## Global Constraints

- **Swift Testing** everywhere (`import Testing`, `@Test`, `#expect`). Package tests: `@testable import HealthGraphCore`, in-memory DB `try AppDatabase.inMemory()`. App tests (`Food IntolerancesTests/`): `import HealthGraphCore` + `@testable import Food_Intolerances`, `@MainActor struct`, in-memory DB, ViewModels take **injectable stores** and a `now: @escaping () -> Date` closure for determinism (mirror `HomeViewModelTests`).
- **Determinism:** `now`/`Date()` only in the app coordinator/VM (injected in tests); core phrasing/feed/policy are pure functions of their inputs.
- **No causal language** in any user-facing phrasing — "associated with", "followed", "we observed"; NEVER "causes", "triggers" (as a certainty), "makes". Enforced by a unit test.
- **Visual language:** reuse `HealthTheme` tokens (`paper`, `card`, `cardBorder`, `ink`, `inkSecondary`, `accent`, `amber` = dot hits, `dotMiss` = dot misses, `onAccent`, `screenTitle()`, `sectionHeader()`, `cardCornerRadius`) and `CategoryStyle.style(for:)` for the exposure icon. Dynamic Type + VoiceOver labels on cards/dots/badges. Light + dark.
- **DB access in the app:** `HealthGraphProvider.shared` (an `AppDatabase`). ViewModels/coordinator default to it, but accept an injected `AppDatabase`/stores for tests.
- The engine, extraction, scoring, and migrations are NOT touched. 2B is read-only over `relationships` except the dismiss write (`status = .userDismissed`), which `recompute` already preserves.
- Build/test: package `cd HealthGraphCore && swift test`; app target builds/tests via Xcode (`xcodebuild ... -scheme "Food Intolerances" test` or the project's usual command).

---

## File Structure

**New (core, pure):** `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPresentation.swift`, `InsightPhrasing.swift`, `InsightsFeed.swift`, `RecomputePolicy.swift` (+ package tests).
**New (app):** `Views/HealthOS/Insights/InsightsView.swift`, `InsightsViewModel.swift`, `InsightCardView.swift`, `InsightBadgeView.swift`, `EvidenceDotsView.swift`, `InsightDetailView.swift`, `InsightsRefreshCoordinator.swift` (+ app tests).
**Modified:** `Views/HealthOS/Shell/HealthOSRootView.swift` (swap `InsightsPlaceholderView()` → `InsightsView(...)`). `InsightsPlaceholderView.swift`'s coverage content is reused as the empty state (Task 6).

---

## Task 1: `InsightPresentation` types + `InsightPhrasing` (pure)

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPresentation.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPhrasing.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/InsightPhrasingTests.swift`

**Interfaces:**
- Produces: `BadgeTier { earlySignal, moderate, strong }`; `ResolvedRelationship { relationship: Relationship, exposureLabel: String, outcomeLabel: String, exposureCategory: EventCategory }`; `InsightPhrasing` with `claim(_:) -> String`, `badge(confidence:) -> BadgeTier`, `subline(_:) -> String`, and `derivedExposureLabel(fromCategory:) -> String?`.

- [ ] **Step 1: Write the failing test** — create `InsightPhrasingTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct InsightPhrasingTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    func rel(type: RelationshipType, confidence: Double, toSubtype: String,
             strength: Double? = 5, lagHours: Double? = 12, ev: Int = 6, contra: Int = 2) -> Relationship {
        Relationship(fromCategory: "food", toCategory: "symptom", type: type,
                     evidenceCount: ev, contradictionCount: contra, confidence: confidence,
                     strength: strength, lagHours: lagHours, firstSeen: now, lastSeen: now,
                     lastRecomputed: now, status: .active, edgeKey: "k", toSubtype: toSubtype)
    }
    func resolved(_ r: Relationship, exposure: String = "Dairy", outcome: String = "bloating") -> ResolvedRelationship {
        ResolvedRelationship(relationship: r, exposureLabel: exposure, outcomeLabel: outcome, exposureCategory: .food)
    }

    @Test func triggerClaimAndBadgeAndSubline() {
        let rr = resolved(rel(type: .possibleTrigger, confidence: 0.6, toSubtype: "bloating"))
        #expect(InsightPhrasing.claim(rr) == "Dairy → bloating")
        #expect(InsightPhrasing.badge(confidence: 0.6) == .moderate)
        let sub = InsightPhrasing.subline(rr)
        #expect(sub.contains("~12h"))
        #expect(sub.contains("severity"))
    }
    @Test func improvesPhrasesProtectively() {
        let rr = resolved(rel(type: .improves, confidence: 0.6, toSubtype: "migraine"),
                          exposure: "Magnesium", outcome: "migraine")
        #expect(InsightPhrasing.claim(rr) == "Magnesium → fewer migraine")
    }
    @Test func badgeTiers() {
        #expect(InsightPhrasing.badge(confidence: 0.4) == .earlySignal)
        #expect(InsightPhrasing.badge(confidence: 0.5) == .moderate)
        #expect(InsightPhrasing.badge(confidence: 0.75) == .moderate)   // ceiling: strong needs >0.75
        #expect(InsightPhrasing.badge(confidence: 0.8) == .strong)
    }
    @Test func derivedLabels() {
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "shortSleep") == "Short sleep")
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "cyclePhase.luteal") == "Luteal phase")
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "food") == nil)   // objects resolve via name
    }
    @Test func noCausalLanguage() {
        let forbidden = ["cause", "causes", "triggers ", "makes you", "guarantee"]
        for type in [RelationshipType.possibleTrigger, .improves, .noEffect] {
            let rr = resolved(rel(type: type, confidence: 0.6, toSubtype: "bloating"))
            let text = (InsightPhrasing.claim(rr) + " " + InsightPhrasing.subline(rr)).lowercased()
            for word in forbidden { #expect(!text.contains(word), "phrasing must avoid causal word '\(word)'") }
        }
    }
}
```

- [ ] **Step 2: Run to verify failure** — `cd HealthGraphCore && swift test --filter InsightPhrasingTests`. Expected: FAIL (types undefined).

- [ ] **Step 3: Create `InsightPresentation.swift`:**

```swift
import Foundation

public enum BadgeTier: String, Sendable, Equatable { case earlySignal, moderate, strong }

/// A mined relationship plus its resolved human labels (object name / derived phrase,
/// outcome subtype) and a representative category for the exposure's icon.
public struct ResolvedRelationship: Sendable, Equatable {
    public let relationship: Relationship
    public let exposureLabel: String
    public let outcomeLabel: String
    public let exposureCategory: EventCategory
    public init(relationship: Relationship, exposureLabel: String,
                outcomeLabel: String, exposureCategory: EventCategory) {
        self.relationship = relationship; self.exposureLabel = exposureLabel
        self.outcomeLabel = outcomeLabel; self.exposureCategory = exposureCategory
    }
}

/// One card's display data. Dots come straight from the stored counts (no query).
public struct InsightCardModel: Sendable, Equatable, Identifiable {
    public let id: UUID              // relationship id
    public let claim: String
    public let exposureCategory: EventCategory
    public let badge: BadgeTier
    public let filledDots: Int       // evidenceCount
    public let hollowDots: Int       // contradictionCount
    public let subline: String
    public let isNew: Bool
    public let kind: RelationshipType
}

public enum InsightSectionKind: Sendable, Equatable { case active, noEffect, archive }
public struct InsightSection: Sendable, Equatable, Identifiable {
    public var id: InsightSectionKind { kind }
    public let kind: InsightSectionKind
    public let cards: [InsightCardModel]
}
public struct InsightsFeedModel: Sendable, Equatable {
    public let sections: [InsightSection]   // active, noEffect, archive (empties omitted)
}

public struct InsightsConfig: Sendable {
    public var newPerWeek = 3
    public var newWindowDays = 7.0
    public var earlyMax = 0.5
    public var strongMin = 0.75
    public init() {}
    public static let `default` = InsightsConfig()
}
```

- [ ] **Step 4: Create `InsightPhrasing.swift`:**

```swift
import Foundation

/// Deterministic, template-based user-facing text. NO causal language (spec §7).
public enum InsightPhrasing {
    public static func claim(_ rr: ResolvedRelationship) -> String {
        switch rr.relationship.type {
        case .improves: return "\(rr.exposureLabel) → fewer \(rr.outcomeLabel)"
        default:        return "\(rr.exposureLabel) → \(rr.outcomeLabel)"
        }
    }

    public static func badge(confidence: Double, config: InsightsConfig = .default) -> BadgeTier {
        if confidence > config.strongMin { return .strong }
        if confidence >= config.earlyMax { return .moderate }
        return .earlySignal
    }

    public static func subline(_ rr: ResolvedRelationship) -> String {
        let r = rr.relationship
        var parts: [String] = []
        if let lag = r.lagHours { parts.append("usually within ~\(Int(lag.rounded()))h") }
        if let s = r.strength { parts.append(String(format: "avg severity +%.1f", s)) }
        return parts.joined(separator: " · ")
    }

    /// Human phrase for a derived-exposure `fromCategory` token; nil for object edges
    /// (those resolve via the object's name).
    public static func derivedExposureLabel(fromCategory: String) -> String? {
        switch fromCategory {
        case "shortSleep": return "Short sleep"
        case "highStress": return "High stress"
        case "pressureDrop": return "Pressure drops"
        case "cyclePhase.menstrual": return "Menstrual phase"
        case "cyclePhase.luteal": return "Luteal phase"
        default: return nil
        }
    }
}
```

- [ ] **Step 5: Run to verify pass** — `cd HealthGraphCore && swift test --filter InsightPhrasingTests`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPresentation.swift \
        HealthGraphCore/Sources/HealthGraphCore/Insights/InsightPhrasing.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/InsightPhrasingTests.swift
git commit -m "feat(core): Insights presentation types + InsightPhrasing (no-causal-language templates)"
```

---

## Task 2: `InsightsFeed` (pure sectioning + ranking + ≤3/week New)

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Insights/InsightsFeed.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/InsightsFeedTests.swift`

**Interfaces:**
- Produces: `InsightsFeed.build(_ resolved: [ResolvedRelationship], now: Date, config: InsightsConfig = .default) -> InsightsFeedModel`.
- Behavior: partition by status — **active** (`.active`), **noEffect** (`.confirmedNoEffect`), **archive** (`.decayed` + `.userDismissed`). Active sorted confidence desc then lastSeen desc; noEffect by lastSeen desc; archive by lastRecomputed desc. **New flag:** among active edges with `firstSeen ≥ now − newWindowDays`, the top `newPerWeek` by `confidence × novelty` (novelty = `1 − ageDays/newWindowDays`, clamped ≥0) get `isNew = true`; New edges sort ahead of non-New within active. Each card built via `InsightPhrasing`.

- [ ] **Step 1: Write the failing test** — create `InsightsFeedTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct InsightsFeedTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    func rr(_ status: RelStatus, conf: Double, firstSeenDaysAgo: Double, type: RelationshipType = .possibleTrigger,
            outcome: String) -> ResolvedRelationship {
        let fs = now.addingTimeInterval(-firstSeenDaysAgo * 86_400)
        let r = Relationship(fromCategory: "food", toCategory: "symptom", type: type,
                             evidenceCount: 6, contradictionCount: 2, confidence: conf,
                             strength: 5, lagHours: 12, firstSeen: fs, lastSeen: now,
                             lastRecomputed: now, status: status, edgeKey: "k-\(outcome)-\(conf)", toSubtype: outcome)
        return ResolvedRelationship(relationship: r, exposureLabel: "Food", outcomeLabel: outcome, exposureCategory: .food)
    }

    @Test func sectionsByStatus() {
        let feed = InsightsFeed.build([
            rr(.active, conf: 0.6, firstSeenDaysAgo: 30, outcome: "bloating"),
            rr(.confirmedNoEffect, conf: 0.5, firstSeenDaysAgo: 100, type: .noEffect, outcome: "fatigue"),
            rr(.decayed, conf: 0.2, firstSeenDaysAgo: 200, outcome: "headache"),
            rr(.userDismissed, conf: 0.6, firstSeenDaysAgo: 40, outcome: "nausea"),
        ], now: now)
        let byKind = Dictionary(uniqueKeysWithValues: feed.sections.map { ($0.kind, $0.cards) })
        #expect(byKind[.active]?.count == 1)
        #expect(byKind[.noEffect]?.count == 1)
        #expect(byKind[.archive]?.count == 2)   // decayed + dismissed
    }

    @Test func newFlagCapsAtThreeMostConfidentRecent() {
        // 4 recent (≤7d) active + 1 old active. Only top-3 recent by conf×novelty are New.
        var input = [
            rr(.active, conf: 0.70, firstSeenDaysAgo: 1, outcome: "a"),
            rr(.active, conf: 0.65, firstSeenDaysAgo: 2, outcome: "b"),
            rr(.active, conf: 0.60, firstSeenDaysAgo: 3, outcome: "c"),
            rr(.active, conf: 0.55, firstSeenDaysAgo: 4, outcome: "d"),
            rr(.active, conf: 0.72, firstSeenDaysAgo: 90, outcome: "old"),  // not recent → never New
        ]
        var rng = SeededGenerator(seed: 1); input.shuffle(using: &rng)   // order-independence
        let active = InsightsFeed.build(input, now: now).sections.first { $0.kind == .active }!.cards
        let newOutcomes = Set(active.filter(\.isNew).map { $0.claim })
        #expect(active.filter(\.isNew).count == 3)
        #expect(!newOutcomes.contains { $0.contains("old") })   // old edge is not New despite high conf
        // New cards sort ahead of non-New.
        #expect(active.prefix(3).allSatisfy(\.isNew))
    }
}
```

- [ ] **Step 2: Run to verify failure** — `cd HealthGraphCore && swift test --filter InsightsFeedTests`. Expected: FAIL.

- [ ] **Step 3: Create `InsightsFeed.swift`:**

```swift
import Foundation

public enum InsightsFeed {
    public static func build(_ resolved: [ResolvedRelationship], now: Date,
                             config: InsightsConfig = .default) -> InsightsFeedModel {
        let active = resolved.filter { $0.relationship.status == .active }
        let noEffect = resolved.filter { $0.relationship.status == .confirmedNoEffect }
        let archive = resolved.filter { $0.relationship.status == .decayed || $0.relationship.status == .userDismissed }

        // "New" selection: recent active edges, top N by confidence × novelty.
        func novelty(_ r: Relationship) -> Double {
            let ageDays = now.timeIntervalSince(r.firstSeen) / 86_400
            return max(0, 1 - ageDays / config.newWindowDays)
        }
        let recent = active.filter { now.timeIntervalSince($0.relationship.firstSeen) / 86_400 <= config.newWindowDays }
        let newIDs = Set(recent
            .sorted { $0.relationship.confidence * novelty($0.relationship)
                    > $1.relationship.confidence * novelty($1.relationship) }
            .prefix(config.newPerWeek)
            .map { $0.relationship.id })

        func card(_ rr: ResolvedRelationship) -> InsightCardModel {
            let r = rr.relationship
            return InsightCardModel(
                id: r.id, claim: InsightPhrasing.claim(rr), exposureCategory: rr.exposureCategory,
                badge: InsightPhrasing.badge(confidence: r.confidence),
                filledDots: r.evidenceCount, hollowDots: r.contradictionCount,
                subline: InsightPhrasing.subline(rr), isNew: newIDs.contains(r.id), kind: r.type)
        }

        let activeCards = active
            .sorted { lhs, rhs in
                let ln = newIDs.contains(lhs.relationship.id), rn = newIDs.contains(rhs.relationship.id)
                if ln != rn { return ln }                                   // New first
                if lhs.relationship.confidence != rhs.relationship.confidence {
                    return lhs.relationship.confidence > rhs.relationship.confidence
                }
                return lhs.relationship.lastSeen > rhs.relationship.lastSeen
            }.map(card)
        let noEffectCards = noEffect.sorted { $0.relationship.lastSeen > $1.relationship.lastSeen }.map(card)
        let archiveCards = archive.sorted { $0.relationship.lastRecomputed > $1.relationship.lastRecomputed }.map(card)

        var sections: [InsightSection] = []
        if !activeCards.isEmpty { sections.append(InsightSection(kind: .active, cards: activeCards)) }
        if !noEffectCards.isEmpty { sections.append(InsightSection(kind: .noEffect, cards: noEffectCards)) }
        if !archiveCards.isEmpty { sections.append(InsightSection(kind: .archive, cards: archiveCards)) }
        return InsightsFeedModel(sections: sections)
    }
}
```

- [ ] **Step 4: Run to verify pass** — `cd HealthGraphCore && swift test --filter InsightsFeedTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Insights/InsightsFeed.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/InsightsFeedTests.swift
git commit -m "feat(core): InsightsFeed — section/rank + ≤3/week New selection (confidence × novelty)"
```

---

## Task 3: `RecomputePolicy` (pure debounce decision)

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Insights/RecomputePolicy.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/RecomputePolicyTests.swift`

**Interfaces:**
- Produces: `RecomputePolicy.shouldRecompute(lastRunAt: Date?, lastWatermark: Int, now: Date, currentWatermark: Int, minInterval: TimeInterval) -> Bool`. Recompute iff never run, OR the watermark changed since last run, OR `now − lastRunAt ≥ minInterval`. (Watermark = a monotonic signal of event changes, e.g. `EventStore.count`; a change means new/deleted events.)

- [ ] **Step 1: Write the failing test** — create `RecomputePolicyTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct RecomputePolicyTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let interval: TimeInterval = 900   // 15 min

    @Test func recomputesWhenNeverRun() {
        #expect(RecomputePolicy.shouldRecompute(lastRunAt: nil, lastWatermark: 0, now: now,
                                                currentWatermark: 0, minInterval: interval))
    }
    @Test func recomputesWhenWatermarkChanged() {
        #expect(RecomputePolicy.shouldRecompute(lastRunAt: now, lastWatermark: 10, now: now.addingTimeInterval(60),
                                                currentWatermark: 11, minInterval: interval))
    }
    @Test func skipsWhenRecentAndUnchanged() {
        #expect(!RecomputePolicy.shouldRecompute(lastRunAt: now, lastWatermark: 10,
                                                 now: now.addingTimeInterval(60), currentWatermark: 10, minInterval: interval))
    }
    @Test func recomputesAfterIntervalEvenIfUnchanged() {
        #expect(RecomputePolicy.shouldRecompute(lastRunAt: now, lastWatermark: 10,
                                                now: now.addingTimeInterval(1000), currentWatermark: 10, minInterval: interval))
    }
}
```

- [ ] **Step 2: Run to verify failure** — `cd HealthGraphCore && swift test --filter RecomputePolicyTests`. Expected: FAIL.

- [ ] **Step 3: Create `RecomputePolicy.swift`:**

```swift
import Foundation

/// Pure debounce decision for when the app should re-mine the graph.
public enum RecomputePolicy {
    public static func shouldRecompute(lastRunAt: Date?, lastWatermark: Int, now: Date,
                                       currentWatermark: Int, minInterval: TimeInterval) -> Bool {
        guard let lastRunAt else { return true }              // never run
        if currentWatermark != lastWatermark { return true }  // events changed
        return now.timeIntervalSince(lastRunAt) >= minInterval
    }
}
```

- [ ] **Step 4: Run to verify pass** — `cd HealthGraphCore && swift test --filter RecomputePolicyTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Insights/RecomputePolicy.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/RecomputePolicyTests.swift
git commit -m "feat(core): RecomputePolicy — pure shouldRecompute debounce decision"
```

---

## Task 4: `InsightsRefreshCoordinator` (app)

**Files:**
- Create: `Views/HealthOS/Insights/InsightsRefreshCoordinator.swift`
- Test: `Food IntolerancesTests/InsightsRefreshCoordinatorTests.swift`

**Interfaces:**
- Produces: `@MainActor final class InsightsRefreshCoordinator: ObservableObject` with `init(database: AppDatabase = HealthGraphProvider.shared, minInterval: TimeInterval = 900, now: @escaping () -> Date = { Date() })`, `@Published private(set) var lastRecomputeAt: Date?`, and `func refreshIfNeeded() async`. On a needed run (via `RecomputePolicy`, watermark = `EventStore.count`), it calls `EvidenceEngine(database:).recompute(asOf: now())`, updates its watermark + `lastRecomputeAt`. A `scheduleBackgroundRecompute()` stub documents the BGTask extension point.

- [ ] **Step 1: Write the failing test** — create `InsightsRefreshCoordinatorTests.swift` in `Food IntolerancesTests/`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct InsightsRefreshCoordinatorTests {
    @Test func recomputesOnceForUnchangedDataWithinInterval() async throws {
        let db = try AppDatabase.inMemory()
        // Seed a strong dairy→bloating signal so recompute produces an edge.
        try await SyntheticDataGenerator.generate(config: SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 1_700_000_000), days: 120, seed: 42,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food, outcomeSubtype: "bloating",
                                      lagHours: 8, lagJitterHours: 3, followProbability: 0.8, exposureProbabilityPerDay: 0.6)],
            outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 1...2)).insert(into: db)
        var t = Date(timeIntervalSince1970: 1_750_000_000)
        let coord = InsightsRefreshCoordinator(database: db, minInterval: 900, now: { t })
        await coord.refreshIfNeeded()
        let firstRun = coord.lastRecomputeAt
        #expect(firstRun != nil)
        let rels = try await GRDBRelationshipStore(database: db).count()
        #expect(rels > 0)                                  // recompute actually ran

        // Second call soon after, no data change → skipped (lastRecomputeAt unchanged).
        t = t.addingTimeInterval(60)
        await coord.refreshIfNeeded()
        #expect(coord.lastRecomputeAt == firstRun)
    }
}
```

- [ ] **Step 2: Run to verify failure** (Xcode/xcodebuild test on the app target, filtered to `InsightsRefreshCoordinatorTests`). Expected: FAIL (type undefined).

- [ ] **Step 3: Create `InsightsRefreshCoordinator.swift`:**

```swift
import Foundation
import HealthGraphCore

@MainActor
final class InsightsRefreshCoordinator: ObservableObject {
    @Published private(set) var lastRecomputeAt: Date?

    private let database: AppDatabase
    private let minInterval: TimeInterval
    private let now: () -> Date
    private var lastWatermark = 0
    private var isRunning = false

    init(database: AppDatabase = HealthGraphProvider.shared,
         minInterval: TimeInterval = 900, now: @escaping () -> Date = { Date() }) {
        self.database = database; self.minInterval = minInterval; self.now = now
    }

    func refreshIfNeeded() async {
        guard !isRunning else { return }
        let watermark = (try? await GRDBEventStore(database: database).count()) ?? lastWatermark
        guard RecomputePolicy.shouldRecompute(lastRunAt: lastRecomputeAt, lastWatermark: lastWatermark,
                                              now: now(), currentWatermark: watermark, minInterval: minInterval)
        else { return }
        isRunning = true
        defer { isRunning = false }
        _ = try? await EvidenceEngine(database: database).recompute(asOf: now())
        lastWatermark = watermark
        lastRecomputeAt = now()
    }

    /// Extension point (spec §6): register a nightly BGTask that calls the same recompute.
    /// Intentionally unimplemented for 2B.
    func scheduleBackgroundRecompute() { /* Phase 2B+: BGTaskScheduler wiring */ }
}
```

- [ ] **Step 4: Run to verify pass** (filtered app test). Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Insights/InsightsRefreshCoordinator.swift" \
        "Food IntolerancesTests/InsightsRefreshCoordinatorTests.swift"
git commit -m "feat(app): InsightsRefreshCoordinator — debounced recompute (RecomputePolicy), BGTask extension point"
```

---

## Task 5: `InsightsViewModel` (app)

**Files:**
- Create: `Views/HealthOS/Insights/InsightsViewModel.swift`
- Test: `Food IntolerancesTests/InsightsViewModelTests.swift`

**Interfaces:**
- Produces: `@MainActor final class InsightsViewModel: ObservableObject` with `init(database: AppDatabase = HealthGraphProvider.shared, now: @escaping () -> Date = { Date() })`, `@Published private(set) var feed: InsightsFeedModel`, `func load() async`, `func dismiss(_ card: InsightCardModel) async`. `load()` fetches relationships (all statuses via `RelationshipStore.all()`), resolves each into `ResolvedRelationship` (object name via `ObjectStore.object(id:)`; derived label via `InsightPhrasing.derivedExposureLabel`; exposure category from `fromCategory`/object kind), builds the feed via `InsightsFeed.build`. `dismiss` sets `status = .userDismissed` and saves, then reloads.

- [ ] **Step 1: Write the failing test** — create `InsightsViewModelTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct InsightsViewModelTests {
    func seedMinedDB() async throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try await SyntheticDataGenerator.generate(config: SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 1_700_000_000), days: 150, seed: 42,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food, outcomeSubtype: "bloating",
                                      lagHours: 8, lagJitterHours: 3, followProbability: 0.8, exposureProbabilityPerDay: 0.6)],
            outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 1...2)).insert(into: db)
        _ = try await EvidenceEngine(database: db).recompute(asOf: Date(timeIntervalSince1970: 1_713_000_000))
        return db
    }

    @Test func loadsActiveDairyBloatingCard() async throws {
        let db = try await seedMinedDB()
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 1_713_000_000) })
        await vm.load()
        let active = vm.feed.sections.first { $0.kind == .active }
        #expect(active?.cards.contains { $0.claim.lowercased().contains("dairy") && $0.claim.contains("bloating") } == true)
    }

    @Test func dismissMovesCardToArchive() async throws {
        let db = try await seedMinedDB()
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 1_713_000_000) })
        await vm.load()
        let card = vm.feed.sections.first { $0.kind == .active }!.cards.first!
        await vm.dismiss(card)
        let stillActive = vm.feed.sections.first { $0.kind == .active }?.cards.contains { $0.id == card.id } ?? false
        let inArchive = vm.feed.sections.first { $0.kind == .archive }?.cards.contains { $0.id == card.id } ?? false
        #expect(!stillActive)
        #expect(inArchive)
    }
}
```

- [ ] **Step 2: Run to verify failure.** Expected: FAIL.

- [ ] **Step 3: Create `InsightsViewModel.swift`:**

```swift
import Foundation
import HealthGraphCore

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var feed = InsightsFeedModel(sections: [])

    private let database: AppDatabase
    private let now: () -> Date
    private let relStore: GRDBRelationshipStore
    private let objectStore: GRDBObjectStore

    init(database: AppDatabase = HealthGraphProvider.shared, now: @escaping () -> Date = { Date() }) {
        self.database = database; self.now = now
        self.relStore = GRDBRelationshipStore(database: database)
        self.objectStore = GRDBObjectStore(database: database)
    }

    func load() async {
        guard let rels = try? await relStore.all() else { feed = InsightsFeedModel(sections: []); return }
        var resolved: [ResolvedRelationship] = []
        for r in rels {
            let (label, category) = await exposure(for: r)
            resolved.append(ResolvedRelationship(relationship: r, exposureLabel: label,
                                                 outcomeLabel: r.toSubtype ?? "outcome", exposureCategory: category))
        }
        feed = InsightsFeed.build(resolved, now: now())
    }

    func dismiss(_ card: InsightCardModel) async {
        guard var r = try? await relStore.relationship(id: card.id) else { return }
        r.status = .userDismissed
        try? await relStore.save(r)
        await load()
    }

    /// Resolve the exposure's display label + a representative category for its icon.
    private func exposure(for r: Relationship) async -> (String, EventCategory) {
        if let oid = r.fromObjectID, let obj = try? await objectStore.object(id: oid) {
            let category = EventCategory(rawValue: r.fromCategory ?? "") ?? .food
            return (obj.name.capitalized, category)
        }
        if let fc = r.fromCategory, let derived = InsightPhrasing.derivedExposureLabel(fromCategory: fc) {
            let category: EventCategory = fc.hasPrefix("cyclePhase") ? .cycle
                : fc == "shortSleep" ? .sleep : fc == "highStress" ? .stress
                : fc == "pressureDrop" ? .environment : .note
            return (derived, category)
        }
        return (r.fromCategory ?? "Something", .note)
    }
}
```

- [ ] **Step 4: Run to verify pass.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Insights/InsightsViewModel.swift" \
        "Food IntolerancesTests/InsightsViewModelTests.swift"
git commit -m "feat(app): InsightsViewModel — resolve relationships → feed model; dismiss → archive"
```

---

## Task 6: Insights views (cards, badge, dots) + screen + shell wiring

**Files:**
- Create: `Views/HealthOS/Insights/EvidenceDotsView.swift`, `InsightBadgeView.swift`, `InsightCardView.swift`, `InsightsView.swift`
- Modify: `Views/HealthOS/Shell/HealthOSRootView.swift`
- Verify: build + previews (SwiftUI views have no snapshot-test infra; behavioral correctness of the model is covered by Tasks 1/2/5; screen behavior is verified in Task 8).

**Interfaces:**
- Consumes: `InsightsViewModel`, `InsightCardModel`, `BadgeTier`, `HealthTheme`, `CategoryStyle`, the existing `InsightsPlaceholderView` coverage content (moved into the empty state).
- Produces: `InsightsView()` (replaces `InsightsPlaceholderView()` in the shell), `InsightCardView(card:onDismiss:)`, `InsightBadgeView(tier:)`, `EvidenceDotsView(filled:hollow:)`.

- [ ] **Step 1: `EvidenceDotsView.swift`** — a wrapping row of dots; filled = `HealthTheme.amber`, hollow = `HealthTheme.dotMiss`; VoiceOver label "N of M followed":

```swift
import SwiftUI

struct EvidenceDotsView: View {
    let filled: Int
    let hollow: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(0, filled), id: \.self) { _ in dot(HealthTheme.amber) }
            ForEach(0..<max(0, hollow), id: \.self) { _ in dot(HealthTheme.dotMiss) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) of \(filled + hollow) followed")
    }
    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 9, height: 9)
    }
}
```

- [ ] **Step 2: `InsightBadgeView.swift`** — pill: Early signal / Moderate / Strong, tinted:

```swift
import SwiftUI

struct InsightBadgeView: View {
    let tier: BadgeTier
    var body: some View {
        Text(label).font(.caption2.weight(.semibold)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(label) pattern")
    }
    private var label: String {
        switch tier { case .earlySignal: "EARLY SIGNAL"; case .moderate: "MODERATE"; case .strong: "STRONG" }
    }
    private var color: Color {
        switch tier { case .earlySignal: HealthTheme.inkSecondary; case .moderate: HealthTheme.accent; case .strong: HealthTheme.accent }
    }
}
```

- [ ] **Step 3: `InsightCardView.swift`** — the card carries only `card.id`; navigation is by value (`NavigationLink(value: card.id)`), and `InsightsView`'s `NavigationStack` provides `.navigationDestination(for: UUID.self) { InsightDetailView(relationshipID: $0) }`. Dismiss calls `onDismiss` (the VM). Verify `CategoryStyle` exposes `.icon` (SF Symbol) and adjust if the property name differs.

```swift
import SwiftUI
import HealthGraphCore

struct InsightCardView: View {
    let card: InsightCardModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                InsightBadgeView(tier: card.badge)
                if card.isNew { Text("NEW").font(.caption2.weight(.bold)).foregroundStyle(HealthTheme.amber) }
                Spacer()
            }
            NavigationLink(value: card.id) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: CategoryStyle.style(for: card.exposureCategory).icon)
                            .foregroundStyle(HealthTheme.inkSecondary)
                        Text(card.claim)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(HealthTheme.ink)
                    }
                    EvidenceDotsView(filled: card.filledDots, hollow: card.hollowDots)
                    if !card.subline.isEmpty {
                        Text(card.subline).font(.footnote).foregroundStyle(HealthTheme.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack {
                NavigationLink(value: card.id) {
                    Text("All evidence →").font(.subheadline.weight(.medium)).foregroundStyle(HealthTheme.accent)
                }
                Spacer()
                Button("Dismiss", action: onDismiss).font(.subheadline).foregroundStyle(HealthTheme.inkMuted)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).hgCard()
    }
}

#Preview {
    NavigationStack {
        InsightCardView(card: InsightCardModel(
            id: UUID(), claim: "Dairy → bloating", exposureCategory: .food, badge: .moderate,
            filledDots: 6, hollowDots: 2, subline: "usually within ~12h · avg severity +2.1",
            isNew: true, kind: .possibleTrigger), onDismiss: {}).padding()
    }
}
```

- [ ] **Step 4: `InsightsView.swift`** — `@StateObject private var vm`, `@StateObject private var refresh = InsightsRefreshCoordinator()`, `@EnvironmentObject captureCoordinator`. `ScrollView` of sections (`InsightSectionKind` → header via `HealthTheme.sectionHeader()`; "No effect" section header framed as wins; "Archive" collapsible). Empty state when `vm.feed.sections.isEmpty`: render the per-category coverage strip currently in `InsightsPlaceholderView` + the honest line. `.task { await refresh.refreshIfNeeded(); await vm.load() }`, `.refreshable`, `.onChange(of: scenePhase == .active)` and `.onChange(of: captureCoordinator.lastCaptureAt)` → `await refresh.refreshIfNeeded(); await vm.load()`, and `.onChange(of: refresh.lastRecomputeAt)` → `await vm.load()`. Background `HealthTheme.paper`. Wrap the `ScrollView` in a `NavigationStack` carrying `.navigationDestination(for: UUID.self) { InsightDetailView(relationshipID: $0) }` (this is what the cards' `NavigationLink(value: card.id)` resolves to). Each card's `onDismiss` = `{ Task { await vm.dismiss(card) } }`, surfaced with the app's existing undo-toast convention.

- [ ] **Step 5: Wire into the shell** — in `HealthOSRootView.swift`, replace `tab(.insights) { InsightsPlaceholderView() }` with `tab(.insights) { InsightsView() }`.

- [ ] **Step 6: Verify build + previews** — `xcodebuild -scheme "Food Intolerances" build` (or the project's build command) succeeds; the `InsightsView`/`InsightCardView` previews render in both color schemes. Full-suite: `cd HealthGraphCore && swift test` (core unchanged, still green) and the app test target builds.

- [ ] **Step 7: Commit**

```bash
git add "Views/HealthOS/Insights/EvidenceDotsView.swift" "Views/HealthOS/Insights/InsightBadgeView.swift" \
        "Views/HealthOS/Insights/InsightCardView.swift" "Views/HealthOS/Insights/InsightsView.swift" \
        "Views/HealthOS/Shell/HealthOSRootView.swift"
git commit -m "feat(app): Insights tab — sectioned cards (badge + dots), empty-state coverage, shell wiring"
```

---

## Task 7: `InsightDetailView` (evidence drill-down)

**Files:**
- Create: `Views/HealthOS/Insights/InsightDetailView.swift`
- Verify: build + preview; behavior verified in Task 8.

**Interfaces:**
- Consumes: `RelationshipStore.relationship(id:)` + `EvidenceEngine.evidence(for:)` + `EventStore.event(id:)` + the existing `EventDetailView(event:)`.
- Produces: `InsightDetailView(relationshipID: UUID)` — on `.task`, loads the `Relationship` via `relationship(id:)` then calls `evidence(for:)`; renders the itemized exposure→outcome rows (incl. misses), confounder warnings, and raw numbers.

- [ ] **Step 1: Build `InsightDetailView.swift`:**
  - `let relationshipID: UUID`; `@State private var relationship: Relationship?`; `@State private var evidence: RelationshipEvidence?`; `.task { let db = HealthGraphProvider.shared; relationship = try? await GRDBRelationshipStore(database: db).relationship(id: relationshipID); if let r = relationship { evidence = try? await EvidenceEngine(database: db).evidence(for: r, asOf: Date()) } }`.
  - **Itemized list:** for each `ExposurePairDetail`, a row — date (`exposureTime`, formatted), a filled/hollow dot (`outcomeFollowed`), and `outcomeValue` if present. Each row is a `NavigationLink` that resolves the event: fetch `EventStore.event(id: pair.outcomeEventID ?? pair.exposureEventID)` and push `EventDetailView(event:)`.
  - **Confounder warnings:** if `!evidence.confounders.isEmpty`, a callout: "Another exposure was often present on these days — can't tell them apart yet; try one without the other." (Resolve confounder labels via the same exposure-label logic as the VM, or show a generic phrase — generic is acceptable for 2B.)
  - **Raw numbers** (bottom, `SF Mono` per §6): confidence %, evidence/contradiction counts, median lag (`relationship.lagHours`), avg effect (`relationship.strength`).
  - A `#Preview` seeded from a mined in-memory DB.

- [ ] **Step 2: Confirm the card → detail wiring** — `InsightCardView` already uses `NavigationLink(value: card.id)` and `InsightsView` provides `.navigationDestination(for: UUID.self) { InsightDetailView(relationshipID: $0) }` (Task 6). Verify tapping a card and "All evidence →" both reach the detail for the right relationship.

- [ ] **Step 3: Verify build + preview** — `xcodebuild ... build` succeeds; the detail preview renders rows + confounder callout + raw numbers.

- [ ] **Step 4: Commit**

```bash
git add "Views/HealthOS/Insights/InsightDetailView.swift" "Views/HealthOS/Insights/InsightCardView.swift"
git commit -m "feat(app): InsightDetailView — evidence(for:) drill-down (rows→EventDetail, confounders, raw numbers)"
```

---

## Task 8: Verify the Insights surface end-to-end

**Files:** none (verification task).

- [ ] **Step 1:** Use the project `verify` / `run` skill to launch the app against a store seeded with the synthetic harness (or real backfilled data) so the engine produces edges. Drive the Insights tab and confirm:
  - Cards render in **Active / No-effect / Archive** sections with correct badges; dot counts match `evidenceCount`/`contradictionCount`.
  - At most 3 cards show the **New** badge; all active edges are visible.
  - **Empty state** shows the coverage strip when there are no active/no-effect edges.
  - **Drill-down** opens, lists pairs incl. misses, shows confounder callout + raw numbers, and a row taps through to `EventDetailView`.
  - **Dismiss** moves a card to Archive with an undo toast; undo restores it.
  - **Refresh:** logging a new symptom (capture) triggers a recompute and the feed updates; reopening Insights within 15 min with no new data does not re-mine (instant).
  - Light + dark both correct; Dynamic Type at XXL survives.
- [ ] **Step 2:** Full regression: `cd HealthGraphCore && swift test` green; app target builds and its tests pass. Record the observed behavior.

---

## Definition of Done

- Insights tab shows sectioned cards (Active / No-effect / Archive) with word-scale badges + stored-count dots, an honest empty state, and the ≤3/week New throttle (never hiding active edges).
- `evidence(for:)` drill-down lists every pair incl. misses, confounder warnings, and raw numbers; rows open `EventDetailView`.
- Dismiss → Archive with undo; recompute is scheduled by the single debounced `InsightsRefreshCoordinator` (foreground / open / post-capture), decided by the pure `RecomputePolicy`.
- All core logic (phrasing, feed/New selection, policy) is unit-tested; ViewModel + coordinator tested against an in-memory mined corpus; the tab verified end-to-end.
- No engine/extraction/scoring/migration changes; no red-flag interstitial, "Test it", missions, or nightly BGTask (all deferred with homes).
