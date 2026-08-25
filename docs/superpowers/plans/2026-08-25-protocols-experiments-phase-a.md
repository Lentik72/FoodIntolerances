# Protocols & Experiments — Phase A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an experiment, run it, end it, and see a result that says only what can honestly be said — entirely within the Health tab.

**Architecture:** An `Experiment` row declares intervention, target outcome, shape and window. Adherence is computed from the dose events the capture sheet already writes — the experiment stores no logging of its own. The verdict **delegates to the evidence engine**: the experiment asks about its declared pair and reports what comes back, so there is no second statistics path to drift out of sync. Copy selection is pure presentation over a result type, testable without a view.

**Tech Stack:** Swift 6, Swift Testing, GRDB, package `HealthGraphCore`, app target `Food Intolerances`.

## Global Constraints

- **Never compute statistics inside this feature.** The verdict comes from the engine's existing relationship for the declared pair. Do not add thresholds, do not reimplement significance, effect size or stability, and do not modify `EvidenceConfig`.
- **A `course` never produces a verdict**, regardless of dose count. Fourteen consecutive days during one illness cannot be separated from recovering anyway.
- **The shape is declared at creation, never inferred from events.**
- **"No detectable effect" must never render as "it doesn't work"** — anywhere, in any branch.
- **Every result whose intervention is `.medication` carries two lines**: the prescriber line, and the statement that the app cannot see organ-level effects. Both are required, not conditional on the outcome.
- An experiment stores no dose logging of its own; adherence is derived from `health_events`.
- Package tests: `swift test --package-path HealthGraphCore`. App tests need `-parallel-testing-enabled NO`.
- Every task ends with a commit.

**Scope note carried from the spec:** the spec allows a target outcome of "a symptom subtype, or mood". **Phase A supports symptom subtypes only.** Mood targets need the engine's `lowMood`/`goodMood` outcome keys rather than a subtype string, which is a second mapping path through result derivation; it is a Phase B addition. `Experiment.outcomeSubtype` is a plain symptom subtype throughout this plan.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `HealthGraphCore/Sources/HealthGraphCore/Models/Experiment.swift` | The record + its enums | 1 |
| `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift` | Migration v8 | 1 |
| `HealthGraphCore/Sources/HealthGraphCore/Database/ExperimentStore.swift` | Persistence | 1 |
| `HealthGraphCore/Sources/HealthGraphCore/Experiments/ExperimentAdherence.swift` | Adherence from events | 2 |
| `HealthGraphCore/Sources/HealthGraphCore/Experiments/ExperimentResult.swift` | Result derivation via the engine | 3 |
| `Views/HealthOS/Experiments/ExperimentPresentation.swift` | The claim ladder | 4 |
| `Views/HealthOS/Experiments/ExperimentWorkflow.swift` | Lifecycle transitions | 5 |
| `Views/HealthOS/Experiments/ExperimentViewState.swift` | Screen state + guard | 5 |
| `Views/HealthOS/Experiments/ExperimentsView.swift` + `ExperimentCreateView.swift` | Health-tab surfaces | 6 |
| `Views/HealthOS/Health/HealthTabView.swift` | Replace the "Soon" row | 6 |

---

## Task 1: The record, the table, the store

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Models/Experiment.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift` (append migration v8 after v7)
- Create: `HealthGraphCore/Sources/HealthGraphCore/Database/ExperimentStore.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExperimentStoreTests.swift`

**Interfaces:**
- Produces: `Experiment`, `ExperimentShape`, `ExperimentStatus`, `GRDBExperimentStore` with `save(_:)`, `all()`, `experiments(status:)`, `experiment(id:)`. Every later task consumes these.

- [ ] **Step 1: Write the failing tests**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/ExperimentStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct ExperimentStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func experiment(status: ExperimentStatus = .running,
                            shape: ExperimentShape = .repeated) -> Experiment {
        Experiment(interventionObjectID: UUID(), outcomeSubtype: "migraine", shape: shape,
                   startedAt: t0, intendedEndAt: t0.addingTimeInterval(21 * 86_400),
                   status: status, createdAt: t0)
    }

    @Test func roundTripsThroughTheDatabase() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBExperimentStore(database: db)
        let e = experiment()
        try await store.save(e)
        let back = try await store.experiment(id: e.id)
        #expect(back == e)
    }

    @Test func filtersByStatus() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBExperimentStore(database: db)
        try await store.save(experiment(status: .running))
        try await store.save(experiment(status: .completed))
        try await store.save(experiment(status: .abandoned))
        #expect(try await store.experiments(status: .running).count == 1)
        #expect(try await store.all().count == 3)
    }

    @Test func theShapeIsStoredNotInferred() async throws {
        // The whole antibiotic case rests on this column: a course and a repeated
        // intake can look identical in the events, so the declaration must survive
        // the round trip rather than being re-derived later.
        let db = try AppDatabase.inMemory()
        let store = GRDBExperimentStore(database: db)
        let course = experiment(shape: .course)
        try await store.save(course)
        #expect(try await store.experiment(id: course.id)?.shape == .course)
    }

    @Test func migrationAddsTheTableToAnExistingDatabase() async throws {
        // v8 must apply to a database created before it existed, not only to a
        // fresh one — a migration that only works on new installs is not one.
        let db = try AppDatabase.inMemory()
        try await GRDBEventStore(database: db).save([
            HealthEvent(timestamp: t0, category: .symptom, subtype: "migraine",
                        value: 5, unit: "severity", source: .manual)
        ])
        let store = GRDBExperimentStore(database: db)
        try await store.save(experiment())
        #expect(try await store.all().count == 1)
        #expect(try await GRDBEventStore(database: db).count() == 1)   // existing data intact
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path HealthGraphCore --filter ExperimentStoreTests 2>&1 | tail -6`
Expected: FAIL — `cannot find 'Experiment' in scope`.

- [ ] **Step 3: The record**

Create `HealthGraphCore/Sources/HealthGraphCore/Models/Experiment.swift`:

