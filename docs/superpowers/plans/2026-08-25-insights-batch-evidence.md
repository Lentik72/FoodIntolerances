# Insights Batch Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `InsightsViewModel.load()` reads the event corpus once per render instead of once per active card.

**Architecture:** Swap the per-card `engine.evidence(for:)` loop for a single `engine.evidenceReports(for:asOf:)` call, reading each card's evidence out of the returned dictionary. The call is routed through an injectable closure — the same pattern the view model already uses for `hasSyntheticData` — so a test can assert it happens exactly once.

**Tech Stack:** Swift 6, Swift Testing, Xcode app target `Food Intolerances`, package `HealthGraphCore`.

## Global Constraints

- **The feed's contents must not change.** All nine existing `InsightsViewModelTests` pass unchanged; an edit to any of them means the change is wrong.
- Scope is the one call. Do **not** batch the `exposure(for:)` object lookup, and do **not** narrow `relStore.all()` — both are explicitly out of scope per the spec.
- Failure behaviour is unchanged: a missing evidence entry yields the same empty dot row that a failed per-card call produced.
- Do not modify `EvidenceEngine`, `EvidenceConfig`, or anything in the package.
- App tests need `-parallel-testing-enabled NO`.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Views/HealthOS/Insights/InsightsViewModel.swift` | Batch the evidence fetch behind an injectable seam | 1 |
| `Food IntolerancesTests/InsightsViewModelTests.swift` | Pin the call count and the unchanged dots | 1 |

---

## Task 1: One corpus read per render

**Files:**
- Modify: `Views/HealthOS/Insights/InsightsViewModel.swift` (the `init` and `load()`)
- Test: `Food IntolerancesTests/InsightsViewModelTests.swift`

**Interfaces:**
- Produces: `InsightsViewModel.init(database:now:hasSyntheticData:evidenceReports:)` — a new trailing parameter, defaulted to the real engine so every existing call site is unaffected.

**Context:** the view model already injects `hasSyntheticData` as an optional `@Sendable` closure defaulted to the real implementation (`InsightsViewModel.swift:20-25`). Follow that shape exactly. `EvidenceEngine` is a struct and `RelationshipEvidence` is `Sendable`, so the closure can capture the engine created in `init` — capture the local constant, not `self`.

- [ ] **Step 1: Write the failing test**

Append to `InsightsViewModelTests`. Match the file's existing harness for building a database and seeding relationships — read the top of the file first and reuse whatever helper it already has rather than inventing a second one.

```swift
    @Test func evidenceIsFetchedOnceForTheWholeFeedNotOncePerCard() async throws {
        // The N+1: evidence(for:) reads the ENTIRE event corpus on every call, so
        // one call per active card meant N full reads of a 38k-event graph — ~7s
        // on a real device. Asserted by CALL COUNT rather than elapsed time: a
        // timing threshold would be flaky on CI and would not say what regressed.
        let db = try AppDatabase.inMemory()
        let store = GRDBRelationshipStore(database: db)
        for i in 0..<4 {
            try await store.upsert(Relationship(
                edgeKey: "derived:highStress|symptom:s\(i)|possibleTrigger",
                fromCategory: "highStress", toCategory: "symptom", toSubtype: "s\(i)",
                status: .active, confidence: 0.6, evidenceCount: 9, contradictionCount: 2))
        }
        let calls = Counter()
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 1_750_000_000) },
                                   hasSyntheticData: { false },
                                   evidenceReports: { rels, _ in
                                       calls.value += 1
                                       #expect(rels.count == 4)   // all four in ONE call
                                       return [:]
                                   })
        await vm.load()
        #expect(calls.value == 1)
    }
```

Add this small helper alongside it if the file does not already have one:

```swift
    final class Counter: @unchecked Sendable {
        var value = 0
    }
```

**If `Relationship`'s initializer does not match the call above**, read its declaration in `HealthGraphCore/Sources/HealthGraphCore/Models/` and use the real one — the four relationships only need to exist with `status: .active` and distinct `edgeKey`s.

- [ ] **Step 2: Run it and watch it fail**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/InsightsViewModelTests" -parallel-testing-enabled NO 2>&1 | grep -E "error:|✘|Test run"`
Expected: FAIL to compile — `extra argument 'evidenceReports' in call`.

