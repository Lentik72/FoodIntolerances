# First Run, Apple Health Connect, and Evidence-Input Correctness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a Release build able to connect Apple Health, import history, and keep ingesting — behind an honest first-run flow — and fix the three verified defects that make the evidence engine mine the wrong inputs.

**Architecture:** Two groups. Tasks 1–8 are pure/near-pure changes in the `HealthGraphCore` Swift package (batch evidence API, three exposure-input fixes, three new support APIs) — all unit-testable with no simulator. Tasks 9–17 are app-target work: a structural root switch replacing the unconditional `HealthOSRootView()` mount, a six-screen first-run flow, a permanent Data sources screen, and the retirement of three shipped strings that claim capabilities which already exist.

**Tech Stack:** Swift 6.3.3 (package builds in Swift 5 language mode), SwiftUI, GRDB, HealthKit, swift-testing.

**Spec:** `docs/superpowers/specs/2026-07-26-first-run-and-health-connect-design.md` (approved at `8bd1965`). Section references below (§1–§14) are to that document.

## Global Constraints

- **Task 1 must ship and be built before Tasks 2–5.** The device-gate baseline (spec §Device gate) is captured by running the Task-1 diagnostic on a build that does **not** yet contain the engine-input fixes. `main` has no dump action, so there is no other way to obtain a baseline. Do not reorder.
- Deployment target iOS 26.0; package platform `.iOS(.v26)`.
- Package tests: `swift test --package-path HealthGraphCore --filter <SuiteName>`.
- App tests: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/<SuiteName>" -parallel-testing-enabled NO`. **`-parallel-testing-enabled NO` is mandatory** — parallel simulator clones produce spurious `failed (0.000s)`. `iPhone 17 Pro` is the only runnable simulator on this machine.
- A full app-suite run **always** prints `** TEST FAILED **` because of the known, unrelated `SwiftDataMigratorTests` teardown crash. Verify by suite name, never by the exit banner.
- Never hand-edit `.pbxproj`. New package files are auto-discovered by SPM; new app files by `PBXFileSystemSynchronizedRootGroup` under `Views/`, `Models/`, `Utilities/`. **Do not add new files at the repo root** — root files are explicit references and would require a pbxproj edit.
- Never stage `Food Intolerances.xcodeproj/project.xcworkspace/xcuserdata/leo.xcuserdatad/UserInterfaceState.xcuserstate` (currently dirty, must stay unstaged) or a cosmetic `.pbxproj` re-sort.
- GRDB migrations are append-only and shipped bodies are immutable. Current highest is `"v7"`. **This plan adds no migration** — the cycle-start marker lives in the existing `metadata` column.
- Swift 6.3.3 quirk: the `#expect` macro can fail to compile when `try` sits directly inside certain nested closures. Fix by let-binding the value and asserting on the binding. Never weaken the assertion.
- App target has a **legacy `SymptomCatalog` and `SymptomDefinition` at the repo root** that shadow the package types. Every app-side reference to the package catalog must be written `HealthGraphCore.SymptomCatalog` / `HealthGraphCore.SymptomDefinition`. The failure mode is not "ambiguous type" — it silently binds the legacy type and then errors on a missing member.
- No `public` in the app target. No ad-hoc `Color` in any HealthOS view — `HealthTheme` / `CategoryStyle` only. `HealthTheme.screenTitle()` and `sectionHeader()` are **functions**; colors are properties.
- No user-facing causal language anywhere (spec §2.4, §17 of the roadmap): "associated with", "historically followed by", "we observed".

---

## File Structure

**Package — created:**
- `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceContext.swift` — shared load-once context + the batch report API's internals.
- `HealthGraphCore/Sources/HealthGraphCore/Ingestion/MenstrualCycleStart.swift` — typed tri-state accessor on `HealthEvent`.
- `HealthGraphCore/Sources/HealthGraphCore/Evidence/IllnessMarkers.swift` — HK↔catalog normalization + illness-day classification.
- `HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomSeeds.swift` — seed validation.

**Package — modified:** `Evidence/EvidenceEngine.swift`, `Evidence/DerivedEventExposureSources.swift`, `Evidence/CyclePhaseExposureSource.swift`, `Evidence/EvidenceConfig.swift`, `Evidence/ExposureModel.swift`, `Capture/SymptomCatalog.swift`, `Capture/ChipRanker.swift`, `Database/EventStore.swift`, `Ingestion/HealthKitSampleMapper.swift`, `Synthetic/SyntheticDataGenerator.swift`.

**App — created:** `Models/FirstRunState.swift`, `Models/HealthImportStatus.swift`, `Views/HealthOS/FirstRun/FirstRunFlowView.swift`, `…/FirstRunPromiseView.swift`, `…/FirstRunConnectView.swift`, `…/FirstRunBackfillView.swift`, `…/FirstRunSeedingView.swift`, `…/FirstRunLocationView.swift`, `…/SeedSymptomGrid.swift`, `Views/HealthOS/Health/DataSourcesView.swift`, `Views/HealthOS/Health/DataSourcesPresentation.swift`.

**App — modified:** `FoodIntolerancesApp.swift`, `Views/HealthOS/Health/HealthTabView.swift`, `Views/HealthGraphDebugView.swift`, `Views/HealthOS/Home/HomeView.swift`, `Views/HealthOS/Insights/InsightsPlaceholderView.swift`, `Views/HealthOS/Timeline/TimelineView.swift`, `Views/HealthOS/Timeline/EventDetailView.swift`, `Views/HealthOS/Capture/SymptomCaptureView.swift`, `Models/HealthKitIngestor.swift`.

---

## Task 1: Batch evidence report + DEBUG relationship dump

**This task must be built and run on device to capture the baseline before Tasks 2–5.** It contains no behavior changes.

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceContext.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift:181-211` (replace the `evidence(for:asOf:)` extension)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift` (append `diagnosticLabel`)
- Modify: `Views/HealthGraphDebugView.swift` (add the dump action)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceBatchReportTests.swift`

**Interfaces:**
- Consumes: `EvidenceEngine.extract(_:)`, `EvidenceEngine.illnessDays(_:)`, `EvidenceEngine.utc`, `EvidenceEngine.illnessConfounderKey` (all internal, same module); `CooccurrenceAnalyzer.analyze(exposure:outcome:window:observation:)`; `ConfounderAnalyzer.penalty(targetDays:others:threshold:)`; `EdgeIdentity.parse(_:)`.
- Produces: `EvidenceEngine.evidenceReports(for:asOf:) async throws -> [UUID: RelationshipEvidence]`; `ExposureKey.diagnosticLabel: String`.

**Why a shared context, not a loop:** `evidence(for:asOf:)` re-reads the entire event table and re-runs `extract` (10 exposure sources, two percentile passes, a `SleepSessionBuilder` fold, and thousands of `metadata` JSON decodes) to answer about **one** edge. Dumping every relationship would scan a 136k-event graph once per edge.

**Three invariants the context must preserve or the numbers silently diverge from `recompute()`:**
1. The corpus is the **same** `.distantPast ... .distantFuture` read. `TemperatureExposureSource` and `HumidityExposureSource` are corpus-relative (quartiles with a hard 20-reading floor), so a narrowed read changes or deletes exposures.
2. `others` is rebuilt **per relationship** as `daySets.filter { $0.key != targetKey }` plus the illness sentinel. Only `daySets` is hoistable. Dropping the `!= target` filter makes every edge confound itself at overlap 1.0 → maximum penalty.
3. All day bucketing uses `EvidenceEngine.utc`.

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceBatchReportTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct EvidenceBatchReportTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    /// Seeds a dairy→bloating signal plus an unrelated coffee exposure, so at
    /// least one edge activates and the confounder pool is non-trivial.
    func seed(into db: AppDatabase) async throws {
        let objects = GRDBObjectStore(database: db)
        let dairy = try await objects.findOrCreate(name: "dairy", kind: .food, metadata: nil)
        let coffee = try await objects.findOrCreate(name: "coffee", kind: .food, metadata: nil)
        var events: [HealthEvent] = []
        for d in 0..<30 {
            let day = now.addingTimeInterval(Double(-d) * 86_400)
            events.append(HealthEvent(timestamp: day, timezoneID: "UTC", category: .food,
                                      subtype: "dairy", objectID: dairy.id,
                                      source: .manual, createdAt: day))
            events.append(HealthEvent(timestamp: day.addingTimeInterval(1800), timezoneID: "UTC",
                                      category: .food, subtype: "coffee", objectID: coffee.id,
                                      source: .manual, createdAt: day))
            if d % 4 != 0 {
                events.append(HealthEvent(timestamp: day.addingTimeInterval(21_600), timezoneID: "UTC",
                                          category: .symptom, subtype: "bloating", value: 5,
                                          source: .manual, createdAt: day))
            }
        }
        try await GRDBEventStore(database: db).save(events)
    }

    @Test func batchMatchesPerRelationshipEvidenceExactly() async throws {
        let db = try AppDatabase.inMemory()
        try await seed(into: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)

        let rels = try await GRDBRelationshipStore(database: db).all()
        #expect(!rels.isEmpty)   // non-vacuous: the loop below must actually run

        let batch = try await engine.evidenceReports(for: rels, asOf: now)
        #expect(batch.count == rels.count)   // every relationship gets an entry

        for r in rels {
            let single = try await engine.evidence(for: r, asOf: now)
            let fromBatch = batch[r.id]
            #expect(fromBatch == single)     // byte-for-byte parity, incl. confounders + pair order
        }
    }

    @Test func unparseableRelationshipYieldsAnEmptyEntryNotAMissingKey() async throws {
        let db = try AppDatabase.inMemory()
        try await seed(into: db)
        let engine = EvidenceEngine(database: db)
        let bogus = Relationship(type: .possibleTrigger, firstSeen: now, lastSeen: now,
                                 lastRecomputed: now, edgeKey: "not-a-valid-edge-key")

        let batch = try await engine.evidenceReports(for: [bogus], asOf: now)
        let entry = batch[bogus.id]
        #expect(entry != nil)                // fail-soft: present, not dropped
        #expect(entry?.exposures.isEmpty == true)
        #expect(entry?.followCount == 0)
        #expect(entry?.relationshipID == bogus.id)
    }

    @Test func decayedRelationshipsAreReportedToo() async throws {
        let db = try AppDatabase.inMemory()
        try await seed(into: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)

        let store = GRDBRelationshipStore(database: db)
        var rels = try await store.all()
        #expect(!rels.isEmpty)
        rels[0].status = .decayed
        try await store.save(rels[0])

        let batch = try await engine.evidenceReports(for: rels, asOf: now)
        #expect(batch[rels[0].id] != nil)    // status is never consulted
    }

    @Test func illnessSentinelPrintsAsIllnessNotAUUID() {
        #expect(EvidenceEngine.illnessConfounderKey.diagnosticLabel == "illness")
        #expect(ExposureKey.derived(.highStress).diagnosticLabel == "derived:highStress")
        #expect(ExposureKey.derived(.cyclePhase(.luteal)).diagnosticLabel == "derived:cyclePhase.luteal")
    }

    @Test func everyOtherKeyLabelsExactlyAsItsEdgeToken() {
        // Pins the delegation. If the label ever forks from EdgeIdentity, the
        // dump's confounder column stops matching its own edgeKey column.
        let keys: [ExposureKey] = [
            .derived(.shortSleep), .derived(.pressureDrop), .derived(.fullMoon),
            .derived(.mercuryRetrograde), .derived(.hotDay), .derived(.coldDay),
            .derived(.humidDay), .derived(.swingDay), .derived(.poorAirDay),
            .derived(.cyclePhase(.menstrual)), .object(UUID(), .food),
        ]
        for key in keys {
            #expect(key.diagnosticLabel == EdgeIdentity.fromToken(key))
        }
    }

    @Test func anEdgeIsNeverItsOwnConfounder() async throws {
        // Pins the per-target `others` filter. Dropping it makes every edge
        // overlap itself at 1.0 and take the maximum confidence penalty.
        let db = try AppDatabase.inMemory()
        try await seed(into: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)
        let rels = try await GRDBRelationshipStore(database: db).all()
        #expect(!rels.isEmpty)
        let batch = try await engine.evidenceReports(for: rels, asOf: now)
        for r in rels {
            guard let (expKey, _) = EdgeIdentity.parse(r) else { continue }
            #expect(batch[r.id]?.confounders.contains(expKey) == false)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter EvidenceBatchReportTests`
Expected: FAIL — compile error, `value of type 'EvidenceEngine' has no member 'evidenceReports'`.

- [ ] **Step 3: Add the diagnostic label**

Append to `HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift`:

```swift
public extension ExposureKey {
    /// Stable, human-readable token for DEBUG diagnostics and device-gate diffs.
    /// The reserved illness confounder sentinel prints as `illness` rather than
    /// its UUID — it is not a real object and its id carries no meaning.
    ///
    /// DELEGATES to `EdgeIdentity.fromToken` rather than re-switching over
    /// `DerivedExposureKind`. A copy would be a second exhaustive switch to
    /// update when a case is added, and if the two ever drifted the dump's
    /// confounder labels would stop matching the `edgeKey` column printed
    /// beside them — silently mis-attributing the very baseline↔after diff the
    /// device gate depends on.
    var diagnosticLabel: String {
        self == EvidenceEngine.illnessConfounderKey ? "illness" : EdgeIdentity.fromToken(self)
    }
}
```

`EdgeIdentity.fromToken` is internal to the package (`EdgeIdentity.swift:8`) and
`ExposureModel.swift` is in the same module, so this compiles.

- [ ] **Step 4: Create the shared context**

Create `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceContext.swift`:

```swift
import Foundation

/// One load + one `extract` of the whole corpus, reused across many relationships.
///
/// Exists because `evidence(for:asOf:)` re-reads the entire event table and
/// re-runs all ten exposure sources to answer about a SINGLE edge — so asking
/// about N edges costs N full-corpus scans. Everything here is shared work;
/// the per-edge work stays in `evidence(for:in:)`.
struct EvidenceContext {
    let exposures: [ExposureKey: [ExposureOccurrence]]
    let outcomes: [OutcomeKey: [OutcomeOccurrence]]
    /// Hoistable. The per-target `others` map is NOT hoistable — see `evidence(for:in:)`.
    let daySets: [ExposureKey: Set<Date>]
    let illness: Set<Date>
    /// nil when the corpus is empty; every per-edge answer is then empty.
    let observation: DateInterval?
}

extension EvidenceEngine {
    /// Builds the shared context. MUST be given the same unbounded corpus
    /// `recompute()` uses: TemperatureExposureSource/HumidityExposureSource are
    /// corpus-relative (quartiles over the slice, 20-reading floor), so a
    /// narrowed read silently changes or deletes those exposures and the batch
    /// numbers stop matching the stored evidenceCount.
    func makeContext(_ events: [HealthEvent]) -> EvidenceContext {
        let cal = Self.utc
        let (exposures, outcomes) = extract(events)
        var daySets: [ExposureKey: Set<Date>] = [:]
        for (key, occ) in exposures { daySets[key] = Set(occ.map { cal.startOfDay(for: $0.timestamp) }) }
        let times = events.map(\.timestamp)
        let observation: DateInterval?
        if let lo = times.min(), let hi = times.max() { observation = DateInterval(start: lo, end: hi) }
        else { observation = nil }
        return EvidenceContext(exposures: exposures, outcomes: outcomes, daySets: daySets,
                               illness: illnessDays(events), observation: observation)
    }

    /// The per-edge half. Pure and synchronous — no I/O.
    ///
    /// Fails soft in six places, each returning the zeroed value rather than nil
    /// or a throw: unparseable edgeKey, exposure key absent, outcome key absent,
    /// empty exposures, no observation window, analyzer returns nil. Callers
    /// (InsightsViewModel) render "card with no dots" from that; dropping the
    /// entry instead would change the UI to "missing data".
    func evidence(for relationship: Relationship, in ctx: EvidenceContext) -> RelationshipEvidence {
        func empty() -> RelationshipEvidence {
            RelationshipEvidence(relationshipID: relationship.id, exposures: [],
                                 followCount: 0, missCount: 0, confounders: [])
        }
        guard let (expKey, outKey) = EdgeIdentity.parse(relationship) else { return empty() }
        guard let exp = ctx.exposures[expKey], let out = ctx.outcomes[outKey], !exp.isEmpty else { return empty() }
        guard let observation = ctx.observation else { return empty() }
        let window = config.lagWindow(for: expKey)
        guard let stats = CooccurrenceAnalyzer(config: config)
            .analyze(exposure: exp, outcome: out, window: window, observation: observation) else { return empty() }

        // Rebuilt PER TARGET: dropping the `!= expKey` filter makes every edge
        // confound itself (overlap 1.0 → maximum penalty). Only daySets is shared.
        var others = ctx.daySets.filter { $0.key != expKey }
        if !ctx.illness.isEmpty { others[Self.illnessConfounderKey] = ctx.illness }
        let (_, confounders) = ConfounderAnalyzer().penalty(targetDays: ctx.daySets[expKey] ?? [], others: others)

        return RelationshipEvidence(relationshipID: relationship.id, exposures: stats.pairs,
                                    followCount: stats.followCount, missCount: stats.missCount,
                                    confounders: confounders)
    }
}
```

- [ ] **Step 5: Rewrite the public entry points over the shared context**

In `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift`, replace the whole `extension EvidenceEngine { public func evidence(for:asOf:) … }` block (starts line 181, ends at the closing brace of the extension) with:

```swift
extension EvidenceEngine {
    public func evidence(for relationship: Relationship, asOf now: Date) async throws -> RelationshipEvidence {
        let events = try await eventStore.events(
            in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        return evidence(for: relationship, in: makeContext(events))
    }

    /// Batched evidence for many relationships against ONE corpus load and ONE
    /// extract. Keyed by `relationship.id` — never zip against the input array,
    /// `GRDBRelationshipStore.all()` has no ORDER BY.
    ///
    /// Every input relationship gets an entry, including unparseable and decayed
    /// ones (`evidence(for:in:)` fails soft). Status is never consulted.
    public func evidenceReports(for relationships: [Relationship],
                                asOf now: Date) async throws -> [UUID: RelationshipEvidence] {
        guard !relationships.isEmpty else { return [:] }
        let events = try await eventStore.events(
            in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        let ctx = makeContext(events)
        var out: [UUID: RelationshipEvidence] = [:]
        for r in relationships { out[r.id] = evidence(for: r, in: ctx) }
        return out
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --package-path HealthGraphCore --filter EvidenceBatchReportTests`
Expected: PASS, 6 tests.

Then the full package suite, because `evidence(for:)` was restructured:
Run: `swift test --package-path HealthGraphCore 2>&1 | tail -5`
Expected: all tests pass (330+ before this task's 4 additions).

- [ ] **Step 7: Add the DEBUG dump action**

In `Views/HealthGraphDebugView.swift`, add to the existing `@State` block near the top of the struct:

```swift
    @State private var relationshipReport: String?
```

Add a new `Section` immediately after the existing `Section("Ingestion")` block:

```swift
            Section("Diagnostics") {
                Button("Dump relationship report") { Task { await dumpRelationshipReport() } }
                    .disabled(isWorking)
                if let relationshipReport {
                    Text(relationshipReport)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }
```

Add the method alongside the view's other `private func … async` helpers:

```swift
    /// Device-gate baseline/after report (spec §10). Deliberate one-shot
    /// diagnostic — it is intentionally NOT wired into any live surface.
    /// Prints as well as displays so the Xcode console copy can be diffed.
    private func dumpRelationshipReport() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let db = HealthGraphProvider.shared
            let all = try await GRDBRelationshipStore(database: db).all()
            let interesting = all.filter { $0.status == .active || $0.status == .decayed }
                .sorted { ($0.edgeKey ?? "") < ($1.edgeKey ?? "") }
            let reports = try await EvidenceEngine(database: db)
                .evidenceReports(for: interesting, asOf: Date())
            var lines: [String] = ["edgeKey | status | confidence | evidence | contradictions | confounders"]
            for r in interesting {
                let conf = reports[r.id]?.confounders.map(\.diagnosticLabel).sorted().joined(separator: ",") ?? ""
                lines.append([
                    r.edgeKey ?? "(nil)",
                    r.status.rawValue,
                    String(format: "%.3f", r.confidence),
                    String(r.evidenceCount),
                    String(r.contradictionCount),
                    conf.isEmpty ? "-" : conf,
                ].joined(separator: " | "))
            }
            let text = lines.joined(separator: "\n")
            relationshipReport = text
            print("=== RELATIONSHIP REPORT (\(interesting.count) rows) ===\n\(text)")
        } catch {
            errorMessage = String(describing: error)
        }
    }
```

- [ ] **Step 8: Build the app and commit**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceContext.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceBatchReportTests.swift \
        Views/HealthGraphDebugView.swift
git commit -m "feat(evidence): batch evidence report over a shared corpus context + DEBUG dump"
```

- [ ] **Step 9: CAPTURE THE DEVICE BASELINE — do not skip, do not defer**

Install **this commit** on the device, then:

1. **Run a recompute first** (debug screen → the recompute/refresh action), immediately
   before dumping. `confidence`, `evidence` and `contradictions` are read from the STORED
   relationship rows — i.e. from whenever `recompute()` last ran — while `confounders` is
   computed live. Dumping without a fresh recompute compares stale stored columns against
   stale stored columns, so a real change reads as "no change" and the device gate passes
   for the wrong reason.
2. Run Health tab → debug screen → **"Dump relationship report"**.
3. Save the console output to `.superpowers/sdd/relationship-baseline.txt` (gitignored scratch).

The same recompute-then-dump order is mandatory for the "after" capture.

This is the only build that has the diagnostic without the engine fixes. Once Task 2 lands, the baseline is unobtainable and the device gate degrades to the weaker screenshot fallback (spec §Device gate).

---

## Task 2: Stress exposures require a real stress rating

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/DerivedEventExposureSources.swift:4-14`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift:228`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift` (existing `HighStress` cases at lines ~109-110)

**Interfaces:**
- Produces: `HighStressExposureSource.ratingSubtype: String` (`"stressRating"`), `HighStressExposureSource.ratingUnit: String` (`"score"`).

**Why an allowlist:** the only real-data producer of `.stress` is HealthKit Mindful Sessions, written with `value` = duration in minutes (`HealthKitSampleMapper.swift:266-281`) — so a 7-minute meditation currently reads as high stress on a threshold documented "on 1–10". A denylist excluding `"mindfulness"` by name would let the next unit-mismatched source through the same hole.

**Accepted consequence:** nothing produces `stressRating` today, so `highStress` becomes dormant on real data. That is the honest state.

- [ ] **Step 1: Write the failing test**

There is **no** `HighStressExposureSourceTests` struct. The existing coverage is
`@Test func highStressAboveThreshold()` at `ExposureSourceTests.swift:107-114`, inside
`struct DerivedEventExposureSourceTests` (`:106-125`) — which also holds
`pressureDropReadsPreEventizedSubtype` (`:115-124`), **the repo's only test of
`PressureDropExposureSource`**.

Delete **only** `highStressAboveThreshold` (`:107-114`). Leave
`pressureDropReadsPreEventizedSubtype` and the enclosing struct intact. That deleted
assertion builds `.stress` events with no subtype and no unit and asserts they yield a
high-stress exposure — it encodes the exact defect §7 outlaws, so removing it is the
point of this task, not a regression.

Then add below it, in the same file:

```swift
struct HighStressExposureSourceTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func stress(_ value: Double?, subtype: String?, unit: String?) -> HealthEvent {
        HealthEvent(timestamp: t0, timezoneID: "UTC", category: .stress, subtype: subtype,
                    value: value, unit: unit, source: .manual, createdAt: t0)
    }

    @Test func acceptsAStressRatingAtOrAboveThreshold() {
        let src = HighStressExposureSource(config: .default)
        let events = [stress(8, subtype: "stressRating", unit: "score"),
                      stress(4, subtype: "stressRating", unit: "score")]
        #expect(src.occurrences(from: events).count == 1)   // 8 passes, 4 below threshold 7
    }

    @Test func rejectsMindfulSessionMinutes() {
        // The live defect: HK Mindful Sessions write category .stress with
        // value = duration in MINUTES, so any session >= 7 min was mined as
        // "high stress" — semantics inverted.
        let src = HighStressExposureSource(config: .default)
        let events = [stress(20, subtype: "mindfulness", unit: "min")]
        #expect(src.occurrences(from: events).isEmpty)
    }

    @Test func rejectsRightSubtypeWithWrongUnit() {
        let src = HighStressExposureSource(config: .default)
        #expect(src.occurrences(from: [stress(8, subtype: "stressRating", unit: "min")]).isEmpty)
    }

    @Test func rejectsOutOfRangeValues() {
        let src = HighStressExposureSource(config: .default)
        #expect(src.occurrences(from: [stress(60, subtype: "stressRating", unit: "score")]).isEmpty)
        #expect(src.occurrences(from: [stress(0, subtype: "stressRating", unit: "score")]).isEmpty)
    }

    @Test func rejectsSubtypeNil() {
        // Absence is not a durable allowlist — a future untyped .stress writer
        // must fail closed, not inherit the old behaviour.
        let src = HighStressExposureSource(config: .default)
        #expect(src.occurrences(from: [stress(8, subtype: nil, unit: nil)]).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter HighStressExposureSourceTests`
Expected: FAIL — `rejectsMindfulSessionMinutes` and `rejectsSubtypeNil` fail (the source currently accepts both); `acceptsAStressRatingAtOrAboveThreshold` passes for the wrong reason.

- [ ] **Step 3: Implement the allowlist**

Replace `HighStressExposureSource` in `HealthGraphCore/Sources/HealthGraphCore/Evidence/DerivedEventExposureSources.swift`:

```swift
public struct HighStressExposureSource: ExposureSource {
    /// The ONLY subtype that counts as a self-reported stress rating.
    /// Positive allowlist, not a denylist: the previous rule accepted any
    /// `.stress` event, and the only real producer is HealthKit Mindful
    /// Sessions carrying duration in MINUTES — so every meditation of 7+ min
    /// was mined as a high-stress exposure with inverted semantics.
    public static let ratingSubtype = "stressRating"
    /// Unit guard. Not redundant with the subtype: it is what makes a future
    /// producer that reuses the subtype with different units fail closed
    /// rather than silently mis-scale, which is exactly how minutes got in.
    public static let ratingUnit = "score"

    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .stress,
                  e.subtype == Self.ratingSubtype,
                  e.unit == Self.ratingUnit,
                  let v = e.value, (1...10).contains(v),
                  v >= config.highStressThreshold else { return nil }
            return ExposureOccurrence(key: .derived(.highStress), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
```

- [ ] **Step 4: Update the synthetic generator to emit the new shape**

In `HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift` at line 228, the stress event is constructed without a subtype or unit. Add both so planted stress signals still activate:

```swift
                events.append(HealthEvent(timestamp: t, timezoneID: tz, category: .stress,
                                          subtype: HighStressExposureSource.ratingSubtype,
                                          value: Double(Int.random(in: 7...10, using: &rng)),
                                          unit: HighStressExposureSource.ratingUnit,
                                          source: .manual, createdAt: t))
```

Keep the surrounding loop and any existing `value:` expression exactly as it is — only `subtype:` and `unit:` are added. If the existing call already passes `value:` differently, preserve that expression verbatim and add the two labels around it.

- [ ] **Step 5: Run the tests**

Run: `swift test --package-path HealthGraphCore --filter HighStressExposureSourceTests`
Expected: PASS, 5 tests.

Run: `swift test --package-path HealthGraphCore 2>&1 | tail -5`
Expected: all pass. The only assertion removed anywhere is `highStressAboveThreshold`; nothing else in `ExposureSourceTests.swift` changes. If a *planted-signal acceptance* test regressed, the generator edit in Step 4 is wrong — fix the generator, never the assertion. (That guidance applies only to the synthetic acceptance suites; `highStressAboveThreshold` is a hand-written unit test and is unaffected by the generator.)

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/DerivedEventExposureSources.swift \
        HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "fix(evidence): stress exposures require a stressRating/score value, not mindful minutes"
```

---

## Task 3: Thread HealthKit's cycle-start marker through the adapter

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/HealthKitSampleMapper.swift:20-30` (DTO) and `:284-309` (menstrual branch)
- Create: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/MenstrualCycleStart.swift`
- Modify: `Models/HealthKitIngestor.swift:301-332` (`mapSample`)
- Modify: `Views/HealthOS/Timeline/EventDetailView.swift:190-201` (metadata label)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/HealthKitSampleMapperTests.swift`

**Interfaces:**
- Produces: `CategorySampleData.menstrualCycleStart: Bool?` (new trailing init param, `= nil`); `HealthEvent.menstrualCycleStart: Bool?` (computed).

**The tri-state is the whole point.** `true` = authoritative start; `false` = definitely not an inference candidate; `nil` = eligible for run inference (export/legacy only). Encoding `Bool?` into `[String: String]` means the key must be **omitted** for nil and present as `"false"` for false. The naive read `dict["menstrualCycleStart"] == "true"` collapses nil→false and destroys the distinction Task 4 depends on.

**Do not rewrite the subtype to `"periodStart"`.** It would discard the flow measurement (spec §8) *and* change `DedupKey.point(.cycle, "menstrualFlow", start)`, orphaning every stored row so re-imports duplicate instead of matching.

- [ ] **Step 1: Write the failing test**

Add to `HealthGraphCore/Tests/HealthGraphCoreTests/HealthKitSampleMapperTests.swift`:

```swift
@Suite struct MenstrualCycleStartTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func flow(_ raw: Int, cycleStart: Bool?) -> HealthEvent? {
        HealthKitSampleMapper.map(
            CategorySampleData(identifier: "HKCategoryTypeIdentifierMenstrualFlow",
                               start: t0, end: t0, value: raw, timezoneID: nil,
                               menstrualCycleStart: cycleStart),
            source: .healthKit)
    }

    @Test func trueIsPreservedAsTrue() throws {
        let e = try #require(flow(2, cycleStart: true))
        #expect(e.menstrualCycleStart == true)
        #expect(e.subtype == "menstrualFlow")   // subtype is NOT rewritten to periodStart
        #expect(e.value == 1)                   // flow measurement survives (light -> 1)
    }

    @Test func falseIsPreservedAsFalseNotNil() throws {
        let e = try #require(flow(3, cycleStart: false))
        #expect(e.menstrualCycleStart == false)
    }

    @Test func nilOmitsTheKeyEntirelyAndReadsBackAsNil() throws {
        let e = try #require(flow(3, cycleStart: nil))
        #expect(e.menstrualCycleStart == nil)
        // The key must be ABSENT, not "false" — Task 4 treats nil and false differently.
        if let data = e.metadata {
            let dict = try #require(try? JSONDecoder().decode([String: String].self, from: data))
            #expect(dict["menstrualCycleStart"] == nil)
        }
    }

    @Test func defaultedParameterKeepsExistingCallSitesAtNil() throws {
        let e = try #require(HealthKitSampleMapper.map(
            CategorySampleData(identifier: "HKCategoryTypeIdentifierMenstrualFlow",
                               start: t0, end: t0, value: 4, timezoneID: nil),
            source: .healthExportFile))
        #expect(e.menstrualCycleStart == nil)   // export records are inference-eligible
    }

    @Test func noneFlowIsStillDroppedRegardlessOfMarker() {
        #expect(flow(5, cycleStart: true) == nil)   // case 5 returns before metadata is considered
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter MenstrualCycleStartTests`
Expected: FAIL — `CategorySampleData` has no `menstrualCycleStart` parameter.

- [ ] **Step 3: Extend the DTO**

In `HealthGraphCore/Sources/HealthGraphCore/Ingestion/HealthKitSampleMapper.swift`, replace `CategorySampleData`:

```swift
public struct CategorySampleData: Sendable {
    public let identifier: String
    public let start: Date
    public let end: Date
    public let value: Int
    public let timezoneID: String?
    /// HealthKit's `HKMetadataKeyMenstrualCycleStart`, tri-state on purpose:
    /// true = authoritative period start, false = definitely not one,
    /// nil = unknown (export/legacy records) and therefore eligible for run
    /// inference. Defaulted so the export parser and all existing fixtures
    /// keep compiling and keep meaning "unknown".
    public let menstrualCycleStart: Bool?
    public init(identifier: String, start: Date, end: Date, value: Int, timezoneID: String?,
                menstrualCycleStart: Bool? = nil) {
        self.identifier = identifier; self.start = start; self.end = end
        self.value = value; self.timezoneID = timezoneID
        self.menstrualCycleStart = menstrualCycleStart
    }
}
```

- [ ] **Step 4: Encode the marker in the menstrual branch**

In the same file, replace the `metadata: nil,` line inside the `HKCategoryTypeIdentifierMenstrualFlow` branch. The branch becomes:

```swift
        // Menstrual Flow
        if sample.identifier == "HKCategoryTypeIdentifierMenstrualFlow" {
            let flowValue: Int?
            switch sample.value {
            case 5: return nil      // none -> skip
            case 1: flowValue = nil // unspecified -> present unrated
            case 2: flowValue = 1   // light
            case 3: flowValue = 2   // medium
            case 4: flowValue = 3   // heavy
            default: return nil
            }

            // Tri-state: OMIT the key when nil. Writing "false" for nil would
            // make export/legacy records ineligible for run inference.
            var meta: Data?
            if let start = sample.menstrualCycleStart {
                meta = try? JSONEncoder().encode(["menstrualCycleStart": start ? "true" : "false"])
            }

            return HealthEvent(
                timestamp: sample.start,
                timezoneID: timezoneID,
                endTimestamp: nil,
                category: .cycle,
                subtype: "menstrualFlow",
                value: flowValue.map { Double($0) },
                unit: "level",
                source: source,
                confidence: 1.0,
                metadata: meta,
                dedupKey: DedupKey.point(.cycle, "menstrualFlow", sample.start)
            )
        }
```

- [ ] **Step 5: Add the typed accessor**

Create `HealthGraphCore/Sources/HealthGraphCore/Ingestion/MenstrualCycleStart.swift`:

```swift
import Foundation

public extension HealthEvent {
    /// HealthKit's period-start marker, tri-state.
    ///
    /// `true` = authoritative start. `false` = authoritatively NOT a start.
    /// `nil` = unknown, which is what export-file and legacy rows carry and is
    /// the ONLY case eligible for run inference (see CyclePhaseExposureSource).
    /// Never collapse nil to false — `dict["…"] == "true"` would do exactly that.
    var menstrualCycleStart: Bool? {
        guard let metadata,
              let dict = try? JSONDecoder().decode([String: String].self, from: metadata),
              let raw = dict["menstrualCycleStart"] else { return nil }
        return raw == "true"
    }
}
```

- [ ] **Step 6: Read the marker from the live HealthKit sample**

In `Models/HealthKitIngestor.swift`, inside `static func mapSample(_ sample: HKSample) -> HealthEvent?`, the `HKCategorySample` branch becomes:

```swift
        if let category = sample as? HKCategorySample {
            // HKMetadataKeyMenstrualCycleStart is stored as an NSNumber boolean.
            // Absent -> nil (unknown), which keeps the sample inference-eligible.
            let cycleStart = (category.metadata?[HKMetadataKeyMenstrualCycleStart] as? NSNumber)?.boolValue
            return HealthKitSampleMapper.map(
                CategorySampleData(identifier: category.categoryType.identifier,
                                   start: category.startDate, end: category.endDate,
                                   value: category.value, timezoneID: timezoneID,
                                   menstrualCycleStart: cycleStart),
                source: .healthKit)
        }
```

- [ ] **Step 7: Label the new metadata key in the UI**

`EventDetailView.metadataRows` filters only `"provenance"` and renders every other key with `labels[$0.key] ?? $0.key`, **and renders the raw value verbatim**. So an unlabelled key ships as `menstrualCycleStart / true` — and worse, every *non-start* flow day would gain a row reading `Cycle start / false`, which is noise on the majority of cycle events in a UI that elsewhere reads "Moon phase / Waxing Gibbous".

Two edits in `Views/HealthOS/Timeline/EventDetailView.swift`. Add the label:

```swift
        "menstrualCycleStart": "Cycle",
```

And extend the existing key filter so the `"false"` case is suppressed rather than shown — only an affirmative start is worth a row:

```swift
            .filter { $0.key != "provenance" && !($0.key == "menstrualCycleStart" && $0.value == "false") }
```

Map the surviving value to human copy where the row is built, so it reads `Cycle / Period start` rather than `Cycle / true`:

```swift
            let display = (row.key == "menstrualCycleStart" && row.value == "true") ? "Period start" : row.value
```

Match the exact shape of the existing filter and row builder at `EventDetailView.swift:189-201` — the snippets above show the transformation, not the surrounding code.

- [ ] **Step 8: Run tests and build**

Run: `swift test --package-path HealthGraphCore --filter MenstrualCycleStartTests`
Expected: PASS, 5 tests.

Run: `swift test --package-path HealthGraphCore 2>&1 | tail -5`
Expected: all pass — the defaulted parameter keeps the export parser and the three existing fixtures compiling untouched.

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Ingestion/HealthKitSampleMapper.swift \
        HealthGraphCore/Sources/HealthGraphCore/Ingestion/MenstrualCycleStart.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/HealthKitSampleMapperTests.swift \
        Models/HealthKitIngestor.swift \
        Views/HealthOS/Timeline/EventDetailView.swift
git commit -m "feat(ingestion): retain HealthKit menstrual cycle-start marker as tri-state metadata"
```

> **Note for the device gate:** anchors mean this does **not** retroactively repair already-ingested rows. `startObserving()` resumes from a stored `HKQueryAnchor`, so live observation never re-delivers old flow samples. Only a full `backfill()` (which starts from `anchor = nil`) re-reads them — and because the dedupKey is unchanged, that re-read reports `updated`, not `inserted`.

---

## Task 4: Cycle-phase resolution — authority beats inference

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift` (two new knobs)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/CyclePhaseExposureSource.swift` (whole file)
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift:183-190` (rewrite one test — see Step 5)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/CyclePhaseResolutionTests.swift`

**Interfaces:**
- Consumes: `HealthEvent.menstrualCycleStart` (Task 3).
- Produces: `EvidenceConfig.maxFlowGapDays: Int` (2), `EvidenceConfig.minInferredStartGapDays: Int` (10).

**The algorithm, in order (spec §8):**
1. **Authoritative** starts = manual `periodStart` events ∪ flow events with `menstrualCycleStart == true`.
2. **Inferred** candidates = run detection over flow events with `menstrualCycleStart == nil` **only**. `false` never participates — a live `false` must not become a start merely because it begins the loaded slice (the source sees a truncated in-memory window, not the DB).
3. Drop any inferred candidate within `minInferredStartGapDays` of **any authoritative start, before or after**.
4. Apply the same gap among surviving inferred candidates.
5. Union and dedupe by day. Authoritative starts are never suppressed by 3 or 4.

Also: the global `guard starts.count >= 2 else { return [] }` is **removed** — one start yields its menstrual-day exposure; two are needed only for a luteal window.

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/CyclePhaseResolutionTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct CyclePhaseResolutionTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)
    let utc = TimeZone(identifier: "UTC")!

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c
    }
    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: t0.addingTimeInterval(Double(offset) * 86_400))
    }
    private func flow(_ offset: Int, cycleStart: Bool?) -> HealthEvent {
        let meta = cycleStart.flatMap {
            try? JSONEncoder().encode(["menstrualCycleStart": $0 ? "true" : "false"])
        }
        return HealthEvent(timestamp: day(offset), timezoneID: "UTC", category: .cycle,
                           subtype: "menstrualFlow", value: 2, unit: "level",
                           source: .healthKit, metadata: meta, createdAt: day(offset))
    }
    private func manualStart(_ offset: Int) -> HealthEvent {
        HealthEvent(timestamp: day(offset), timezoneID: "UTC", category: .cycle,
                    subtype: "periodStart", source: .manual, createdAt: day(offset))
    }
    private func menstrualDays(_ events: [HealthEvent]) -> Set<Date> {
        let occ = CyclePhaseExposureSource(config: .default, timeZone: utc).occurrences(from: events)
        return Set(occ.filter { $0.key == .derived(.cyclePhase(.menstrual)) }.map(\.timestamp))
    }

    @Test func authoritativeMarkerWins() {
        let events = [flow(0, cycleStart: true), flow(1, cycleStart: false), flow(2, cycleStart: false)]
        #expect(menstrualDays(events) == [day(0)])
    }

    @Test func falseIsNeverInferredEvenWhenFirstInTheSlice() {
        // The corpus is a truncated in-memory window; the first flow row in it
        // is NOT necessarily the first day of that period.
        let events = [flow(0, cycleStart: false), flow(1, cycleStart: false)]
        #expect(menstrualDays(events).isEmpty)
    }

    @Test func nilRunsFallBackToInference() {
        // Two runs 28 days apart, no metadata anywhere (export/legacy shape).
        let events = [flow(0, cycleStart: nil), flow(1, cycleStart: nil), flow(2, cycleStart: nil),
                      flow(28, cycleStart: nil), flow(29, cycleStart: nil)]
        #expect(menstrualDays(events) == [day(0), day(28)])
    }

    @Test func oneMissingMiddleDayDoesNotSplitARun() {
        // maxFlowGapDays == 2, so a single skipped day keeps one period.
        let events = [flow(0, cycleStart: nil), flow(2, cycleStart: nil), flow(3, cycleStart: nil)]
        #expect(menstrualDays(events) == [day(0)])
    }

    @Test func inferredCandidateNearAnAuthoritativeStartIsDroppedOnBothSides() {
        // Authoritative start at day 10. Inferred runs at day 5 (before) and
        // day 14 (after) are both inside minInferredStartGapDays == 10.
        let events = [flow(5, cycleStart: nil),
                      flow(10, cycleStart: true),
                      flow(14, cycleStart: nil), flow(15, cycleStart: nil)]
        #expect(menstrualDays(events) == [day(10)])
    }

    @Test func authoritativeStartsAreNeverSuppressedByEachOther() {
        // Two authoritative starts 3 days apart: unusual, but authority wins.
        let events = [flow(0, cycleStart: true), flow(3, cycleStart: true)]
        #expect(menstrualDays(events) == [day(0), day(3)])
    }

    @Test func manualPeriodStartUnionsWithMarkersAndDedupesByDay() {
        let events = [manualStart(0), flow(0, cycleStart: true), flow(28, cycleStart: true)]
        #expect(menstrualDays(events) == [day(0), day(28)])
    }

    @Test func aSingleStartStillYieldsItsMenstrualDayAndNoLuteal() {
        // The old `guard starts.count >= 2` returned [] and threw away the
        // menstrual exposure along with the (correctly) underivable luteal one.
        let occ = CyclePhaseExposureSource(config: .default, timeZone: utc)
            .occurrences(from: [flow(0, cycleStart: true)])
        #expect(occ.contains { $0.key == .derived(.cyclePhase(.menstrual)) })
        #expect(!occ.contains { $0.key == .derived(.cyclePhase(.luteal)) })
    }

    @Test func lutealWindowStillDerivesFromTwoStarts() {
        let occ = CyclePhaseExposureSource(config: .default, timeZone: utc)
            .occurrences(from: [flow(0, cycleStart: true), flow(28, cycleStart: true)])
        let luteal = occ.filter { $0.key == .derived(.cyclePhase(.luteal)) }
        #expect(luteal.count == EvidenceConfig.default.lutealWindowDays)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter CyclePhaseResolutionTests`
Expected: FAIL — every test returns an empty set, because the source filters `subtype == "periodStart"` and real flow rows never match.

- [ ] **Step 3: Add the config knobs**

In `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift`, in the "Derived-exposure thresholds" block immediately after `lutealWindowDays`:

```swift
    public var maxFlowGapDays: Int = 2                    // a gap this small keeps one period (a missed day mustn't split a run)
    public var minInferredStartGapDays: Int = 10          // suppression window for INFERRED starts only; does not touch authoritative ones
```

- [ ] **Step 4: Implement the resolution algorithm**

Replace the body of `occurrences(from:)` in `HealthGraphCore/Sources/HealthGraphCore/Evidence/CyclePhaseExposureSource.swift`. The file becomes:

```swift
import Foundation

/// Cycle-phase exposures. v1 scopes to the two symptomatic windows: menstrual
/// (a period-start day) and luteal (the configured number of days before the
/// *next* start). Each phase-day is emitted as one occurrence at that day's
/// start, so the analyzer treats it with a standard 24h window.
///
/// Start resolution is authority-first. HealthKit stamps
/// `HKMetadataKeyMenstrualCycleStart` on flow samples; that marker is
/// authoritative and run inference is only a fallback for export/legacy rows
/// that carry no marker. Inference must never override or crowd out authority —
/// this source sees a truncated in-memory slice, so "first row in the slice" is
/// not "first day of the period".
public struct CyclePhaseExposureSource: ExposureSource {
    let config: EvidenceConfig
    let timeZone: TimeZone
    public init(config: EvidenceConfig, timeZone: TimeZone) {
        self.config = config; self.timeZone = timeZone
    }

    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let cycle = events.filter { $0.category == .cycle }

        // 1. Authoritative: explicit manual starts + marker == true.
        var authoritative = Set(cycle.filter { $0.subtype == "periodStart" }
            .map { cal.startOfDay(for: $0.timestamp) })
        let flow = cycle.filter { $0.subtype == "menstrualFlow" }
        authoritative.formUnion(flow.filter { $0.menstrualCycleStart == true }
            .map { cal.startOfDay(for: $0.timestamp) })

        // 2. Inferred candidates: run detection over UNMARKED flow days only.
        //    marker == false is excluded outright — it is a positive statement
        //    that the day is not a start.
        let unmarkedDays = Set(flow.filter { $0.menstrualCycleStart == nil }
            .map { cal.startOfDay(for: $0.timestamp) }).sorted()
        var inferred: [Date] = []
        var previous: Date?
        for d in unmarkedDays {
            if let p = previous, let gap = cal.dateComponents([.day], from: p, to: d).day,
               gap <= config.maxFlowGapDays {
                previous = d          // same run
            } else {
                inferred.append(d)    // first day of a new run
                previous = d
            }
        }

        // 3. Drop inferred candidates near ANY authoritative start, either side.
        let sortedAuthoritative = authoritative.sorted()
        inferred = inferred.filter { candidate in
            !sortedAuthoritative.contains { a in
                guard let gap = cal.dateComponents([.day], from: min(a, candidate),
                                                   to: max(a, candidate)).day else { return false }
                return gap < config.minInferredStartGapDays
            }
        }

        // 4. Apply the same gap among the surviving inferred candidates.
        var keptInferred: [Date] = []
        for candidate in inferred {
            if let last = keptInferred.last,
               let gap = cal.dateComponents([.day], from: last, to: candidate).day,
               gap < config.minInferredStartGapDays { continue }
            keptInferred.append(candidate)
        }

        // 5. Union + dedupe by day.
        let starts = Array(authoritative.union(keptInferred)).sorted()
        guard !starts.isEmpty else { return [] }

        var out: [ExposureOccurrence] = []
        func occ(_ phase: CyclePhase, day: Date) -> ExposureOccurrence {
            let d = cal.startOfDay(for: day)
            // Deterministic synthetic id from the day (phase-days aren't graph events).
            let sid = UUID(uuidString: ShortSleepExposureSource.uuid(from: d)) ?? UUID()
            return ExposureOccurrence(key: .derived(.cyclePhase(phase)), timestamp: d,
                                      timezoneID: timeZone.identifier, sourceEventID: sid)
        }
        // One start is enough for its own menstrual day; a luteal window needs
        // two, because it is defined relative to the NEXT start.
        for start in starts { out.append(occ(.menstrual, day: start)) }
        guard starts.count >= 2 else { return out }
        for i in 1..<starts.count {
            let nextStart = cal.startOfDay(for: starts[i])
            if config.lutealWindowDays >= 1 {
                for back in 1...config.lutealWindowDays {
                    if let day = cal.date(byAdding: .day, value: -back, to: nextStart) {
                        out.append(occ(.luteal, day: day))
                    }
                }
            }
        }
        return out
    }
}
```

- [ ] **Step 5: Rewrite the existing test that pins the removed guard**

`ExposureSourceTests.swift:183-190` holds `@Test func singleDistinctStartYieldsNothing()`,
which feeds two same-day `periodStart` events and asserts `#expect(occ.isEmpty)`. It passes
today **only** because of the `guard starts.count >= 2 else { return [] }` that Step 4
deletes. After Step 4 it returns one menstrual occurrence and the assertion fails.

That old assertion encodes the behaviour §8 deliberately changes. **Rewrite it — do not
"repair" it by restoring the guard**, which would silently revert this task:

```swift
    @Test func singleDistinctStartYieldsMenstrualButNoLuteal() {
        // Two period-start events on the same day = one distinct start.
        // One start is enough for its own menstrual day; a luteal window needs
        // a NEXT start to be defined relative to, so there is none here.
        let events = [periodStart(dayOffset: 0, hourOffset: 0), periodStart(dayOffset: 0, hourOffset: 1)]
        let src = CyclePhaseExposureSource(config: .default, timeZone: TimeZone(identifier: "UTC")!)
        let occ = src.occurrences(from: events)
        #expect(occ.count == 1)
        #expect(occ.allSatisfy { $0.key == .derived(.cyclePhase(.menstrual)) })
    }
```

- [ ] **Step 6: Run the tests**

Run: `swift test --package-path HealthGraphCore --filter CyclePhaseResolutionTests`
Expected: PASS, 9 tests.

Run: `swift test --package-path HealthGraphCore 2>&1 | tail -5`
Expected: all pass. The synthetic generator writes `subtype: "periodStart"`, which is still treated as authoritative, so planted cycle signals are unaffected.

- [ ] **Step 7: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/CyclePhaseExposureSource.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/CyclePhaseResolutionTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "fix(evidence): resolve cycle starts from HealthKit metadata, inference only as fallback"
```

---

## Task 5: Illness markers and classification

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomCatalog.swift` (append 7 entries)
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/IllnessMarkers.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift:56-59` (`illnessDays`)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/IllnessMarkersTests.swift`

**Interfaces:**
- Produces: `IllnessMarkers.normalize(healthKitSubtype:) -> String`, `IllnessMarkers.isIllnessDay(subtypes:) -> Bool`, `IllnessMarkers.healthKitIdentifierSubtypes: Set<String>`.

**Two sets that must not be conflated.** *Normalization coverage* spans all eight HK illness identifiers so none is silently unmapped. *Classification markers* are a strict subset: `runnyNose` is searchable and normalized but is **not** a marker — too common and nonspecific (allergies) to justify penalizing every exposure that day.

**Appends are safe; renames are destructive.** `canonicalKey` is derived from `displayName` and stored `health_events.subtype` values *are* those derived keys. Add only to the package catalog — the legacy root `SymptomCatalog.swift` has count assertions in `Food_IntolerancesTests` and must not be touched.

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/IllnessMarkersTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct IllnessMarkersTests {
    @Test func everyHealthKitIllnessIdentifierResolvesToARealCatalogKey() {
        let catalog = Set(SymptomCatalog.all.map(\.canonicalKey))
        #expect(!IllnessMarkers.healthKitIdentifierSubtypes.isEmpty)   // non-vacuous
        #expect(IllnessMarkers.healthKitIdentifierSubtypes.count == 8)
        for hk in IllnessMarkers.healthKitIdentifierSubtypes {
            let normalized = IllnessMarkers.normalize(healthKitSubtype: hk)
            #expect(catalog.contains(normalized))   // no HK identifier is left unmapped
        }
    }

    @Test func theTwoRealAliasesAreMapped() {
        #expect(IllnessMarkers.normalize(healthKitSubtype: "coughing") == "cough")
        #expect(IllnessMarkers.normalize(healthKitSubtype: "sinusCongestion") == "congestion")
    }

    @Test func theOtherSixAreIdentity() {
        for s in ["fever", "chills", "nightSweats", "soreThroat", "runnyNose", "generalizedBodyAche"] {
            #expect(IllnessMarkers.normalize(healthKitSubtype: s) == s)
        }
    }

    @Test func feverAloneQualifies() {
        #expect(IllnessMarkers.isIllnessDay(subtypes: ["fever"]))
    }

    @Test func twoCompositeMarkersQualify() {
        #expect(IllnessMarkers.isIllnessDay(subtypes: ["cough", "soreThroat"]))
    }

    @Test func oneCompositeMarkerDoesNot() {
        #expect(!IllnessMarkers.isIllnessDay(subtypes: ["cough"]))
        #expect(!IllnessMarkers.isIllnessDay(subtypes: ["chills"]))
        #expect(!IllnessMarkers.isIllnessDay(subtypes: ["nightSweats"]))
    }

    @Test func runnyNoseIsNormalizedButIsNotAMarker() {
        // Searchable and mapped, deliberately not a classifier input: too
        // common and nonspecific (allergies) to penalise every exposure that day.
        #expect(!IllnessMarkers.isIllnessDay(subtypes: ["runnyNose", "cough"]))
    }

    @Test func aliasedHealthKitSubtypesCountTowardTheComposite() {
        let normalized = ["coughing", "sinusCongestion"].map { IllnessMarkers.normalize(healthKitSubtype: $0) }
        #expect(IllnessMarkers.isIllnessDay(subtypes: Set(normalized)))
    }
}

@Suite struct IllnessDaysTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func symptom(_ subtype: String, dayOffset: Int) -> HealthEvent {
        let t = t0.addingTimeInterval(Double(dayOffset) * 86_400)
        return HealthEvent(timestamp: t, timezoneID: "UTC", category: .symptom,
                           subtype: subtype, value: 5, source: .manual, createdAt: t)
    }

    @Test func explicitIllnessEventsStillCount() async throws {
        let db = try AppDatabase.inMemory()
        let engine = EvidenceEngine(database: db)
        let e = HealthEvent(timestamp: t0, timezoneID: "UTC", category: .illness,
                            subtype: "cold", source: .manual, createdAt: t0)
        #expect(engine.illnessDays([e]).count == 1)
    }

    @Test func feverSymptomMarksTheDay() async throws {
        let db = try AppDatabase.inMemory()
        let engine = EvidenceEngine(database: db)
        #expect(engine.illnessDays([symptom("fever", dayOffset: 0)]).count == 1)
    }

    @Test func aLoneCoughDoesNotMarkTheDay() async throws {
        let db = try AppDatabase.inMemory()
        let engine = EvidenceEngine(database: db)
        #expect(engine.illnessDays([symptom("cough", dayOffset: 0)]).isEmpty)
    }

    @Test func twoMarkersOnTheSameDayMarkIt_butSpreadAcrossDaysDoNot() async throws {
        let db = try AppDatabase.inMemory()
        let engine = EvidenceEngine(database: db)
        let sameDay = [symptom("cough", dayOffset: 0), symptom("soreThroat", dayOffset: 0)]
        #expect(engine.illnessDays(sameDay).count == 1)

        let differentDays = [symptom("cough", dayOffset: 0), symptom("soreThroat", dayOffset: 3)]
        #expect(engine.illnessDays(differentDays).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter IllnessMarkers`
Expected: FAIL — `cannot find 'IllnessMarkers' in scope`.

- [ ] **Step 3: Append the catalog entries**

In `HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomCatalog.swift`, add to the `raw` array. Place them in the region that matches their body area, following the existing `// Chest region` / `// Head region` comment style; the exact position does not matter because `all` sorts alphabetically, but the region comments should stay truthful:

```swift
        // Illness markers (appended 2026-07-26 — see IllnessMarkers).
        // APPEND ONLY: canonicalKey is derived from displayName, so renaming any
        // of these orphans every stored event that used the old key.
        ("Fever", "chest"),
        ("Chills", "chest"),
        ("Night Sweats", "chest"),
        ("Sore Throat", "neck"),
        ("Congestion", "head"),
        ("Runny Nose", "head"),
        ("Generalized Body Ache", "chest"),
```

- [ ] **Step 4: Create the markers namespace**

Create `HealthGraphCore/Sources/HealthGraphCore/Evidence/IllnessMarkers.swift`:

```swift
import Foundation

/// Illness-day classification from ordinary symptom events.
///
/// The engine treats illness as an always-on confounder, but nothing ever wrote
/// an `.illness` event, so the confounder pool was permanently empty on real
/// data. Rather than add a sixth capture type, illness is derived from symptoms
/// the user can already log through the existing symptom path.
public enum IllnessMarkers {
    /// HealthKit symptom subtypes that indicate illness. HK subtypes are derived
    /// by stripping `HKCategoryTypeIdentifier` and lowercasing the first char;
    /// catalog keys come from `SymptomCatalog.canonicalize`. Those two agree for
    /// six of these and diverge for exactly two — hence `normalize`.
    public static let healthKitIdentifierSubtypes: Set<String> = [
        "coughing", "fever", "chills", "soreThroat",
        "runnyNose", "sinusCongestion", "nightSweats", "generalizedBodyAche",
    ]

    /// The only two genuine mismatches between the HK-derived subtype and the
    /// catalog key. Everything else is identity.
    private static let aliases: [String: String] = [
        "coughing": "cough",
        "sinusCongestion": "congestion",
    ]

    /// Fever alone is specific enough to call the day an illness day.
    private static let strong: Set<String> = ["fever"]

    /// Any two of these together indicate illness. Individually they are too
    /// common to justify penalising every exposure on that day.
    /// `runnyNose` is deliberately ABSENT: allergies make it near-useless as a
    /// signal, though it is still normalized and searchable.
    private static let composite: Set<String> = [
        "chills", "nightSweats", "soreThroat", "congestion", "cough", "generalizedBodyAche",
    ]

    public static func normalize(healthKitSubtype subtype: String) -> String {
        aliases[subtype] ?? subtype
    }

    /// True when the day's symptom subtypes indicate illness: fever alone, or
    /// at least two distinct composite markers. Inputs must already be
    /// normalized via `normalize(healthKitSubtype:)`.
    public static func isIllnessDay(subtypes: Set<String>) -> Bool {
        if !strong.isDisjoint(with: subtypes) { return true }
        return composite.intersection(subtypes).count >= 2
    }
}
```

- [ ] **Step 5: Use it in `illnessDays`**

In `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift`, replace `illnessDays(_:)`:

```swift
    // Illness windows as day-sets (always a confounder — spec §7.3).
    // Two producers: explicit `.illness` events (none exist today, but a future
    // capture surface would land here unchanged), and symptom events that meet
    // the IllnessMarkers bar. Day-of only; multi-day forward extension is a
    // deliberate follow-up, not part of this fix.
    func illnessDays(_ events: [HealthEvent]) -> Set<Date> {
        let cal = Self.utc
        var days = Set(events.filter { $0.category == .illness }.map { cal.startOfDay(for: $0.timestamp) })

        var markersByDay: [Date: Set<String>] = [:]
        for e in events where e.category == .symptom {
            guard let subtype = e.subtype else { continue }
            let day = cal.startOfDay(for: e.timestamp)
            markersByDay[day, default: []].insert(IllnessMarkers.normalize(healthKitSubtype: subtype))
        }
        for (day, subtypes) in markersByDay where IllnessMarkers.isIllnessDay(subtypes: subtypes) {
            days.insert(day)
        }
        return days
    }
```

- [ ] **Step 6: Run the tests**

Run: `swift test --package-path HealthGraphCore --filter Illness`
Expected: PASS, 12 tests across the two suites.

Run: `swift test --package-path HealthGraphCore 2>&1 | tail -5`
Expected: all pass. `SymptomCatalogTests` pins specific derived keys, not the total count, so appending is safe — if a count assertion does fail, update the count, never the keys.

- [ ] **Step 7: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomCatalog.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/IllnessMarkers.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/IllnessMarkersTests.swift
git commit -m "feat(evidence): derive illness days from loggable symptom markers"
```

---

## Task 6: Synchronous existence check for bootstrap

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift`

**Interfaces:**
- Produces: `GRDBEventStore.anyEventExistsSync(includingDeleted: Bool) throws -> Bool`.

Added to the concrete struct, **not** the `EventStore` protocol — there is precedent (`rawCountIncludingDeleted`) and the only caller is concrete-typed. Includes soft-deleted rows by default: a user who deleted everything is not a fresh install. `SELECT EXISTS`, not a count of 136k rows.

- [ ] **Step 1: Write the failing test**

Add to `HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift`:

```swift
@Suite struct AnyEventExistsTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func emptyGraphHasNoEvents() throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        #expect(try store.anyEventExistsSync(includingDeleted: true) == false)
    }

    @Test func softDeletedOnlyGraphStillCountsAsPopulated() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let e = HealthEvent(timestamp: t0, timezoneID: "UTC", category: .symptom,
                            subtype: "headache", source: .manual, createdAt: t0)
        try await store.save(e)
        try await store.softDelete(id: e.id)

        let including = try store.anyEventExistsSync(includingDeleted: true)
        let excluding = try store.anyEventExistsSync(includingDeleted: false)
        #expect(including == true)    // not a fresh install
        #expect(excluding == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter AnyEventExistsTests`
Expected: FAIL — no member `anyEventExistsSync`.

- [ ] **Step 3: Implement**

Add to `GRDBEventStore` in `HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift`, next to `rawCountIncludingDeleted`:

```swift
    /// Synchronous existence check for bootstrap, where no `await` is available
    /// (mirrors `purgeSyntheticDataSync`). `SELECT EXISTS` — never a COUNT over
    /// a six-figure table.
    ///
    /// `includingDeleted: true` is the first-run reconciliation's question: a
    /// user who soft-deleted everything is NOT a fresh install and must not be
    /// onboarded again.
    public func anyEventExistsSync(includingDeleted: Bool) throws -> Bool {
        try dbWriter.read { db in
            let sql = includingDeleted
                ? "SELECT EXISTS(SELECT 1 FROM health_events)"
                : "SELECT EXISTS(SELECT 1 FROM health_events WHERE deletedAt IS NULL)"
            return try Bool.fetchOne(db, sql: sql) ?? false
        }
    }
```

- [ ] **Step 4: Run tests and commit**

Run: `swift test --package-path HealthGraphCore --filter AnyEventExistsTests`
Expected: PASS, 2 tests.

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift
git commit -m "feat(store): synchronous anyEventExistsSync for bootstrap reconciliation"
```

---

## Task 7: Source-scoped import summary

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift`

**Interfaces:**
- Produces: `ImportedCategorySummary` (public struct with a `public init`), `GRDBEventStore.importedSummary(source:) async throws -> [ImportedCategorySummary]`.

**The predicate is three conditions, all required:** `source = ? AND syntheticBatch IS NULL AND deletedAt IS NULL`. `source == .healthKit` alone is wrong — `SyntheticDataGenerator.swift:207` emits demo sleep with `source: .healthKit`, so a DEBUG graph with demo data loaded would report fabricated rows as imported Apple Health history. `syntheticBatch` has a partial index, so the clause is cheap.

Needs a `public init` — the app target constructs these in previews and tests, and package DTOs without one are unconstructable outside the module.

- [ ] **Step 1: Write the failing test**

Add to `HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift`:

```swift
@Suite struct ImportedSummaryTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func event(_ category: EventCategory, _ source: EventSource,
                       dayOffset: Int, synthetic: String? = nil) -> HealthEvent {
        let t = t0.addingTimeInterval(Double(dayOffset) * 86_400)
        return HealthEvent(timestamp: t, timezoneID: "UTC", category: category,
                           subtype: "x", source: source, createdAt: t, syntheticBatch: synthetic)
    }

    @Test func scopesToSourceAndReportsCountsAndEarliestDates() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        try await store.save([
            event(.sleep, .healthKit, dayOffset: -30),
            event(.sleep, .healthKit, dayOffset: -10),
            event(.symptom, .healthKit, dayOffset: -5),
            event(.symptom, .manual, dayOffset: -1),            // wrong source
            event(.food, .healthExportFile, dayOffset: -2),     // wrong source
        ])

        let summary = try await store.importedSummary(source: .healthKit)
        let byCategory = Dictionary(uniqueKeysWithValues: summary.map { ($0.category, $0) })
        #expect(byCategory.count == 2)                              // sleep + symptom only
        #expect(byCategory["sleep"]?.count == 2)
        #expect(byCategory["sleep"]?.earliest == t0.addingTimeInterval(-30 * 86_400))
        #expect(byCategory["symptom"]?.count == 1)
    }

    @Test func excludesSyntheticRowsCarryingTheHealthKitSource() async throws {
        // SyntheticDataGenerator emits demo sleep as source .healthKit, so a
        // source-only predicate would report fabricated rows as real history.
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        try await store.save([
            event(.sleep, .healthKit, dayOffset: -10),
            event(.sleep, .healthKit, dayOffset: -40, synthetic: "demo-v7"),
        ])

        let summary = try await store.importedSummary(source: .healthKit)
        #expect(summary.count == 1)
        #expect(summary[0].count == 1)
        #expect(summary[0].earliest == t0.addingTimeInterval(-10 * 86_400))  // NOT the synthetic -40
    }

    @Test func excludesSoftDeletedRows() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let keep = event(.sleep, .healthKit, dayOffset: -10)
        let drop = event(.sleep, .healthKit, dayOffset: -40)
        try await store.save([keep, drop])
        try await store.softDelete(id: drop.id)

        let summary = try await store.importedSummary(source: .healthKit)
        #expect(summary.count == 1)
        #expect(summary[0].count == 1)
    }

    @Test func emptyGraphReturnsNoRows() async throws {
        let db = try AppDatabase.inMemory()
        #expect(try await GRDBEventStore(database: db).importedSummary(source: .healthKit).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter ImportedSummaryTests`
Expected: FAIL — `cannot find 'ImportedCategorySummary' in scope`.

- [ ] **Step 3: Implement**

Add to `HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift`, above `GRDBEventStore`:

```swift
/// Per-category count + earliest event for ONE ingestion source.
/// `category` is the raw stored value, so the app can map it to its own
/// CategoryFamily without the package importing any UI type.
public struct ImportedCategorySummary: Sendable, Equatable {
    public let category: String
    public let count: Int
    public let earliest: Date
    public init(category: String, count: Int, earliest: Date) {
        self.category = category; self.count = count; self.earliest = earliest
    }
}
```

And to `GRDBEventStore`:

```swift
    /// What a given ingestion source has actually contributed: per-category
    /// counts and the earliest surviving event.
    ///
    /// The predicate is deliberately three conditions. `source` alone is NOT
    /// enough — SyntheticDataGenerator emits demo sleep with `source: .healthKit`,
    /// so a DEBUG graph with demo data would report fabricated rows as imported
    /// Apple Health history. Release purges synthetic rows at bootstrap, which
    /// does not make the clause optional: DEBUG is where first run is exercised.
    public func importedSummary(source: EventSource) async throws -> [ImportedCategorySummary] {
        try await dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT category AS k, COUNT(*) AS c, MIN(timestamp) AS earliest
                FROM health_events
                WHERE source = ? AND syntheticBatch IS NULL AND deletedAt IS NULL
                GROUP BY category
                """, arguments: [source.rawValue])
            return rows.compactMap { row in
                guard let earliest: Date = row["earliest"] else { return nil }
                return ImportedCategorySummary(category: row["k"] as String,
                                               count: row["c"] as Int,
                                               earliest: earliest)
            }
        }
    }
```

- [ ] **Step 4: Run tests and commit**

Run: `swift test --package-path HealthGraphCore --filter ImportedSummaryTests`
Expected: PASS, 4 tests.

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift
git commit -m "feat(store): source-scoped imported summary excluding synthetic and deleted rows"
```

---

## Task 8: Seeded quick-log chips

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Capture/ChipRanker.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomSeeds.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ChipRankerTests.swift`

**Interfaces:**
- Produces: `ChipRanker.rank(history:category:now:timeZone:limit:seeds:)` with `seeds: [String] = []`; `SymptomSeeds.validate(_:limit:) -> [String]`.

**`seeds:` must be trailing with `= []`** — three app call sites and three package tests pass the existing labels without it.

**Append seeds after the sort, around `.prefix(limit)`.** `ChipRanker` iterates a Dictionary, so determinism comes only from the explicit sort; injecting seeds into `scored` with a synthetic score would make ties nondeterministic across runs.

**Validation runs on write *and* read.** The persisted list outlives catalog changes and future `RedFlagCatalog` additions. `canonicalKey(for:)` is **not** a validator — it is total and returns a derived key for arbitrary garbage. Use catalog membership.

**A seeded red-flag chip would be dangerous, not just wrong:** `CaptureSheet.logged(_:)` calls `redFlagPresenter.consider(event)` after every write, so a "Chest Pain" chip is a one-tap path to a full-screen emergency takeover on the first screen a new user sees.

- [ ] **Step 1: Write the failing test**

Add to `HealthGraphCore/Tests/HealthGraphCoreTests/ChipRankerTests.swift`:

```swift
@Suite struct SymptomSeedsTests {
    @Test func dropsUnknownKeysAndPreservesOrder() {
        let real = SymptomCatalog.canonicalKey(for: "Headache")
        let other = SymptomCatalog.canonicalKey(for: "Bloating")
        #expect(SymptomSeeds.validate([other, "notARealKey", real], limit: 8) == [other, real])
    }

    @Test func excludesEveryRedFlagKey() {
        #expect(!RedFlagCatalog.allSymptomKeys.isEmpty)   // non-vacuous
        let cleaned = SymptomSeeds.validate(RedFlagCatalog.allSymptomKeys, limit: 8)
        #expect(cleaned.isEmpty)
    }

    @Test func dedupesPreservingFirstOccurrence() {
        let a = SymptomCatalog.canonicalKey(for: "Headache")
        let b = SymptomCatalog.canonicalKey(for: "Nausea")
        #expect(SymptomSeeds.validate([a, b, a], limit: 8) == [a, b])
    }

    @Test func appliesTheLimit() {
        let keys = SymptomCatalog.all.map(\.canonicalKey)
            .filter { !Set(RedFlagCatalog.allSymptomKeys).contains($0) }
        #expect(SymptomSeeds.validate(keys, limit: 8).count == 8)
    }
}

@Suite struct ChipRankerSeedsTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let tz = TimeZone(identifier: "UTC")!

    private func ev(_ sub: String, _ t: Date) -> HealthEvent {
        HealthEvent(timestamp: t, timezoneID: "UTC", category: .symptom,
                    subtype: sub, source: .manual, createdAt: t)
    }

    @Test func historyRanksFirstAndSeedsFillOnlyLeftoverSlots() {
        let history = [ev("headache", now), ev("headache", now.addingTimeInterval(-3600)),
                       ev("nausea", now.addingTimeInterval(-7200))]
        let ranked = ChipRanker.rank(history: history, category: .symptom, now: now,
                                     timeZone: tz, limit: 4, seeds: ["bloating", "fatigue"])
        #expect(ranked.prefix(2) == ["headache", "nausea"])   // history wins the top slots
        #expect(ranked.count == 4)
        #expect(ranked.contains("bloating") && ranked.contains("fatigue"))
    }

    @Test func seedsAlreadyInHistoryAreNotDuplicated() {
        let history = [ev("headache", now)]
        let ranked = ChipRanker.rank(history: history, category: .symptom, now: now,
                                     timeZone: tz, limit: 4, seeds: ["headache", "nausea"])
        #expect(ranked == ["headache", "nausea"])
    }

    @Test func seedsNeverExceedTheLimit() {
        let ranked = ChipRanker.rank(history: [], category: .symptom, now: now,
                                     timeZone: tz, limit: 2, seeds: ["a", "b", "c", "d"])
        #expect(ranked == ["a", "b"])
    }

    @Test func anEmptyHistoryIsFullySeeded() {
        // The hole this closes: chips are filtered to sources [.manual], so a
        // HealthKit-only graph yields ZERO chips today.
        let ranked = ChipRanker.rank(history: [], category: .symptom, now: now,
                                     timeZone: tz, limit: 8, seeds: ["headache", "bloating"])
        #expect(ranked == ["headache", "bloating"])
    }

    @Test func omittingSeedsKeepsTheOldBehaviour() {
        let history = [ev("headache", now)]
        #expect(ChipRanker.rank(history: history, category: .symptom, now: now,
                                timeZone: tz, limit: 8) == ["headache"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter Seeds`
Expected: FAIL — `cannot find 'SymptomSeeds' in scope`; `rank` has no `seeds:` parameter.

- [ ] **Step 3: Create the validator**

Create `HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomSeeds.swift`:

```swift
import Foundation

/// Validation for the first-run "what brings you here?" seed list.
///
/// Runs on BOTH write and read: the stored list outlives catalog changes and
/// future RedFlagCatalog additions, so a key that was fine when saved can
/// become invalid later.
public enum SymptomSeeds {
    /// Keeps only keys that resolve to a current catalog entry, drops every
    /// red-flag key, dedupes preserving selection order, and applies `limit`.
    ///
    /// Membership is checked against `SymptomCatalog.all` — NOT via
    /// `canonicalKey(for:)`, which is total and happily derives a key for
    /// arbitrary garbage, so it would accept anything.
    ///
    /// The red-flag exclusion is a safety requirement, not tidiness: capture
    /// calls the red-flag evaluator after every write, so a seeded "Chest Pain"
    /// chip is a one-tap path to a full-screen emergency takeover on the first
    /// screen a new user sees.
    public static func validate(_ keys: [String], limit: Int) -> [String] {
        let known = Set(SymptomCatalog.all.map(\.canonicalKey))
        let redFlags = Set(RedFlagCatalog.allSymptomKeys)
        var seen = Set<String>()
        var out: [String] = []
        for key in keys {
            guard known.contains(key), !redFlags.contains(key), seen.insert(key).inserted else { continue }
            out.append(key)
            if out.count == limit { break }
        }
        return out
    }
}
```

- [ ] **Step 4: Add `seeds:` to the ranker**

In `HealthGraphCore/Sources/HealthGraphCore/Capture/ChipRanker.swift`, change the signature and the return:

```swift
    /// Ranks the distinct (category, subtype) pairs in `history` for quick-log chips.
    /// Score = frequency (log-damped) × recency (exponential, ~14-day half-life)
    ///       × time-of-day affinity (share of this item's logs within ±2h of `now`'s hour).
    /// Returns the top `limit`, highest first. `history` is any recent event slice.
    ///
    /// `seeds` fill ONLY the slots left over after history-ranked items and never
    /// displace them. They are appended after the sort — injecting them into the
    /// scored set with a synthetic score would make ties nondeterministic, since
    /// the intermediate dictionary order is not stable. No expiry: as real
    /// history accumulates it outranks and pushes seeds out naturally.
    public static func rank(history: [HealthEvent], category: EventCategory, now: Date,
                            timeZone: TimeZone, limit: Int, seeds: [String] = []) -> [String] {
```

Replace the final `return` statement:

```swift
        let ranked = scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }
            .prefix(limit).map(\.0)
        guard ranked.count < limit, !seeds.isEmpty else { return ranked }
        var out = ranked
        let existing = Set(ranked)
        for seed in seeds where !existing.contains(seed) {
            out.append(seed)
            if out.count == limit { break }
        }
        return out
```

- [ ] **Step 5: Run tests and commit**

Run: `swift test --package-path HealthGraphCore --filter Seeds`
Expected: PASS, 9 tests across the two suites.

Run: `swift test --package-path HealthGraphCore 2>&1 | tail -5`
Expected: all pass — the defaulted parameter leaves the three existing `ChipRankerTests` cases untouched.

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Capture/ChipRanker.swift \
        HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomSeeds.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ChipRankerTests.swift
git commit -m "feat(capture): seed quick-log chips from first-run symptom selection"
```

---

## Task 9: First-run state and the resolver

**Files:**
- Create: `Models/FirstRunState.swift`
- Test: `Food IntolerancesTests/FirstRunResolverTests.swift`

**Interfaces:**
- Produces: `FirstRunKeys` (key names), `FirstRunResolution` (enum), `FirstRunResolver.resolve(defaults:currentVersion:anyEventExists:backfillAttempted:) -> FirstRunResolution`, `FirstRunState` (`@MainActor final class`, `ObservableObject`).

**The resolver is pure** so the whole truth table is testable without a host app or a simulator kill. It takes the graph-existence answer and the backfill flag as **inputs**, never reading them itself.

**Every comparison is against `currentVersion`, never zero.** `completedVersion > 0 → shell` is a Boolean in disguise: when a later round raises `currentVersion` to 2, a user at `completedVersion == 1` would go straight to the shell and never see the added screen.

**`startedVersion` prevents a silent, permanent skip.** Backfill inserts events *during* the flow. Without an in-progress marker, a termination after the first insert leaves `completedVersion == 0` and a populated graph — exactly the reconciliation predicate — so the next launch marks onboarding complete and mounts the shell. The user never sees symptom seeding or location again and nothing looks wrong.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/FirstRunResolverTests.swift`:

```swift
import Foundation
import Testing
@testable import Food_Intolerances

@Suite struct FirstRunResolverTests {
    private func defaults(started: Int = 0, completed: Int = 0, forceShow: Bool = false) -> UserDefaults {
        let suite = UserDefaults(suiteName: "firstrun-test-\(UUID().uuidString)")!
        suite.set(started, forKey: FirstRunKeys.startedVersion)
        suite.set(completed, forKey: FirstRunKeys.completedVersion)
        suite.set(forceShow, forKey: FirstRunKeys.forceShow)
        return suite
    }

    @Test func completedAtOrAboveCurrentGoesToShell() {
        let r = FirstRunResolver.resolve(defaults: defaults(completed: 2), currentVersion: 2,
                                         anyEventExists: { false }, backfillAttempted: false)
        #expect(r == .shell)
    }

    @Test func interruptedCurrentVersionResumesTheFlow() {
        // started == current, completed < current: the app died mid-flow.
        let r = FirstRunResolver.resolve(defaults: defaults(started: 1, completed: 0), currentVersion: 1,
                                         anyEventExists: { true }, backfillAttempted: true)
        #expect(r == .flow(.resume))
    }

    @Test func upgradeFromAnOlderCompletedVersionRunsTheFlow() {
        // A Boolean resolver (completedVersion > 0 -> shell) passes every other
        // case and fails exactly this one.
        let r = FirstRunResolver.resolve(defaults: defaults(completed: 1), currentVersion: 2,
                                         anyEventExists: { true }, backfillAttempted: true)
        #expect(r == .flow(.upgrade(from: 1)))
    }

    @Test func interruptedUpgradeAlsoRunsTheFlow() {
        // completed 1, started 2, current 2 — the other case a Boolean resolver misses.
        let r = FirstRunResolver.resolve(defaults: defaults(started: 2, completed: 1), currentVersion: 2,
                                         anyEventExists: { true }, backfillAttempted: true)
        #expect(r == .flow(.resume))
    }

    @Test func bothZeroWithAPopulatedGraphReconcilesToShell() {
        let r = FirstRunResolver.resolve(defaults: defaults(), currentVersion: 1,
                                         anyEventExists: { true }, backfillAttempted: false)
        #expect(r == .reconcileThenShell)
    }

    @Test func bothZeroWithABackfillFlagReconcilesEvenOnAnEmptyGraph() {
        let r = FirstRunResolver.resolve(defaults: defaults(), currentVersion: 1,
                                         anyEventExists: { false }, backfillAttempted: true)
        #expect(r == .reconcileThenShell)
    }

    @Test func bothZeroAndTrulyEmptyRunsTheFreshFlow() {
        let r = FirstRunResolver.resolve(defaults: defaults(), currentVersion: 1,
                                         anyEventExists: { false }, backfillAttempted: false)
        #expect(r == .flow(.fresh))
    }

    @Test func reconciliationNeverConsultsTheGraphOnceOnboardingHasStarted() {
        // The self-skipping defect: onboarding's OWN writes satisfied the
        // predicate that decides whether onboarding is needed.
        var graphConsulted = false
        let r = FirstRunResolver.resolve(defaults: defaults(started: 1, completed: 0), currentVersion: 1,
                                         anyEventExists: { graphConsulted = true; return true },
                                         backfillAttempted: true)
        #expect(r == .flow(.resume))
        #expect(graphConsulted == false)
    }

    @Test func forceShowBypassesReconciliation() {
        let r = FirstRunResolver.resolve(defaults: defaults(forceShow: true), currentVersion: 1,
                                         anyEventExists: { true }, backfillAttempted: true)
        #expect(r == .flow(.fresh))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/FirstRunResolverTests" -parallel-testing-enabled NO 2>&1 | tail -8`
Expected: FAIL — `cannot find 'FirstRunKeys' in scope`.

- [ ] **Step 3: Implement**

Create `Models/FirstRunState.swift`:

```swift
import Foundation
import HealthGraphCore

enum FirstRunKeys {
    static let startedVersion = "hg.firstRun.startedVersion"
    static let completedVersion = "hg.firstRun.completedVersion"
    static let symptomSeeds = "hg.firstRun.symptomSeeds"
    static let forceShow = "hg.firstRun.forceShow"
}

enum FirstRunEntry: Equatable {
    case fresh
    case resume
    case upgrade(from: Int)
}

enum FirstRunResolution: Equatable {
    case shell
    case reconcileThenShell
    case flow(FirstRunEntry)
}

/// Pure launch resolution. Every comparison is against `currentVersion`, never
/// against zero — `completedVersion > 0 -> shell` would make the versioning
/// decorative, sending a v1-completed user straight past a v2 screen.
///
/// Graph existence and the backfill flag arrive as INPUTS and are consulted
/// only in the both-zero row: onboarding itself writes events, so consulting
/// them any later lets onboarding's own writes decide that onboarding is
/// unnecessary.
enum FirstRunResolver {
    static func resolve(defaults: UserDefaults,
                        currentVersion: Int,
                        anyEventExists: () -> Bool,
                        backfillAttempted: Bool) -> FirstRunResolution {
        #if DEBUG
        if defaults.bool(forKey: FirstRunKeys.forceShow) { return .flow(.fresh) }
        #endif
        let started = defaults.integer(forKey: FirstRunKeys.startedVersion)
        let completed = defaults.integer(forKey: FirstRunKeys.completedVersion)

        if completed >= currentVersion { return .shell }
        if started == currentVersion { return .flow(.resume) }
        if completed > 0 { return .flow(.upgrade(from: completed)) }
        if started == 0 && (backfillAttempted || anyEventExists()) { return .reconcileThenShell }
        return .flow(.fresh)
    }
}

/// Owns the persisted first-run markers. Resolution happens once, synchronously,
/// before the first frame — a `@Query`-driven or async gate renders the wrong
/// branch first and flashes.
@MainActor
final class FirstRunState: ObservableObject {
    /// Bump when a round ADDS a screen, and extend the entry mapping with it.
    static let currentVersion = 1

    @Published private(set) var resolution: FirstRunResolution
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, store: GRDBEventStore) {
        self.defaults = defaults
        // FAIL CLOSED: a read error is a bootstrap failure, not "show
        // onboarding". Onboarding over a populated graph is unrecoverable.
        let exists: () -> Bool = {
            do { return try store.anyEventExistsSync(includingDeleted: true) }
            catch { fatalError("first-run: graph existence check failed: \(error)") }
        }
        let resolved = FirstRunResolver.resolve(
            defaults: defaults,
            currentVersion: Self.currentVersion,
            anyEventExists: exists,
            backfillAttempted: defaults.bool(forKey: HealthKitIngestor.backfillCompletedKey))
        if resolved == .reconcileThenShell {
            defaults.set(Self.currentVersion, forKey: FirstRunKeys.completedVersion)
        }
        self.resolution = resolved
    }

    /// The resolved entry, or nil when the shell should mount. Deliberately NOT
    /// a Bool: `.resume` has to reach the flow so an interrupted import can be
    /// recovered rather than silently restarted, and `.upgrade` will need it too.
    var flowEntry: FirstRunEntry? { if case let .flow(entry) = resolution { return entry }; return nil }

    /// Written BEFORE any side effect, so a termination mid-flow resumes.
    func markStarted() {
        defaults.set(Self.currentVersion, forKey: FirstRunKeys.startedVersion)
    }

    func markCompleted(seeds: [String]) {
        defaults.set(SymptomSeeds.validate(seeds, limit: 8), forKey: FirstRunKeys.symptomSeeds)
        defaults.set(Self.currentVersion, forKey: FirstRunKeys.completedVersion)
        defaults.removeObject(forKey: FirstRunKeys.startedVersion)
        defaults.removeObject(forKey: FirstRunKeys.forceShow)
        resolution = .shell
    }

    /// Re-validated on READ: the stored list outlives catalog and red-flag changes.
    var seeds: [String] {
        SymptomSeeds.validate(defaults.stringArray(forKey: FirstRunKeys.symptomSeeds) ?? [], limit: 8)
    }
}
```

- [ ] **Step 4: Run tests and commit**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/FirstRunResolverTests" -parallel-testing-enabled NO 2>&1 | grep -E "✔|✘|Test run"`
Expected: 9 tests pass.

```bash
git add Models/FirstRunState.swift "Food IntolerancesTests/FirstRunResolverTests.swift"
git commit -m "feat(first-run): versioned launch resolver with interrupted-flow protection"
```

---

## Task 10: Persisted import status

**Files:**
- Create: `Models/HealthImportStatus.swift`
- Test: `Food IntolerancesTests/HealthImportStatusTests.swift`

**Interfaces:**
- Produces: `HealthImportOutcome` (enum), `HealthImportStatus` (Codable struct), `HealthImportStatusStore` (`@MainActor final class`, `ObservableObject`) with `beginAttempt()`, `finish(summary:failures:)`, `failAttempt()`, `normalizeAtLaunch()`, `current`.

**`inProgress` must never be rendered literally.** After process death no task exists to finish it, so a surface drawing the state verbatim shows a spinner that never resolves. Normalization to `.interrupted` runs at launch **before** either surface renders.

**`interrupted` is its own case, not `attemptFailed(reason:)`** — nothing errored, the process died, and the right offer is resume rather than a failure report.

**A prior successful summary must survive an interrupted re-import**, so the summary fields persist independently of the outcome.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/HealthImportStatusTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct HealthImportStatusTests {
    private func store() -> (HealthImportStatusStore, UserDefaults) {
        let d = UserDefaults(suiteName: "import-status-\(UUID().uuidString)")!
        return (HealthImportStatusStore(defaults: d), d)
    }

    @Test func startsNotStarted() {
        let (s, _) = store()
        #expect(s.current.outcome == .notStarted)
    }

    @Test func beginAttemptPersistsInProgressBeforeAnyWork() {
        let (s, d) = store()
        s.beginAttempt()
        let reloaded = HealthImportStatusStore(defaults: d)
        #expect(reloaded.current.outcome == .inProgress)   // survives a relaunch
    }

    @Test func launchNormalizationTurnsAStrandedInProgressIntoInterrupted() {
        let (s, d) = store()
        s.beginAttempt()
        let afterRelaunch = HealthImportStatusStore(defaults: d)
        afterRelaunch.normalizeAtLaunch()
        #expect(afterRelaunch.current.outcome == .interrupted)
    }

    @Test func finishWithEventsAndNoFailuresIsCompleted() {
        let (s, _) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 10, updated: 2), failures: [])
        #expect(s.current.outcome == .completed)
        #expect(s.current.eventsImported == 12)   // inserted + updated, per HealthKitIngestor
    }

    @Test func finishWithZeroEventsAndNoFailuresIsCompletedNoData() {
        let (s, _) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(), failures: [])
        #expect(s.current.outcome == .completedNoData)
    }

    @Test func finishWithFailuresIsCompletedWithIssues() {
        let (s, _) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 5), failures: ["HKQuantityTypeIdentifierHeartRate: denied"])
        #expect(s.current.outcome == .completedWithIssues)
        #expect(s.current.failureIdentifiers == ["HKQuantityTypeIdentifierHeartRate"])  // sanitised
    }

    @Test func failAttemptIsAttemptFailed() {
        let (s, _) = store()
        s.beginAttempt()
        s.failAttempt()
        #expect(s.current.outcome == .attemptFailed)
    }

    @Test func aCompletedZeroEventRunWritesZeroRatherThanCarryingTheOldTotal() {
        let (s, _) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 100), failures: [])
        s.beginAttempt()
        s.finish(summary: IngestSummary(), failures: ["HKQuantityTypeIdentifierHeartRate: denied"])
        #expect(s.current.outcome == .completedWithIssues)
        #expect(s.current.eventsImported == 0)   // NOT 100 — the copy branches on this
    }

    @Test func aPriorSuccessfulSummarySurvivesAnInterruptedReimport() {
        let (s, d) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 100), failures: [])
        s.beginAttempt()                                   // re-import starts…
        let afterRelaunch = HealthImportStatusStore(defaults: d)
        afterRelaunch.normalizeAtLaunch()                  // …and is killed
        #expect(afterRelaunch.current.outcome == .interrupted)
        #expect(afterRelaunch.current.eventsImported == 100)      // NOT blanked
        #expect(afterRelaunch.current.lastCompletedAt != nil)
    }

    @Test func everyTerminalPathLeavesInProgress() {
        for makeTerminal in [
            { (s: HealthImportStatusStore) in s.finish(summary: IngestSummary(inserted: 1), failures: []) },
            { (s: HealthImportStatusStore) in s.finish(summary: IngestSummary(), failures: []) },
            { (s: HealthImportStatusStore) in s.finish(summary: IngestSummary(), failures: ["x: y"]) },
            { (s: HealthImportStatusStore) in s.failAttempt() },
        ] {
            let (s, _) = store()
            s.beginAttempt()
            makeTerminal(s)
            #expect(s.current.outcome != .inProgress)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/HealthImportStatusTests" -parallel-testing-enabled NO 2>&1 | tail -8`
Expected: FAIL — `cannot find 'HealthImportStatusStore' in scope`.

- [ ] **Step 3: Implement**

Create `Models/HealthImportStatus.swift`:

```swift
import Foundation
import HealthGraphCore

/// Full state machine, not three terminal results. `notStarted`/`completed*`
/// alone cannot express an authorization failure, an import that began and was
/// killed, or one attempted but never finished.
enum HealthImportOutcome: String, Codable, Equatable {
    case notStarted
    case inProgress
    case interrupted
    case attemptFailed
    case completedNoData
    case completed
    case completedWithIssues
}

/// Summary fields persist INDEPENDENTLY of `outcome` so an interruption during a
/// re-import doesn't blank what a prior successful import established.
struct HealthImportStatus: Codable, Equatable {
    var outcome: HealthImportOutcome = .notStarted
    var lastAttemptAt: Date?
    var lastCompletedAt: Date?
    var eventsImported: Int = 0
    var categoriesImported: Int = 0
    /// Type identifiers only — never sample payloads.
    var failureIdentifiers: [String] = []
}

@MainActor
final class HealthImportStatusStore: ObservableObject {
    private static let key = "hg.hk.importStatus"
    private let defaults: UserDefaults
    @Published private(set) var current: HealthImportStatus

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(HealthImportStatus.self, from: data) {
            self.current = decoded
        } else {
            self.current = HealthImportStatus()
        }
    }

    /// Call at launch BEFORE any surface renders. A persisted `inProgress` has
    /// no live task after process death, so rendering it verbatim shows a
    /// spinner that never resolves.
    func normalizeAtLaunch() {
        guard current.outcome == .inProgress else { return }
        var next = current
        next.outcome = .interrupted
        persist(next)
    }

    /// Persisted BEFORE authorization or backfill begins — that is what makes a
    /// kill detectable at all.
    func beginAttempt() {
        var next = current
        next.outcome = .inProgress
        next.lastAttemptAt = Date()
        persist(next)
    }

    func failAttempt() {
        var next = current
        next.outcome = .attemptFailed
        persist(next)
    }

    /// `backfill()` only throws when requestAuthorization throws; every per-type
    /// failure is swallowed into `lastBackfillFailures`. Both signals must be
    /// read, or a run where every type failed reports success.
    func finish(summary: IngestSummary, failures: [String]) {
        var next = current
        // inserted + updated: a repair re-import matches existing dedupKeys and
        // reports `updated`, so an inserted-only count says "0 events" on a run
        // that in fact fixed thousands of rows.
        let imported = summary.inserted + summary.updated
        // ALWAYS write the real count, including zero. Carrying a previous
        // nonzero total forward would let a genuinely empty run be presented as
        // though it imported events — and `backfillMessage` branches on
        // `eventsImported > 0`, so a zero-event run WITH failures would read
        // "your history was imported, but…" instead of "couldn't be fully
        // imported". A killed import keeps its old summary for free, because
        // `finish()` is not called on that path at all.
        next.eventsImported = imported
        next.lastCompletedAt = Date()
        next.failureIdentifiers = failures.map { String($0.prefix(while: { $0 != ":" })) }
        if !failures.isEmpty { next.outcome = .completedWithIssues }
        else if imported == 0 { next.outcome = .completedNoData }
        else { next.outcome = .completed }
        persist(next)
    }

    func recordCategories(_ count: Int) {
        var next = current
        next.categoriesImported = count
        persist(next)
    }

    private func persist(_ status: HealthImportStatus) {
        current = status
        if let data = try? JSONEncoder().encode(status) { defaults.set(data, forKey: Self.key) }
    }
}
```

- [ ] **Step 4: Run tests and commit**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/HealthImportStatusTests" -parallel-testing-enabled NO 2>&1 | grep -E "✔|✘|Test run"`
Expected: 10 tests pass.

```bash
git add Models/HealthImportStatus.swift "Food IntolerancesTests/HealthImportStatusTests.swift"
git commit -m "feat(first-run): persisted Apple Health import status with interrupted recovery"
```

---

## Task 11: Root switch and launch ordering

**Files:**
- Modify: `FoodIntolerancesApp.swift:1-2` (add import), `:32` (remove notification prompt), `:105-158` (root switch)
- Modify: `Models/EnvironmentalDataService.swift:1064-1072` (stop `LocationService.init()` prompting)
- Create: `Models/LocationPermissionStore.swift`
- Create: `Views/HealthOS/FirstRun/FirstRunFlowView.swift` + five screen stubs (filled in Tasks 12–15)

**Interfaces:**
- Consumes: `FirstRunState` (Task 9), `HealthImportStatusStore` (Task 10).
- Produces: `FirstRunFlowView(onComplete:)`.

**Three traps this step must avoid:**

1. **A naked `if/else` at the root re-fires the app's `.task`s.** `startObserving()`, the initial emit, and both `onChange` handlers hang directly on `HealthOSRootView()`. An identity change on completion re-runs them. They belong *inside* the shell branch, which is also what spec Decision 2 requires — attach them to `HealthOSRootView`, never as common modifiers on the switch.
2. **`.modelContainer` is applied last, after the ten `environmentObject`s.** A first-run view presented from *above* the injections crashes at runtime on first `@EnvironmentObject` access — it is not a compile error. The switch must sit inside the modifier chain.
3. **Mounting the shell during onboarding does real work.** All four tabs mount simultaneously by design, so `HomeView`'s AQI evaluation and `InsightsView`'s refresh would run against an empty graph while the user is still on the promise screen.

- [ ] **Step 1: Remove the cold notification prompt**

In `FoodIntolerancesApp.swift`, delete line 32:

```swift
        NotificationManager.shared.requestNotificationPermission()
```

`Views/HealthOS/` and `HealthGraphCore/` schedule zero notifications — this asks for a permission the app never uses, on top of whatever the first screen is.

- [ ] **Step 2: Stop `LocationService` prompting at launch**

Removing the notification prompt is not enough — **location is also requested from
`init()`**, which would make Task 15's explaining screen pointless: the system dialog would
appear over the promise screen, and by the time the user reached the location step the
status would already be `.authorized` or `.denied`.

`FoodIntolerancesApp.swift:45` eagerly constructs `LocationService()`, and
`LocationService.init()` (`Models/EnvironmentalDataService.swift:1064-1072`) calls
`requestWhenInUseAuthorization()` in its `.notDetermined` branch behind
`if !UserDefaults.standard.bool(forKey: "hasShownLocationAlert")`. That guard is
**permanently true** — `hasShownLocationAlert` has two readers
(`EnvironmentalDataService.swift:1064`, `LogItemViewModel.swift:1345`) and **no writer
anywhere in the repo**.

Delete **only** the `locationManager.requestWhenInUseAuthorization()` line from that
`.notDetermined` branch, leaving the branch, its `hasLoggedPermissionRequest` bookkeeping,
and the `.authorizedWhenInUse`/`default` branches exactly as they are:

```swift
                case .notDetermined:
                    if !hasLoggedPermissionRequest {
                        hasLoggedPermissionRequest = true
                    }
                    // Asking moved to FirstRunLocationView via
                    // LocationPermissionStore (Step 3). From here, the system
                    // dialog landed on whatever happened to be on screen at
                    // cold launch, with no explanation.
```

Do **not** add a `requestAuthorization()` method to `LocationService`. It is a private
`CLLocationManagerDelegate` owned by `EnvironmentalDataService`
(`EnvironmentalDataService.swift:93,159`) — not `ObservableObject`, never injected, and
unreachable from a first-run view. Step 3 introduces the single observable owner instead.

- [ ] **Step 3: Add the state objects**

`FoodIntolerancesApp.swift` imports only `SwiftUI` and `SwiftData` (lines 1-2), so add:

```swift
import HealthGraphCore
```

Create `Models/LocationPermissionStore.swift` — the single observable owner of location
authorization. `FirstRunLocationView` must not own a bare `CLLocationManager`: reading
`authorizationStatus` straight after `requestWhenInUseAuthorization()` still returns
`.notDetermined` (the dialog is asynchronous), so the screen would sit stale after the user
answers.

```swift
import Foundation
import CoreLocation

/// The ONLY thing that asks for location authorization, and the only observable
/// source of its current value. Status arrives via the delegate callback, not
/// by re-reading the manager after `request()` — that read races the dialog and
/// almost always still says `.notDetermined`.
@MainActor
final class LocationPermissionStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func request() {
        guard status == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let latest = manager.authorizationStatus
        Task { @MainActor in self.status = latest }
    }
}
```

Then, alongside the existing `@StateObject` declarations:

```swift
    @StateObject private var firstRunState = FirstRunState(
        store: GRDBEventStore(database: HealthGraphProvider.shared))
    @StateObject private var importStatus: HealthImportStatusStore
    @StateObject private var locationPermission = LocationPermissionStore()
```

`importStatus` has **no default** on purpose. Normalization must be applied to the *live*
instance, so it is constructed and normalized inside `init()` and then assigned — see below.

Both types are `@MainActor`, and these are property-default expressions on the `@main` App struct — that is the same shape the existing `@StateObject`s use, so it resolves on the main actor. If the compiler complains about isolation here, move construction into `init()` rather than dropping `@MainActor` from the types: `FirstRunState` mutates published state that views read directly.

Touching `HealthGraphProvider.shared` here opens the SQLite file and runs migrations synchronously (and `fatalError`s on failure, by design). That cost is paid at launch either way — the resolver needs the graph-existence answer before the first frame.

At the end of `init()`, after the existing setup:

```swift
        // Normalize the LIVE store, then hand that exact instance to the
        // @StateObject. Constructing a throwaway store, normalizing it, and
        // letting the @StateObject build its own would write .interrupted to
        // UserDefaults while the instance the UI actually observes still holds
        // the stale .inProgress it loaded — so the Backfill screen would render
        // (or auto-run) instead of showing the recovery branch.
        let status = HealthImportStatusStore()
        status.normalizeAtLaunch()
        _importStatus = StateObject(wrappedValue: status)
```

Assigning `_importStatus` directly is the supported way to give a `@StateObject` a
runtime-constructed value; the wrapped value is created once and survives re-renders.

- [ ] **Step 4: Create the flow shell**

Create `Views/HealthOS/FirstRun/FirstRunFlowView.swift`:

```swift
import SwiftUI
import HealthGraphCore

/// Six-step value-first first run. Screens are added in Tasks 12-15; this file
/// owns only the step machine and the shared state they mutate.
struct FirstRunFlowView: View {
    enum Step: Int, CaseIterable { case promise, connect, backfill, seeding, location, done }

    let entry: FirstRunEntry
    let onComplete: ([String]) -> Void

    @State private var step: Step
    @State private var selectedSeeds: [String] = []

    /// A resumed flow whose import was killed lands straight on Backfill, so
    /// the user meets the recovery screen instead of being walked back through
    /// Promise and Connect and silently restarting a multi-minute import.
    init(entry: FirstRunEntry, importOutcome: HealthImportOutcome, onComplete: @escaping ([String]) -> Void) {
        self.entry = entry
        self.onComplete = onComplete
        let resumesIntoBackfill = entry == .resume
            && (importOutcome == .interrupted || importOutcome == .inProgress)
        _step = State(initialValue: resumesIntoBackfill ? .backfill : .promise)
    }

    @EnvironmentObject private var firstRunState: FirstRunState

    var body: some View {
        ZStack {
            HealthTheme.paper.ignoresSafeArea()
            content
        }
        // Marked at FLOW ENTRY, before any branch. Doing it inside Connect
        // instead would leave "Not now" running the rest of the flow — including
        // the location prompt, a real side effect — with startedVersion still 0,
        // so a kill there plus a populated graph hits the reconciliation row and
        // skips onboarding forever. Same defect class as the original blocker.
        .task { firstRunState.markStarted() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .promise:  FirstRunPromiseView { advance(to: .connect) }
        case .connect:  FirstRunConnectView(onSkip: { advance(to: .seeding) },
                                            onConnected: { advance(to: .backfill) })
        case .backfill: FirstRunBackfillView { advance(to: .seeding) }
        case .seeding:  FirstRunSeedingView(selection: $selectedSeeds) { advance(to: .location) }
        case .location: FirstRunLocationView(seeds: selectedSeeds) { advance(to: .done) }
        case .done:     Color.clear.onAppear { onComplete(selectedSeeds) }
        }
    }

    private func advance(to next: Step) {
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }
}
```

- [ ] **Step 5: Switch the root**

In `FoodIntolerancesApp.swift`, replace `HealthOSRootView()` at line 109 with a switch, keeping **every** existing modifier below it unchanged and moving the four launch modifiers onto the shell branch:

```swift
            Group {
                if let entry = firstRunState.flowEntry {
                    FirstRunFlowView(entry: entry, importOutcome: importStatus.current.outcome) { seeds in
                        firstRunState.markCompleted(seeds: seeds)
                    }
                } else {
                    HealthOSRootView()
                        // Launch side effects live HERE, on the shell branch only.
                        // As common modifiers on the Group they would run during
                        // onboarding — fetching weather and prompting for location
                        // before the user has been told why.
                        .task { healthKitIngestor.startObserving() }
                        .task { emitCoordinator.emit(forced: false) }
                        .onChange(of: scenePhase) { _, phase in
                            guard phase == .active else { return }
                            emitCoordinator.emit(forced: false)
                        }
                        .onChange(of: environmentalService.locationRecoveryTick) { _, _ in
                            let hasLiveLocationFailure = environmentStatusStore.statuses.values.contains {
                                $0.liveFailure?.reason == .locationDenied || $0.liveFailure?.reason == .locationUnavailable
                            }
                            guard hasLiveLocationFailure else { return }
                            emitCoordinator.emit(forced: true)
                        }
                }
            }
            .environmentObject(healthKitManager)
            .environmentObject(healthKitIngestor)
            .environmentObject(logItemViewModel)
            .environmentObject(tabManager)
            .environmentObject(captureCoordinator)
            .environmentObject(graphMutationCoordinator)
            .environmentObject(redFlagMuteStore)
            .environmentObject(redFlagPresenter)
            .environmentObject(environmentStatusStore)
            .environmentObject(environmentalService)
            .environmentObject(firstRunState)
            .environmentObject(importStatus)
            .environmentObject(locationPermission)
            .environment(\.emitCoordinator, emitCoordinator)
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
            .modelContainer(sharedModelContainer)
            .resetSwiftDataCache()
            .onAppear {
                Logger.debug("App started in DEBUG mode", category: .app)
                if enableDiagnostics {
                    Logger.debug("Diagnostics mode enabled", category: .app)
                }
            }
```

Delete the four launch modifiers from their old position at the end of the chain — they now live on the shell branch.

- [ ] **Step 6: Build and commit**

The flow screens don't exist yet, so this step will not compile on its own. Create all five
as stubs now and fill them in Tasks 12–15. **The signatures must match what
`FirstRunFlowView` passes** — a stub with the wrong shape breaks this step's own build gate:

```swift
// Views/HealthOS/FirstRun/FirstRunPromiseView.swift
import SwiftUI
struct FirstRunPromiseView: View {
    let onContinue: () -> Void
    var body: some View { Button("Continue", action: onContinue) }
}

// Views/HealthOS/FirstRun/FirstRunConnectView.swift
import SwiftUI
struct FirstRunConnectView: View {
    let onSkip: () -> Void
    let onConnected: () -> Void
    var body: some View { Button("Continue", action: onConnected) }
}

// Views/HealthOS/FirstRun/FirstRunBackfillView.swift
import SwiftUI
struct FirstRunBackfillView: View {
    let onContinue: () -> Void
    var body: some View { Button("Continue", action: onContinue) }
}

// Views/HealthOS/FirstRun/FirstRunSeedingView.swift
import SwiftUI
struct FirstRunSeedingView: View {
    @Binding var selection: [String]          // NOT `let` — the flow passes $selectedSeeds
    let onContinue: () -> Void
    var body: some View { Button("Continue", action: onContinue) }
}

// Views/HealthOS/FirstRun/FirstRunLocationView.swift
import SwiftUI
struct FirstRunLocationView: View {
    let seeds: [String]
    let onContinue: () -> Void
    var body: some View { Button("Continue", action: onContinue) }
}
```

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add FoodIntolerancesApp.swift Models/EnvironmentalDataService.swift \
        Models/LocationPermissionStore.swift Views/HealthOS/FirstRun/
git commit -m "feat(first-run): structural root switch with launch side effects on the shell branch"
```

---

## Task 12: Promise and Connect screens

**Files:**
- Modify: `Views/HealthOS/FirstRun/FirstRunPromiseView.swift`, `Views/HealthOS/FirstRun/FirstRunConnectView.swift`

**The promise copy supersedes the approved UI spec** (`2026-07-04-ui-design.md` §5) on both counts, and the spec records why: "your data never leaves this device" is false (coordinates go to OpenWeather; `CloudAIService` is a BYOK client for OpenAI/Anthropic), and "find what actually helps you" implies causation the engine does not establish.

- [ ] **Step 1: Write the promise screen**

Replace `Views/HealthOS/FirstRun/FirstRunPromiseView.swift`:

```swift
import SwiftUI

struct FirstRunPromiseView: View {
    let onContinue: () -> Void

    /// Testable — pins the two claims the spec supersedes from UI design §5.
    static let headline = "Notice patterns in what may help — or make symptoms worse."
    static let privacy = """
        Your Health Graph is stored on this device. Environment features share your \
        location with the weather provider only when enabled. Cloud AI is optional \
        and off by default.
        """

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(Self.headline)
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
            Text(Self.privacy)
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            Spacer()
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: Write the connect screen with exhaustive branching**

Replace `Views/HealthOS/FirstRun/FirstRunConnectView.swift`:

```swift
import SwiftUI

struct FirstRunConnectView: View {
    let onSkip: () -> Void
    let onConnected: () -> Void

    @EnvironmentObject private var ingestor: HealthKitIngestor
    @EnvironmentObject private var importStatus: HealthImportStatusStore
    @State private var authorizationFailed = false
    @State private var isRequesting = false

    private let imported = ["sleep", "workouts", "heart rate", "HRV", "cycle", "weight"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bring in the history you already have.")
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(imported, id: \.self) { item in
                    Text("· \(item)")
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.inkSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hgCard()

            if authorizationFailed {
                Text("Couldn't reach Apple Health. You can try again, or continue and connect later.")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
            }
            Spacer()
            Button(authorizationFailed ? "Retry" : "Connect Apple Health") { Task { await connect() } }
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isRequesting)
            Button("Not now", action: onSkip)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
    }

    private func connect() async {
        isRequesting = true
        defer { isRequesting = false }
        // startedVersion is NOT written here — FirstRunFlowView marks the flow
        // started at entry, so every branch (including "Not now") is covered.
        // MUST NOT clobber a persisted .interrupted: beginAttempt() overwrites
        // the outcome unconditionally, and the Backfill screen's recovery branch
        // reads it AFTER this runs. Without this guard that branch is dead code
        // on every onboarding path and a killed import silently restarts.
        if importStatus.current.outcome != .interrupted { importStatus.beginAttempt() }
        do {
            try await ingestor.requestAuthorization()
            authorizationFailed = false
            onConnected()
        } catch {   // see the beginAttempt() guard above
            // Stay on Connect. Denied READS are not an error — Apple reports
            // them as "not determined" — so only a genuine throw lands here.
            importStatus.failAttempt()
            authorizationFailed = true
        }
    }
}
```

- [ ] **Step 3: Build and commit**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Views/HealthOS/FirstRun/FirstRunPromiseView.swift Views/HealthOS/FirstRun/FirstRunConnectView.swift
git commit -m "feat(first-run): promise + connect screens with honest privacy copy"
```

---

## Task 13: Backfill screen — all terminal and recovery states

**Files:**
- Modify: `Views/HealthOS/FirstRun/FirstRunBackfillView.swift`
- Create: `Views/HealthOS/Health/DataSourcesPresentation.swift`
- Test: `Food IntolerancesTests/DataSourcesPresentationTests.swift`

**Interfaces:**
- Produces: `DataSourcesPresentation.backfillMessage(for:) -> String`, `.statusLabel(for:) -> String`, `.summaryLine(from:) -> String?`.

**Snapshot the ingestor's state, don't read it after the await.** `lastBackfillFailures` is reset at the start of each run and `progress` is nil'd in a `defer`, so reading them after `backfill()` returns gives the wrong answer.

**The "sleep back to …" date comes from the earliest HealthKit-sourced sleep event** (Task 7), never inferred from the requested one-year window — export.zip reaches further back and a partial grant yields less.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/DataSourcesPresentationTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct DataSourcesPresentationTests {
    private func status(_ outcome: HealthImportOutcome, events: Int = 0,
                        failures: [String] = []) -> HealthImportStatus {
        HealthImportStatus(outcome: outcome, lastAttemptAt: Date(), lastCompletedAt: Date(),
                           eventsImported: events, categoriesImported: 3,
                           failureIdentifiers: failures)
    }

    @Test func zeroEventsAndNoFailuresSaysNothingCameThrough() {
        let msg = DataSourcesPresentation.backfillMessage(for: status(.completedNoData))
        #expect(msg == "Nothing came through yet.")
    }

    @Test func eventsPlusFailuresSaysPartiallyImported() {
        let msg = DataSourcesPresentation.backfillMessage(
            for: status(.completedWithIssues, events: 500, failures: ["HKQuantityTypeIdentifierHeartRate"]))
        #expect(msg == "Your history was imported, but some data couldn't be read.")
    }

    @Test func zeroEventsPlusFailuresSaysCouldNotBeFullyImported() {
        let msg = DataSourcesPresentation.backfillMessage(
            for: status(.completedWithIssues, events: 0, failures: ["HKQuantityTypeIdentifierHeartRate"]))
        #expect(msg == "Apple Health couldn't be fully imported.")
    }

    @Test func interruptedGetsItsOwnRecoveryCopy() {
        let msg = DataSourcesPresentation.backfillMessage(for: status(.interrupted, events: 100))
        #expect(msg == "The previous import was interrupted.")
    }

    @Test func statusVocabularyNeverSaysConnectedOrDenied() {
        // Apple deliberately obscures read denial, so a definitive
        // Connected/Denied label would be a claim we cannot support.
        let all: [HealthImportOutcome] = [.notStarted, .inProgress, .interrupted, .attemptFailed,
                                          .completedNoData, .completed, .completedWithIssues]
        for outcome in all {
            let label = DataSourcesPresentation.statusLabel(for: status(outcome))
            #expect(!label.localizedCaseInsensitiveContains("connected"))
            #expect(!label.localizedCaseInsensitiveContains("denied"))
        }
    }

    @Test func summaryLineNamesTheEarliestImportedEventNotTheRequestedWindow() throws {
        // 1_700_000_000 == 2023-11-14 UTC. Deliberately older than one year, so
        // a line derived from the requested 1-year backfill window would fail.
        let earliest = Date(timeIntervalSince1970: 1_700_000_000)
        let summaries = [ImportedCategorySummary(category: "sleep", count: 400, earliest: earliest),
                         ImportedCategorySummary(category: "symptom", count: 12,
                                                 earliest: Date(timeIntervalSince1970: 1_750_000_000))]
        let line = try #require(DataSourcesPresentation.summaryLine(from: summaries))
        #expect(line.contains("412"))              // total across categories
        #expect(line.contains("2 categories"))
        #expect(line.contains("2023"))             // the EARLIEST of the two, not the latest
        #expect(!line.contains("2025"))
    }

    @Test func summaryLineIsNilForAnEmptyImport() {
        #expect(DataSourcesPresentation.summaryLine(from: []) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/DataSourcesPresentationTests" -parallel-testing-enabled NO 2>&1 | tail -8`
Expected: FAIL — `cannot find 'DataSourcesPresentation' in scope`.

- [ ] **Step 3: Implement the presentation namespace**

Create `Views/HealthOS/Health/DataSourcesPresentation.swift`:

```swift
import Foundation
import HealthGraphCore

/// Pure copy + formatting for the import surfaces, so the state machine's
/// wording is unit-testable without rendering a view.
enum DataSourcesPresentation {
    /// Vocabulary deliberately avoids Connected/Denied: Apple reports denied
    /// READS as "not determined", so the app cannot know and must not claim.
    static func statusLabel(for status: HealthImportStatus) -> String {
        switch status.outcome {
        case .notStarted:          return "Not imported"
        case .inProgress:          return "Importing…"
        case .interrupted:         return "Import interrupted"
        case .attemptFailed:       return "Import attempted"
        case .completedNoData:     return "Imported — nothing came through"
        case .completed:           return "Last imported"
        case .completedWithIssues: return "Imported with issues"
        }
    }

    static func backfillMessage(for status: HealthImportStatus) -> String {
        switch status.outcome {
        case .interrupted:
            return "The previous import was interrupted."
        case .attemptFailed:
            return "Apple Health couldn't be reached."
        case .completedNoData:
            return "Nothing came through yet."
        case .completedWithIssues:
            return status.eventsImported > 0
                ? "Your history was imported, but some data couldn't be read."
                : "Apple Health couldn't be fully imported."
        case .completed:
            return "You're not starting from zero."
        case .notStarted, .inProgress:
            return "Importing your history…"
        }
    }

    /// Derived from the HealthKit-scoped summary, never from the requested
    /// one-year window: export.zip reaches further back, a partial grant less.
    /// The earliest date is the whole point of Task 7 computing `earliest` —
    /// "back to March 2025" is what makes the number feel like the user's own
    /// history rather than a counter.
    static func summaryLine(from summaries: [ImportedCategorySummary]) -> String? {
        guard !summaries.isEmpty else { return nil }
        let total = summaries.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        let categories = summaries.count
        var line = "\(total.formatted()) events across \(categories) categor\(categories == 1 ? "y" : "ies")"
        if let earliest = summaries.map(\.earliest).min() {
            line += ", back to \(earliest.formatted(.dateTime.month(.wide).year()))"
        }
        return line
    }
}
```

- [ ] **Step 4: Implement the backfill screen**

Replace `Views/HealthOS/FirstRun/FirstRunBackfillView.swift`:

```swift
import SwiftUI
import HealthGraphCore

struct FirstRunBackfillView: View {
    let onContinue: () -> Void

    @EnvironmentObject private var ingestor: HealthKitIngestor
    @EnvironmentObject private var importStatus: HealthImportStatusStore
    @State private var isRunning = false
    @State private var summaries: [ImportedCategorySummary] = []
    @State private var hasRun = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(DataSourcesPresentation.backfillMessage(for: importStatus.current))
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)

            if isRunning, let p = ingestor.progress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(p.completedSteps), total: Double(max(p.totalSteps, 1)))
                        .tint(HealthTheme.accent)
                    Text("\(p.eventsIngested.formatted()) events so far")
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.inkSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hgCard()
            } else if let line = DataSourcesPresentation.summaryLine(from: summaries) {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hgCard()
            }

            Spacer()
            if hasRun && !isRunning {
                Button("Retry") { Task { await runBackfill() } }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isRunning)
        }
        .padding(.horizontal, 16)
        .task {
            // An interrupted import resumes here as a recovery screen rather
            // than silently restarting a multi-minute job.
            guard !hasRun, importStatus.current.outcome != .interrupted else { hasRun = true; return }
            await runBackfill()
        }
    }

    private func runBackfill() async {
        isRunning = true
        hasRun = true
        importStatus.beginAttempt()
        defer { isRunning = false }
        do {
            let summary = try await ingestor.backfill()
            // SNAPSHOT: lastBackfillFailures resets at the start of each run and
            // progress is nil'd in a defer, so both must be read now.
            let failures = ingestor.lastBackfillFailures
            importStatus.finish(summary: summary, failures: failures)
            ingestor.startObserving()
            let store = GRDBEventStore(database: HealthGraphProvider.shared)
            summaries = (try? await store.importedSummary(source: .healthKit)) ?? []
            importStatus.recordCategories(summaries.count)
        } catch {
            importStatus.failAttempt()
        }
    }
}
```

- [ ] **Step 5: Run tests, build, commit**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/DataSourcesPresentationTests" -parallel-testing-enabled NO 2>&1 | grep -E "✔|✘|Test run"`
Expected: 7 tests pass.

```bash
git add Views/HealthOS/FirstRun/FirstRunBackfillView.swift \
        Views/HealthOS/Health/DataSourcesPresentation.swift \
        "Food IntolerancesTests/DataSourcesPresentationTests.swift"
git commit -m "feat(first-run): backfill screen covering all terminal and recovery states"
```

---

## Task 14: Seeding screen and chip wiring

**Files:**
- Modify: `Views/HealthOS/FirstRun/FirstRunSeedingView.swift`
- Create: `Views/HealthOS/FirstRun/SeedSymptomGrid.swift`
- Modify: `Views/HealthOS/Capture/SymptomCaptureView.swift:27-31`
- Test: `Food IntolerancesTests/SeedCatalogTests.swift`

**The grid is an explicit ordered list, not derived from the catalog.** `SymptomCatalog.all` is sorted alphabetically and deduped first-wins, so "the twenty things people actually track" cannot be computed from it.

**Every red-flag key is excluded** — the package catalog contains "Thoughts of self-harm or suicide", which must never appear on a first-run screen.

**Do not reuse `SymptomChip`, `SymptomCategorySection`, `CustomSymptomSheet`** — all three are already app-target-global names from the legacy `OnboardingSymptomsStep.swift`. And `QuickLogChip` has no selected state; adding one would mutate a component shared by all three capture views.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/SeedCatalogTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct SeedCatalogTests {
    /// Iterates the NAMES, not the mapped keys. Asserting over the keys would
    /// only re-check whatever `offered` was built from and could not fail.
    @Test func everyOfferedNameIsARealCatalogEntry() {
        let known = Set(HealthGraphCore.SymptomCatalog.all.map(\.canonicalKey))
        #expect(!SeedSymptomGrid.offeredNames.isEmpty)   // non-vacuous
        for name in SeedSymptomGrid.offeredNames {
            let key = HealthGraphCore.SymptomCatalog.canonicalKey(for: name)
            #expect(known.contains(key), "\(name) does not exist in SymptomCatalog")
        }
    }

    @Test func nothingIsDroppedBetweenNamesAndKeys() {
        #expect(SeedSymptomGrid.offered.count == SeedSymptomGrid.offeredNames.count)
    }

    @Test func noRedFlagKeyIsOffered() {
        let redFlags = Set(RedFlagCatalog.allSymptomKeys)
        #expect(!redFlags.isEmpty)
        for key in SeedSymptomGrid.offered {
            #expect(!redFlags.contains(key))
        }
    }

    @Test func offeredKeysAreUnique() {
        #expect(Set(SeedSymptomGrid.offered).count == SeedSymptomGrid.offered.count)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/SeedCatalogTests" -parallel-testing-enabled NO 2>&1 | tail -8`
Expected: FAIL — `cannot find 'SeedSymptomGrid' in scope`.

- [ ] **Step 3: Create the grid**

Create `Views/HealthOS/FirstRun/SeedSymptomGrid.swift`:

```swift
import SwiftUI
import HealthGraphCore

/// Multi-select grid for "what brings you here?".
///
/// Its own chip view on purpose: QuickLogChip has no selected state and is
/// shared by all three capture surfaces, and the legacy onboarding's
/// `SymptomChip` is already an app-target-global name.
struct SeedSymptomGrid: View {
    /// Curated and ORDERED — deliberately not derived from
    /// `SymptomCatalog.all`, which is alphabetical.
    ///
    /// These are CATALOG DISPLAY NAMES, verified to exist. The catalog was
    /// ported from a body-map app and is region-oriented, so the everyday word
    /// is often not the entry: it has "Loose Stool" not "Diarrhea",
    /// "Indigestion" not "Heartburn", "Cognitive Fog" not "Brain Fog".
    /// `canonicalKey(for:)` is TOTAL — it derives a key for any string — so a
    /// wrong name here produces a plausible key that silently matches nothing.
    /// The test below guards against exactly that, which is why it iterates
    /// THESE NAMES and not the mapped keys.
    static let offeredNames: [String] = [
        "Headache", "Migraine", "Bloating", "Upper Abdominal Cramps", "Nausea",
        "Loose Stool", "Hard Stool", "Indigestion", "Fatigue", "Cognitive Fog",
        "Joint Pain", "Muscle Soreness", "Skin Rash", "Congestion",
        "Anxiety", "Dizziness",
    ]

    /// No filtering here. A filter would silently swallow a bad name and leave
    /// the guard test asserting a predicate the array was already filtered on —
    /// a tautology that cannot fail. Red-flag exclusion is asserted separately.
    static let offered: [String] = offeredNames.map {
        HealthGraphCore.SymptomCatalog.canonicalKey(for: $0)
    }

    @Binding var selection: [String]

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Self.offered, id: \.self) { key in
                let isSelected = selection.contains(key)
                Button {
                    if let i = selection.firstIndex(of: key) { selection.remove(at: i) }
                    else if selection.count < 8 { selection.append(key) }
                } label: {
                    Text(HealthGraphCore.SymptomCatalog.displayName(for: key))
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? HealthTheme.onAccent : HealthTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(isSelected ? HealthTheme.accent : HealthTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HealthTheme.cardBorder))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(HealthGraphCore.SymptomCatalog.displayName(for: key))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
```

- [ ] **Step 4: Implement the seeding screen**

Replace `Views/HealthOS/FirstRun/FirstRunSeedingView.swift`:

```swift
import SwiftUI

struct FirstRunSeedingView: View {
    @Binding var selection: [String]
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What brings you here?")
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
            Text("Pick up to eight. They become your one-tap log buttons — nothing is recorded yet.")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            ScrollView { SeedSymptomGrid(selection: $selection) }
            Button(selection.isEmpty ? "Skip" : "Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
    }
}
```

- [ ] **Step 5: Wire seeds into symptom chips**

`@StateObject` property defaults cannot read `@EnvironmentObject` (`SymptomCaptureView.swift:50` is such a default), so seeds are passed **as a parameter at call time**, not stored as mutable state on the model. A mutable `model.seeds` property would work only if every caller remembered to set it before `loadChips()` — a parameter makes that ordering unrepresentable.

In `Views/HealthOS/Capture/SymptomCaptureView.swift`, change `loadChips()` (line 27) to take seeds:

```swift
    func loadChips(seeds: [String] = []) async {
        guard let recent = try? await store.eventsPage(before: nil, limit: 300, categories: [.symptom], sources: [.manual]) else { return }
        chipKeys = ChipRanker.rank(history: recent, category: .symptom, now: now(),
                                   timeZone: .current, limit: 8, seeds: seeds)
    }
```

Add the environment object to `SymptomCaptureView`:

```swift
    @EnvironmentObject private var firstRunState: FirstRunState
```

And change the `.task` at line 66:

```swift
        .task { await model.loadChips(seeds: firstRunState.seeds) }   // re-validated on read
```

Only the symptom site takes seeds — food and dose seeding is out of scope.

> `CaptureSheet` presents `SymptomCaptureView` from inside `HealthOSRootView`, which is below the `environmentObject` injections in `FoodIntolerancesApp` — so `firstRunState` resolves. Verify this at build time: a missing `@EnvironmentObject` is a **runtime crash on first access**, not a compile error. `SymptomCaptureView`'s `#Preview`, if it has one, must also inject a `FirstRunState`.

- [ ] **Step 6: Run tests, build, commit**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/SeedCatalogTests" -parallel-testing-enabled NO 2>&1 | grep -E "✔|✘|Test run"`
Expected: 4 tests pass.

```bash
git add Views/HealthOS/FirstRun/FirstRunSeedingView.swift \
        Views/HealthOS/FirstRun/SeedSymptomGrid.swift \
        Views/HealthOS/Capture/SymptomCaptureView.swift \
        "Food IntolerancesTests/SeedCatalogTests.swift"
git commit -m "feat(first-run): symptom seeding screen priming quick-log chips"
```

---

## Task 15: Location screen

**Files:**
- Modify: `Views/HealthOS/FirstRun/FirstRunLocationView.swift`

**State-aware, never blocking.** Request only for `.notDetermined`; offer **Open Settings** for denied/restricted; allow Continue when already authorized. Completion never waits on a first coordinate.

**Copy says "watch", never "find"** — every weather exposure is `.contested` in `PlausibilityCatalog`.

- [ ] **Step 1: Implement**

Replace `Views/HealthOS/FirstRun/FirstRunLocationView.swift`:

```swift
import SwiftUI
import CoreLocation
import HealthGraphCore

struct FirstRunLocationView: View {
    /// Passed in from the flow's in-memory selection. Reading
    /// `firstRunState.seeds` here would ALWAYS be empty: that key is written by
    /// `markCompleted(seeds:)`, which runs after this screen.
    let seeds: [String]
    let onContinue: () -> Void

    /// The one observable owner (Task 11 Step 3). A view-local CLLocationManager
    /// would have no delegate, so the screen could never learn the user's answer.
    @EnvironmentObject private var permission: LocationPermissionStore
    private var status: CLAuthorizationStatus { permission.status }

    /// "watch", never "find": every weather exposure is `.contested` in
    /// PlausibilityCatalog, so promising discovery would oversell it.
    /// Testable — pins the "you picked X and Y" phrasing spec §3.5 requires.
    static func explanation(for seeds: [String]) -> String {
        let picked = SymptomSeeds.validate(seeds, limit: 8).prefix(2)
            .map { HealthGraphCore.SymptomCatalog.displayName(for: $0) }
        guard !picked.isEmpty else {
            return "If you share location, we'll watch pressure drops, temperature swings and air quality against your symptoms."
        }
        return "You picked \(picked.joined(separator: " and ")). If you share location, we'll also watch pressure drops, temperature swings and air quality against them."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your environment")
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
            Text(Self.explanation(for: seeds))
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            Spacer()
            switch status {
            case .notDetermined:
                Button("Share location") {
                    // The ONLY request site in the app, now that Task 11 Step 2
                    // removed it from LocationService.init(). The answer arrives
                    // via the store's delegate callback — do NOT re-read the
                    // status here, that races the dialog.
                    permission.request()
                }
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
            case .denied, .restricted:
                Text("Location is turned off for this app.")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            default:
                EmptyView()
            }
            // Never gated on a first coordinate arriving.
            Button(status == .notDetermined ? "Not now" : "Continue", action: onContinue)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
    }
}
```

- [ ] **Step 2: Build and commit**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Views/HealthOS/FirstRun/FirstRunLocationView.swift
git commit -m "feat(first-run): state-aware location screen that never blocks completion"
```

---

## Task 16: Data sources screen

**Files:**
- Create: `Views/HealthOS/Health/DataSourcesView.swift`
- Modify: `Views/HealthOS/Health/HealthTabView.swift`

**The import action must call `startObserving()` after backfill.** The root `.task` has already run and will not retry until relaunch, so a user who skips onboarding and imports later gets no live ingestion for the rest of the session.

**Two separate DEBUG resets.** *Reset first run* clears `startedVersion` + `completedVersion` + `symptomSeeds` and sets `forceShow`; without `forceShow`, reconciliation immediately re-marks a populated graph complete and the flow never appears. *Reset HealthKit backfill* is its own labelled action because clearing `backfillCompleted` invites a year-long re-backfill and silently disables observers.

- [ ] **Step 1: Create the screen**

Create `Views/HealthOS/Health/DataSourcesView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers   // UTType.zip / .xml for the fileImporter
import UIKit                    // UIApplication.isIdleTimerDisabled
import HealthGraphCore

/// One view, two presentations: a NavigationLink destination in the Health tab
/// and a sheet from the Timeline empty state, so "connect Apple Health" finally
/// points at something real without cross-tab routing machinery.
struct DataSourcesView: View {
    @EnvironmentObject private var ingestor: HealthKitIngestor
    @EnvironmentObject private var importStatus: HealthImportStatusStore
    @State private var isImporting = false
    @State private var summaries: [ImportedCategorySummary] = []
    @State private var showingImporter = false
    @State private var exportProgress: Int?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Data sources")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Health")
                            .font(.subheadline)
                            .foregroundStyle(HealthTheme.ink)
                        Text(DataSourcesPresentation.statusLabel(for: importStatus.current))
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.inkSecondary)
                        if let line = DataSourcesPresentation.summaryLine(from: summaries) {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                        }
                        if !importStatus.current.failureIdentifiers.isEmpty {
                            Text("Couldn't read: \(importStatus.current.failureIdentifiers.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(HealthTheme.inkMuted)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    Divider().padding(.leading, 16)

                    Button(isImporting ? "Importing…" : "Import from Apple Health") {
                        Task { await runImport() }
                    }
                    .disabled(isImporting)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .hgCard()

                // export.zip / export.xml — spec §5. The long-running warning is
                // shown DURING the import, mirroring the debug screen's copy.
                VStack(alignment: .leading, spacing: 0) {
                    Button("Import Apple Health export.zip…") { showingImporter = true }
                        .disabled(isImporting || exportProgress != nil)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(16)
                        .contentShape(Rectangle())
                    if let exportProgress {
                        Divider().padding(.leading, 16)
                        Text("Importing… \(exportProgress.formatted()) records read. Large exports take many minutes — keep the app open.")
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.inkSecondary)
                            .padding(16)
                    }
                    if let errorMessage {
                        Divider().padding(.leading, 16)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.inkMuted)
                            .padding(16)
                    }
                }
                .hgCard()

                // Location & environment (spec §5). Links to the shipped status
                // screen rather than re-rendering EnvironmentStatusStore here —
                // same destination the Health tab already uses.
                NavigationLink {
                    EnvironmentStatusView()
                } label: {
                    HStack {
                        Image(systemName: "cloud.sun").foregroundStyle(HealthTheme.accent)
                        Text("Location & environment").foregroundStyle(HealthTheme.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(HealthTheme.inkMuted)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .hgCard()
                .accessibilityHint("Review which environment data is being collected")

                #if DEBUG
                VStack(alignment: .leading, spacing: 0) {
                    Button("Reset first run (DEBUG)") { resetFirstRun() }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(16)
                    Divider().padding(.leading, 16)
                    Button("Reset HealthKit backfill (DEBUG)", role: .destructive) { resetBackfill() }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(16)
                }
                .hgCard()
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
        .task { await loadSummary() }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.zip, .xml],
                      allowsMultipleSelection: false) { result in
            Task { await importExport(result) }
        }
    }

    private func loadSummary() async {
        let store = GRDBEventStore(database: HealthGraphProvider.shared)
        summaries = (try? await store.importedSummary(source: .healthKit)) ?? []
    }

    private func runImport() async {
        isImporting = true
        importStatus.beginAttempt()
        defer { isImporting = false }
        do {
            let summary = try await ingestor.backfill()
            let failures = ingestor.lastBackfillFailures     // snapshot before defer clears state
            importStatus.finish(summary: summary, failures: failures)
            // REQUIRED: the root .task already ran this session and will not
            // retry, so without this a later import yields no live ingestion.
            ingestor.startObserving()
            await loadSummary()
            importStatus.recordCategories(summaries.count)
        } catch {
            importStatus.failAttempt()
        }
    }

    /// Ported from HealthGraphDebugView.importExport — same security-scoped copy,
    /// same detached parse, same idle-timer hold. The graph write is identical;
    /// only the surface is new.
    private func importExport(_ result: Result<[URL], Error>) async {
        errorMessage = nil
        exportProgress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            exportProgress = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
        do {
            guard let picked = try result.get().first else { return }
            guard picked.startAccessingSecurityScopedResource() else {
                errorMessage = "No permission to read the selected file"
                return
            }
            defer { picked.stopAccessingSecurityScopedResource() }
            let local = FileManager.default.temporaryDirectory
                .appendingPathComponent(picked.lastPathComponent)
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.copyItem(at: picked, to: local)
            let xmlURL = picked.pathExtension.lowercased() == "zip"
                ? try ExportArchive.extractExportXML(from: local)
                : local
            let db = HealthGraphProvider.shared
            _ = try await Task.detached(priority: .userInitiated) {
                try AppleHealthExportParser(database: db).parse(xmlAt: xmlURL) { count in
                    Task { @MainActor in exportProgress = count }
                }
            }.value
            await loadSummary()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    #if DEBUG
    /// forceShow is essential: without it, reconciliation re-marks a populated
    /// graph complete on the very next launch and the flow never appears.
    private func resetFirstRun() {
        let d = UserDefaults.standard
        d.removeObject(forKey: FirstRunKeys.startedVersion)
        d.removeObject(forKey: FirstRunKeys.completedVersion)
        d.removeObject(forKey: FirstRunKeys.symptomSeeds)
        d.set(true, forKey: FirstRunKeys.forceShow)
    }

    /// Separate and labelled: clearing this invites a year-long re-backfill and
    /// silently disables observers if the flow is then abandoned.
    private func resetBackfill() {
        UserDefaults.standard.removeObject(forKey: HealthKitIngestor.backfillCompletedKey)
    }
    #endif
}
```

- [ ] **Step 2: Add the Health tab entry**

In `Views/HealthOS/Health/HealthTabView.swift`, add a navigation row above the "Soon" card, following the existing row idiom exactly (note the 16pt divider inset for icon-less rows):

```swift
                NavigationLink {
                    DataSourcesView()
                } label: {
                    HStack {
                        Image(systemName: "heart.text.square").foregroundStyle(HealthTheme.accent)
                        Text("Data sources").foregroundStyle(HealthTheme.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(HealthTheme.inkMuted)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .accessibilityHint("Connect Apple Health and review what has been imported")
```

- [ ] **Step 3: Build and commit**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Views/HealthOS/Health/DataSourcesView.swift Views/HealthOS/Health/HealthTabView.swift
git commit -m "feat(health): Data sources screen with import, status and DEBUG resets"
```

---

## Task 17: Retire the three stale strings

**Files:**
- Modify: `Views/HealthOS/Home/HomeView.swift:146-156`, `Views/HealthOS/Insights/InsightsPlaceholderView.swift:18,36`, `Views/HealthOS/Timeline/TimelineView.swift:208-221`

**The three sites need three different fixes — do not unify them.** `whatsNext` is an unconditional roadmap blurb; `InsightsPlaceholderView` is a data-state empty screen; `TimelineView.emptyState` is a List row with branches.

**The existing strings are not ASCII.** `"The engine isn't watching yet — but your data is ready."` contains U+2019 and U+2014; `"What's next"` contains U+2019. Retyping them with ASCII `'` and `-` makes the exact-match edit silently fail.

**`InsightsPlaceholderView` is not a placeholder** despite the name — it is the live Insights empty state, rendered whenever `vm.feed.sections.isEmpty`, including the error path. Keep the coverage strip; replace only the two false claims.

- [ ] **Step 1: Delete the Home block**

In `Views/HealthOS/Home/HomeView.swift`, delete the entire `private var whatsNext: some View { … }` computed property (lines 146–156) and remove `whatsNext` from the body's VStack. Home already carries the backfill card, mood check-in, poor-air banner and passive strip; nothing replaces it.

- [ ] **Step 2: Rewrite the Insights empty-state copy**

In `Views/HealthOS/Insights/InsightsPlaceholderView.swift`, replace the two strings, leaving the per-family coverage strip untouched:

```swift
                    Text("Nothing conclusive yet — here's what your graph holds.")
```

and

```swift
                    Text("A pattern appears here once an exposure repeats enough times to test, and the result holds up when the data is split in half.")
```

- [ ] **Step 3: Branch the Timeline empty state**

In `Views/HealthOS/Timeline/TimelineView.swift`, replace `emptyState`. It reads the persisted `HealthImportStatus`, never `hg.hk.backfillCompleted` — that flag is set even after a total failure, so it means "we tried once", not "we have data":

```swift
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.isSearchActive ? "magnifyingglass" : "list.bullet.rectangle")
                .font(.system(size: 32))
                .foregroundStyle(HealthTheme.inkMuted)
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if showsConnectAction {
                Button("Connect Apple Health") { showingDataSources = true }
                    .frame(minHeight: 44)
            }
        }
    }

    private var showsConnectAction: Bool {
        !viewModel.isSearchActive
            && !hasActiveFilters
            && importStatus.current.outcome == .notStarted
    }

    private var hasActiveFilters: Bool {
        !viewModel.activeFamilies.isEmpty || !viewModel.activeSources.isEmpty
    }

    private var emptyStateMessage: String {
        if viewModel.isSearchActive { return "Nothing matches that search." }
        // Fourth state: data exists but the active filters match none of it.
        // The old copy wrongly told these users their timeline was empty.
        if hasActiveFilters { return "No events match these filters." }
        if importStatus.current.outcome == .notStarted {
            return "Your timeline is empty. Connect Apple Health to bring in the history you already have."
        }
        return "Nothing logged yet. Tap + to log your first thing."
    }
```

Add the supporting declarations to `TimelineView`:

```swift
    @EnvironmentObject private var importStatus: HealthImportStatusStore
    @State private var showingDataSources = false
```

and attach the sheet to the same view that already owns the List:

```swift
        .sheet(isPresented: $showingDataSources) { NavigationStack { DataSourcesView() } }
```

Keep the three List-row modifiers already on the empty-state row — `.listRowInsets(EdgeInsets())`, `.listRowSeparator(.hidden)`, `.listRowBackground(Color.clear)` — or it renders on a white system row with separators against the cream backdrop.

- [ ] **Step 4: Build, run the full suites, commit**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

Run: `swift test --package-path HealthGraphCore 2>&1 | tail -5`
Expected: all pass.

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 | grep -E "✔ Suite|✘|Test run with"`
Expected: every suite passes except the known `SwiftDataMigratorTests` teardown crash. The overall banner will read `** TEST FAILED **` — verify by suite name.

```bash
git add Views/HealthOS/Home/HomeView.swift \
        Views/HealthOS/Insights/InsightsPlaceholderView.swift \
        Views/HealthOS/Timeline/TimelineView.swift
git commit -m "fix(ui): retire copy claiming capture, insights and connect don't exist yet"
```

---

## Device gate

Per spec §Device gate. **The baseline must already have been captured at Task 1 Step 9.**

- [ ] Build final branch HEAD, install, **run a recompute**, then run the relationship dump, saving as `.superpowers/sdd/relationship-after.txt`. The recompute is mandatory and must come first — `confidence`/`evidence`/`contradictions` are stored columns, so dumping without it compares two stale snapshots and a real change reads as "no change".
- [ ] Diff against `relationship-baseline.txt` as text.
- [ ] Classify every difference:

| Observation | Verdict |
|---|---|
| A `highStress` relationship decays or vanishes, no new confounder | **Expected** — its exposures were mindfulness minutes and no longer exist (Task 2). |
| Any other relationship demotes, with `derived:cyclePhase.*` or `illness` in its new confounder list | **Expected** — Tasks 4 and 5 doing their job. |
| Any other disappearance, unexplained by either | **Regression.** Investigate before merge. |

- [ ] Fresh-install flow end to end: promise → connect → backfill → seeding → location → Home.
- [ ] Reset first run (DEBUG) reproduces the flow on the already-populated device.
- [ ] Kill the app during backfill; relaunch returns to the flow (not the shell) and shows the interrupted recovery copy.
- [ ] Skip Apple Health at onboarding, then import later from Health → Data sources; confirm live ingestion starts in the same session (log a HealthKit sample and watch it arrive without relaunching).
- [ ] Deny location; confirm Open Settings appears and Continue still works.
- [ ] **Run a full `backfill()` before checking cycle exposures.** Anchors mean live observation never re-delivers already-ingested flow samples, so the cycle-start marker only appears on rows a full backfill re-read. Expect `updated`, not `inserted`.

---

## Self-Review

**Spec coverage:** §1 root switch → Task 11. §2 state/reconciliation/resets → Tasks 9, 16. §3.1–3.6 six screens → Tasks 12–15. §4 seeds → Tasks 8, 14. §5 DataSourcesView + `HealthImportStatus` → Tasks 10, 16. §6 copy → Task 17. §7 stress → Task 2. §8 cycle → Tasks 3, 4. §9 illness → Task 5. §10 diagnostic → Task 1. Supporting APIs (`anyEventExistsSync`, scoped summary) → Tasks 6, 7. Device gate → final section.

**Known gaps deliberately carried, not silently dropped:**
- `FirstRunEntry.upgrade(from:)` resolves but has no distinct screen mapping, because `currentVersion` is 1 and there is no prior version to upgrade from. The resolver and its test pin the behavior so a v2 round has a correct foundation; the entry-to-screens map itself is that round's work.
- The Timeline `.sheet` and `TimelineView`'s exact body structure must be confirmed against the real file at implementation time — the anchor lines are current as of `8bd1965` but the surrounding List composition is not reproduced here in full.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-26-first-run-and-health-connect.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