```swift
import Foundation
import GRDB

/// Fixed-run versus ongoing intake. DECLARED at creation and never inferred: a
/// fortnight of consecutive doses could be an antibiotic course or the start of
/// a daily habit, and the events cannot tell them apart. Guessing wrong is how a
/// single course ends up with a fabricated verdict.
public enum ExperimentShape: String, Codable, Sendable, CaseIterable {
    case repeated, course
}

public enum ExperimentStatus: String, Codable, Sendable, CaseIterable {
    case running, completed, abandoned
}

/// A declared question with a window. Stores no logging of its own — adherence is
/// derived from the dose events the capture sheet already writes, so the
/// experiment can never disagree with the Timeline.
public struct Experiment: Codable, Identifiable, Equatable,
                          FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "experiments"

    public var id: UUID
    public var interventionObjectID: UUID
    /// A symptom subtype. Mood targets are Phase B: they need the engine's
    /// lowMood/goodMood outcome keys rather than a subtype string.
    public var outcomeSubtype: String
    public var shape: ExperimentShape
    public var startedAt: Date
    public var intendedEndAt: Date
    public var endedAt: Date?
    public var status: ExperimentStatus
    /// Unused in Phase A, stored from the start so Phase B does not need a
    /// migration to record it. A reminded regimen and an unreminded one are
    /// different evidence, and the record should say which it was.
    public var remindersEnabled: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), interventionObjectID: UUID, outcomeSubtype: String,
                shape: ExperimentShape, startedAt: Date, intendedEndAt: Date,
                endedAt: Date? = nil, status: ExperimentStatus = .running,
                remindersEnabled: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.interventionObjectID = interventionObjectID
        self.outcomeSubtype = outcomeSubtype
        self.shape = shape
        self.startedAt = startedAt
        self.intendedEndAt = intendedEndAt
        self.endedAt = endedAt
        self.status = status
        self.remindersEnabled = remindersEnabled
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Migration v8**

In `AppDatabase.swift`, append after the `v7` block (do not modify v1–v7):

```swift
        migrator.registerMigration("v8") { db in
            // Protocols & experiments. A declared question with a window; no dose
            // logging of its own, so nothing here duplicates health_events.
            try db.create(table: "experiments") { t in
                t.primaryKey("id", .text).notNull()
                t.column("interventionObjectID", .text).notNull()
                t.column("outcomeSubtype", .text).notNull()
                t.column("shape", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("intendedEndAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("status", .text).notNull()
                t.column("remindersEnabled", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }
            try db.execute(sql: "CREATE INDEX idx_experiments_status ON experiments(status)")
        }
```

- [ ] **Step 5: The store**

Create `HealthGraphCore/Sources/HealthGraphCore/Database/ExperimentStore.swift`, following `GRDBRelationshipStore`'s shape exactly:

```swift
import Foundation
import GRDB

public protocol ExperimentStore {
    func save(_ experiment: Experiment) async throws
    func experiment(id: UUID) async throws -> Experiment?
    func experiments(status: ExperimentStatus) async throws -> [Experiment]
    func all() async throws -> [Experiment]
}

public struct GRDBExperimentStore: ExperimentStore {
    let dbWriter: any DatabaseWriter

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    public func save(_ experiment: Experiment) async throws {
        try await dbWriter.write { db in try experiment.save(db) }
    }

    public func experiment(id: UUID) async throws -> Experiment? {
        try await dbWriter.read { db in try Experiment.fetchOne(db, key: id.uuidString) }
    }

    public func experiments(status: ExperimentStatus) async throws -> [Experiment] {
        try await dbWriter.read { db in
            try Experiment.filter(Column("status") == status.rawValue)
                .order(Column("startedAt").desc).fetchAll(db)
        }
    }

    public func all() async throws -> [Experiment] {
        try await dbWriter.read { db in
            try Experiment.order(Column("startedAt").desc).fetchAll(db)
        }
    }
}
```

**If `fetchOne(db, key:)` does not resolve the UUID primary key** — GRDB stores it per the record's encoding — use `Experiment.filter(Column("id") == id.uuidString).fetchOne(db)` instead, and check how `GRDBRelationshipStore.relationship(id:)` does it rather than guessing.

- [ ] **Step 6: Run the tests, then the whole package suite**

Run: `swift test --package-path HealthGraphCore --filter ExperimentStoreTests 2>&1 | tail -6`
Expected: 4 pass.

Run: `swift test --package-path HealthGraphCore 2>&1 | tail -3`
Expected: all pass. **Watch the migration tests in particular** — `AppDatabaseTests` and `EnvProvenanceMigrationTests` exercise the migrator, and a malformed v8 breaks every database in the suite, not just this table.

- [ ] **Step 7: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Models/Experiment.swift \
        HealthGraphCore/Sources/HealthGraphCore/Database/ExperimentStore.swift \
        HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExperimentStoreTests.swift
git commit -m "feat(experiments): experiment record, migration v8, and store"
```

---

## Task 2: Adherence, derived from the events

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Experiments/ExperimentAdherence.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExperimentAdherenceTests.swift`

**Interfaces:**
- Consumes: `Experiment` from Task 1.
- Produces: `ExperimentAdherence` (`doseDays`, `doses`, `windowDays`) and `ExperimentAdherence.measure(experiment:events:calendar:)`. Tasks 3, 4 and 6 consume it.

**Why days and not doses:** "you logged it on 18 of these 21 days" is the honest adherence statement. Raw dose count would let three doses in one day read as three days of adherence.

- [ ] **Step 1: Write the failing tests**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/ExperimentAdherenceTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct ExperimentAdherenceTests {
    /// EXACTLY midnight UTC (1_749_945_600 = 86_400 x 20_254). This matters: the
    /// `hour:` parameter below is an offset from t0, so if t0 were mid-afternoon
    /// — as 1_750_000_000 is, at 15:06 UTC — then `hour: 14` would land on the
    /// NEXT day and the distinct-day expectations would be silently wrong.
    let t0 = Date(timeIntervalSince1970: 1_749_945_600)
    let utc = TimeZone(identifier: "UTC")!
    let objectID = UUID()

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c
    }

    private func exp(days: Int = 21) -> Experiment {
        Experiment(interventionObjectID: objectID, outcomeSubtype: "migraine", shape: .repeated,
                   startedAt: t0, intendedEndAt: t0.addingTimeInterval(Double(days) * 86_400),
                   createdAt: t0)
    }

    private func dose(dayOffset: Double, hour: Double = 9, objectID: UUID? = nil) -> HealthEvent {
        HealthEvent(timestamp: t0.addingTimeInterval(dayOffset * 86_400 + hour * 3600),
                    timezoneID: "UTC", category: .supplement, subtype: "Magnesium",
                    objectID: objectID ?? self.objectID, value: 200, unit: "mg", source: .manual)
    }

    @Test func countsDistinctDaysNotRawDoses() {
        // Three doses in one day is one day of adherence. Counting doses would let
        // a single heavy day read as three days of a regimen.
        let a = ExperimentAdherence.measure(
            experiment: exp(),
            events: [dose(dayOffset: 0, hour: 8), dose(dayOffset: 0, hour: 14),
                     dose(dayOffset: 0, hour: 20), dose(dayOffset: 1)],
            calendar: cal)
        #expect(a.doseDays == 2)
        #expect(a.doses == 4)
        #expect(a.windowDays == 21)
    }

    @Test func ignoresDosesOfOtherThings() {
        let other = UUID()
        let a = ExperimentAdherence.measure(
            experiment: exp(),
            events: [dose(dayOffset: 0), dose(dayOffset: 1, objectID: other)],
            calendar: cal)
        #expect(a.doseDays == 1)
    }

    @Test func ignoresDosesOutsideTheWindow() {
        let a = ExperimentAdherence.measure(
            experiment: exp(days: 5),
            events: [dose(dayOffset: -3), dose(dayOffset: 2), dose(dayOffset: 40)],
            calendar: cal)
        #expect(a.doseDays == 1)
    }

    @Test func ignoresDeletedDoses() {
        // The Timeline supports swipe-delete, and a deleted dose is not adherence.
        var deleted = dose(dayOffset: 1)
        deleted.deletedAt = t0
        let a = ExperimentAdherence.measure(experiment: exp(),
                                            events: [dose(dayOffset: 0), deleted], calendar: cal)
        #expect(a.doseDays == 1)
    }

    @Test func anEndedExperimentMeasuresToItsEndNotItsIntendedEnd() {
        // Abandoned on day 3 of 21: doses logged afterwards belong to whatever the
        // person did next, not to the experiment.
        var e = exp()
        e.endedAt = t0.addingTimeInterval(3 * 86_400)
        e.status = .abandoned
        let a = ExperimentAdherence.measure(
            experiment: e, events: [dose(dayOffset: 1), dose(dayOffset: 10)], calendar: cal)
        #expect(a.doseDays == 1)
        #expect(a.windowDays == 3)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path HealthGraphCore --filter ExperimentAdherenceTests 2>&1 | tail -6`
Expected: FAIL — `cannot find 'ExperimentAdherence' in scope`.

- [ ] **Step 3: Implement**

Create `HealthGraphCore/Sources/HealthGraphCore/Experiments/ExperimentAdherence.swift`:

```swift
import Foundation

/// What the person actually did, derived from the events they already logged.
/// The experiment stores no logging of its own, so this can never disagree with
/// the Timeline.
public struct ExperimentAdherence: Equatable, Sendable {
    /// Distinct calendar days carrying at least one dose. The honest adherence
    /// statement is "you logged it on 18 of these 21 days"; a raw dose count would
    /// let three doses in one day read as three days of a regimen.
    public let doseDays: Int
    public let doses: Int
    public let windowDays: Int

    public init(doseDays: Int, doses: Int, windowDays: Int) {
        self.doseDays = doseDays; self.doses = doses; self.windowDays = windowDays
    }
}

extension ExperimentAdherence {
    public static func measure(experiment: Experiment, events: [HealthEvent],
                               calendar: Calendar) -> ExperimentAdherence {
        // An ended experiment measures to its END, not its intended end: doses
        // logged after someone abandoned on day 3 belong to whatever they did
        // next, not to the experiment.
        let end = experiment.endedAt ?? experiment.intendedEndAt
        let inWindow = events.filter { e in
            e.deletedAt == nil
                && e.objectID == experiment.interventionObjectID
                && e.timestamp >= experiment.startedAt
                && e.timestamp <= end
        }
        let days = Set(inWindow.map { calendar.startOfDay(for: $0.timestamp) })
        let windowDays = max(calendar.dateComponents([.day],
                                                     from: calendar.startOfDay(for: experiment.startedAt),
                                                     to: calendar.startOfDay(for: end)).day ?? 0, 0)
        return ExperimentAdherence(doseDays: days.count, doses: inWindow.count, windowDays: windowDays)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path HealthGraphCore --filter ExperimentAdherenceTests 2>&1 | tail -6`
Expected: 5 pass.

- [ ] **Step 5: Demonstrate two mutants**

1. Count raw doses instead of distinct days (`doseDays: inWindow.count`) → `countsDistinctDaysNotRawDoses` fails.
2. Measure to `intendedEndAt` always (ignore `endedAt`) → `anEndedExperimentMeasuresToItsEndNotItsIntendedEnd` fails.

Apply, run, confirm the named test fails, restore, confirm green. Report both directions.

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Experiments/ExperimentAdherence.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExperimentAdherenceTests.swift
git commit -m "feat(experiments): adherence in distinct days, derived from logged events"
```

---

## Task 3: The result, delegated to the engine

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Experiments/ExperimentResult.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ExperimentResultTests.swift`

**Interfaces:**
- Consumes: `Experiment`, `ExperimentAdherence`.
- Produces: `ExperimentOutcomeKind` (`.helps`, `.worsens`, `.noDetectableEffect`, `.pictureOnly`), `ExperimentResult` **with a public memberwise init**, and `ExperimentResult.derive(experiment:adherence:relationship:)`. Task 4 consumes all three — its tests are in the app target, which imports the package normally, so the init must be public or they will not compile.

**This task is where the spec's central rule lives.** The derivation takes the engine's relationship for the declared pair **as an input** — it does not query, score, or threshold anything itself. A caller finds the relationship; this function maps it. That keeps every statistical decision inside `EvidenceEngine` where it already is.

- [ ] **Step 1: Write the failing tests**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/ExperimentResultTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct ExperimentResultTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func exp(_ shape: ExperimentShape) -> Experiment {
        Experiment(interventionObjectID: UUID(), outcomeSubtype: "migraine", shape: shape,
                   startedAt: t0, intendedEndAt: t0.addingTimeInterval(21 * 86_400), createdAt: t0)
    }

    private func adherence(_ days: Int = 18) -> ExperimentAdherence {
        ExperimentAdherence(doseDays: days, doses: days, windowDays: 21)
    }

    private func rel(_ type: RelationshipType, status: RelStatus = .active) -> Relationship {
        Relationship(fromObjectID: UUID(), fromCategory: "supplement", toCategory: "symptom",
                     type: type, evidenceCount: 12, contradictionCount: 4, confidence: 0.7,
                     firstSeen: t0, lastSeen: t0, lastRecomputed: t0, status: status,
                     edgeKey: "obj:x|symptom:migraine|\(type.rawValue)", toSubtype: "migraine")
    }

    @Test func aCourseNeverGetsAVerdictEvenWithAStrongRelationship() {
        // Fourteen consecutive antibiotic days during one illness cannot be
        // separated from recovering anyway. This is the rule the whole shape
        // distinction exists to enforce.
        let r = ExperimentResult.derive(experiment: exp(.course), adherence: adherence(),
                                        relationship: rel(.improves))
        #expect(r.kind == .pictureOnly)
    }

    @Test func anImprovesRelationshipReadsAsHelps() {
        #expect(ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(),
                                        relationship: rel(.improves)).kind == .helps)
    }

    @Test func aWorsensRelationshipIsReportedNotSwallowed() {
        // Analgesic overuse genuinely causes rebound headaches — this may be the
        // most valuable result the feature produces, so it must not be collapsed
        // into "no effect" for comfort.
        #expect(ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(),
                                        relationship: rel(.worsens)).kind == .worsens)
    }

    @Test func aConfirmedNoEffectIsADistinctOutcome() {
        let r = ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(),
                                        relationship: rel(.noEffect, status: .confirmedNoEffect))
        #expect(r.kind == .noDetectableEffect)
    }

    @Test func noRelationshipMeansNoVerdict() {
        // The engine did not clear its gates for this pair — thin adherence, too
        // few exposures, or clumped ones. The experiment reports a picture rather
        // than inventing a threshold of its own.
        #expect(ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(4),
                                        relationship: nil).kind == .pictureOnly)
    }

    @Test func aCandidateRelationshipIsNotAVerdict() {
        // `candidate` means the engine has NOT cleared its gates. Reporting it as
        // a verdict would be exactly the second statistics path this design
        // refuses to build.
        #expect(ExperimentResult.derive(experiment: exp(.repeated), adherence: adherence(),
                                        relationship: rel(.improves, status: .candidate)).kind == .pictureOnly)
    }

    @Test func theAdherenceIsCarriedOntoEveryResult() {
        // Every output shows what the person actually did, including the pictures.
        for shape in ExperimentShape.allCases {
            let r = ExperimentResult.derive(experiment: exp(shape), adherence: adherence(11),
                                            relationship: rel(.improves))
            #expect(r.adherence.doseDays == 11)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path HealthGraphCore --filter ExperimentResultTests 2>&1 | tail -6`
Expected: FAIL — `cannot find 'ExperimentResult' in scope`.

- [ ] **Step 3: Implement**

Create `HealthGraphCore/Sources/HealthGraphCore/Experiments/ExperimentResult.swift`:

```swift
import Foundation

public enum ExperimentOutcomeKind: String, Equatable, Sendable {
    case helps, worsens, noDetectableEffect, pictureOnly
}

/// What an experiment is allowed to conclude.
///
/// The relationship arrives as an INPUT. This type never queries, scores or
/// thresholds anything: every statistical decision stays inside EvidenceEngine,
/// where it already is. A second statistics path here would be a second opinion
/// the app could contradict itself with.
public struct ExperimentResult: Equatable, Sendable {
    public let kind: ExperimentOutcomeKind
    public let adherence: ExperimentAdherence
    /// The engine's edge, when there is one. nil for every picture.
    public let relationship: Relationship?

    /// Public because the presentation tests live in the APP target, which
    /// imports HealthGraphCore normally rather than @testable — without it the
    /// synthesised memberwise init is internal and those tests cannot compile.
    public init(kind: ExperimentOutcomeKind, adherence: ExperimentAdherence,
                relationship: Relationship?) {
        self.kind = kind; self.adherence = adherence; self.relationship = relationship
    }

    public static func derive(experiment: Experiment, adherence: ExperimentAdherence,
                              relationship: Relationship?) -> ExperimentResult {
        // A course never gets a verdict, however strong the edge looks. Fourteen
        // consecutive days during one illness cannot be separated from recovering
        // anyway, and the engine's stability gate cannot see that it is one block.
        guard experiment.shape == .repeated else {
            return ExperimentResult(kind: .pictureOnly, adherence: adherence, relationship: nil)
        }
        guard let r = relationship else {
            return ExperimentResult(kind: .pictureOnly, adherence: adherence, relationship: nil)
        }
        // `candidate` means the engine has NOT cleared its gates. Only a settled
        // status speaks.
        switch (r.type, r.status) {
        case (.improves, .active):
            return ExperimentResult(kind: .helps, adherence: adherence, relationship: r)
        case (.worsens, .active), (.possibleTrigger, .active):
            return ExperimentResult(kind: .worsens, adherence: adherence, relationship: r)
        case (_, .confirmedNoEffect):
            return ExperimentResult(kind: .noDetectableEffect, adherence: adherence, relationship: r)
        default:
            return ExperimentResult(kind: .pictureOnly, adherence: adherence, relationship: nil)
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path HealthGraphCore --filter ExperimentResultTests 2>&1 | tail -6`
Expected: 7 pass.

- [ ] **Step 5: Demonstrate three mutants**

1. Remove the course guard → `aCourseNeverGetsAVerdictEvenWithAStrongRelationship` fails. **This is the most important mutant in the plan.**
2. Accept `.candidate` as a verdict → `aCandidateRelationshipIsNotAVerdict` fails.
3. Map `.worsens` to `.noDetectableEffect` → `aWorsensRelationshipIsReportedNotSwallowed` fails.

Apply, run, confirm the named test fails, restore, confirm green. Report all three, both directions.

- [ ] **Step 6: Commit**

```bash
git add HealthGraphCore/Sources/HealthGraphCore/Experiments/ExperimentResult.swift \
        HealthGraphCore/Tests/HealthGraphCoreTests/ExperimentResultTests.swift
git commit -m "feat(experiments): derive the result from the engine's edge, never from new statistics"
```

---

## Task 4: The claim ladder

**Files:**
- Create: `Views/HealthOS/Experiments/ExperimentPresentation.swift`
- Test: `Food IntolerancesTests/ExperimentPresentationTests.swift`

**Interfaces:**
- Consumes: `ExperimentResult`, `ExperimentOutcomeKind`, `ExperimentAdherence`, `ObjectKind`.
- Produces: `ExperimentPresentation.headline(for:interventionName:)`, `.detail(for:)`, `.caveats(for:interventionKind:)`.

**This task carries the spec's safety rules.** Follow the `DataSourcesPresentation` pattern: pure functions, no view, every branch testable.

- [ ] **Step 1: Write the failing tests**

Create `Food IntolerancesTests/ExperimentPresentationTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct ExperimentPresentationTests {
    private func result(_ kind: ExperimentOutcomeKind, days: Int = 18) -> ExperimentResult {
        ExperimentResult(kind: kind,
                         adherence: ExperimentAdherence(doseDays: days, doses: days, windowDays: 21),
                         relationship: nil)
    }

    @Test func noDetectableEffectNeverReadsAsDoesNotWork() {
        // Absence of a detectable effect in one person's logs is not proof of
        // absence. This is the single wording rule most likely to be softened by
        // a later edit, so it is pinned across the whole surface, not one string.
        let all = [ExperimentPresentation.headline(for: result(.noDetectableEffect),
                                                   interventionName: "Magnesium"),
                   ExperimentPresentation.detail(for: result(.noDetectableEffect))]
        for text in all {
            #expect(!text.localizedCaseInsensitiveContains("doesn't work"))
            #expect(!text.localizedCaseInsensitiveContains("does not work"))
            #expect(!text.localizedCaseInsensitiveContains("ineffective"))
        }
        #expect(all[0].localizedCaseInsensitiveContains("no detectable effect"))
    }

    @Test func everyMedicationResultCarriesBothSafetyLines() {
        // Required on EVERY outcome, not only the discouraging ones: a "helps"
        // result is exactly when someone feels licensed to self-manage.
        for kind in [ExperimentOutcomeKind.helps, .worsens, .noDetectableEffect, .pictureOnly] {
            let caveats = ExperimentPresentation.caveats(for: result(kind), interventionKind: .medication)
            let joined = caveats.joined(separator: " ")
            #expect(joined.localizedCaseInsensitiveContains("prescriber")
                    || joined.localizedCaseInsensitiveContains("doctor"))
            #expect(joined.localizedCaseInsensitiveContains("kidney")
                    || joined.localizedCaseInsensitiveContains("organ"))
        }
    }

    @Test func aSelfChosenSupplementDoesNotGetThePrescriberLine() {
        // The line has to mean something. On every result it becomes wallpaper.
        let caveats = ExperimentPresentation.caveats(for: result(.helps), interventionKind: .supplement)
        #expect(!caveats.joined().localizedCaseInsensitiveContains("prescriber"))
    }

    @Test func everyVerdictSaysItIsObservational() {
        for kind in [ExperimentOutcomeKind.helps, .worsens] {
            let joined = ExperimentPresentation.caveats(for: result(kind),
                                                        interventionKind: .supplement).joined(separator: " ")
            #expect(joined.localizedCaseInsensitiveContains("not a trial")
                    || joined.localizedCaseInsensitiveContains("observation"))
        }
    }

    @Test func aPictureSaysWhyThereIsNoVerdict() {
        // "Nothing to show" would read as a malfunction. The honest version says
        // a single course has nothing to compare against.
        let text = ExperimentPresentation.detail(for: result(.pictureOnly, days: 12))
        #expect(text.localizedCaseInsensitiveContains("can't be evaluated")
                || text.localizedCaseInsensitiveContains("nothing to compare"))
    }

    @Test func adherenceIsStatedInDaysOnEveryOutcome() {
        for kind in [ExperimentOutcomeKind.helps, .worsens, .noDetectableEffect, .pictureOnly] {
            #expect(ExperimentPresentation.detail(for: result(kind, days: 18)).contains("18"))
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/ExperimentPresentationTests" -parallel-testing-enabled NO 2>&1 | grep -E "error:|Test run"`
Expected: FAIL — `cannot find 'ExperimentPresentation' in scope`.

- [ ] **Step 3: Implement**

Create `Views/HealthOS/Experiments/ExperimentPresentation.swift`:

```swift
import Foundation
import HealthGraphCore

/// Pure copy for experiment results, so every branch of the claim ladder is
/// unit-testable without rendering a view — the DataSourcesPresentation pattern.
///
/// The wording rules here are the feature, not decoration. "No detectable
/// effect" is not "it doesn't work"; a prescription result never reads as
/// licence to change a prescription; and the app states plainly that it cannot
/// see organ-level harm, because silence lets a clean result read as a clean
/// bill of health.
enum ExperimentPresentation {
    static func headline(for result: ExperimentResult, interventionName: String) -> String {
        switch result.kind {
        case .helps:
            return "\(interventionName) appears to help."
        case .worsens:
            return "\(interventionName) may be making things worse."
        case .noDetectableEffect:
            return "No detectable effect."
        case .pictureOnly:
            return "Here's what happened."
        }
    }

    static func detail(for result: ExperimentResult) -> String {
        let a = result.adherence
        let logged = "You logged it on \(a.doseDays) of \(a.windowDays) days."
        switch result.kind {
        case .helps, .worsens, .noDetectableEffect:
            return logged
        case .pictureOnly:
            // Never "nothing to show" — that reads as a malfunction rather than a
            // limit of the evidence.
            return logged + " A single course can't be evaluated — there's nothing to compare it against."
        }
    }

    /// Order matters: the observational caveat first, then the prescription
    /// framing, then the limitation. Required on EVERY medication outcome
    /// including "helps" — that is exactly when someone feels licensed to
    /// self-manage.
    static func caveats(for result: ExperimentResult, interventionKind: ObjectKind) -> [String] {
        var out: [String] = []
        if result.kind == .helps || result.kind == .worsens {
            out.append("This is your own observation, not a trial — it can't rule out that something else changed.")
        }
        if interventionKind == .medication {
            out.append("This isn't a reason to change a prescription. Talk to your prescriber first.")
            out.append("This app can't see effects on your kidneys, liver or other organs — those don't show up in symptom logs. Ask your doctor if you're taking this regularly.")
        }
        return out
    }
}
```

- [ ] **Step 4: Run the tests**

Run the Step 2 command again.
Expected: 6 pass.

- [ ] **Step 5: Demonstrate two mutants**

1. Change the `.noDetectableEffect` headline to `"\(interventionName) doesn't work for you."` → `noDetectableEffectNeverReadsAsDoesNotWork` fails.
2. Gate the organ-harm caveat on `result.kind != .helps` → `everyMedicationResultCarriesBothSafetyLines` fails.

Apply, run, confirm, restore, confirm green.

- [ ] **Step 6: Commit**

```bash
git add Views/HealthOS/Experiments/ExperimentPresentation.swift \
        "Food IntolerancesTests/ExperimentPresentationTests.swift"
git commit -m "feat(experiments): the claim ladder, with the safety lines pinned by tests"
```

---

## Task 5: Lifecycle workflow and screen state

**Files:**
- Create: `Views/HealthOS/Experiments/ExperimentWorkflow.swift`
- Create: `Views/HealthOS/Experiments/ExperimentViewState.swift`
- Test: `Food IntolerancesTests/ExperimentWorkflowTests.swift`
- Test: `Food IntolerancesTests/ExperimentViewStateTests.swift`

**Interfaces:**
- Consumes: `Experiment`, `GRDBExperimentStore`.
- Produces: `ExperimentWorkflow` (`start(...)`, `end(_:)`, `abandon(_:)`, `all()`) and `ExperimentViewState` (`createTapped(...)`, `endTapped(_:)`, published `experiments`, `isSaving`, `endingIDs`, read-only `saveTask`).

**No `resolve(_:)`, deliberately.** An earlier draft routed result derivation through the workflow; Task 6 instead resolves the relationship at the call site and passes it to `ExperimentResult.derive`, which keeps the "relationship arrives as an input" rule visible where the lookup happens. This task therefore does not consume `ExperimentAdherence` or `ExperimentResult` at all.

Follow the Connect/Backfill split exactly: ordering and persistence in the workflow pinned by recording doubles; screen state, callbacks and a **synchronous** double-invocation guard in the view state, with the in-flight `Task` exposed read-only so tests await it deterministically.

- [ ] **Step 1: Write the workflow tests**

Create `Food IntolerancesTests/ExperimentWorkflowTests.swift`, using a recording store double that appends to a shared recorder, in the shape of `ConnectWorkflowTests`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct ExperimentWorkflowTests {
    enum Call: Equatable {
        case save(ExperimentStatus)
        case loadAll
        case readEvents
        case readRelationships
    }

    final class Recorder { var calls: [Call] = [] }

    final class RecordingStore: ExperimentPersisting {
        let recorder: Recorder
        var stored: [Experiment] = []
        init(recorder: Recorder) { self.recorder = recorder }
        func save(_ e: Experiment) async throws {
            recorder.calls.append(.save(e.status))
            stored.removeAll { $0.id == e.id }
            stored.append(e)
        }
        func all() async throws -> [Experiment] {
            recorder.calls.append(.loadAll)
            return stored
        }
    }

    private func harness() -> (ExperimentWorkflow, Recorder, RecordingStore) {
        let recorder = Recorder()
        let store = RecordingStore(recorder: recorder)
        return (ExperimentWorkflow(store: store), recorder, store)
    }

    @Test func startingPersistsARunningExperimentWithTheDeclaredShape() async throws {
        let (workflow, recorder, store) = harness()
        let objectID = UUID()
        let e = try await workflow.start(interventionObjectID: objectID, outcomeSubtype: "migraine",
                                         shape: .course, startedAt: Date(), days: 14)
        #expect(e.status == .running)
        #expect(e.shape == .course)          // declared, not inferred
        #expect(e.interventionObjectID == objectID)
        #expect(recorder.calls == [.save(.running)])
        #expect(store.stored.count == 1)
    }

    @Test func endingMarksCompletedAndStampsTheEndDate() async throws {
        let (workflow, recorder, _) = harness()
        let e = try await workflow.start(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                                         shape: .repeated, startedAt: Date(), days: 21)
        let ended = try await workflow.end(e, at: Date())
        #expect(ended.status == .completed)
        #expect(ended.endedAt != nil)
        #expect(recorder.calls == [.save(.running), .save(.completed)])
    }

    @Test func abandoningIsDistinctFromCompleting() async throws {
        // They mean different things to the result: an abandoned experiment
        // measures adherence to the day it stopped, not its intended end.
        let (workflow, _, _) = harness()
        let e = try await workflow.start(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                                         shape: .repeated, startedAt: Date(), days: 21)
        let stopped = try await workflow.abandon(e, at: Date())
        #expect(stopped.status == .abandoned)
        #expect(stopped.endedAt != nil)
    }
}
```

**`ExperimentPersisting` is a narrow protocol declared in `ExperimentWorkflow.swift`** — `save(_:)` and `all()` only — with `GRDBExperimentStore` conformed in the same file. The workflow must not depend on the concrete store.

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/ExperimentWorkflowTests" -parallel-testing-enabled NO 2>&1 | grep -E "error:|Test run"`
Expected: FAIL — `cannot find 'ExperimentWorkflow' in scope`.

- [ ] **Step 3: Implement the workflow**

Create `Views/HealthOS/Experiments/ExperimentWorkflow.swift`:

```swift
import Foundation
import HealthGraphCore

/// The slice of experiment persistence the workflow needs. Narrow on purpose, so
/// tests can record the call sequence without a database.
@MainActor
protocol ExperimentPersisting {
    func save(_ experiment: Experiment) async throws
    func all() async throws -> [Experiment]
}

extension GRDBExperimentStore: ExperimentPersisting {}

/// Experiment lifecycle transitions, extracted from the view so their ORDER and
/// their effect on stored state are testable with recording doubles — the same
/// split ConnectWorkflow and BackfillWorkflow use.
@MainActor
struct ExperimentWorkflow {
    private let store: any ExperimentPersisting

    init(store: any ExperimentPersisting) { self.store = store }

    /// The shape is taken from the caller and stored verbatim. It is never
    /// derived from the events, because a fortnight of consecutive doses cannot
    /// be told apart from the start of a daily habit.
    func start(interventionObjectID: UUID, outcomeSubtype: String, shape: ExperimentShape,
               startedAt: Date, days: Int) async throws -> Experiment {
        let e = Experiment(interventionObjectID: interventionObjectID,
                           outcomeSubtype: outcomeSubtype, shape: shape,
                           startedAt: startedAt,
                           intendedEndAt: startedAt.addingTimeInterval(Double(days) * 86_400),
                           status: .running, createdAt: startedAt)
        try await store.save(e)
        return e
    }

    /// Completed and abandoned are deliberately different states: adherence
    /// measures to `endedAt`, so an abandoned experiment is not judged on days
    /// its owner never intended to fill.
    func end(_ experiment: Experiment, at date: Date) async throws -> Experiment {
        try await finish(experiment, status: .completed, at: date)
    }

    func abandon(_ experiment: Experiment, at date: Date) async throws -> Experiment {
        try await finish(experiment, status: .abandoned, at: date)
    }

    private func finish(_ experiment: Experiment, status: ExperimentStatus,
                        at date: Date) async throws -> Experiment {
        var e = experiment
        e.status = status
        e.endedAt = date
        try await store.save(e)
        return e
    }

    func all() async throws -> [Experiment] { try await store.all() }
}
```

- [ ] **Step 4: Write the view-state test**

Create `Food IntolerancesTests/ExperimentViewStateTests.swift`. Reuse the recording store from the workflow suite by declaring an equivalent one here (the suites are independent, matching how `ConnectWorkflowTests` and `ConnectViewStateTests` each nest their own doubles):

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct ExperimentViewStateTests {
    final class CountingStore: ExperimentPersisting {
        var saves = 0
        var stored: [Experiment] = []
        func save(_ e: Experiment) async throws {
            saves += 1
            stored.removeAll { $0.id == e.id }
            stored.append(e)
        }
        func all() async throws -> [Experiment] { stored }
    }

    private func settle() async { for _ in 0..<25 { await Task.yield() } }

    @Test func twoImmediateCreateTapsCreateOneExperiment() async {
        // Both taps land in the same main-actor turn, before any re-render applies
        // .disabled. Only a guard that runs synchronously inside createTapped
        // separates one experiment from two — and two would silently double every
        // adherence count for the same regimen.
        let store = CountingStore()
        let state = ExperimentViewState(store: store)
        state.createTapped(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                           shape: .repeated, days: 21)
        state.createTapped(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                           shape: .repeated, days: 21)
        await state.saveTask?.value
        await settle()
        #expect(store.saves == 1)
        #expect(state.isSaving == false)
    }

    @Test func creatingPublishesTheNewExperiment() async {
        let store = CountingStore()
        let state = ExperimentViewState(store: store)
        state.createTapped(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                           shape: .course, days: 14)
        #expect(state.isSaving == true)      // synchronous, disables the button this turn
        await state.saveTask?.value
        #expect(state.experiments.count == 1)
        #expect(state.experiments.first?.shape == .course)
    }
}
```

- [ ] **Step 5: Implement the view state**

Create `Views/HealthOS/Experiments/ExperimentViewState.swift`, following `BackfillViewState`: published state, a synchronous guard, and a read-only in-flight `Task` for deterministic tests.

```swift
import Foundation
import HealthGraphCore

/// Screen state for the experiments surfaces. Transitions live in
/// ExperimentWorkflow; this owns published state, the callbacks, and the guard.
@MainActor
final class ExperimentViewState: ObservableObject {
    @Published private(set) var experiments: [Experiment] = []
    @Published private(set) var isSaving = false

    private let workflow: ExperimentWorkflow

    /// Read-only outside; tests await it so assertions run after completion
    /// rather than spinning a run loop. Production code never reads it.
    private(set) var saveTask: Task<Void, Never>?
    private(set) var loadTask: Task<Void, Never>?

    init(store: any ExperimentPersisting) {
        self.workflow = ExperimentWorkflow(store: store)
    }

    func appeared() {
        loadTask = Task { experiments = (try? await workflow.all()) ?? [] }
    }

    /// The guard runs SYNCHRONOUSLY, before any dispatch: two taps can land in the
    /// same main-actor turn, and two experiments over one regimen would double
    /// every adherence count derived from the same doses.
    func createTapped(interventionObjectID: UUID, outcomeSubtype: String,
                      shape: ExperimentShape, days: Int) {
        guard !isSaving else { return }
        isSaving = true
        saveTask = Task {
            defer { isSaving = false }
            _ = try? await workflow.start(interventionObjectID: interventionObjectID,
                                          outcomeSubtype: outcomeSubtype, shape: shape,
                                          startedAt: Date(), days: days)
            experiments = (try? await workflow.all()) ?? []
        }
    }

    func endTapped(_ experiment: Experiment) {
        guard !isSaving else { return }
        isSaving = true
        saveTask = Task {
            defer { isSaving = false }
            _ = try? await workflow.end(experiment, at: Date())
            experiments = (try? await workflow.all()) ?? []
        }
    }
}
```

- [ ] **Step 6: Run both suites**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/ExperimentWorkflowTests" -only-testing:"Food IntolerancesTests/ExperimentViewStateTests" -parallel-testing-enabled NO 2>&1 | grep -E "✘|Test run"`
Expected: 5 pass.

- [ ] **Step 7: Demonstrate two mutants**

1. Move the `isSaving = true` assignment inside the `Task` → `twoImmediateCreateTapsCreateOneExperiment` fails with 2 saves.
2. Make `abandon` set `.completed` → `abandoningIsDistinctFromCompleting` fails.

Apply, run, confirm, restore, confirm green.

- [ ] **Step 8: Commit**

```bash
git add Views/HealthOS/Experiments/ExperimentWorkflow.swift \
        Views/HealthOS/Experiments/ExperimentViewState.swift \
        "Food IntolerancesTests/ExperimentWorkflowTests.swift" \
        "Food IntolerancesTests/ExperimentViewStateTests.swift"
git commit -m "feat(experiments): lifecycle workflow and screen state with a synchronous guard"
```

---

## Task 6: The Health-tab surfaces

**Files:**
- Create: `Views/HealthOS/Experiments/ExperimentsView.swift`
- Create: `Views/HealthOS/Experiments/ExperimentCreateView.swift`
- Modify: `Views/HealthOS/Health/HealthTabView.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–5.

Thin wiring only — every decision already lives in the workflow, the view state, or the presentation namespace. Follow `FirstRunBackfillView`: one model method per control, published state rendered directly.

- [ ] **Step 1: The list**

Create `ExperimentsView.swift`: a `List` of experiments grouped running-then-finished. Each running row shows the intervention name, `"\(adherence.doseDays) of \(adherence.windowDays) days logged"`, and days remaining. Each finished row shows `ExperimentPresentation.headline(...)`. Tapping a finished row shows the detail: headline, `detail(for:)`, then `caveats(for:interventionKind:)` rendered one per line in `HealthTheme.inkMuted`.

Resolve the intervention name via `GRDBObjectStore.object(id:)`, and the relationship for the declared pair via `GRDBRelationshipStore.relationships(fromObjectID:)`, filtered to `toSubtype == experiment.outcomeSubtype`. Pass that relationship into `ExperimentResult.derive` — the view never inspects `confidence` or `status` itself.

- [ ] **Step 2: The create sheet**

Create `ExperimentCreateView.swift`: pick an intervention from existing objects of kind `.medication`, `.supplement` or `.peptide`; pick a target symptom via `SymptomCatalog.search`; choose the shape with a segmented control labelled **"As needed / ongoing"** and **"A fixed course"**; choose a length in days (default 21). The Start button calls `state.createTapped(...)` exactly once.

The shape control carries a one-line explanation, because the choice determines whether a verdict is possible and the user cannot be expected to infer that:

```swift
Text(shape == .course
     ? "A fixed run, like a two-week antibiotic course. We'll show you what happened, but a single course can't be tested."
     : "Taken as needed or ongoing. With enough repetition this can be tested.")
```

- [ ] **Step 3: Replace the Health-tab row**

In `HealthTabView.swift`, replace the `("checklist", "Protocols & experiments", "adherence and outcomes")` entry in `comingRows` with a real `NavigationLink` to `ExperimentsView()`, following the "Data sources" row idiom exactly (icon, label, chevron, `.padding(16)`, `.contentShape(Rectangle())`, `.accessibilityHint`).

- [ ] **Step 4: Build and run the app suite**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

Run the full app suite; expect 70+ suites, zero `✘`, and the familiar exit-65 banner from the pre-existing `SwiftDataMigratorTests` crash.

- [ ] **Step 5: Commit**

```bash
git add Views/HealthOS/Experiments/ExperimentsView.swift \
        Views/HealthOS/Experiments/ExperimentCreateView.swift \
        Views/HealthOS/Health/HealthTabView.swift
git commit -m "feat(experiments): Health-tab list, creation and result surfaces"
```

---

## Final verification

- [ ] `swift test --package-path HealthGraphCore 2>&1 | tail -3` — expect 409 + 16 = 425 passing.
- [ ] App suite: count `✔ Suite` lines and grep `✘`; the trailing total is unreliable because the pre-existing `SwiftDataMigratorTests` crash forces a relaunch.
- [ ] **Migration check on a populated database**, not only an empty one: load the STRESS demo, confirm the app still launches and the Timeline still renders after v8 applies.

## Device check

- [ ] Health → **Protocols & experiments** → create a *course* experiment over an existing supplement. Confirm the result is a picture and **never** a verdict, whatever the graph contains.
- [ ] Create a *repeated* experiment against an intervention with no mined relationship. Confirm it also shows a picture rather than an empty screen or a spurious verdict.
- [ ] Confirm a medication intervention shows **both** safety lines on its result, including when the result is "helps".

## Phase B — committed follow-up, not a maybe

Named here so it cannot quietly disappear:

- The **Home card** for a running experiment, with the **midpoint nudge** ("day 10, two logs — keep going, extend, or stop?"), yielding to the poor-air banner.
- The **Insights result rendering**, visually and verbally distinct from mined cards — "you tested this" versus "we noticed this".
- The **Test this** action on an insight card, opening creation pre-filled. This is the loop the feature exists to close.
- **Per-experiment reminders** at a user-set time, with the notification permission requested at that moment, and cancelled when the experiment ends or is abandoned.
- **Mood as a target outcome** (needs the engine's `lowMood`/`goodMood` keys rather than a subtype string).