- [ ] **Step 3: Add the seam**

In `InsightsViewModel`, add the stored property beside `hasSyntheticDataCheck`:

```swift
    private let evidenceReportsProvider: @Sendable ([Relationship], Date) async throws -> [UUID: RelationshipEvidence]
```

and extend `init`, defaulting it to the real engine. Capture the local `engine` constant, never `self`:

```swift
    init(database: AppDatabase = HealthGraphProvider.shared, now: @escaping () -> Date = { Date() },
         hasSyntheticData: (@Sendable () async throws -> Bool)? = nil,
         evidenceReports: (@Sendable ([Relationship], Date) async throws -> [UUID: RelationshipEvidence])? = nil) {
        self.database = database; self.now = now
        self.relStore = GRDBRelationshipStore(database: database)
        self.objectStore = GRDBObjectStore(database: database)
        let engine = EvidenceEngine(database: database)
        self.engine = engine
        self.hasSyntheticDataCheck = hasSyntheticData ?? { try await database.hasSyntheticData() }
        self.evidenceReportsProvider = evidenceReports ?? { rels, asOf in
            try await engine.evidenceReports(for: rels, asOf: asOf)
        }
    }
```

- [ ] **Step 4: Batch the fetch in `load()`**

Replace the resolution loop. The `asOf` timestamp is now taken once, so every card in a render is dated from the same instant:

```swift
        guard let rels = try? await relStore.all() else { feed = InsightsFeedModel(sections: []); return }
        // ONE corpus read for every active card. evidence(for:) reads the entire
        // event corpus per call, so the previous per-card loop cost N full reads
        // of the graph — measured at ~7s for 10 cards over 38k events.
        let asOf = now()
        let active = rels.filter { $0.status == .active }
        let reports = (try? await evidenceReportsProvider(active, asOf)) ?? [:]
        var resolved: [ResolvedRelationship] = []
        for r in rels {
            let (label, category) = await exposure(for: r)
            var recent: [Bool] = []
            // Unchanged failure behaviour: the batch path fails soft per edge, so a
            // missing entry yields the same empty dot row a failed per-card call did.
            if r.status == .active, let ev = reports[r.id] {
                recent = ev.exposures.suffix(config.recentDotCount).map(\.outcomeFollowed)   // last-N chronological
            }
            resolved.append(ResolvedRelationship(relationship: r, exposureLabel: label,
                                                 outcomeLabel: InsightPhrasing.outcomeLabel(for: r),
                                                 exposureCategory: category, recentOutcomes: recent))
        }
        feed = InsightsFeed.build(resolved, now: asOf)
```

- [ ] **Step 5: Run the whole suite for this file**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/InsightsViewModelTests" -parallel-testing-enabled NO 2>&1 | grep -E "✘|Test run"`
Expected: 10 pass (9 pre-existing unchanged + the new one). **If any pre-existing test fails, the feed's contents changed — that is a defect in this change, not a stale test.**

- [ ] **Step 6: Demonstrate the mutant**

Revert `load()` to the per-card form — call the provider inside the loop, once per active relationship:

```swift
            if r.status == .active,
               let ev = try? await evidenceReportsProvider([r], asOf)[r.id] { ... }
```

Run the filtered tests and confirm `evidenceIsFetchedOnceForTheWholeFeedNotOncePerCard` fails with a call count of 4. Restore and confirm green. If it does not fail, the test is theatre and needs fixing before this task is done.

- [ ] **Step 7: Build and commit**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Views/HealthOS/Insights/InsightsViewModel.swift "Food IntolerancesTests/InsightsViewModelTests.swift"
git commit -m "perf(insights): one corpus read per render instead of one per card"
```

---

## Final verification

- [ ] Package suite unchanged: `swift test --package-path HealthGraphCore 2>&1 | tail -3` — expect 409 passing (this branch does not touch the package).
- [ ] App suite: 70 suites, zero `✘`, with the familiar exit-65 banner from the pre-existing `SwiftDataMigratorTests` runner crash. Verify by counting `✔ Suite` lines and grepping `✘`, not by the trailing total.

## Device check

Optional and cheap, now that a corpus exists:

- [ ] Health Graph Debug → **Load STRESS demo** (creates active relationships), then open **Insights**. It should render without a visible stall. Then **Clear demo data**.
