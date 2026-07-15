# Phase 2A — Evidence Engine (headless) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deterministic, headless Evidence Engine that mines the event graph into `relationships` (exposure→outcome edges with confidence), validated end-to-end by an extended synthetic-data harness. No UI.

**Architecture:** A pipeline of small pure stages inside a new `Evidence/` module in the `HealthGraphCore` package — extract exposures & outcomes → generate candidate pairs → windowed co-occurrence counting → confounder + confidence scoring → type/status classification → idempotent upsert into `relationships`. The engine persists only the relationship summary; per-exposure evidence detail for the (future) Insights drill-down is recomputed on demand by re-running the co-occurrence stage for a single pair. Full recompute each run (not incremental).

**Tech Stack:** Swift 5.9+, GRDB (SQLite), Swift Testing (`import Testing`, `@Test`, `#expect`). Package: `HealthGraphCore`.

## Global Constraints

- **Test framework:** Swift Testing only (`import Testing`, `@Test`, `#expect`, `@testable import HealthGraphCore`). Struct-based test types. In-memory DB via `try AppDatabase.inMemory()`. NOT XCTest.
- **Migrations are append-only and immutable.** Never edit migrations v1–v4. Schema change = a new numbered migration (`v5`). GRDB does not checksum bodies; editing a shipped migration silently drifts installs.
- **Engine is deterministic.** No `Date()`, `Date.now`, `Math.random`, or `UUID()` for logic inside `Evidence/` — `now` is always an injected parameter. (`UUID()` is allowed only when minting the `id` of a brand-new `Relationship` row, never for control flow.) Seeded randomness lives only in the synthetic harness.
- **Lag windows are absolute-time** (hours between timestamps), so they stay timezone-correct via each event's real `Date`. Day-bucketing for base-rate uses a **UTC calendar** in v1 for determinism (documented where used).
- **Observational confidence is clamped ≤ 0.75.** Exceeding it requires Phase 4 experiments.
- **The engine's only persistence side-effect is upserting `relationships`.** It reads through `EventStore`/`ObjectStore`; it never writes events or objects.
- **No user-facing copy in 2A** — it is headless. `RelationshipType` names are internal.
- All new source files live in `HealthGraphCore/Sources/HealthGraphCore/Evidence/` unless noted; all tests in `HealthGraphCore/Tests/HealthGraphCoreTests/`.
- Build/test command: `cd HealthGraphCore && swift test` (add `--filter <TypeName>` to scope).

---

## File Structure

**New (`Evidence/`):**
- `EvidenceConfig.swift` — every tunable number + `lagWindow(for:)`.
- `ExposureModel.swift` — `ExposureKey`, `DerivedExposureKind`, `CyclePhase`, `ExposureOccurrence`, `OutcomeKey`, `OutcomeOccurrence`, `ExposureSource` protocol.
- `ObjectExposureSource.swift` — object (food/med/supplement/peptide) exposures.
- `OutcomeSource.swift` — symptom + low-mood outcomes.
- `ShortSleepExposureSource.swift` — short-sleep nights via `SleepSessionBuilder`.
- `DerivedEventExposureSources.swift` — `HighStressExposureSource`, `PressureDropExposureSource`.
- `CyclePhaseExposureSource.swift` — menstrual + luteal phase-days.
- `CooccurrenceAnalyzer.swift` — `PairStats`, `ExposurePairDetail`, windowed counting + base-rate.
- `CandidateGenerator.swift` — candidate pair enumeration + evaluation gate.
- `ConfounderAnalyzer.swift` — co-occurrence penalty.
- `ConfidenceScorer.swift` — the sigmoid formula + decay + ceiling.
- `RelationshipClassifier.swift` — `ClassifiedEdge`, type + status assignment.
- `EdgeIdentity.swift` — `edgeKey` build + structured columns + parse-back.
- `EvidenceEngine.swift` — `recompute` + `evidence(for:)`, `RecomputeReport`, `RelationshipEvidence`.

**Modified:**
- `Models/Relationship.swift` — add `edgeKey`, `toSubtype` fields.
- `Database/AppDatabase.swift` — migration `v5`.
- `Database/RelationshipStore.swift` — add `all()` + batch `save([Relationship])`.
- `Synthetic/SyntheticDataGenerator.swift` — plant derived-exposure patterns + protective/confounder/null-effect scenarios.

**New tests:**
- `EdgeIdentityTests.swift`, `ExposureSourceTests.swift`, `CooccurrenceAnalyzerTests.swift`, `CandidateGeneratorTests.swift`, `ConfounderAnalyzerTests.swift`, `ConfidenceScorerTests.swift`, `RelationshipClassifierTests.swift`, `EvidenceEngineTests.swift`, `EvidenceEngineAcceptanceTests.swift`, `EvidenceEnginePerformanceTests.swift`. Plus additions to `RelationshipStoreTests.swift`, `AppDatabaseTests.swift`, `SyntheticDataTests.swift`.

---

## Task 1: Migration v5 — edge identity columns + store additions

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Models/Relationship.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift` (append migration `v5`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/RelationshipStore.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipStoreTests.swift`, `HealthGraphCoreTests/AppDatabaseTests.swift`

**Interfaces:**
- Produces: `Relationship.edgeKey: String?`, `Relationship.toSubtype: String?`; `RelationshipStore.all() async throws -> [Relationship]`; `RelationshipStore.save(_ relationships: [Relationship]) async throws`.

- [ ] **Step 1: Write the failing test** — append to `RelationshipStoreTests.swift`:

```swift
@Test func batchSaveAndAllRoundTrips() async throws {
    let db = try AppDatabase.inMemory()
    let store = GRDBRelationshipStore(database: db)
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let a = Relationship(fromCategory: "food", toCategory: "symptom", toSubtype: "bloating",
                         type: .possibleTrigger, confidence: 0.6,
                         firstSeen: now, lastSeen: now, lastRecomputed: now,
                         status: .active, edgeKey: "obj:a|symptom:bloating|possibleTrigger")
    let b = Relationship(fromCategory: "shortSleep", toCategory: "symptom", toSubtype: "fatigue",
                         type: .possibleTrigger, confidence: 0.5,
                         firstSeen: now, lastSeen: now, lastRecomputed: now,
                         status: .active, edgeKey: "derived:shortSleep|symptom:fatigue|possibleTrigger")
    try await store.save([a, b])
    let all = try await store.all()
    #expect(all.count == 2)
    #expect(Set(all.compactMap(\.edgeKey)).count == 2)
    #expect(all.first(where: { $0.edgeKey == a.edgeKey })?.toSubtype == "bloating")
}

@Test func duplicateEdgeKeyIsRejectedByUniqueIndex() async throws {
    let db = try AppDatabase.inMemory()
    let store = GRDBRelationshipStore(database: db)
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    func edge(_ id: UUID) -> Relationship {
        Relationship(id: id, fromCategory: "food", toCategory: "symptom", toSubtype: "x",
                     type: .possibleTrigger, firstSeen: now, lastSeen: now,
                     lastRecomputed: now, status: .active, edgeKey: "same-key")
    }
    try await store.save(edge(UUID()))
    await #expect(throws: (any Error).self) { try await store.save(edge(UUID())) }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd HealthGraphCore && swift test --filter RelationshipStoreTests`
Expected: FAIL — `Relationship` has no `toSubtype`/`edgeKey`; `store.all()` / `save([])` don't exist.

- [ ] **Step 3: Add fields to `Relationship`** — in `Models/Relationship.swift`, add two stored properties after `aiExplanation` and two init params (both defaulting to `nil`), assigned in the body:

```swift
    public var aiExplanation: String?
    public var edgeKey: String?     // deterministic edge identity; unique (migration v5)
    public var toSubtype: String?   // outcome subtype for labelling (e.g. "bloating")
```

```swift
        aiExplanation: String? = nil,
        edgeKey: String? = nil,
        toSubtype: String? = nil
    ) {
        // ...existing assignments...
        self.aiExplanation = aiExplanation
        self.edgeKey = edgeKey
        self.toSubtype = toSubtype
    }
```

- [ ] **Step 4: Add migration v5** — in `AppDatabase.swift`, immediately before `return migrator`:

```swift
        migrator.registerMigration("v5") { db in
            // Phase 2A edge identity. `edgeKey` is the engine-computed, deterministic
            // identity of an exposure→outcome edge (the schema deliberately left edge
            // identity to the engine, v1 comment). A composite unique index can't work
            // here — SQLite treats NULLs as distinct and every derived edge has a NULL
            // fromObjectID — so a single non-null edgeKey carries uniqueness.
            try db.alter(table: "relationships") { t in
                t.add(column: "edgeKey", .text)
                t.add(column: "toSubtype", .text)
            }
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_rel_edgeKey
                ON relationships(edgeKey) WHERE edgeKey IS NOT NULL
                """)
        }
```

- [ ] **Step 5: Add store methods** — in `RelationshipStore.swift`, add to the protocol and the `GRDBRelationshipStore` struct:

```swift
    // protocol RelationshipStore
    func all() async throws -> [Relationship]
    func save(_ relationships: [Relationship]) async throws
```

```swift
    // struct GRDBRelationshipStore
    public func all() async throws -> [Relationship] {
        try await dbWriter.read { db in try Relationship.fetchAll(db) }
    }

    public func save(_ relationships: [Relationship]) async throws {
        try await dbWriter.write { db in
            for r in relationships { try r.save(db) }
        }
    }
```

- [ ] **Step 6: Add a migration presence test** — append to `AppDatabaseTests.swift`:

```swift
@Test func migrationV5AddsEdgeKeyColumns() async throws {
    let db = try AppDatabase.inMemory()
    try await db.dbWriter.read { database in
        let columns = try database.columns(in: "relationships").map(\.name)
        #expect(columns.contains("edgeKey"))
        #expect(columns.contains("toSubtype"))
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd HealthGraphCore && swift test --filter RelationshipStoreTests` then `--filter AppDatabaseTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Models/Relationship.swift \
        HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift \
        HealthGraphCore/Sources/HealthGraphCore/Database/RelationshipStore.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipStoreTests.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/AppDatabaseTests.swift
git commit -m "feat(core): migration v5 — relationship edgeKey identity + toSubtype; store all()/batch save"
```

---

## Task 2: EvidenceConfig — the single source of tunable numbers

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift`
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift` (shared test file; config test lives here first)

**Interfaces:**
- Produces: `EvidenceConfig` (all params below), `EvidenceConfig.default`, `EvidenceConfig.lagWindow(for: ExposureKey) -> ClosedRange<Double>`. Depends on `ExposureKey` (Task 3) — so this task defines a minimal forward stub? No: to keep tasks ordered, **define `ExposureKey`/`DerivedExposureKind`/`CyclePhase` in this file's sibling `ExposureModel.swift` first is cleaner.** Reorder: create `ExposureModel.swift` here too. To avoid a circular dependency, this task creates BOTH `ExposureModel.swift` (types only) and `EvidenceConfig.swift`.

- [ ] **Step 1: Create `ExposureModel.swift`** (types only; sources come in Task 3):

```swift
import Foundation

public enum CyclePhase: String, Sendable, Equatable, Hashable { case menstrual, luteal }

public enum DerivedExposureKind: Sendable, Equatable, Hashable {
    case shortSleep, highStress, pressureDrop
    case cyclePhase(CyclePhase)
}

public enum ExposureKey: Sendable, Equatable, Hashable {
    case object(UUID, EventCategory)
    case derived(DerivedExposureKind)
}

public struct ExposureOccurrence: Sendable, Equatable {
    public let key: ExposureKey
    public let timestamp: Date
    public let timezoneID: String
    public let sourceEventID: UUID
    public init(key: ExposureKey, timestamp: Date, timezoneID: String, sourceEventID: UUID) {
        self.key = key; self.timestamp = timestamp
        self.timezoneID = timezoneID; self.sourceEventID = sourceEventID
    }
}

public enum OutcomeKey: Sendable, Equatable, Hashable {
    case symptom(String)   // subtype
    case lowMood
}

public struct OutcomeOccurrence: Sendable, Equatable {
    public let key: OutcomeKey
    public let timestamp: Date
    public let value: Double?
    public let sourceEventID: UUID
    public init(key: OutcomeKey, timestamp: Date, value: Double?, sourceEventID: UUID) {
        self.key = key; self.timestamp = timestamp
        self.value = value; self.sourceEventID = sourceEventID
    }
}

/// Pure extractor: raw events → normalized exposure occurrences.
public protocol ExposureSource {
    func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence]
}
```

- [ ] **Step 2: Write the failing test** — create `ExposureSourceTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct EvidenceConfigTests {
    @Test func lagWindowsByExposureKind() {
        let c = EvidenceConfig.default
        #expect(c.lagWindow(for: .object(UUID(), .food)) == 0...24)
        #expect(c.lagWindow(for: .object(UUID(), .supplement)) == 0...48)
        #expect(c.lagWindow(for: .derived(.shortSleep)) == 0...18)
        #expect(c.lagWindow(for: .derived(.cyclePhase(.luteal))) == 0...24)
    }
    @Test func defaultsAreSane() {
        let c = EvidenceConfig.default
        #expect(c.minExposures == 5)
        #expect(c.observationalCeiling == 0.75)
        #expect(c.candidateRatioTrigger > 1.0)
        #expect(c.candidateRatioProtective < 1.0)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd HealthGraphCore && swift test --filter EvidenceConfigTests`
Expected: FAIL — `EvidenceConfig` not defined.

- [ ] **Step 4: Create `EvidenceConfig.swift`:**

```swift
import Foundation

/// Every tunable number for the Evidence Engine in one place. Weights are
/// harness-tuned in the acceptance task; nothing here is a magic constant
/// buried in a stage.
public struct EvidenceConfig: Sendable {
    // Lag windows (hours, absolute time).
    public var foodLagHours: ClosedRange<Double> = 0...24
    public var interventionLagHours: ClosedRange<Double> = 0...48   // med/supplement/peptide
    public var shortSleepLagHours: ClosedRange<Double> = 0...18
    public var stressLagHours: ClosedRange<Double> = 0...24
    public var pressureLagHours: ClosedRange<Double> = 0...24
    public var cyclePhaseLagHours: ClosedRange<Double> = 0...24

    // Derived-exposure thresholds.
    public var shortSleepThresholdMinutes: Double = 360   // < 6h asleep
    public var highStressThreshold: Double = 7            // value ≥ 7 on 1–10
    public var lowMoodThreshold: Double = 3               // mood value ≤ 3 → low mood
    public var lutealWindowDays: Int = 5                  // days before next period start

    // Candidate evaluation gate.
    public var minExposures: Int = 5
    public var minOutcomeOccurrences: Int = 3

    // Direction thresholds (ratio = P(Y|X)/P(Y|¬X)).
    public var candidateRatioTrigger: Double = 1.5
    public var candidateRatioProtective: Double = 0.67

    // Negative learning.
    public var noEffectMinExposures: Int = 20
    public var noEffectMinSpanDays: Double = 90
    public var noEffectRatioBand: ClosedRange<Double> = 0.83...1.2

    // Status thresholds.
    public var activationThreshold: Double = 0.35
    public var decayThreshold: Double = 0.3
    public var stalenessHalfLifeDays: Double = 60
    public var observationalCeiling: Double = 0.75

    // Confidence weights (direction-symmetric): sigmoid(
    //   w1·log(exposureCount) + w2·signalStrength
    //   − w4·confounderPenalty − w5·staleness + bias)
    // signalStrength = min(1, |ln(ratio)|/ln(3)) — a 3×/⅓× shift is full signal,
    // so `improves` (ratio<1) scores like `possibleTrigger` (ratio>1). See
    // spec §6: §7's literal follows-based formula is trigger-biased and can't
    // activate protective edges.
    public var w1 = 0.4    // amount of evidence (log exposureCount)
    public var w2 = 1.5    // effect magnitude (signalStrength)
    public var w4 = 1.5    // confounder penalty
    public var w5 = 1.5    // staleness
    public var bias = -2.0

    public init() {}
    public static let `default` = EvidenceConfig()

    public func lagWindow(for key: ExposureKey) -> ClosedRange<Double> {
        switch key {
        case let .object(_, category):
            switch category {
            case .food: return foodLagHours
            case .medication, .supplement, .peptide: return interventionLagHours
            default: return foodLagHours
            }
        case let .derived(kind):
            switch kind {
            case .shortSleep: return shortSleepLagHours
            case .highStress: return stressLagHours
            case .pressureDrop: return pressureLagHours
            case .cyclePhase: return cyclePhaseLagHours
            }
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd HealthGraphCore && swift test --filter EvidenceConfigTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ExposureModel.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "feat(core): Evidence domain types + EvidenceConfig (lag windows, gates, weights)"
```

---

## Task 3: ObjectExposureSource + OutcomeSource

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ObjectExposureSource.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/OutcomeSource.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift`

**Interfaces:**
- Consumes: `ExposureSource`, `ExposureOccurrence`, `OutcomeOccurrence`, `EvidenceConfig` (Task 2).
- Produces: `ObjectExposureSource()` conforming to `ExposureSource`; `OutcomeSource(config:)` with `func occurrences(from: [HealthEvent]) -> [OutcomeOccurrence]`.

- [ ] **Step 1: Write the failing tests** — append to `ExposureSourceTests.swift`:

```swift
struct ObjectExposureSourceTests {
    @Test func extractsObjectLinkedFoodMedSupplementPeptide() {
        let oid = UUID()
        let events = [
            HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .food,
                        subtype: "dairy", objectID: oid, source: .manual),
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .food,
                        subtype: "rice", objectID: nil, source: .manual),     // no object → skipped
            HealthEvent(timestamp: Date(timeIntervalSince1970: 300), category: .symptom,
                        subtype: "bloating", source: .manual),                 // outcome → skipped
        ]
        let occ = ObjectExposureSource().occurrences(from: events)
        #expect(occ.count == 1)
        #expect(occ.first?.key == .object(oid, .food))
        #expect(occ.first?.sourceEventID == events[0].id)
    }
}

struct OutcomeSourceTests {
    @Test func extractsSymptomsAndLowMood() {
        let events = [
            HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .symptom,
                        subtype: "headache", value: 6, source: .manual),
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .mood,
                        subtype: "mood", value: 2, source: .manual),           // ≤3 → low mood
            HealthEvent(timestamp: Date(timeIntervalSince1970: 300), category: .mood,
                        subtype: "mood", value: 8, source: .manual),           // high → skipped
        ]
        let occ = OutcomeSource(config: .default).occurrences(from: events)
        #expect(occ.contains { $0.key == .symptom("headache") && $0.value == 6 })
        #expect(occ.contains { $0.key == .lowMood })
        #expect(occ.count == 2)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter ObjectExposureSourceTests`
Expected: FAIL — sources not defined.

- [ ] **Step 3: Implement `ObjectExposureSource.swift`:**

```swift
import Foundation

/// Discrete object exposures: food / medication / supplement / peptide events
/// that reference a health_object. One occurrence per event, keyed by objectID.
public struct ObjectExposureSource: ExposureSource {
    static let categories: Set<EventCategory> = [.food, .medication, .supplement, .peptide]
    public init() {}
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard Self.categories.contains(e.category), let oid = e.objectID else { return nil }
            return ExposureOccurrence(key: .object(oid, e.category), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
```

- [ ] **Step 4: Implement `OutcomeSource.swift`:**

```swift
import Foundation

/// Outcomes to test exposures against: every distinct symptom subtype, plus
/// low mood (a mood event at or below the configured threshold). "Energy"
/// folds in as the symptom subtype "fatigue".
public struct OutcomeSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [OutcomeOccurrence] {
        events.compactMap { e in
            switch e.category {
            case .symptom:
                guard let subtype = e.subtype else { return nil }
                return OutcomeOccurrence(key: .symptom(subtype), timestamp: e.timestamp,
                                         value: e.value, sourceEventID: e.id)
            case .mood:
                guard let v = e.value, v <= config.lowMoodThreshold else { return nil }
                return OutcomeOccurrence(key: .lowMood, timestamp: e.timestamp,
                                         value: v, sourceEventID: e.id)
            default:
                return nil
            }
        }
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter ObjectExposureSourceTests` then `--filter OutcomeSourceTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ObjectExposureSource.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/OutcomeSource.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "feat(core): ObjectExposureSource + OutcomeSource (symptom + low-mood)"
```

---

## Task 4: ShortSleepExposureSource

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ShortSleepExposureSource.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift`

**Interfaces:**
- Consumes: `SleepSessionBuilder.sessions(from:timeZone:)` (existing), `ExposureSource`, `EvidenceConfig`.
- Produces: `ShortSleepExposureSource(config:)` → one exposure at wake time per **night** session with `asleepMinutes < shortSleepThresholdMinutes`, keyed `.derived(.shortSleep)`.

- [ ] **Step 1: Write the failing test** — append to `ExposureSourceTests.swift`:

```swift
struct ShortSleepExposureSourceTests {
    // Build one night of contiguous core-sleep segments totalling `hours`.
    func night(startEpoch: Double, hours: Double) -> [HealthEvent] {
        let start = Date(timeIntervalSince1970: startEpoch)
        let end = start.addingTimeInterval(hours * 3600)
        return [HealthEvent(timestamp: start, timezoneID: "UTC", endTimestamp: end,
                            category: .sleep, subtype: "asleepCore", source: .healthKit)]
    }
    @Test func flagsNightsUnderSixHours() {
        // Night A: 5h (short) starting 1700000000 (a 23:00-ish UTC bedtime); Night B: 8h (ok) a day later.
        let events = night(startEpoch: 1_700_000_000, hours: 5)
            + night(startEpoch: 1_700_000_000 + 86_400, hours: 8)
        let occ = ShortSleepExposureSource(config: .default).occurrences(from: events)
        #expect(occ.count == 1)
        #expect(occ.first?.key == .derived(.shortSleep))
        // Timestamped at wake time = start + 5h.
        #expect(occ.first?.timestamp == Date(timeIntervalSince1970: 1_700_000_000 + 5 * 3600))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter ShortSleepExposureSourceTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ShortSleepExposureSource.swift`:**

```swift
import Foundation

/// Short-sleep nights as exposures. Reuses SleepSessionBuilder to fold raw
/// stage segments into nightly sessions, then flags nights whose total asleep
/// falls below the threshold. Naps are never "short sleep". Timestamped at
/// wake time, so the lag window measures forward into the waking day.
public struct ShortSleepExposureSource: ExposureSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        let tzID = events.first(where: { $0.category == .sleep })?.timezoneID ?? "UTC"
        let tz = TimeZone(identifier: tzID) ?? .current
        let sessions = SleepSessionBuilder.sessions(from: events, timeZone: tz)
        // Deterministic synthetic id derived from the wake time (sessions aren't
        // graph events); reused for drill-down provenance.
        return sessions.compactMap { s in
            guard s.kind == .night, s.asleepMinutes < config.shortSleepThresholdMinutes else { return nil }
            let syntheticID = UUID(uuidString: Self.uuid(from: s.end)) ?? UUID()
            return ExposureOccurrence(key: .derived(.shortSleep), timestamp: s.end,
                                      timezoneID: tzID, sourceEventID: syntheticID)
        }
    }
    // Stable UUID string from an epoch second — no randomness (determinism rule).
    static func uuid(from date: Date) -> String {
        let n = UInt64(max(0, date.timeIntervalSince1970))
        let hex = String(format: "%016llx", n)
        return "00000000-0000-0000-\(hex.prefix(4))-\(hex.suffix(12))"
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter ShortSleepExposureSourceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ShortSleepExposureSource.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "feat(core): ShortSleepExposureSource — <6h nights via SleepSessionBuilder"
```

---

## Task 5: HighStress + PressureDrop exposure sources

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/DerivedEventExposureSources.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift`

**Interfaces:**
- Produces: `HighStressExposureSource(config:)` → `stress` events with `value ≥ highStressThreshold`, keyed `.derived(.highStress)`. `PressureDropExposureSource()` → `environment` events with `subtype == "pressureDrop"` (already emitted by `EnvironmentalEventFactory`), keyed `.derived(.pressureDrop)`.

- [ ] **Step 1: Write the failing tests** — append to `ExposureSourceTests.swift`:

```swift
struct DerivedEventExposureSourceTests {
    @Test func highStressAboveThreshold() {
        let events = [
            HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .stress, value: 8, source: .manual),
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .stress, value: 4, source: .manual),
        ]
        let occ = HighStressExposureSource(config: .default).occurrences(from: events)
        #expect(occ.map(\.key) == [.derived(.highStress)])
    }
    @Test func pressureDropReadsPreEventizedSubtype() {
        let events = [
            HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .environment,
                        subtype: "pressureDrop", value: 9, unit: "hPa", source: .weatherAPI),
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .environment,
                        subtype: "pressure", value: 1005, unit: "hPa", source: .weatherAPI),
        ]
        let occ = PressureDropExposureSource().occurrences(from: events)
        #expect(occ.map(\.key) == [.derived(.pressureDrop)])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter DerivedEventExposureSourceTests`
Expected: FAIL.

- [ ] **Step 3: Implement `DerivedEventExposureSources.swift`:**

```swift
import Foundation

/// High-stress exposures: stress events at or above the threshold.
public struct HighStressExposureSource: ExposureSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .stress, let v = e.value, v >= config.highStressThreshold else { return nil }
            return ExposureOccurrence(key: .derived(.highStress), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}

/// Pressure-drop exposures. EnvironmentalEventFactory already emits a
/// `subtype: "pressureDrop"` event when pressure falls ≥ its threshold, so this
/// extractor simply reads those — no delta math here.
public struct PressureDropExposureSource: ExposureSource {
    public init() {}
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .environment, e.subtype == "pressureDrop" else { return nil }
            return ExposureOccurrence(key: .derived(.pressureDrop), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter DerivedEventExposureSourceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/DerivedEventExposureSources.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "feat(core): HighStress + PressureDrop exposure sources"
```

---

## Task 6: CyclePhaseExposureSource

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/CyclePhaseExposureSource.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift`

**Interfaces:**
- Produces: `CyclePhaseExposureSource(config:, timeZone:)` → **one occurrence per phase-active day** (menstrual = period-start day span; luteal = the `lutealWindowDays` before the *next* period start), keyed `.derived(.cyclePhase(.menstrual/.luteal))`, timestamped at that day's UTC start. Modeling note: representing each phase-day as a 24h-window exposure unifies cycle-phase with every other exposure in the analyzer.

- [ ] **Step 1: Write the failing test** — append to `ExposureSourceTests.swift`:

```swift
struct CyclePhaseExposureSourceTests {
    // Period starts (category .cycle, subtype "periodStart") 28 days apart.
    func periodStart(dayOffset: Int) -> HealthEvent {
        let base = 1_700_000_000.0
        return HealthEvent(timestamp: Date(timeIntervalSince1970: base + Double(dayOffset) * 86_400),
                           timezoneID: "UTC", category: .cycle, subtype: "periodStart", source: .manual)
    }
    @Test func derivesMenstrualAndLutealDays() {
        // Two cycles: starts on day 0, 28, 56.
        let events = [periodStart(dayOffset: 0), periodStart(dayOffset: 28), periodStart(dayOffset: 56)]
        let src = CyclePhaseExposureSource(config: .default, timeZone: TimeZone(identifier: "UTC")!)
        let occ = src.occurrences(from: events)
        // Luteal = 5 days before each *next* start → days 23–27 and 51–55.
        let luteal = occ.filter { $0.key == .derived(.cyclePhase(.luteal)) }
        #expect(luteal.count == 10)
        // Menstrual = the start day itself (v1: 1 day per logged start that has a known day).
        let menstrual = occ.filter { $0.key == .derived(.cyclePhase(.menstrual)) }
        #expect(menstrual.count >= 1)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter CyclePhaseExposureSourceTests`
Expected: FAIL.

- [ ] **Step 3: Implement `CyclePhaseExposureSource.swift`:**

```swift
import Foundation

/// Cycle-phase exposures. v1 scopes to the two symptomatic windows: menstrual
/// (the logged period-start day) and luteal (the configured number of days
/// before the *next* logged period start). Each phase-day is emitted as one
/// occurrence at that day's start, so the analyzer treats it with a standard
/// 24h window. Needs ≥2 logged period starts to bound a luteal window.
public struct CyclePhaseExposureSource: ExposureSource {
    let config: EvidenceConfig
    let timeZone: TimeZone
    public init(config: EvidenceConfig, timeZone: TimeZone) {
        self.config = config; self.timeZone = timeZone
    }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let starts = events
            .filter { $0.category == .cycle && $0.subtype == "periodStart" }
            .map(\.timestamp)
            .sorted()
        guard starts.count >= 2 else { return [] }
        var out: [ExposureOccurrence] = []
        func occ(_ phase: CyclePhase, day: Date) -> ExposureOccurrence {
            let d = cal.startOfDay(for: day)
            return ExposureOccurrence(key: .derived(.cyclePhase(phase)), timestamp: d,
                                      timezoneID: timeZone.identifier,
                                      sourceEventID: ShortSleepExposureSource.uuid(from: d).flatMap(UUID.init(uuidString:)) ?? UUID())
        }
        for start in starts { out.append(occ(.menstrual, day: start)) }
        for i in 1..<starts.count {
            let nextStart = cal.startOfDay(for: starts[i])
            for back in 1...config.lutealWindowDays {
                if let day = cal.date(byAdding: .day, value: -back, to: nextStart) {
                    out.append(occ(.luteal, day: day))
                }
            }
        }
        return out
    }
}
```

Note: `ShortSleepExposureSource.uuid(from:)` returns a `String`; wrap with `UUID(uuidString:)`. Fix the line to:

```swift
            let sid = UUID(uuidString: ShortSleepExposureSource.uuid(from: d)) ?? UUID()
            return ExposureOccurrence(key: .derived(.cyclePhase(phase)), timestamp: d,
                                      timezoneID: timeZone.identifier, sourceEventID: sid)
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter CyclePhaseExposureSourceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/CyclePhaseExposureSource.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExposureSourceTests.swift
git commit -m "feat(core): CyclePhaseExposureSource — menstrual + luteal phase-days"
```

---

## Task 7: CooccurrenceAnalyzer — the statistical core

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/CooccurrenceAnalyzer.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/CooccurrenceAnalyzerTests.swift`

**Interfaces:**
- Produces: `ExposurePairDetail`, `PairStats`, `CooccurrenceAnalyzer(config:)` with
  `func analyze(exposure: [ExposureOccurrence], outcome: [OutcomeOccurrence], window: ClosedRange<Double>, observation: DateInterval) -> PairStats?` (nil when `exposure.isEmpty`).
- Semantics: `pairs` is **per exposure occurrence** (drives dots + evidenceCount). `ratio` is **per-day** P(Y|X)/P(Y|¬X) using a **UTC** calendar (deterministic; matches existing synthetic tests). `evidenceCount` = follows, `contradiction` handled by the caller as misses.

- [ ] **Step 1: Write the failing test** — create `CooccurrenceAnalyzerTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct CooccurrenceAnalyzerTests {
    let day = 86_400.0
    let base = 1_700_000_000.0

    @Test func countsFollowsAndMissesWithinWindow() {
        // 3 exposures; outcome follows the 1st (+6h) and 3rd (+2h), not the 2nd.
        let exposures = [0, 1, 2].map {
            ExposureOccurrence(key: .object(UUID(), .food),
                               timestamp: Date(timeIntervalSince1970: base + Double($0) * day + 9 * 3600),
                               timezoneID: "UTC", sourceEventID: UUID())
        }
        let outcomes = [
            OutcomeOccurrence(key: .symptom("bloating"),
                              timestamp: Date(timeIntervalSince1970: base + 0 * day + 15 * 3600),
                              value: 5, sourceEventID: UUID()),   // +6h after exp0
            OutcomeOccurrence(key: .symptom("bloating"),
                              timestamp: Date(timeIntervalSince1970: base + 2 * day + 11 * 3600),
                              value: 7, sourceEventID: UUID()),   // +2h after exp2
        ]
        let obs = DateInterval(start: Date(timeIntervalSince1970: base),
                               end: Date(timeIntervalSince1970: base + 3 * day))
        let stats = CooccurrenceAnalyzer(config: .default)
            .analyze(exposure: exposures, outcome: outcomes, window: 0...24, observation: obs)
        #expect(stats?.exposureCount == 3)
        #expect(stats?.followCount == 2)
        #expect(stats?.missCount == 1)
        #expect(stats?.avgEffect == 6)                 // mean of 5 and 7
        #expect((stats?.ratio ?? 0) > 1.5)             // no spontaneous outcomes → high ratio
        #expect(stats?.pairs.filter { $0.outcomeFollowed }.count == 2)
    }

    @Test func returnsNilWithoutExposures() {
        let stats = CooccurrenceAnalyzer(config: .default)
            .analyze(exposure: [], outcome: [], window: 0...24,
                     observation: DateInterval(start: Date(timeIntervalSince1970: base),
                                               end: Date(timeIntervalSince1970: base + day)))
        #expect(stats == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter CooccurrenceAnalyzerTests`
Expected: FAIL.

- [ ] **Step 3: Implement `CooccurrenceAnalyzer.swift`:**

```swift
import Foundation

/// One exposure occurrence and whether its outcome followed — the drill-down row.
public struct ExposurePairDetail: Sendable, Equatable {
    public let exposureEventID: UUID
    public let exposureTime: Date
    public let outcomeFollowed: Bool
    public let outcomeEventID: UUID?
    public let outcomeValue: Double?
    public let lagHours: Double?
}

/// Result of scoring one (exposure, outcome) pair.
public struct PairStats: Sendable, Equatable {
    public let exposureCount: Int
    public let followCount: Int
    public let missCount: Int
    public let baseRate: Double        // P(Y | ¬X), per non-exposure day
    public let ratio: Double           // P(Y|X) / P(Y|¬X), per-day
    public let avgEffect: Double?      // mean outcome value among follows
    public let medianLagHours: Double?
    public let firstExposure: Date
    public let lastExposure: Date
    public let pairs: [ExposurePairDetail]
}

public struct CooccurrenceAnalyzer {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }

    public func analyze(exposure: [ExposureOccurrence], outcome: [OutcomeOccurrence],
                        window: ClosedRange<Double>, observation: DateInterval) -> PairStats? {
        guard !exposure.isEmpty else { return nil }
        let cal = Self.utc
        let sortedOutcomes = outcome.sorted { $0.timestamp < $1.timestamp }

        // Per-occurrence pairs (drives dots + evidenceCount).
        var pairs: [ExposurePairDetail] = []
        var effects: [Double] = []
        var lags: [Double] = []
        for e in exposure.sorted(by: { $0.timestamp < $1.timestamp }) {
            let lo = e.timestamp.addingTimeInterval(window.lowerBound * 3600)
            let hi = e.timestamp.addingTimeInterval(window.upperBound * 3600)
            let hit = sortedOutcomes.first { $0.timestamp >= lo && $0.timestamp <= hi }
            if let hit {
                let lag = hit.timestamp.timeIntervalSince(e.timestamp) / 3600
                lags.append(lag); if let v = hit.value { effects.append(v) }
                pairs.append(ExposurePairDetail(exposureEventID: e.sourceEventID, exposureTime: e.timestamp,
                                                outcomeFollowed: true, outcomeEventID: hit.sourceEventID,
                                                outcomeValue: hit.value, lagHours: lag))
            } else {
                pairs.append(ExposurePairDetail(exposureEventID: e.sourceEventID, exposureTime: e.timestamp,
                                                outcomeFollowed: false, outcomeEventID: nil,
                                                outcomeValue: nil, lagHours: nil))
            }
        }
        let followCount = pairs.filter(\.outcomeFollowed).count

        // Per-day base rate & ratio.
        let exposureDays = Set(exposure.map { cal.startOfDay(for: $0.timestamp) })
        let outcomeDays = Set(sortedOutcomes.map { cal.startOfDay(for: $0.timestamp) })
        let exposureDaysWithOutcome = exposureDays.filter { exDay in
            // an exposure that day whose window contains an outcome
            exposure.contains { e in
                guard cal.startOfDay(for: e.timestamp) == exDay else { return false }
                let lo = e.timestamp.addingTimeInterval(window.lowerBound * 3600)
                let hi = e.timestamp.addingTimeInterval(window.upperBound * 3600)
                return sortedOutcomes.contains { $0.timestamp >= lo && $0.timestamp <= hi }
            }
        }.count
        let totalDays = max(1, Int(observation.duration / 86_400) + 1)
        let nonExposureDays = max(1, totalDays - exposureDays.count)
        let spontaneousOutcomeDays = outcomeDays.subtracting(exposureDays).count
        let baseRate = Double(spontaneousOutcomeDays) / Double(nonExposureDays)
        let pYgivenX = Double(exposureDaysWithOutcome) / Double(max(1, exposureDays.count))
        let eps = 0.01
        let ratio = pYgivenX / max(baseRate, eps)

        let sortedLags = lags.sorted()
        let medianLag = sortedLags.isEmpty ? nil : sortedLags[sortedLags.count / 2]
        let avgEffect = effects.isEmpty ? nil : effects.reduce(0, +) / Double(effects.count)
        let times = exposure.map(\.timestamp).sorted()

        return PairStats(exposureCount: exposure.count, followCount: followCount,
                         missCount: exposure.count - followCount, baseRate: baseRate, ratio: ratio,
                         avgEffect: avgEffect, medianLagHours: medianLag,
                         firstExposure: times.first!, lastExposure: times.last!, pairs: pairs)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter CooccurrenceAnalyzerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/CooccurrenceAnalyzer.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/CooccurrenceAnalyzerTests.swift
git commit -m "feat(core): CooccurrenceAnalyzer — windowed follows/misses + per-day ratio"
```

---

## Task 8: CandidateGenerator — bounded pair enumeration

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/CandidateGenerator.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/CandidateGeneratorTests.swift`

**Interfaces:**
- Produces: `struct Candidate { let exposure: ExposureKey; let outcome: OutcomeKey }`; `CandidateGenerator(config:)` with
  `func candidates(exposuresByKey: [ExposureKey: [ExposureOccurrence]], outcomesByKey: [OutcomeKey: [OutcomeOccurrence]]) -> [Candidate]`.
- Gate: exposure key has `≥ minExposures` occurrences AND outcome key has `≥ minOutcomeOccurrences` occurrences overall. Direction-agnostic (no ratio pre-filter).

- [ ] **Step 1: Write the failing test** — create `CandidateGeneratorTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct CandidateGeneratorTests {
    func exp(_ key: ExposureKey, _ n: Int) -> [ExposureOccurrence] {
        (0..<n).map { ExposureOccurrence(key: key, timestamp: Date(timeIntervalSince1970: Double($0) * 86_400),
                                         timezoneID: "UTC", sourceEventID: UUID()) }
    }
    func out(_ key: OutcomeKey, _ n: Int) -> [OutcomeOccurrence] {
        (0..<n).map { OutcomeOccurrence(key: key, timestamp: Date(timeIntervalSince1970: Double($0) * 3600),
                                        value: 5, sourceEventID: UUID()) }
    }
    @Test func gatesOnMinCounts() {
        let dairy = ExposureKey.object(UUID(), .food)
        let rareFood = ExposureKey.object(UUID(), .food)
        let exposures = [dairy: exp(dairy, 6), rareFood: exp(rareFood, 3)]   // rareFood < 5 → excluded
        let outcomes = [OutcomeKey.symptom("bloating"): out(.symptom("bloating"), 4),
                        OutcomeKey.symptom("rare"): out(.symptom("rare"), 2)] // rare < 3 → excluded
        let cands = CandidateGenerator(config: .default)
            .candidates(exposuresByKey: exposures, outcomesByKey: outcomes)
        #expect(cands.count == 1)
        #expect(cands.first?.exposure == dairy)
        #expect(cands.first?.outcome == .symptom("bloating"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter CandidateGeneratorTests`
Expected: FAIL.

- [ ] **Step 3: Implement `CandidateGenerator.swift`:**

```swift
import Foundation

public struct Candidate: Sendable, Equatable {
    public let exposure: ExposureKey
    public let outcome: OutcomeKey
}

/// Bounds the exposure×outcome space to pairs worth scoring: the exposure must
/// have enough occurrences to compare, and the outcome must exist enough in the
/// corpus to associate with. Deliberately direction-agnostic — a low ratio is
/// exactly what `improves`/`noEffect` need to observe (spec §5).
public struct CandidateGenerator {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    public func candidates(exposuresByKey: [ExposureKey: [ExposureOccurrence]],
                           outcomesByKey: [OutcomeKey: [OutcomeOccurrence]]) -> [Candidate] {
        let exposures = exposuresByKey.filter { $0.value.count >= config.minExposures }.keys
        let outcomes = outcomesByKey.filter { $0.value.count >= config.minOutcomeOccurrences }.keys
        var out: [Candidate] = []
        for e in exposures { for o in outcomes { out.append(Candidate(exposure: e, outcome: o)) } }
        return out
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter CandidateGeneratorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/CandidateGenerator.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/CandidateGeneratorTests.swift
git commit -m "feat(core): CandidateGenerator — direction-agnostic evaluation gate"
```

---

## Task 9: ConfounderAnalyzer

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ConfounderAnalyzer.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ConfounderAnalyzerTests.swift`

**Interfaces:**
- Produces: `ConfounderAnalyzer()` with
  `func penalty(targetDays: Set<Date>, others: [ExposureKey: Set<Date>], threshold: Double = 0.6) -> (penalty: Double, confounders: [ExposureKey])`.
- Penalty = `max(0, maxCoOccurrenceFraction − threshold) / (1 − threshold)`, clamped 0…1. A key is a confounder when its co-occurrence fraction with the target exceeds `threshold`. Cycle/illness day-sets are provided by the caller in `others` (they are always present).

- [ ] **Step 1: Write the failing test** — create `ConfounderAnalyzerTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct ConfounderAnalyzerTests {
    func days(_ offsets: [Int]) -> Set<Date> {
        Set(offsets.map { Date(timeIntervalSince1970: Double($0) * 86_400) })
    }
    @Test func penalizesHighCoOccurrence() {
        let target = days([1, 2, 3, 4, 5])
        let coffee = ExposureKey.object(UUID(), .food)
        let others = [coffee: days([1, 2, 3, 4])]   // 4/5 = 0.8 > 0.6
        let (penalty, confounders) = ConfounderAnalyzer().penalty(targetDays: target, others: others)
        #expect(penalty > 0)
        #expect(confounders == [coffee])
    }
    @Test func noPenaltyWhenIndependent() {
        let target = days([1, 2, 3, 4, 5])
        let other = ExposureKey.derived(.highStress)
        let (penalty, confounders) = ConfounderAnalyzer()
            .penalty(targetDays: target, others: [other: days([9, 10])])   // 0/5
        #expect(penalty == 0)
        #expect(confounders.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter ConfounderAnalyzerTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ConfounderAnalyzer.swift`:**

```swift
import Foundation

/// Measures whether another exposure shadows the target — if some other
/// exposure is present on more than `threshold` of the target's days, we can't
/// tell them apart yet, so confidence is penalized. Cycle-phase and illness
/// day-sets are always supplied in `others` by the engine (spec §6).
public struct ConfounderAnalyzer {
    public init() {}
    public func penalty(targetDays: Set<Date>, others: [ExposureKey: Set<Date>],
                        threshold: Double = 0.6) -> (penalty: Double, confounders: [ExposureKey]) {
        guard !targetDays.isEmpty else { return (0, []) }
        var confounders: [ExposureKey] = []
        var maxFraction = 0.0
        for (key, days) in others {
            let overlap = Double(targetDays.intersection(days).count) / Double(targetDays.count)
            if overlap > threshold { confounders.append(key) }
            maxFraction = max(maxFraction, overlap)
        }
        let penalty = max(0, maxFraction - threshold) / (1 - threshold)
        // Stable order for determinism when the engine records confounders.
        confounders.sort { String(describing: $0) < String(describing: $1) }
        return (min(1, penalty), confounders)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter ConfounderAnalyzerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ConfounderAnalyzer.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ConfounderAnalyzerTests.swift
git commit -m "feat(core): ConfounderAnalyzer — co-occurrence penalty over day-sets"
```

---

## Task 10: ConfidenceScorer

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/ConfidenceScorer.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ConfidenceScorerTests.swift`

**Interfaces:**
- Produces: `ConfidenceScorer(config:)` with
  `func confidence(stats: PairStats, confounderPenalty: Double, now: Date) -> Double`.
- **Direction-symmetric** (spec §6): `signalStrength = min(1, |ln(ratio)|/ln(3))`; `staleness = clamp((now − stats.lastExposure)/(halfLifeDays·86400), 0, 1)`. Result = `min(observationalCeiling, sigmoid(w1·log(max(1,exposureCount)) + w2·signalStrength − w4·penalty − w5·staleness + bias))`. Scoring uses `exposureCount` + `ratio`, NOT the follow count — so protective (`improves`, ratio<1) edges score like triggers.

- [ ] **Step 1: Write the failing test** — create `ConfidenceScorerTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct ConfidenceScorerTests {
    func stats(follows: Int, exposures: Int, baseRate: Double, lastExposure: Date) -> PairStats {
        PairStats(exposureCount: exposures, followCount: follows, missCount: exposures - follows,
                  baseRate: baseRate, ratio: 3, avgEffect: 5, medianLagHours: 6,
                  firstExposure: Date(timeIntervalSince1970: 0), lastExposure: lastExposure, pairs: [])
    }
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func strongRecentPatternIsHighButClampedTo075() {
        let s = stats(follows: 140, exposures: 200, baseRate: 0.05, lastExposure: now)
        let c = ConfidenceScorer(config: .default).confidence(stats: s, confounderPenalty: 0, now: now)
        #expect(c <= 0.75)
        #expect(c > 0.6)
    }
    @Test func confounderLowersConfidence() {
        let s = stats(follows: 140, exposures: 200, baseRate: 0.05, lastExposure: now)
        let clean = ConfidenceScorer(config: .default).confidence(stats: s, confounderPenalty: 0, now: now)
        let confounded = ConfidenceScorer(config: .default).confidence(stats: s, confounderPenalty: 1, now: now)
        #expect(confounded < clean)
    }
    @Test func stalenessLowersConfidence() {
        let recent = stats(follows: 140, exposures: 200, baseRate: 0.05, lastExposure: now)
        let old = stats(follows: 140, exposures: 200, baseRate: 0.05,
                        lastExposure: now.addingTimeInterval(-200 * 86_400))
        let scorer = ConfidenceScorer(config: .default)
        #expect(scorer.confidence(stats: old, confounderPenalty: 0, now: now)
                < scorer.confidence(stats: recent, confounderPenalty: 0, now: now))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter ConfidenceScorerTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ConfidenceScorer.swift`:**

```swift
import Foundation

/// The confidence formula (spec §6). Deterministic in `now`. Clamps to the
/// observational ceiling — exceeding it needs Phase 4 experiments.
public struct ConfidenceScorer {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    public func confidence(stats: PairStats, confounderPenalty: Double, now: Date) -> Double {
        // Direction-symmetric: score by amount of data + effect magnitude, so a
        // protective edge (ratio<1, few follows) scores like a trigger. See spec §6.
        let signalStrength = min(1, abs(log(max(stats.ratio, 1e-6))) / log(3))
        let ageDays = now.timeIntervalSince(stats.lastExposure) / 86_400
        let staleness = min(1, max(0, ageDays / config.stalenessHalfLifeDays))
        let score = config.w1 * log(Double(max(1, stats.exposureCount)))
                  + config.w2 * signalStrength
                  - config.w4 * confounderPenalty
                  - config.w5 * staleness
                  + config.bias
        let sigmoid = 1 / (1 + exp(-score))
        return min(config.observationalCeiling, sigmoid)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter ConfidenceScorerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/ConfidenceScorer.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ConfidenceScorerTests.swift
git commit -m "feat(core): ConfidenceScorer — sigmoid formula, staleness, 0.75 ceiling"
```

---

## Task 11: RelationshipClassifier

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/RelationshipClassifier.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipClassifierTests.swift`

**Interfaces:**
- Produces: `struct ClassifiedEdge { let type: RelationshipType; let status: RelStatus }`; `RelationshipClassifier(config:)` with
  `func classify(stats: PairStats, confidence: Double, now: Date) -> ClassifiedEdge?` (nil = too weak to persist).
- Logic: noEffect first (≥20 exposures, span ≥90d, ratio in band) → `(.noEffect, .confirmedNoEffect)`. Else direction: `ratio ≥ trigger` → `.possibleTrigger`; `ratio ≤ protective` → `.improves`; else nil. Status from confidence: `≥ activation → .active`; `< decay → .decayed`; else `.candidate`.

- [ ] **Step 1: Write the failing test** — create `RelationshipClassifierTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct RelationshipClassifierTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    func stats(ratio: Double, exposures: Int, spanDays: Double) -> PairStats {
        let last = now
        let first = now.addingTimeInterval(-spanDays * 86_400)
        return PairStats(exposureCount: exposures, followCount: exposures / 2, missCount: exposures / 2,
                         baseRate: 0.1, ratio: ratio, avgEffect: 5, medianLagHours: 6,
                         firstExposure: first, lastExposure: last, pairs: [])
    }
    let c = RelationshipClassifier(config: .default)

    @Test func triggerAtHighRatioAndConfidence() {
        let e = c.classify(stats: stats(ratio: 3, exposures: 10, spanDays: 30), confidence: 0.6, now: now)
        #expect(e?.type == .possibleTrigger)
        #expect(e?.status == .active)
    }
    @Test func protectiveAtLowRatio() {
        let e = c.classify(stats: stats(ratio: 0.4, exposures: 10, spanDays: 30), confidence: 0.5, now: now)
        #expect(e?.type == .improves)
    }
    @Test func noEffectAfterLongNullExposure() {
        let e = c.classify(stats: stats(ratio: 1.0, exposures: 25, spanDays: 120), confidence: 0.1, now: now)
        #expect(e?.type == .noEffect)
        #expect(e?.status == .confirmedNoEffect)
    }
    @Test func weakUndirectedReturnsNil() {
        let e = c.classify(stats: stats(ratio: 1.1, exposures: 8, spanDays: 20), confidence: 0.2, now: now)
        #expect(e == nil)
    }
    @Test func lowConfidenceTriggerIsCandidate() {
        let e = c.classify(stats: stats(ratio: 2, exposures: 8, spanDays: 20), confidence: 0.32, now: now)
        #expect(e?.status == .candidate)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter RelationshipClassifierTests`
Expected: FAIL.

- [ ] **Step 3: Implement `RelationshipClassifier.swift`:**

```swift
import Foundation

public struct ClassifiedEdge: Sendable, Equatable {
    public let type: RelationshipType
    public let status: RelStatus
}

/// Turns a scored pair into an edge type + status, or nil when it isn't worth a
/// row (weak and undirected, without enough evidence for a null-effect claim).
public struct RelationshipClassifier {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }

    public func classify(stats: PairStats, confidence: Double, now: Date) -> ClassifiedEdge? {
        let spanDays = stats.lastExposure.timeIntervalSince(stats.firstExposure) / 86_400
        if stats.exposureCount >= config.noEffectMinExposures,
           spanDays >= config.noEffectMinSpanDays,
           config.noEffectRatioBand.contains(stats.ratio) {
            return ClassifiedEdge(type: .noEffect, status: .confirmedNoEffect)
        }
        let type: RelationshipType?
        if stats.ratio >= config.candidateRatioTrigger { type = .possibleTrigger }
        else if stats.ratio <= config.candidateRatioProtective { type = .improves }
        else { type = nil }
        guard let type else { return nil }
        let status: RelStatus =
            confidence >= config.activationThreshold ? .active
            : confidence < config.decayThreshold ? .decayed
            : .candidate
        return ClassifiedEdge(type: type, status: status)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter RelationshipClassifierTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/RelationshipClassifier.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipClassifierTests.swift
git commit -m "feat(core): RelationshipClassifier — type/status incl. noEffect + decay"
```

---

## Task 12: EdgeIdentity — build + structured columns + parse

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EdgeIdentity.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EdgeIdentityTests.swift`

**Interfaces:**
- Produces: `enum EdgeIdentity` with
  - `static func edgeKey(from: ExposureKey, to: OutcomeKey, type: RelationshipType) -> String`
  - `static func columns(from: ExposureKey, to: OutcomeKey) -> (fromObjectID: UUID?, fromCategory: String?, toCategory: String, toSubtype: String?)`
  - `static func parse(_ r: Relationship) -> (exposure: ExposureKey, outcome: OutcomeKey)?`
- `parse` reads `r.edgeKey` (authoritative) and must round-trip whatever `edgeKey` produced.

- [ ] **Step 1: Write the failing test** — create `EdgeIdentityTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct EdgeIdentityTests {
    func roundTrip(_ from: ExposureKey, _ to: OutcomeKey) {
        let key = EdgeIdentity.edgeKey(from: from, to: to, type: .possibleTrigger)
        let cols = EdgeIdentity.columns(from: from, to: to)
        let r = Relationship(fromObjectID: cols.fromObjectID, fromCategory: cols.fromCategory,
                             toCategory: cols.toCategory, toSubtype: cols.toSubtype,
                             type: .possibleTrigger, firstSeen: Date(), lastSeen: Date(),
                             lastRecomputed: Date(), status: .active, edgeKey: key)
        let parsed = EdgeIdentity.parse(r)
        #expect(parsed?.exposure == from)
        #expect(parsed?.outcome == to)
    }
    @Test func objectExposureRoundTrips() {
        roundTrip(.object(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, .food), .symptom("bloating"))
    }
    @Test func derivedExposuresRoundTrip() {
        roundTrip(.derived(.shortSleep), .symptom("fatigue"))
        roundTrip(.derived(.pressureDrop), .symptom("headache"))
        roundTrip(.derived(.cyclePhase(.luteal)), .symptom("cramps"))
        roundTrip(.derived(.highStress), .lowMood)
    }
    @Test func objectColumnsCarryStructuredPointers() {
        let oid = UUID()
        let cols = EdgeIdentity.columns(from: .object(oid, .supplement), to: .symptom("headache"))
        #expect(cols.fromObjectID == oid)
        #expect(cols.fromCategory == "supplement")
        #expect(cols.toCategory == "symptom")
        #expect(cols.toSubtype == "headache")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter EdgeIdentityTests`
Expected: FAIL.

- [ ] **Step 3: Implement `EdgeIdentity.swift`:**

```swift
import Foundation

/// Deterministic serialization of an edge's identity. `edgeKey` is the unique,
/// non-null upsert key (migration v5); the structured columns are populated for
/// indexed queries and name resolution. `parse` reverses `edgeKey` so
/// `evidence(for:)` can re-derive an edge's occurrences on demand.
public enum EdgeIdentity {
    static func fromToken(_ key: ExposureKey) -> String {
        switch key {
        case let .object(uuid, category): return "obj:\(uuid.uuidString):\(category.rawValue)"
        case let .derived(kind):
            switch kind {
            case .shortSleep: return "derived:shortSleep"
            case .highStress: return "derived:highStress"
            case .pressureDrop: return "derived:pressureDrop"
            case let .cyclePhase(phase): return "derived:cyclePhase.\(phase.rawValue)"
            }
        }
    }
    static func toToken(_ key: OutcomeKey) -> String {
        switch key {
        case let .symptom(subtype): return "symptom:\(subtype)"
        case .lowMood: return "mood:low"
        }
    }

    public static func edgeKey(from: ExposureKey, to: OutcomeKey, type: RelationshipType) -> String {
        "\(fromToken(from))|\(toToken(to))|\(type.rawValue)"
    }

    public static func columns(from: ExposureKey, to: OutcomeKey)
        -> (fromObjectID: UUID?, fromCategory: String?, toCategory: String, toSubtype: String?) {
        let fromObjectID: UUID?
        let fromCategory: String?
        switch from {
        case let .object(uuid, category): fromObjectID = uuid; fromCategory = category.rawValue
        case .derived: fromObjectID = nil; fromCategory = fromToken(from).replacingOccurrences(of: "derived:", with: "")
        }
        switch to {
        case let .symptom(subtype): return (fromObjectID, fromCategory, "symptom", subtype)
        case .lowMood: return (fromObjectID, fromCategory, "mood", "low")
        }
    }

    public static func parse(_ r: Relationship) -> (exposure: ExposureKey, outcome: OutcomeKey)? {
        guard let key = r.edgeKey else { return nil }
        let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        guard let exposure = parseFrom(parts[0]), let outcome = parseTo(parts[1]) else { return nil }
        return (exposure, outcome)
    }

    static func parseFrom(_ token: String) -> ExposureKey? {
        if token.hasPrefix("obj:") {
            let rest = token.dropFirst(4).split(separator: ":", maxSplits: 1).map(String.init)
            guard rest.count == 2, let uuid = UUID(uuidString: rest[0]),
                  let category = EventCategory(rawValue: rest[1]) else { return nil }
            return .object(uuid, category)
        }
        if token.hasPrefix("derived:") {
            let kind = String(token.dropFirst(8))
            switch kind {
            case "shortSleep": return .derived(.shortSleep)
            case "highStress": return .derived(.highStress)
            case "pressureDrop": return .derived(.pressureDrop)
            default:
                if kind.hasPrefix("cyclePhase."),
                   let phase = CyclePhase(rawValue: String(kind.dropFirst("cyclePhase.".count))) {
                    return .derived(.cyclePhase(phase))
                }
                return nil
            }
        }
        return nil
    }

    static func parseTo(_ token: String) -> OutcomeKey? {
        if token.hasPrefix("symptom:") { return .symptom(String(token.dropFirst(8))) }
        if token == "mood:low" { return .lowMood }
        return nil
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter EdgeIdentityTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/EdgeIdentity.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EdgeIdentityTests.swift
git commit -m "feat(core): EdgeIdentity — deterministic edgeKey build + parse round-trip"
```

---

## Task 13: EvidenceEngine.recompute() — orchestration + idempotent upsert

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEngineTests.swift`

**Interfaces:**
- Consumes: every stage above; `GRDBEventStore`, `GRDBRelationshipStore`.
- Produces:
  - `struct RecomputeReport { let pairsEvaluated: Int; let relationshipsUpserted: Int; let relationshipsDecayed: Int }`
  - `EvidenceEngine(database:config:)`, `func recompute(asOf now: Date) async throws -> RecomputeReport`.
- Upsert rules: match existing by `edgeKey`; preserve `id` + `firstSeen`; never overwrite `.userDismissed`; new edges get `firstSeen = now`; edges present before but absent now → `.decayed` (unless dismissed).

- [ ] **Step 1: Write the failing test** — create `EvidenceEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct EvidenceEngineTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    // A dataset where "dairy" reliably precedes "bloating".
    func seedDairyBloating(into db: AppDatabase) async throws {
        let store = GRDBEventStore(database: db)
        let objects = GRDBObjectStore(database: db)
        let dairy = try await objects.findOrCreate(name: "dairy", kind: .food, metadata: nil)
        var events: [HealthEvent] = []
        let base = now.addingTimeInterval(-60 * 86_400)   // 60 days of history
        for d in 0..<30 {
            let exp = base.addingTimeInterval(Double(d) * 2 * 86_400 + 9 * 3600)  // every 2 days, 09:00
            events.append(HealthEvent(timestamp: exp, timezoneID: "UTC", category: .food,
                                      subtype: "dairy", objectID: dairy.id, source: .manual))
            events.append(HealthEvent(timestamp: exp.addingTimeInterval(6 * 3600), timezoneID: "UTC",
                                      category: .symptom, subtype: "bloating", value: 6, source: .manual))
        }
        try await store.save(events)
    }

    @Test func minesDairyBloatingAsActiveTrigger() async throws {
        let db = try AppDatabase.inMemory()
        try await seedDairyBloating(into: db)
        let report = try await EvidenceEngine(database: db).recompute(asOf: now)
        #expect(report.pairsEvaluated >= 1)
        let rels = try await GRDBRelationshipStore(database: db).relationships(status: .active)
        #expect(rels.contains { $0.toSubtype == "bloating" && $0.type == .possibleTrigger })
    }

    @Test func recomputeIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        try await seedDairyBloating(into: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)
        let first = try await GRDBRelationshipStore(database: db).all()
        _ = try await engine.recompute(asOf: now)
        let second = try await GRDBRelationshipStore(database: db).all()
        #expect(first.count == second.count)                       // no duplicates
        #expect(Set(first.compactMap(\.edgeKey)) == Set(second.compactMap(\.edgeKey)))
    }

    @Test func userDismissedSurvivesRecompute() async throws {
        let db = try AppDatabase.inMemory()
        try await seedDairyBloating(into: db)
        let store = GRDBRelationshipStore(database: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)
        var rel = try await store.all().first { $0.toSubtype == "bloating" }!
        rel.status = .userDismissed
        try await store.save(rel)
        _ = try await engine.recompute(asOf: now)
        let after = try await store.relationship(id: rel.id)
        #expect(after?.status == .userDismissed)
    }

    @Test func disappearedEdgeDecaysOnRecompute() async throws {
        let db = try AppDatabase.inMemory()
        try await seedDairyBloating(into: db)
        let events = GRDBEventStore(database: db)
        let rels = GRDBRelationshipStore(database: db)
        let engine = EvidenceEngine(database: db)
        _ = try await engine.recompute(asOf: now)
        #expect(try await rels.relationships(status: .active).contains { $0.toSubtype == "bloating" })
        // Remove every dairy exposure; the edge can no longer be produced → decayed.
        let all = try await events.events(in: DateInterval(start: .distantPast, end: .distantFuture),
                                          category: .food)
        for e in all where e.subtype == "dairy" { try await events.softDelete(id: e.id) }
        _ = try await engine.recompute(asOf: now)
        let bloating = try await rels.all().first { $0.toSubtype == "bloating" }
        #expect(bloating?.status == .decayed)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter EvidenceEngineTests`
Expected: FAIL — `EvidenceEngine` not defined.

- [ ] **Step 3: Implement `EvidenceEngine.swift` (recompute + helpers):**

```swift
import Foundation

public struct RecomputeReport: Sendable, Equatable {
    public let pairsEvaluated: Int
    public let relationshipsUpserted: Int
    public let relationshipsDecayed: Int
}

public struct EvidenceEngine {
    let eventStore: GRDBEventStore
    let relationshipStore: GRDBRelationshipStore
    let config: EvidenceConfig

    public init(database: AppDatabase, config: EvidenceConfig = .default) {
        self.eventStore = GRDBEventStore(database: database)
        self.relationshipStore = GRDBRelationshipStore(database: database)
        self.config = config
    }

    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    /// Reserved key under which illness days enter the confounder pool. Never
    /// appears in `exposuresByKey`, so CandidateGenerator never mines it — illness
    /// is confounder-only (spec §4).
    static let illnessConfounderKey = ExposureKey.object(
        UUID(uuidString: "00000000-0000-0000-0000-0000000000ff")!, .illness)

    // Extract all exposures and outcomes from a slice of events.
    func extract(_ events: [HealthEvent]) -> (exposures: [ExposureKey: [ExposureOccurrence]],
                                              outcomes: [OutcomeKey: [OutcomeOccurrence]]) {
        let tz = TimeZone(identifier: "UTC")!
        let sources: [ExposureSource] = [
            ObjectExposureSource(),
            ShortSleepExposureSource(config: config),
            HighStressExposureSource(config: config),
            PressureDropExposureSource(),
            CyclePhaseExposureSource(config: config, timeZone: tz),
        ]
        var exposures: [ExposureKey: [ExposureOccurrence]] = [:]
        for s in sources {
            for occ in s.occurrences(from: events) { exposures[occ.key, default: []].append(occ) }
        }
        var outcomes: [OutcomeKey: [OutcomeOccurrence]] = [:]
        for occ in OutcomeSource(config: config).occurrences(from: events) {
            outcomes[occ.key, default: []].append(occ)
        }
        return (exposures, outcomes)
    }

    // Illness windows as day-sets (always a confounder). Each illness event's day.
    func illnessDays(_ events: [HealthEvent]) -> Set<Date> {
        let cal = Self.utc
        return Set(events.filter { $0.category == .illness }.map { cal.startOfDay(for: $0.timestamp) })
    }

    public func recompute(asOf now: Date) async throws -> RecomputeReport {
        let cal = Self.utc
        let events = try await eventStore.events(
            in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        guard !events.isEmpty else { return RecomputeReport(pairsEvaluated: 0, relationshipsUpserted: 0, relationshipsDecayed: 0) }

        let (exposures, outcomes) = extract(events)
        let times = events.map(\.timestamp)
        let observation = DateInterval(start: times.min()!, end: times.max()!)

        // Day-sets for confounder analysis: every exposure key + illness (always).
        var daySets: [ExposureKey: Set<Date>] = [:]
        for (key, occ) in exposures { daySets[key] = Set(occ.map { cal.startOfDay(for: $0.timestamp) }) }
        let illness = illnessDays(events)

        let candidates = CandidateGenerator(config: config)
            .candidates(exposuresByKey: exposures, outcomesByKey: outcomes)
        let analyzer = CooccurrenceAnalyzer(config: config)
        let confounder = ConfounderAnalyzer()
        let scorer = ConfidenceScorer(config: config)
        let classifier = RelationshipClassifier(config: config)

        var computed: [String: Relationship] = [:]   // by edgeKey
        for cand in candidates {
            guard let exp = exposures[cand.exposure], let out = outcomes[cand.outcome] else { continue }
            let window = config.lagWindow(for: cand.exposure)
            guard let stats = analyzer.analyze(exposure: exp, outcome: out, window: window, observation: observation)
            else { continue }

            // Others = every other exposure's day-set (cycle-phase keys are already
            // in daySets, so they flow in automatically), plus illness (always).
            var others = daySets.filter { $0.key != cand.exposure }
            if !illness.isEmpty { others[Self.illnessConfounderKey] = illness }
            let (penalty, _) = confounder.penalty(targetDays: daySets[cand.exposure] ?? [], others: others)

            let conf = scorer.confidence(stats: stats, confounderPenalty: penalty, now: now)
            guard let edge = classifier.classify(stats: stats, confidence: conf, now: now) else { continue }

            let key = EdgeIdentity.edgeKey(from: cand.exposure, to: cand.outcome, type: edge.type)
            let cols = EdgeIdentity.columns(from: cand.exposure, to: cand.outcome)
            let rel = Relationship(
                fromObjectID: cols.fromObjectID, fromCategory: cols.fromCategory,
                toCategory: cols.toCategory, type: edge.type,
                evidenceCount: stats.followCount, contradictionCount: stats.missCount,
                confidence: conf, strength: stats.avgEffect, lagHours: stats.medianLagHours,
                firstSeen: now, lastSeen: stats.lastExposure, lastRecomputed: now,
                status: edge.status, edgeKey: key, toSubtype: cols.toSubtype)
            computed[key] = rel
        }

        // Idempotent upsert against existing edges.
        let existing = try await relationshipStore.all()
        let existingByKey = Dictionary(existing.compactMap { r in r.edgeKey.map { ($0, r) } },
                                       uniquingKeysWith: { a, _ in a })
        var toSave: [Relationship] = []
        var decayedCount = 0

        for (key, fresh) in computed {
            if let prior = existingByKey[key] {
                if prior.status == .userDismissed { continue }         // preserve dismissal
                var merged = fresh
                merged.id = prior.id
                merged.firstSeen = prior.firstSeen                      // never bump
                toSave.append(merged)
            } else {
                toSave.append(fresh)                                    // firstSeen == now
            }
        }
        // Reconcile disappeared edges → decayed (unless dismissed).
        for prior in existing {
            guard let key = prior.edgeKey, computed[key] == nil,
                  prior.status != .userDismissed, prior.status != .decayed else { continue }
            var d = prior; d.status = .decayed; d.lastRecomputed = now
            toSave.append(d); decayedCount += 1
        }

        try await relationshipStore.save(toSave)
        return RecomputeReport(pairsEvaluated: candidates.count,
                               relationshipsUpserted: computed.count,
                               relationshipsDecayed: decayedCount)
    }
}
```

> **Implementer note:** the confounder pool for each candidate is every *other* exposure's day-set (cycle-phase keys included automatically, since they're in `daySets`) plus illness days under the reserved `illnessConfounderKey`. That key uses a fixed UUID so it's deterministic and never collides with a real object, and it never appears in `exposuresByKey` so `CandidateGenerator` never mines illness as an exposure. If the fixed-UUID key reads awkwardly, an equivalent cleanup is a dedicated `ExposureKey` case (e.g. `.illnessConfounder`) in `ExposureModel.swift` — behavior must stay identical.

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter EvidenceEngineTests`
Expected: PASS (all three tests). If `minesDairyBloatingAsActiveTrigger` fails on confidence, note it — weights get tuned in Task 16; for this hand-built strong signal the default weights should already clear activation.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEngineTests.swift
git commit -m "feat(core): EvidenceEngine.recompute — pipeline orchestration + idempotent upsert"
```

---

## Task 14: EvidenceEngine.evidence(for:) — on-demand drill-down

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEngineTests.swift`

**Interfaces:**
- Produces: `struct RelationshipEvidence { let relationshipID: UUID; let exposures: [ExposurePairDetail]; let followCount: Int; let missCount: Int; let confounders: [ExposureKey] }`; `func evidence(for relationship: Relationship, asOf now: Date) async throws -> RelationshipEvidence`.
- Reuses the same extraction + `CooccurrenceAnalyzer` for the single parsed pair, so the itemized counts equal the stored `evidenceCount`/`contradictionCount`; also recomputes the confounder list (design doc §3).

- [ ] **Step 1: Write the failing test** — append to `EvidenceEngineTests.swift`:

```swift
@Test func evidenceForParityWithStoredCounts() async throws {
    let db = try AppDatabase.inMemory()
    try await seedDairyBloating(into: db)
    let engine = EvidenceEngine(database: db)
    _ = try await engine.recompute(asOf: now)
    let rel = try await GRDBRelationshipStore(database: db).all().first { $0.toSubtype == "bloating" }!
    let ev = try await engine.evidence(for: rel, asOf: now)
    #expect(ev.followCount == rel.evidenceCount)
    #expect(ev.missCount == rel.contradictionCount)
    #expect(ev.exposures.count == rel.evidenceCount + rel.contradictionCount)
    #expect(ev.exposures.contains { $0.outcomeFollowed })
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter EvidenceEngineTests`
Expected: FAIL — `evidence(for:)` not defined.

- [ ] **Step 3: Add to `EvidenceEngine.swift`:**

```swift
public struct RelationshipEvidence: Sendable, Equatable {
    public let relationshipID: UUID
    public let exposures: [ExposurePairDetail]
    public let followCount: Int
    public let missCount: Int
    public let confounders: [ExposureKey]   // exposures that shadow this one (design doc §3)
}

extension EvidenceEngine {
    public func evidence(for relationship: Relationship, asOf now: Date) async throws -> RelationshipEvidence {
        func empty() -> RelationshipEvidence {
            RelationshipEvidence(relationshipID: relationship.id, exposures: [],
                                 followCount: 0, missCount: 0, confounders: [])
        }
        guard let (expKey, outKey) = EdgeIdentity.parse(relationship) else { return empty() }
        let events = try await eventStore.events(
            in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        let (exposures, outcomes) = extract(events)
        guard let exp = exposures[expKey], let out = outcomes[outKey], !exp.isEmpty else { return empty() }
        let times = events.map(\.timestamp)
        guard let lo = times.min(), let hi = times.max() else { return empty() }
        let window = config.lagWindow(for: expKey)
        guard let stats = CooccurrenceAnalyzer(config: config)
            .analyze(exposure: exp, outcome: out, window: window,
                     observation: DateInterval(start: lo, end: hi)) else { return empty() }

        // Recompute the confounder set for this one edge (same logic as recompute()).
        let cal = Self.utc
        var daySets: [ExposureKey: Set<Date>] = [:]
        for (key, occ) in exposures { daySets[key] = Set(occ.map { cal.startOfDay(for: $0.timestamp) }) }
        var others = daySets.filter { $0.key != expKey }
        let illness = illnessDays(events)
        if !illness.isEmpty { others[Self.illnessConfounderKey] = illness }
        let (_, confounders) = ConfounderAnalyzer().penalty(targetDays: daySets[expKey] ?? [], others: others)

        return RelationshipEvidence(relationshipID: relationship.id, exposures: stats.pairs,
                                    followCount: stats.followCount, missCount: stats.missCount,
                                    confounders: confounders)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter EvidenceEngineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceEngine.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEngineTests.swift
git commit -m "feat(core): EvidenceEngine.evidence(for:) — on-demand drill-down, parity with summary"
```

---

## Task 15: Extend the synthetic harness — derived patterns + scenarios

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticDataTests.swift`

**Interfaces:**
- Produces: extend `SyntheticConfig` with optional scenario toggles; the generator emits **sleep**, **stress**, **environment(pressureDrop)**, and **cycle** events, plus a protective-, confounder-, and null-effect scenario. Existing object→symptom planting and the existing tests keep working (new fields default to empty/off).

- [ ] **Step 1: Write the failing test** — append to `SyntheticDataTests.swift`:

```swift
@Test func emitsDerivedExposureEvents() {
    var cfg = config
    cfg.derivedScenarios = DerivedScenarios(
        shortSleepFatigue: true, pressureHeadache: true, stressSymptom: true, lutealSymptom: true)
    let data = SyntheticDataGenerator.generate(config: cfg)
    #expect(data.events.contains { $0.category == .sleep && $0.endTimestamp != nil })
    #expect(data.events.contains { $0.category == .environment && $0.subtype == "pressureDrop" })
    #expect(data.events.contains { $0.category == .stress && ($0.value ?? 0) >= 7 })
    #expect(data.events.contains { $0.category == .cycle && $0.subtype == "periodStart" })
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd HealthGraphCore && swift test --filter SyntheticDataTests`
Expected: FAIL — `derivedScenarios` / `DerivedScenarios` not defined.

- [ ] **Step 3: Extend `SyntheticDataGenerator.swift`.** Add the scenarios struct and fields, and emit events. Add near the top:

```swift
public struct DerivedScenarios: Sendable {
    public var shortSleepFatigue = false     // <6h nights → fatigue next day
    public var pressureHeadache = false      // pressureDrop → headache
    public var stressSymptom = false         // high stress → tension
    public var lutealSymptom = false         // luteal window → cramps
    public var protectiveSupplement = false  // magnesium → reduced headache base rate
    public var confounderPair = false        // coffee always with dairy (>60%)
    public var nullEffectSupplement = false  // vitaminX, ≥20 exposures/≥90d, no effect
    public init() {}
}
```

Add to `SyntheticConfig` a stored `public var derivedScenarios = DerivedScenarios()` (give it a default so existing call-sites and the `init` still compile — add the parameter with a default at the end of `init`).

Then in `generate`, after the existing per-day loop body (inside `for day in 0..<config.days`), append emission blocks. Use the existing `rng`, `dayStart`, `tz` locals:

```swift
            let s = config.derivedScenarios
            // Short sleep → fatigue (about half the nights are short).
            if s.shortSleepFatigue {
                let short = Double.random(in: 0..<1, using: &rng) < 0.5
                let hours = short ? Double.random(in: 4.0..<5.5, using: &rng)
                                  : Double.random(in: 7.0..<8.5, using: &rng)
                let bed = dayStart.addingTimeInterval(-2 * 3600)         // ~22:00 previous
                let wake = bed.addingTimeInterval(hours * 3600)
                events.append(HealthEvent(timestamp: bed, timezoneID: tz, endTimestamp: wake,
                                          category: .sleep, subtype: "asleepCore", source: .healthKit))
                if short && Double.random(in: 0..<1, using: &rng) < 0.7 {
                    events.append(HealthEvent(timestamp: wake.addingTimeInterval(3 * 3600),
                                              timezoneID: tz, category: .symptom, subtype: "fatigue",
                                              value: Double(Int.random(in: 3...7, using: &rng)), source: .manual))
                }
            }
            // Pressure drop → headache.
            if s.pressureHeadache, Double.random(in: 0..<1, using: &rng) < 0.3 {
                let t = dayStart.addingTimeInterval(8 * 3600)
                events.append(HealthEvent(timestamp: t, timezoneID: tz, category: .environment,
                                          subtype: "pressureDrop", value: 9, unit: "hPa", source: .weatherAPI))
                if Double.random(in: 0..<1, using: &rng) < 0.7 {
                    events.append(HealthEvent(timestamp: t.addingTimeInterval(5 * 3600), timezoneID: tz,
                                              category: .symptom, subtype: "headache",
                                              value: Double(Int.random(in: 4...8, using: &rng)), source: .manual))
                }
            }
            // High stress → tension.
            if s.stressSymptom, Double.random(in: 0..<1, using: &rng) < 0.4 {
                let t = dayStart.addingTimeInterval(14 * 3600)
                events.append(HealthEvent(timestamp: t, timezoneID: tz, category: .stress,
                                          value: Double(Int.random(in: 7...10, using: &rng)), source: .manual))
                if Double.random(in: 0..<1, using: &rng) < 0.65 {
                    events.append(HealthEvent(timestamp: t.addingTimeInterval(3 * 3600), timezoneID: tz,
                                              category: .symptom, subtype: "tension",
                                              value: Double(Int.random(in: 3...7, using: &rng)), source: .manual))
                }
            }
```

And AFTER the day loop (cycle events span multiple days), append:

```swift
        // Menstrual cycles every 28 days; cramps concentrated in the luteal window.
        if config.derivedScenarios.lutealSymptom {
            var day = 0
            while day < config.days {
                let start = config.startDate.addingTimeInterval(Double(day) * 86_400)
                events.append(HealthEvent(timestamp: start, timezoneID: tz, category: .cycle,
                                          subtype: "periodStart", source: .manual))
                for back in 1...5 {   // luteal = 5 days before the next start
                    if day + 28 - back < config.days,
                       Double.random(in: 0..<1, using: &rng) < 0.6 {
                        let t = config.startDate.addingTimeInterval(Double(day + 28 - back) * 86_400 + 10 * 3600)
                        events.append(HealthEvent(timestamp: t, timezoneID: tz, category: .symptom,
                                                  subtype: "cramps", value: Double(Int.random(in: 3...7, using: &rng)),
                                                  source: .manual))
                    }
                }
                day += 28
            }
        }
```

- [ ] **Step 3b: Create the scenario objects.** Right after the existing `noiseObjects` loop (before the day loop), add:

```swift
        let scenarios = config.derivedScenarios
        var magnesium: HealthObject?, espresso: HealthObject?, croissant: HealthObject?, vitaminX: HealthObject?
        if scenarios.protectiveSupplement {
            let o = HealthObject(kind: .supplement, name: "magnesium"); magnesium = o; objects.append(o)
        }
        if scenarios.confounderPair {
            let e = HealthObject(kind: .food, name: "espresso"); espresso = e; objects.append(e)
            let c = HealthObject(kind: .food, name: "croissant"); croissant = c; objects.append(c)
        }
        if scenarios.nullEffectSupplement {
            let o = HealthObject(kind: .supplement, name: "vitaminX"); vitaminX = o; objects.append(o)
        }
```

- [ ] **Step 3c: Emit the three scenarios inside the day loop** (alongside the short-sleep/pressure/stress blocks, using the same `s`, `dayStart`, `tz`, `rng`):

```swift
            // Protective: magnesium ~half the days; migraine rare on magnesium days, common off.
            if s.protectiveSupplement {
                let onMag = Double.random(in: 0..<1, using: &rng) < 0.5
                if onMag {
                    events.append(HealthEvent(timestamp: dayStart.addingTimeInterval(8 * 3600), timezoneID: tz,
                                              category: .supplement, subtype: "magnesium",
                                              objectID: magnesium?.id, source: .manual))
                }
                if Double.random(in: 0..<1, using: &rng) < (onMag ? 0.05 : 0.30) {
                    events.append(HealthEvent(timestamp: dayStart.addingTimeInterval(16 * 3600), timezoneID: tz,
                                              category: .symptom, subtype: "migraine",
                                              value: Double(Int.random(in: 4...8, using: &rng)), source: .manual))
                }
            }
            // Confounder: espresso & croissant ALWAYS logged together → jitters. Not separable.
            if s.confounderPair, Double.random(in: 0..<1, using: &rng) < 0.5 {
                let t = dayStart.addingTimeInterval(7 * 3600)
                events.append(HealthEvent(timestamp: t, timezoneID: tz, category: .food,
                                          subtype: "espresso", objectID: espresso?.id, source: .manual))
                events.append(HealthEvent(timestamp: t.addingTimeInterval(300), timezoneID: tz, category: .food,
                                          subtype: "croissant", objectID: croissant?.id, source: .manual))
                if Double.random(in: 0..<1, using: &rng) < 0.7 {
                    events.append(HealthEvent(timestamp: t.addingTimeInterval(2 * 3600), timezoneID: tz,
                                              category: .symptom, subtype: "jitters",
                                              value: Double(Int.random(in: 3...7, using: &rng)), source: .manual))
                }
            }
            // Null effect: vitaminX taken ~half the days, influences nothing (balanced for a clean base rate).
            if s.nullEffectSupplement, Double.random(in: 0..<1, using: &rng) < 0.5 {
                events.append(HealthEvent(timestamp: dayStart.addingTimeInterval(12 * 3600), timezoneID: tz,
                                          category: .supplement, subtype: "vitaminX",
                                          objectID: vitaminX?.id, source: .manual))
            }
```

- [ ] **Step 4: Ensure final sort covers post-loop events.** Confirm the `events.sort { $0.timestamp < $1.timestamp }` at the end of `generate` runs after ALL emission (the post-loop cycle block must be emitted before that sort, or add a second `events.sort` after it).

- [ ] **Step 5: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter SyntheticDataTests`
Expected: PASS (new test + the two existing tests still green).

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticDataTests.swift
git commit -m "feat(core): synthetic harness — derived-exposure + protective/confounder/null-effect scenarios"
```

---

## Task 16: Acceptance suite + weight tuning

**Files:**
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEngineAcceptanceTests.swift`
- Possibly modify: `HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift` (tune `w1…w5`, `bias` so the suite passes with margin)

**Interfaces:**
- Consumes: extended harness (Task 15), `EvidenceEngine`.
- This is the §8 acceptance bar. Where a test fails on scoring, **tune `EvidenceConfig.default` weights, never the algorithm.**

- [ ] **Step 1: Write the acceptance tests** — create `EvidenceEngineAcceptanceTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct EvidenceEngineAcceptanceTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    func fullConfig() -> SyntheticConfig {
        var cfg = SyntheticConfig(
            startDate: now.addingTimeInterval(-400 * 86_400), days: 400, seed: 42,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food,
                                      outcomeSubtype: "bloating", lagHours: 8, lagJitterHours: 3,
                                      followProbability: 0.7, exposureProbabilityPerDay: 0.5)],
            outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 1...3)
        cfg.derivedScenarios = DerivedScenarios(
            shortSleepFatigue: true, pressureHeadache: true, stressSymptom: true,
            lutealSymptom: true, protectiveSupplement: true, confounderPair: true,
            nullEffectSupplement: true)
        return cfg
    }

    func minedDB() async throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try await SyntheticDataGenerator.generate(config: fullConfig()).insert(into: db)
        _ = try await EvidenceEngine(database: db).recompute(asOf: now)
        return db
    }

    @Test func recallAllPlantedPatterns() async throws {
        let rels = try await GRDBRelationshipStore(database: minedDB()).relationships(status: .active)
        let outcomes = Set(rels.map { $0.toSubtype ?? "" })
        #expect(outcomes.contains("bloating"))   // object trigger
        #expect(outcomes.contains("fatigue"))    // short-sleep
        #expect(outcomes.contains("headache"))   // pressure-drop
        #expect(outcomes.contains("tension"))    // stress
        #expect(outcomes.contains("cramps"))     // luteal
        #expect(rels.contains { $0.type == .improves })  // protective supplement
    }

    @Test func precisionRejectsNoise() async throws {
        let rels = try await GRDBRelationshipStore(database: minedDB()).relationships(status: .active)
        // Noise foods (rice/chicken/…) are logged daily but drive nothing, so no
        // active edge should point at an outcome we never planted.
        let planted: Set<String> = ["bloating", "fatigue", "headache", "tension", "cramps", "jitters", "migraine"]
        #expect(rels.allSatisfy { planted.contains($0.toSubtype ?? "") })
    }

    @Test func confounderIsRecordedForInseparablePair() async throws {
        let db = try await minedDB()
        let espresso = try await GRDBObjectStore(database: db)
            .findOrCreate(name: "espresso", kind: .food, metadata: nil)   // returns the existing object
        let edges = try await GRDBRelationshipStore(database: db).relationships(fromObjectID: espresso.id)
        guard let edge = edges.first(where: { $0.toSubtype == "jitters" }) else {
            Issue.record("expected an espresso→jitters edge"); return
        }
        let ev = try await EvidenceEngine(database: db).evidence(for: edge, asOf: now)
        #expect(!ev.confounders.isEmpty)   // croissant always co-occurs → shadows espresso
    }

    @Test func confirmedNoEffectForNullSupplement() async throws {
        let rels = try await GRDBRelationshipStore(database: minedDB()).all()
        #expect(rels.contains { $0.status == .confirmedNoEffect })
    }

    @Test func observationalCeilingNeverExceeded() async throws {
        let rels = try await GRDBRelationshipStore(database: minedDB()).all()
        #expect(rels.allSatisfy { $0.confidence <= 0.75 + 1e-9 })
    }

    @Test func deterministicAcrossRuns() async throws {
        func keys() async throws -> Set<String> {
            let db = try AppDatabase.inMemory()
            try await SyntheticDataGenerator.generate(config: fullConfig()).insert(into: db)
            _ = try await EvidenceEngine(database: db).recompute(asOf: now)
            return Set(try await GRDBRelationshipStore(database: db).all().compactMap(\.edgeKey))
        }
        let a = try await keys(); let b = try await keys()
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run the suite**

Run: `cd HealthGraphCore && swift test --filter EvidenceEngineAcceptanceTests`
Expected: initially some may FAIL on recall/precision margins.

- [ ] **Step 3: Tune weights until green.** Adjust `EvidenceConfig` defaults (`w1…w5`, `bias`, and if needed `activationThreshold`) so every acceptance test passes with margin: planted patterns land comfortably `.active`, noise stays below activation, the null-effect supplement reaches `confirmedNoEffect`, and nothing exceeds 0.75. Change ONLY config values, re-running after each change:

Run: `cd HealthGraphCore && swift test --filter EvidenceEngineAcceptanceTests`
Expected: PASS (all).

- [ ] **Step 4: Full regression**

Run: `cd HealthGraphCore && swift test`
Expected: PASS (entire package — no stage test regressed from tuning).

- [ ] **Step 5: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEngineAcceptanceTests.swift \
        HealthGraphCore/Sources/HealthGraphCore/Evidence/EvidenceConfig.swift
git commit -m "test(core): Evidence Engine acceptance suite (recall/precision/noEffect/ceiling/determinism) + tuned weights"
```

---

## Task 17: Performance guard

**Files:**
- Create: `HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEnginePerformanceTests.swift`

**Interfaces:**
- Consumes: harness + engine. Asserts a full recompute over a large corpus completes within a loose bound (CI-safe; not the on-device 30s budget, but a regression tripwire).

- [ ] **Step 1: Write the test** — create `EvidenceEnginePerformanceTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct EvidenceEnginePerformanceTests {
    @Test func recomputeOverLargeCorpusIsBounded() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var cfg = SyntheticConfig(
            startDate: now.addingTimeInterval(-1000 * 86_400), days: 1000, seed: 7,
            patterns: [PlantedPattern(exposureName: "dairy", exposureCategory: .food,
                                      outcomeSubtype: "bloating", lagHours: 8, lagJitterHours: 3,
                                      followProbability: 0.7, exposureProbabilityPerDay: 0.6)],
            outcomeBaseRatePerDay: 0.05, noiseFoodsPerDay: 5...12)
        cfg.derivedScenarios = DerivedScenarios(shortSleepFatigue: true, pressureHeadache: true,
                                                stressSymptom: true, lutealSymptom: true)
        let db = try AppDatabase.inMemory()
        try await SyntheticDataGenerator.generate(config: cfg).insert(into: db)
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            _ = try await EvidenceEngine(database: db).recompute(asOf: now)
        }
        // Loose CI tripwire — the on-device budget is 30s at 100k events; this
        // catches an accidental O(n²) blow-up, not micro-perf.
        #expect(elapsed < .seconds(60))
    }
}
```

- [ ] **Step 2: Run to verify pass**

Run: `cd HealthGraphCore && swift test --filter EvidenceEnginePerformanceTests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add HealthGraphCore/Tests/HealthGraphCoreTests/EvidenceEnginePerformanceTests.swift
git commit -m "test(core): Evidence Engine performance tripwire over a large synthetic corpus"
```

- [ ] **Step 4: Final full regression**

Run: `cd HealthGraphCore && swift test`
Expected: PASS (whole package).

---

## Definition of Done

- `swift test` passes for the whole `HealthGraphCore` package.
- The engine mines the full §7 exposure set (objects + short-sleep + high-stress + pressure-drop + cycle-phase) into `relationships`, with `edgeKey` identity and idempotent upsert preserving `userDismissed` + `firstSeen`.
- `evidence(for:)` returns per-exposure detail whose counts match the stored summary.
- The acceptance suite (recall across all planted kinds + both directions, precision, confirmedNoEffect, 0.75 ceiling, determinism) is green, with weights tuned in `EvidenceConfig.default`.
- No UI, scheduling, explanation copy, or surfacing cap — those are Phase 2B.
