# Phase 0: Health Graph Re-foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the GRDB-backed event-graph data layer (three core tables, repositories, name-dedup, soft delete), a one-time SwiftData→GRDB migrator behind a feature flag, and the synthetic-data harness — per spec `docs/superpowers/specs/2026-07-03-health-graph-design.md` §4, §5.5, §7 (harness), §16 Phase 0.

**Architecture:** All new core code lives in a **local Swift package** `HealthGraphCore/` at the repo root — GRDB is a package dependency (no .pbxproj editing), and all core tests run via `swift test` on macOS (fast, no simulator). Only two things live in the app target: `SwiftDataMigrator` (needs the app's SwiftData models) and a DEBUG-only screen. The app target picks up new files automatically because it uses Xcode 16 file-system-synchronized groups (`Models/` and `Views/` folders sync to the app target; the tests folder syncs to the test target).

**Tech Stack:** Swift (language mode 5), GRDB 7 (SQLite), Swift Testing (`import Testing`, `#expect` — already used by the app's test target), SwiftData (source side of the migrator only), SwiftUI (debug screen).

## Global Constraints

- Repo root: `/Users/leo/Desktop/FoodIntolerances`. App project: `Food Intolerances.xcodeproj` (note the space), deployment target iOS 18.0.
- Schema changes ONLY inside numbered GRDB migrations (`registerMigration("v1")`...). Never `ALTER TABLE` outside the migrator. (Spec §16 hand-off rules.)
- Soft delete only: events get `deletedAt`; never `DELETE FROM health_events` in product code. (Spec §4.)
- All timestamps stored with a `timezoneID` (IANA identifier) captured at event creation. (Spec §4.)
- The migrator must never write to the SwiftData store — read-only source; runs behind flag `hg.migration.v1.completed`; the old store stays intact. (Spec §3.)
- No user-facing causal language anywhere (N/A for Phase 0 code, applies to debug copy too).
- Approved spec deltas locked in by this plan: `EventSource` gains `legacyImport` (migrated rows need a source); `ObjectKind` gains `activity` (for avoided activities) and spells `protocol` as `careProtocol = "protocol"` (Swift keyword).
- Package tests: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`. App build: `xcodebuild -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 16' build` (if the scheme name differs, check `xcodebuild -list`).
- Commit after every task with the message given in its final step.

---

### Task 1: Package scaffold + schema migration v1

**Files:**
- Create: `HealthGraphCore/Package.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/AppDatabaseTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `AppDatabase` — `init(_ dbWriter: any DatabaseWriter) throws`, `static func open(at url: URL) throws -> AppDatabase`, `static func inMemory() throws -> AppDatabase`, property `dbWriter: any DatabaseWriter`. Tables `health_objects`, `health_events`, `relationships` with the exact columns below. Every later task builds on this.

- [ ] **Step 1: Create the package manifest**

`HealthGraphCore/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthGraphCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "HealthGraphCore", targets: ["HealthGraphCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "HealthGraphCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HealthGraphCoreTests",
            dependencies: ["HealthGraphCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
```

- [ ] **Step 2: Write the failing test**

`HealthGraphCore/Tests/HealthGraphCoreTests/AppDatabaseTests.swift`:

```swift
import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

struct AppDatabaseTests {
    @Test func migrationCreatesCoreTables() throws {
        let db = try AppDatabase.inMemory()
        try db.dbWriter.read { d in
            #expect(try d.tableExists("health_objects"))
            #expect(try d.tableExists("health_events"))
            #expect(try d.tableExists("relationships"))
            let eventCols = try d.columns(in: "health_events").map(\.name)
            #expect(eventCols.contains("timezoneID"))
            #expect(eventCols.contains("deletedAt"))
            #expect(eventCols.contains("attachmentPath"))
            let objCols = try d.columns(in: "health_objects").map(\.name)
            #expect(objCols.contains("normalizedName"))
            let relCols = try d.columns(in: "relationships").map(\.name)
            #expect(relCols.contains("contradictionCount"))
            #expect(relCols.contains("lagHours"))
        }
    }

    @Test func migrationIsIdempotentOnReopen() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("test.sqlite")
        _ = try AppDatabase.open(at: url)
        _ = try AppDatabase.open(at: url) // must not throw on second open
        try? FileManager.default.removeItem(at: dir)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: compile FAILURE — `cannot find 'AppDatabase' in scope` (the first run also resolves/downloads GRDB, which takes a minute).

- [ ] **Step 4: Implement AppDatabase with migration v1**

`HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift`:

```swift
import Foundation
import GRDB

/// Owns the GRDB database and its schema migrations.
/// Schema changes happen ONLY here, in numbered migrations.
public struct AppDatabase {
    public let dbWriter: any DatabaseWriter

    public init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.migrator.migrate(dbWriter)
    }

    /// Opens (creating if needed) a database file, creating parent directories.
    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let dbQueue = try DatabaseQueue(path: url.path)
        return try AppDatabase(dbQueue)
    }

    /// In-memory database for tests, previews, and the synthetic harness.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "health_objects") { t in
                t.primaryKey("id", .blob)
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("normalizedName", .text).notNull()
                t.column("metadata", .blob)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_objects_normalized",
                          on: "health_objects", columns: ["normalizedName", "kind"])

            try db.create(table: "health_events") { t in
                t.primaryKey("id", .blob)
                t.column("timestamp", .datetime).notNull()
                t.column("timezoneID", .text).notNull()
                t.column("endTimestamp", .datetime)
                t.column("category", .text).notNull()
                t.column("subtype", .text)
                t.column("objectID", .blob)
                    .references("health_objects", onDelete: .setNull)
                t.column("value", .double)
                t.column("unit", .text)
                t.column("source", .text).notNull()
                t.column("confidence", .double).notNull().defaults(to: 1.0)
                t.column("metadata", .blob)
                t.column("attachmentPath", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(index: "idx_events_category_timestamp",
                          on: "health_events", columns: ["category", "timestamp"])
            try db.create(index: "idx_events_object_timestamp",
                          on: "health_events", columns: ["objectID", "timestamp"])

            try db.create(table: "relationships") { t in
                t.primaryKey("id", .blob)
                t.column("fromObjectID", .blob)
                    .references("health_objects", onDelete: .cascade)
                t.column("fromCategory", .text)
                t.column("toObjectID", .blob)
                    .references("health_objects", onDelete: .cascade)
                t.column("toCategory", .text)
                t.column("type", .text).notNull()
                t.column("evidenceCount", .integer).notNull().defaults(to: 0)
                t.column("contradictionCount", .integer).notNull().defaults(to: 0)
                t.column("confidence", .double).notNull().defaults(to: 0)
                t.column("strength", .double)
                t.column("lagHours", .double)
                t.column("firstSeen", .datetime).notNull()
                t.column("lastSeen", .datetime).notNull()
                t.column("lastRecomputed", .datetime).notNull()
                t.column("status", .text).notNull()
                t.column("aiExplanation", .text)
            }
            try db.create(index: "idx_rel_from", on: "relationships", columns: ["fromObjectID"])
            try db.create(index: "idx_rel_to", on: "relationships", columns: ["toObjectID"])
            try db.create(index: "idx_rel_status", on: "relationships", columns: ["status"])
        }

        return migrator
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: `Test run with 2 tests passed`

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): HealthGraphCore package with GRDB schema migration v1"
```

---

### Task 2: Enums + NameNormalizer

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Models/Enums.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Support/NameNormalizer.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/NameNormalizerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `EventCategory`, `EventSource`, `ObjectKind` (note `careProtocol = "protocol"`), `RelationshipType`, `RelStatus` — all `String`-raw, `Codable`, `CaseIterable`, `Sendable`. `NameNormalizer.normalize(_ raw: String) -> String`. Used by every later task.

- [ ] **Step 1: Write the failing tests**

`HealthGraphCore/Tests/HealthGraphCoreTests/NameNormalizerTests.swift`:

```swift
import Testing
@testable import HealthGraphCore

struct NameNormalizerTests {
    @Test func stripsDoseAndLowercases() {
        #expect(NameNormalizer.normalize("Magnesium Glycinate 400mg") == "magnesium glycinate")
    }
    @Test func stripsIUDose() {
        #expect(NameNormalizer.normalize("Vitamin D3 5000 IU") == "vitamin d3")
    }
    @Test func trimsAndCollapsesWhitespace() {
        #expect(NameNormalizer.normalize("  BPC-157   ") == "bpc-157")
    }
    @Test func plainNameUnchangedExceptCase() {
        #expect(NameNormalizer.normalize("Coffee") == "coffee")
    }
    @Test func stripsCapsuleCount() {
        #expect(NameNormalizer.normalize("Omega 3 2 capsules") == "omega 3")
    }
    @Test func enumRawValuesAreStable() {
        // These raw values are persisted to disk — a change is a schema migration.
        #expect(ObjectKind.careProtocol.rawValue == "protocol")
        #expect(EventCategory.protocolMarker.rawValue == "protocolMarker")
        #expect(EventSource.legacyImport.rawValue == "legacyImport")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: compile FAILURE — `cannot find 'NameNormalizer' in scope`

- [ ] **Step 3: Implement enums and normalizer**

`HealthGraphCore/Sources/HealthGraphCore/Models/Enums.swift`:

```swift
import Foundation

/// Spec §4. Raw values are persisted — never rename a case's raw value
/// without a schema migration.
public enum EventCategory: String, Codable, CaseIterable, Sendable {
    case food, medication, supplement, peptide, symptom, sleep, exercise,
         vitals, lab, mood, stress, stool, bodyMetric, cycle, illness,
         environment, travel, doctorVisit, protocolMarker, note
}

public enum EventSource: String, Codable, CaseIterable, Sendable {
    case manual, photo, voice, healthKit, healthExportFile, labImport,
         weatherAPI, appIntent, legacyImport
}

public enum ObjectKind: String, Codable, CaseIterable, Sendable {
    case medication, supplement, peptide, food, allergen, doctor, labTest,
         condition, activity, experiment, location, device
    case careProtocol = "protocol" // "protocol" is a Swift keyword
}

public enum RelationshipType: String, Codable, CaseIterable, Sendable {
    case possibleTrigger, improves, worsens, noEffect, precedes
}

public enum RelStatus: String, Codable, CaseIterable, Sendable {
    case candidate, active, decayed, confirmedNoEffect, userDismissed
}
```

`HealthGraphCore/Sources/HealthGraphCore/Support/NameNormalizer.swift`:

```swift
import Foundation

/// Normalizes object names for dedup: lowercased, dose tokens stripped,
/// whitespace collapsed. "Magnesium Glycinate 400mg" -> "magnesium glycinate".
public enum NameNormalizer {
    public static func normalize(_ raw: String) -> String {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let dose = #"\b\d+([.,]\d+)?\s*(mg|mcg|µg|ug|g|kg|iu|ml|l|caps?|capsules?|tabs?|tablets?|drops?|units?)\b"#
        s = s.replacingOccurrences(of: dose, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: all tests pass (8 total so far).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): event/object/relationship enums and name normalizer"
```

---

### Task 3: Core record types (HealthEvent, HealthObject, Relationship)

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Models/HealthEvent.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Models/HealthObject.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Models/Relationship.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/RecordRoundtripTests.swift`

**Interfaces:**
- Consumes: `AppDatabase` (Task 1), enums + `NameNormalizer` (Task 2).
- Produces: three `Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord, Sendable` structs whose property names match the v1 columns exactly. `HealthEvent.init` defaults: `id: UUID = UUID()`, `timezoneID: String = TimeZone.current.identifier`, `confidence: Double = 1.0`, `createdAt: Date = Date()`, optionals nil. `HealthObject.init(id:kind:name:metadata:isArchived:createdAt:)` computes `normalizedName` via `NameNormalizer`. `Relationship.init` defaults counts 0, confidence 0, `status: RelStatus = .candidate`.

- [ ] **Step 1: Write the failing tests**

`HealthGraphCore/Tests/HealthGraphCoreTests/RecordRoundtripTests.swift`:

```swift
import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

struct RecordRoundtripTests {
    @Test func healthEventRoundtrips() throws {
        let db = try AppDatabase.inMemory()
        let event = HealthEvent(
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            category: .symptom, subtype: "headache",
            value: 6, source: .manual
        )
        try db.dbWriter.write { try event.insert($0) }
        let fetched = try db.dbWriter.read { try HealthEvent.fetchOne($0, key: event.id) }
        #expect(fetched == event)
        #expect(fetched?.timezoneID == TimeZone.current.identifier)
        #expect(fetched?.deletedAt == nil)
    }

    @Test func healthObjectComputesNormalizedName() throws {
        let db = try AppDatabase.inMemory()
        let object = HealthObject(kind: .supplement, name: "Magnesium Glycinate 400mg")
        #expect(object.normalizedName == "magnesium glycinate")
        try db.dbWriter.write { try object.insert($0) }
        let fetched = try db.dbWriter.read { try HealthObject.fetchOne($0, key: object.id) }
        #expect(fetched == object)
    }

    @Test func relationshipRoundtrips() throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let rel = Relationship(
            fromCategory: "food", toCategory: "symptom",
            type: .possibleTrigger, firstSeen: now, lastSeen: now, lastRecomputed: now
        )
        try db.dbWriter.write { try rel.insert($0) }
        let fetched = try db.dbWriter.read { try Relationship.fetchOne($0, key: rel.id) }
        #expect(fetched == rel)
        #expect(fetched?.status == .candidate)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: compile FAILURE — `cannot find 'HealthEvent' in scope`

- [ ] **Step 3: Implement the three record types**

`HealthGraphCore/Sources/HealthGraphCore/Models/HealthEvent.swift`:

```swift
import Foundation
import GRDB

/// Everything that happens is an event. Spec §4.
public struct HealthEvent: Codable, Identifiable, Equatable,
                           FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "health_events"

    public var id: UUID
    public var timestamp: Date
    public var timezoneID: String
    public var endTimestamp: Date?
    public var category: EventCategory
    public var subtype: String?
    public var objectID: UUID?
    public var value: Double?
    public var unit: String?
    public var source: EventSource
    public var confidence: Double
    public var metadata: Data?
    public var attachmentPath: String?
    public var createdAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        timezoneID: String = TimeZone.current.identifier,
        endTimestamp: Date? = nil,
        category: EventCategory,
        subtype: String? = nil,
        objectID: UUID? = nil,
        value: Double? = nil,
        unit: String? = nil,
        source: EventSource,
        confidence: Double = 1.0,
        metadata: Data? = nil,
        attachmentPath: String? = nil,
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.timezoneID = timezoneID
        self.endTimestamp = endTimestamp
        self.category = category
        self.subtype = subtype
        self.objectID = objectID
        self.value = value
        self.unit = unit
        self.source = source
        self.confidence = confidence
        self.metadata = metadata
        self.attachmentPath = attachmentPath
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}
```

`HealthGraphCore/Sources/HealthGraphCore/Models/HealthObject.swift`:

```swift
import Foundation
import GRDB

/// A persistent thing events reference (a supplement, a food, a doctor…). Spec §4.
public struct HealthObject: Codable, Identifiable, Equatable,
                            FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "health_objects"

    public var id: UUID
    public var kind: ObjectKind
    public var name: String
    public var normalizedName: String
    public var metadata: Data?
    public var isArchived: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: ObjectKind,
        name: String,
        metadata: Data? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.normalizedName = NameNormalizer.normalize(name)
        self.metadata = metadata
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}
```

`HealthGraphCore/Sources/HealthGraphCore/Models/Relationship.swift`:

```swift
import Foundation
import GRDB

/// A mined edge between an exposure and an outcome — the moat. Spec §4.
/// `confidence` is computed by the EvidenceEngine (Phase 2), never by an LLM.
public struct Relationship: Codable, Identifiable, Equatable,
                            FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "relationships"

    public var id: UUID
    public var fromObjectID: UUID?
    public var fromCategory: String?
    public var toObjectID: UUID?
    public var toCategory: String?
    public var type: RelationshipType
    public var evidenceCount: Int
    public var contradictionCount: Int
    public var confidence: Double
    public var strength: Double?
    public var lagHours: Double?
    public var firstSeen: Date
    public var lastSeen: Date
    public var lastRecomputed: Date
    public var status: RelStatus
    public var aiExplanation: String?

    public init(
        id: UUID = UUID(),
        fromObjectID: UUID? = nil,
        fromCategory: String? = nil,
        toObjectID: UUID? = nil,
        toCategory: String? = nil,
        type: RelationshipType,
        evidenceCount: Int = 0,
        contradictionCount: Int = 0,
        confidence: Double = 0,
        strength: Double? = nil,
        lagHours: Double? = nil,
        firstSeen: Date,
        lastSeen: Date,
        lastRecomputed: Date,
        status: RelStatus = .candidate,
        aiExplanation: String? = nil
    ) {
        self.id = id
        self.fromObjectID = fromObjectID
        self.fromCategory = fromCategory
        self.toObjectID = toObjectID
        self.toCategory = toCategory
        self.type = type
        self.evidenceCount = evidenceCount
        self.contradictionCount = contradictionCount
        self.confidence = confidence
        self.strength = strength
        self.lagHours = lagHours
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.lastRecomputed = lastRecomputed
        self.status = status
        self.aiExplanation = aiExplanation
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: all pass (11 total).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): HealthEvent, HealthObject, Relationship record types"
```

---

### Task 4: EventStore repository

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift`

**Interfaces:**
- Consumes: `AppDatabase`, `HealthEvent`, `EventCategory` (Tasks 1–3).
- Produces:

```swift
public protocol EventStore {
    func save(_ event: HealthEvent) async throws
    func save(_ events: [HealthEvent]) async throws
    func event(id: UUID) async throws -> HealthEvent?
    func events(in interval: DateInterval, category: EventCategory?) async throws -> [HealthEvent]
    func recentEvents(limit: Int) async throws -> [HealthEvent]
    func softDelete(id: UUID) async throws
    func count() async throws -> Int
}
public struct GRDBEventStore: EventStore { public init(database: AppDatabase) }
```

All fetches exclude soft-deleted rows; `count()` counts non-deleted only. `save` upserts (insert or replace by id).

- [ ] **Step 1: Write the failing tests**

`HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct EventStoreTests {
    func makeStore() throws -> (GRDBEventStore, AppDatabase) {
        let db = try AppDatabase.inMemory()
        return (GRDBEventStore(database: db), db)
    }

    func event(daysAgo: Double, category: EventCategory, subtype: String) -> HealthEvent {
        HealthEvent(
            timestamp: Date(timeIntervalSince1970: 1_750_000_000 - daysAgo * 86_400),
            category: category, subtype: subtype, source: .manual
        )
    }

    @Test func rangeQueryFiltersByIntervalAndCategory() async throws {
        let (store, _) = try makeStore()
        try await store.save([
            event(daysAgo: 1, category: .symptom, subtype: "headache"),
            event(daysAgo: 2, category: .food, subtype: "coffee"),
            event(daysAgo: 40, category: .symptom, subtype: "old headache")
        ])
        let last30 = DateInterval(
            start: Date(timeIntervalSince1970: 1_750_000_000 - 30 * 86_400),
            end: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let symptoms = try await store.events(in: last30, category: .symptom)
        #expect(symptoms.count == 1)
        #expect(symptoms.first?.subtype == "headache")
        let all = try await store.events(in: last30, category: nil)
        #expect(all.count == 2)
        #expect(all.first?.subtype == "coffee") // ascending by timestamp
    }

    @Test func softDeleteHidesEventEverywhere() async throws {
        let (store, _) = try makeStore()
        let e = event(daysAgo: 1, category: .symptom, subtype: "headache")
        try await store.save(e)
        try await store.softDelete(id: e.id)
        let fetched = try await store.event(id: e.id)
        #expect(fetched == nil)
        let visible = try await store.count()
        #expect(visible == 0)
        // but the row still physically exists (history preserved)
        let raw = try await store.rawCountIncludingDeleted()
        #expect(raw == 1)
    }

    @Test func saveIsUpsertById() async throws {
        let (store, _) = try makeStore()
        var e = event(daysAgo: 1, category: .symptom, subtype: "headache")
        try await store.save(e)
        e.value = 8
        try await store.save(e)
        let total = try await store.count()
        #expect(total == 1)
        let fetched = try await store.event(id: e.id)
        #expect(fetched?.value == 8)
    }

    @Test func recentEventsOrdersDescendingAndLimits() async throws {
        let (store, _) = try makeStore()
        try await store.save([
            event(daysAgo: 3, category: .food, subtype: "a"),
            event(daysAgo: 1, category: .food, subtype: "b"),
            event(daysAgo: 2, category: .food, subtype: "c")
        ])
        let recent = try await store.recentEvents(limit: 2)
        #expect(recent.map(\.subtype) == ["b", "c"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: compile FAILURE — `cannot find 'GRDBEventStore' in scope`

- [ ] **Step 3: Implement the store**

`HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift`:

```swift
import Foundation
import GRDB

public protocol EventStore {
    func save(_ event: HealthEvent) async throws
    func save(_ events: [HealthEvent]) async throws
    func event(id: UUID) async throws -> HealthEvent?
    func events(in interval: DateInterval, category: EventCategory?) async throws -> [HealthEvent]
    func recentEvents(limit: Int) async throws -> [HealthEvent]
    func softDelete(id: UUID) async throws
    func count() async throws -> Int
}

public struct GRDBEventStore: EventStore {
    let dbWriter: any DatabaseWriter

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    private var notDeleted: SQLExpression { Column("deletedAt") == nil }

    public func save(_ event: HealthEvent) async throws {
        try await save([event])
    }

    public func save(_ events: [HealthEvent]) async throws {
        try await dbWriter.write { db in
            for event in events { try event.save(db) }
        }
    }

    public func event(id: UUID) async throws -> HealthEvent? {
        try await dbWriter.read { [notDeleted] db in
            try HealthEvent.filter(key: id).filter(notDeleted).fetchOne(db)
        }
    }

    public func events(in interval: DateInterval, category: EventCategory?) async throws -> [HealthEvent] {
        try await dbWriter.read { [notDeleted] db in
            var request = HealthEvent
                .filter(notDeleted)
                .filter(Column("timestamp") >= interval.start)
                .filter(Column("timestamp") <= interval.end)
                .order(Column("timestamp"))
            if let category {
                request = request.filter(Column("category") == category.rawValue)
            }
            return try request.fetchAll(db)
        }
    }

    public func recentEvents(limit: Int) async throws -> [HealthEvent] {
        try await dbWriter.read { [notDeleted] db in
            try HealthEvent.filter(notDeleted)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func softDelete(id: UUID) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "UPDATE health_events SET deletedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    public func count() async throws -> Int {
        try await dbWriter.read { [notDeleted] db in
            try HealthEvent.filter(notDeleted).fetchCount(db)
        }
    }

    /// Test/debug helper: physical row count, including soft-deleted.
    public func rawCountIncludingDeleted() async throws -> Int {
        try await dbWriter.read { db in try HealthEvent.fetchCount(db) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: all pass (15 total).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): EventStore with range queries, upsert, soft delete"
```

---

### Task 5: ObjectStore repository with dedup

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Database/ObjectStore.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ObjectStoreTests.swift`

**Interfaces:**
- Consumes: `AppDatabase`, `HealthObject`, `ObjectKind`, `NameNormalizer`.
- Produces:

```swift
public protocol ObjectStore {
    func findOrCreate(name: String, kind: ObjectKind, metadata: Data?) async throws -> HealthObject
    func object(id: UUID) async throws -> HealthObject?
    func objects(kind: ObjectKind?, includeArchived: Bool) async throws -> [HealthObject]
    func setArchived(id: UUID, _ archived: Bool) async throws
    func count() async throws -> Int
}
public struct GRDBObjectStore: ObjectStore { public init(database: AppDatabase) }
```

`findOrCreate` matches on `(normalizedName, kind)` inside ONE write transaction (no race); when a match exists it returns the existing object unchanged (does not overwrite metadata).

- [ ] **Step 1: Write the failing tests**

`HealthGraphCore/Tests/HealthGraphCoreTests/ObjectStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct ObjectStoreTests {
    @Test func findOrCreateDedupsOnNormalizedName() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        let a = try await store.findOrCreate(name: "Magnesium Glycinate 400mg", kind: .supplement, metadata: nil)
        let b = try await store.findOrCreate(name: "magnesium glycinate", kind: .supplement, metadata: nil)
        #expect(a.id == b.id)
        let total = try await store.count()
        #expect(total == 1)
    }

    @Test func sameNameDifferentKindCreatesSeparateObjects() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        let food = try await store.findOrCreate(name: "Ginger", kind: .food, metadata: nil)
        let supp = try await store.findOrCreate(name: "Ginger", kind: .supplement, metadata: nil)
        #expect(food.id != supp.id)
        let total = try await store.count()
        #expect(total == 2)
    }

    @Test func archivedObjectsAreHiddenByDefault() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        let obj = try await store.findOrCreate(name: "Old Med", kind: .medication, metadata: nil)
        try await store.setArchived(id: obj.id, true)
        let visible = try await store.objects(kind: .medication, includeArchived: false)
        #expect(visible.isEmpty)
        let all = try await store.objects(kind: .medication, includeArchived: true)
        #expect(all.count == 1)
    }

    @Test func kindNilReturnsAllKinds() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        _ = try await store.findOrCreate(name: "Coffee", kind: .food, metadata: nil)
        _ = try await store.findOrCreate(name: "BPC-157", kind: .peptide, metadata: nil)
        let all = try await store.objects(kind: nil, includeArchived: false)
        #expect(all.count == 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: compile FAILURE — `cannot find 'GRDBObjectStore' in scope`

- [ ] **Step 3: Implement the store**

`HealthGraphCore/Sources/HealthGraphCore/Database/ObjectStore.swift`:

```swift
import Foundation
import GRDB

public protocol ObjectStore {
    func findOrCreate(name: String, kind: ObjectKind, metadata: Data?) async throws -> HealthObject
    func object(id: UUID) async throws -> HealthObject?
    func objects(kind: ObjectKind?, includeArchived: Bool) async throws -> [HealthObject]
    func setArchived(id: UUID, _ archived: Bool) async throws
    func count() async throws -> Int
}

public struct GRDBObjectStore: ObjectStore {
    let dbWriter: any DatabaseWriter

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    public func findOrCreate(name: String, kind: ObjectKind, metadata: Data?) async throws -> HealthObject {
        let normalized = NameNormalizer.normalize(name)
        return try await dbWriter.write { db in
            if let existing = try HealthObject
                .filter(Column("normalizedName") == normalized)
                .filter(Column("kind") == kind.rawValue)
                .fetchOne(db) {
                return existing
            }
            let object = HealthObject(kind: kind, name: name, metadata: metadata)
            try object.insert(db)
            return object
        }
    }

    public func object(id: UUID) async throws -> HealthObject? {
        try await dbWriter.read { db in
            try HealthObject.fetchOne(db, key: id)
        }
    }

    public func objects(kind: ObjectKind?, includeArchived: Bool) async throws -> [HealthObject] {
        try await dbWriter.read { db in
            var request = HealthObject.order(Column("name"))
            if let kind {
                request = request.filter(Column("kind") == kind.rawValue)
            }
            if !includeArchived {
                request = request.filter(Column("isArchived") == false)
            }
            return try request.fetchAll(db)
        }
    }

    public func setArchived(id: UUID, _ archived: Bool) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "UPDATE health_objects SET isArchived = ? WHERE id = ?",
                arguments: [archived, id]
            )
        }
    }

    public func count() async throws -> Int {
        try await dbWriter.read { db in try HealthObject.fetchCount(db) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: all pass (19 total).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): ObjectStore with normalized-name dedup and archiving"
```

---

### Task 6: RelationshipStore repository

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Database/RelationshipStore.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipStoreTests.swift`

**Interfaces:**
- Consumes: `AppDatabase`, `Relationship`, `RelStatus`.
- Produces:

```swift
public protocol RelationshipStore {
    func save(_ relationship: Relationship) async throws
    func relationship(id: UUID) async throws -> Relationship?
    func relationships(status: RelStatus?) async throws -> [Relationship]
    func relationships(fromObjectID: UUID) async throws -> [Relationship]
    func count() async throws -> Int
}
public struct GRDBRelationshipStore: RelationshipStore { public init(database: AppDatabase) }
```

`save` upserts by id (Phase 2's engine recomputes and re-saves the same edge). `relationships(status:)` orders by `confidence` descending.

- [ ] **Step 1: Write the failing tests**

`HealthGraphCore/Tests/HealthGraphCoreTests/RelationshipStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct RelationshipStoreTests {
    func rel(confidence: Double, status: RelStatus, from: UUID? = nil) -> Relationship {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        return Relationship(
            fromObjectID: from, fromCategory: from == nil ? "food" : nil,
            toCategory: "symptom", type: .possibleTrigger,
            confidence: confidence, firstSeen: now, lastSeen: now,
            lastRecomputed: now, status: status
        )
    }

    @Test func saveUpsertsById() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBRelationshipStore(database: db)
        var r = rel(confidence: 0.4, status: .candidate)
        try await store.save(r)
        r.confidence = 0.7
        r.status = .active
        try await store.save(r)
        let total = try await store.count()
        #expect(total == 1)
        let fetched = try await store.relationship(id: r.id)
        #expect(fetched?.confidence == 0.7)
        #expect(fetched?.status == .active)
    }

    @Test func filtersByStatusOrderedByConfidence() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBRelationshipStore(database: db)
        try await store.save(rel(confidence: 0.5, status: .active))
        try await store.save(rel(confidence: 0.9, status: .active))
        try await store.save(rel(confidence: 0.2, status: .decayed))
        let active = try await store.relationships(status: .active)
        #expect(active.map(\.confidence) == [0.9, 0.5])
        let all = try await store.relationships(status: nil)
        #expect(all.count == 3)
    }

    @Test func filtersByFromObject() async throws {
        let db = try AppDatabase.inMemory()
        let objects = GRDBObjectStore(database: db)
        let dairy = try await objects.findOrCreate(name: "Dairy", kind: .food, metadata: nil)
        let store = GRDBRelationshipStore(database: db)
        try await store.save(rel(confidence: 0.6, status: .active, from: dairy.id))
        try await store.save(rel(confidence: 0.3, status: .candidate))
        let forDairy = try await store.relationships(fromObjectID: dairy.id)
        #expect(forDairy.count == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: compile FAILURE — `cannot find 'GRDBRelationshipStore' in scope`

- [ ] **Step 3: Implement the store**

`HealthGraphCore/Sources/HealthGraphCore/Database/RelationshipStore.swift`:

```swift
import Foundation
import GRDB

public protocol RelationshipStore {
    func save(_ relationship: Relationship) async throws
    func relationship(id: UUID) async throws -> Relationship?
    func relationships(status: RelStatus?) async throws -> [Relationship]
    func relationships(fromObjectID: UUID) async throws -> [Relationship]
    func count() async throws -> Int
}

public struct GRDBRelationshipStore: RelationshipStore {
    let dbWriter: any DatabaseWriter

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    public func save(_ relationship: Relationship) async throws {
        try await dbWriter.write { db in
            try relationship.save(db)
        }
    }

    public func relationship(id: UUID) async throws -> Relationship? {
        try await dbWriter.read { db in
            try Relationship.fetchOne(db, key: id)
        }
    }

    public func relationships(status: RelStatus?) async throws -> [Relationship] {
        try await dbWriter.read { db in
            var request = Relationship.order(Column("confidence").desc)
            if let status {
                request = request.filter(Column("status") == status.rawValue)
            }
            return try request.fetchAll(db)
        }
    }

    public func relationships(fromObjectID: UUID) async throws -> [Relationship] {
        try await dbWriter.read { db in
            try Relationship
                .filter(Column("fromObjectID") == fromObjectID)
                .order(Column("confidence").desc)
                .fetchAll(db)
        }
    }

    public func count() async throws -> Int {
        try await dbWriter.read { db in try Relationship.fetchCount(db) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: all pass (22 total).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): RelationshipStore with upsert and status queries"
```

---

### Task 7: Synthetic-data harness

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Synthetic/SeededGenerator.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticDataTests.swift`

**Interfaces:**
- Consumes: `HealthEvent`, `HealthObject`, enums, `AppDatabase`, `GRDBEventStore`/`GRDBObjectStore`.
- Produces (Phase 2's engine tests will consume these exact types):

```swift
public struct SeededGenerator: RandomNumberGenerator { public init(seed: UInt64) }
public struct PlantedPattern {
    public var exposureName: String; public var exposureCategory: EventCategory
    public var outcomeSubtype: String; public var lagHours: Double
    public var lagJitterHours: Double; public var followProbability: Double
    public var exposureProbabilityPerDay: Double
    public init(exposureName:exposureCategory:outcomeSubtype:lagHours:lagJitterHours:followProbability:exposureProbabilityPerDay:)
}
public struct SyntheticConfig {
    public var startDate: Date; public var days: Int; public var seed: UInt64
    public var patterns: [PlantedPattern]; public var outcomeBaseRatePerDay: Double
    public var noiseFoodsPerDay: ClosedRange<Int>
    public init(startDate:days:seed:patterns:outcomeBaseRatePerDay:noiseFoodsPerDay:)
}
public struct SyntheticDataset {
    public var objects: [HealthObject]; public var events: [HealthEvent]
    public func insert(into database: AppDatabase) async throws
}
public enum SyntheticDataGenerator {
    public static func generate(config: SyntheticConfig) -> SyntheticDataset
}
```

**Behavior:** deterministic for a given seed (no `Date()`/`UUID()`-dependent *content* — UUIDs differ between runs but timestamps, categories, subtypes, and counts must be identical). Per simulated day: each pattern's exposure occurs with `exposureProbabilityPerDay` (event at 09:00 + up to 4h jitter); if it occurred, the outcome fires with `followProbability` at `lagHours ± lagJitterHours` (severity 3–8); independently, a spontaneous outcome fires with `outcomeBaseRatePerDay` at a random hour; noise food events (from a fixed list: rice, chicken, banana, oats, salad, apple) are added per `noiseFoodsPerDay`. All events `source: .manual`, `confidence: 1.0`.

- [ ] **Step 1: Write the failing tests**

`HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticDataTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct SyntheticDataTests {
    var config: SyntheticConfig {
        SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            days: 400,
            seed: 42,
            patterns: [PlantedPattern(
                exposureName: "dairy", exposureCategory: .food,
                outcomeSubtype: "bloating", lagHours: 12, lagJitterHours: 3,
                followProbability: 0.7, exposureProbabilityPerDay: 0.5
            )],
            outcomeBaseRatePerDay: 0.05,
            noiseFoodsPerDay: 1...3
        )
    }

    @Test func sameSeedProducesIdenticalContent() {
        let a = SyntheticDataGenerator.generate(config: config)
        let b = SyntheticDataGenerator.generate(config: config)
        #expect(a.events.count == b.events.count)
        #expect(a.events.map(\.timestamp) == b.events.map(\.timestamp))
        #expect(a.events.map(\.subtype) == b.events.map(\.subtype))
        #expect(a.objects.map(\.name) == b.objects.map(\.name))
    }

    @Test func plantedPatternIsStatisticallyPresent() {
        let data = SyntheticDataGenerator.generate(config: config)
        let exposures = data.events.filter { $0.subtype == "dairy" }
        let outcomes = data.events.filter { $0.subtype == "bloating" }
        #expect(exposures.count > 150) // ~200 expected over 400 days at p=0.5

        // conditional rate: outcome within 12±3h (+1h slack) after exposure
        var followed = 0
        for e in exposures {
            let hit = outcomes.contains {
                let dt = $0.timestamp.timeIntervalSince(e.timestamp) / 3600
                return dt >= 8 && dt <= 16
            }
            if hit { followed += 1 }
        }
        let conditional = Double(followed) / Double(exposures.count)
        #expect(conditional > 0.55 && conditional < 0.85) // planted 0.7

        // base rate on non-exposure days stays low
        let cal = Calendar(identifier: .gregorian)
        let exposureDays = Set(exposures.map { cal.startOfDay(for: $0.timestamp) })
        let spontaneous = outcomes.filter { outcome in
            !exposureDays.contains(cal.startOfDay(for: outcome.timestamp.addingTimeInterval(-12 * 3600)))
        }
        let nonExposureDayCount = max(1, config.days - exposureDays.count)
        let baseRate = Double(spontaneous.count) / Double(nonExposureDayCount)
        #expect(baseRate < 0.2) // planted 0.05, generous ceiling
    }

    @Test func datasetInsertsIntoDatabase() async throws {
        let db = try AppDatabase.inMemory()
        let data = SyntheticDataGenerator.generate(config: config)
        try await data.insert(into: db)
        let eventCount = try await GRDBEventStore(database: db).count()
        #expect(eventCount == data.events.count)
        let objectCount = try await GRDBObjectStore(database: db).count()
        #expect(objectCount == data.objects.count)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: compile FAILURE — `cannot find 'SyntheticConfig' in scope`

- [ ] **Step 3: Implement the seeded RNG**

`HealthGraphCore/Sources/HealthGraphCore/Synthetic/SeededGenerator.swift`:

```swift
/// SplitMix64 — deterministic RNG so synthetic datasets are reproducible.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
```

- [ ] **Step 4: Implement the generator**

`HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift`:

```swift
import Foundation

/// A correlation deliberately planted in generated data. Phase 2's engine
/// must find these and must NOT find patterns in the noise.
public struct PlantedPattern {
    public var exposureName: String
    public var exposureCategory: EventCategory
    public var outcomeSubtype: String
    public var lagHours: Double
    public var lagJitterHours: Double
    public var followProbability: Double
    public var exposureProbabilityPerDay: Double

    public init(exposureName: String, exposureCategory: EventCategory,
                outcomeSubtype: String, lagHours: Double, lagJitterHours: Double,
                followProbability: Double, exposureProbabilityPerDay: Double) {
        self.exposureName = exposureName
        self.exposureCategory = exposureCategory
        self.outcomeSubtype = outcomeSubtype
        self.lagHours = lagHours
        self.lagJitterHours = lagJitterHours
        self.followProbability = followProbability
        self.exposureProbabilityPerDay = exposureProbabilityPerDay
    }
}

public struct SyntheticConfig {
    public var startDate: Date
    public var days: Int
    public var seed: UInt64
    public var patterns: [PlantedPattern]
    public var outcomeBaseRatePerDay: Double
    public var noiseFoodsPerDay: ClosedRange<Int>

    public init(startDate: Date, days: Int, seed: UInt64, patterns: [PlantedPattern],
                outcomeBaseRatePerDay: Double, noiseFoodsPerDay: ClosedRange<Int>) {
        self.startDate = startDate
        self.days = days
        self.seed = seed
        self.patterns = patterns
        self.outcomeBaseRatePerDay = outcomeBaseRatePerDay
        self.noiseFoodsPerDay = noiseFoodsPerDay
    }
}

public struct SyntheticDataset {
    public var objects: [HealthObject]
    public var events: [HealthEvent]

    public func insert(into database: AppDatabase) async throws {
        let objectStore = GRDBObjectStore(database: database)
        let eventStore = GRDBEventStore(database: database)
        // findOrCreate remaps object ids; keep event objectIDs consistent.
        var idMap: [UUID: UUID] = [:]
        for object in objects {
            let saved = try await objectStore.findOrCreate(
                name: object.name, kind: object.kind, metadata: object.metadata)
            idMap[object.id] = saved.id
        }
        var remapped = events
        for i in remapped.indices {
            if let oid = remapped[i].objectID { remapped[i].objectID = idMap[oid] ?? oid }
        }
        try await eventStore.save(remapped)
    }
}

public enum SyntheticDataGenerator {
    static let noiseFoods = ["rice", "chicken", "banana", "oats", "salad", "apple"]

    public static func generate(config: SyntheticConfig) -> SyntheticDataset {
        var rng = SeededGenerator(seed: config.seed)
        var objects: [HealthObject] = []
        var events: [HealthEvent] = []

        var exposureObjects: [String: HealthObject] = [:]
        for pattern in config.patterns {
            let kind: ObjectKind = pattern.exposureCategory == .food ? .food : .supplement
            let object = HealthObject(kind: kind, name: pattern.exposureName)
            exposureObjects[pattern.exposureName] = object
            objects.append(object)
        }
        var noiseObjects: [String: HealthObject] = [:]
        for name in Self.noiseFoods {
            let object = HealthObject(kind: .food, name: name)
            noiseObjects[name] = object
            objects.append(object)
        }

        let tz = "UTC"
        for day in 0..<config.days {
            let dayStart = config.startDate.addingTimeInterval(Double(day) * 86_400)

            for pattern in config.patterns {
                guard Double.random(in: 0..<1, using: &rng) < pattern.exposureProbabilityPerDay
                else { continue }
                let jitter = Double.random(in: 0..<4, using: &rng) * 3600
                let exposureTime = dayStart.addingTimeInterval(9 * 3600 + jitter)
                events.append(HealthEvent(
                    timestamp: exposureTime, timezoneID: tz,
                    category: pattern.exposureCategory,
                    subtype: pattern.exposureName,
                    objectID: exposureObjects[pattern.exposureName]?.id,
                    source: .manual
                ))
                if Double.random(in: 0..<1, using: &rng) < pattern.followProbability {
                    let lag = pattern.lagHours
                        + Double.random(in: -pattern.lagJitterHours...pattern.lagJitterHours, using: &rng)
                    events.append(HealthEvent(
                        timestamp: exposureTime.addingTimeInterval(lag * 3600),
                        timezoneID: tz, category: .symptom,
                        subtype: pattern.outcomeSubtype,
                        value: Double(Int.random(in: 3...8, using: &rng)),
                        source: .manual
                    ))
                }
            }

            if Double.random(in: 0..<1, using: &rng) < config.outcomeBaseRatePerDay,
               let subtype = config.patterns.first?.outcomeSubtype {
                let hour = Double.random(in: 7..<22, using: &rng)
                events.append(HealthEvent(
                    timestamp: dayStart.addingTimeInterval(hour * 3600),
                    timezoneID: tz, category: .symptom, subtype: subtype,
                    value: Double(Int.random(in: 2...6, using: &rng)),
                    source: .manual
                ))
            }

            let noiseCount = Int.random(in: config.noiseFoodsPerDay, using: &rng)
            for _ in 0..<noiseCount {
                let name = Self.noiseFoods[Int.random(in: 0..<Self.noiseFoods.count, using: &rng)]
                let hour = Double.random(in: 7..<21, using: &rng)
                events.append(HealthEvent(
                    timestamp: dayStart.addingTimeInterval(hour * 3600),
                    timezoneID: tz, category: .food, subtype: name,
                    objectID: noiseObjects[name]?.id, source: .manual
                ))
            }
        }

        events.sort { $0.timestamp < $1.timestamp }
        return SyntheticDataset(objects: objects, events: events)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`
Expected: all pass (25 total). If `plantedPatternIsStatisticallyPresent` fails on the bounds, the generator logic is wrong (400 days at these probabilities sits comfortably inside the tolerances) — fix the generator, do not widen the bounds.

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): synthetic-data harness with seeded planted correlations"
```

---

### Task 8: Link package to the app + database bootstrap — ⚠️ HUMAN CHECKPOINT

**Files:**
- Modify: `Food Intolerances.xcodeproj` (via Xcode GUI — human step)
- Create: `Models/HealthGraphProvider.swift`

**Interfaces:**
- Consumes: `AppDatabase` (Task 1).
- Produces: `HealthGraphProvider.shared: AppDatabase` — the app-side singleton every app-target file uses. DB file: `Application Support/HealthGraph/healthgraph.sqlite`.

- [ ] **Step 1: HUMAN — add the local package in Xcode (~1 minute)**

In Xcode: open `Food Intolerances.xcodeproj` → **File → Add Package Dependencies… → Add Local…** → select the `HealthGraphCore` folder → when prompted, add the **HealthGraphCore** library product to the **Food Intolerances** target. Then also link it to the test target (needed for `import HealthGraphCore` in Task 9's tests): project → **Food IntolerancesTests** target → Build Phases → Link Binary With Libraries → + → HealthGraphCore. (Verify afterwards: both targets list HealthGraphCore under their libraries.)

- [ ] **Step 2: Create the provider**

`Models/HealthGraphProvider.swift` (the `Models/` folder is a synchronized group — the file joins the app target automatically):

```swift
import Foundation
import HealthGraphCore

/// App-wide access to the Health Graph database.
enum HealthGraphProvider {
    static let shared: AppDatabase = {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let url = support.appendingPathComponent("HealthGraph/healthgraph.sqlite")
            return try AppDatabase.open(at: url)
        } catch {
            fatalError("Health Graph database could not be opened: \(error)")
        }
    }()

    /// Root folder for event attachments (photos). Paths stored on events
    /// are relative to Application Support.
    static func attachmentsDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = support.appendingPathComponent("HealthGraph/attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

- [ ] **Step 3: Verify the app builds**

Run:
```bash
cd /Users/leo/Desktop/FoodIntolerances
xcodebuild -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. (If the scheme or simulator name differs, list them with `xcodebuild -list` / `xcrun simctl list devices available`.)

- [ ] **Step 4: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add "Food Intolerances.xcodeproj" Models/HealthGraphProvider.swift
git commit -m "feat(app): link HealthGraphCore package and add database provider"
```

---

### Task 9: SwiftData → Health Graph migrator

**Files:**
- Create: `Models/SwiftDataMigrator.swift`
- Test: `Food IntolerancesTests/SwiftDataMigratorTests.swift`

**Interfaces:**
- Consumes: app SwiftData models (`LogEntry`, `TrackedItem`, `AvoidedItem`, `CabinetItem`, `OngoingSymptom`, `SymptomCheckIn`, `TherapyProtocol` — all existing), `AppDatabase`, `GRDBEventStore`, `GRDBObjectStore`, enums (`.legacyImport`, `.careProtocol`, `.activity`).
- Produces: `SwiftDataMigrator.run(context:database:force:) async throws -> Report` (`@MainActor`), `SwiftDataMigrator.isCompleted: Bool`, `SwiftDataMigrator.Report` (Codable struct of counters). Task 10's debug screen calls these.

**Mapping rules (source of truth for the code below):**

| Source | Destination |
|---|---|
| `LogEntry` (`itemType == .symptom`) | one `symptom` event per name in `symptoms` (fallback `[itemName]`); `value` = `Double(severity)` (legacy scale preserved as-is); `endTimestamp` = `endDate`; metadata: notes, affectedAreas, symptomTriggers, contributingFactors, category + legacy environment (moonPhase, atmosphericPressure, suddenChange, season, isMercuryRetrograde); `symptomPhotoData` saved to attachments dir; `isActive == false` → `deletedAt` set |
| `LogEntry.treatments` | one `medication`/`supplement` event each (kind from `type` containing "supp") + `findOrCreate` object |
| `LogEntry` (`itemType == .foodDrink`) | one `food` event, object = `findOrCreate(foodDrinkItem ?? itemName, .food)` |
| `TrackedItem` | object only: kind from type (supplement/medication/food); metadata brand+notes; `!isActive` → archived |
| `AvoidedItem` | object only: food/drink→`.food`, supplement→`.supplement`, activity→`.activity`; metadata avoided="true", reason, isRecommended |
| `CabinetItem` | object only: category containing "med"→`.medication`, "device"→`.device`, else `.supplement`; metadata dosage, ingredients, quantity, stock fields |
| `OngoingSymptom` | one `symptom` event with `endTimestamp`; metadata episodeID, isOpen, usedProtocolID |
| `SymptomCheckIn` | one `symptom` event; `subtype` = parent symptom's name (fallback "check-in"); metadata episodeID |
| `TherapyProtocol` | object only: `.careProtocol`; metadata instructions, frequency, duration, status, effectiveness, symptoms, tags. (`protocolMarker` adherence events are NOT reconstructable from legacy data — deliberately skipped.) |

Timestamps: `combine(day: entry.date, time: entry.timeOfDay)` merges the clock time when present. All migrated events: `source: .legacyImport`, `timezoneID = TimeZone.current.identifier`, `confidence: 1.0`.

- [ ] **Step 1: Write the failing tests**

`Food IntolerancesTests/SwiftDataMigratorTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct SwiftDataMigratorTests {
    func makeContext() throws -> ModelContext {
        StringArrayTransformer.register()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LogEntry.self, TrackedItem.self, AvoidedItem.self, CabinetItem.self,
            OngoingSymptom.self, SymptomCheckIn.self, TherapyProtocol.self,
            TherapyProtocolItem.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func migratesSymptomLogEntry() async throws {
        let context = try makeContext()
        let entry = LogEntry(
            itemName: "Headache", itemType: .symptom, category: "Neurological",
            symptoms: ["Headache"], severity: 4, notes: "after lunch",
            date: Date(timeIntervalSince1970: 1_740_000_000),
            moonPhase: "Full Moon", atmosphericPressure: "Falling",
            suddenChange: true, isMercuryRetrograde: false, season: "Winter"
        )
        context.insert(entry)
        try context.save()

        let db = try AppDatabase.inMemory()
        let report = try await SwiftDataMigrator.run(context: context, database: db, force: true)

        #expect(report.logEntriesMigrated == 1)
        #expect(report.eventsCreated == 1)
        let events = GRDBEventStore(database: db)
        let all = try await events.recentEvents(limit: 10)
        #expect(all.count == 1)
        #expect(all.first?.category == .symptom)
        #expect(all.first?.subtype == "Headache")
        #expect(all.first?.value == 4)
        #expect(all.first?.source == .legacyImport)
    }

    @Test func migratesTrackedItemsWithDedup() async throws {
        let context = try makeContext()
        context.insert(TrackedItem(name: "Magnesium Glycinate 400mg", type: .supplement))
        context.insert(TrackedItem(name: "magnesium glycinate", type: .supplement))
        context.insert(TrackedItem(name: "Ibuprofen", type: .medication, isActive: false))
        try context.save()

        let db = try AppDatabase.inMemory()
        let report = try await SwiftDataMigrator.run(context: context, database: db, force: true)

        #expect(report.trackedItemsMigrated == 3)
        let objects = GRDBObjectStore(database: db)
        let objectCount = try await objects.count()
        #expect(objectCount == 2) // magnesium deduped
        let meds = try await objects.objects(kind: .medication, includeArchived: true)
        #expect(meds.first?.isArchived == true) // inactive -> archived
    }

    @Test func migratesOngoingSymptomWithCheckIns() async throws {
        let context = try makeContext()
        let ongoing = OngoingSymptom(
            name: "Back pain",
            startDate: Date(timeIntervalSince1970: 1_740_000_000)
        )
        context.insert(ongoing)
        context.insert(SymptomCheckIn(
            parentSymptomID: ongoing.id,
            date: Date(timeIntervalSince1970: 1_740_086_400),
            severity: 5
        ))
        try context.save()

        let db = try AppDatabase.inMemory()
        let report = try await SwiftDataMigrator.run(context: context, database: db, force: true)

        #expect(report.ongoingSymptomsMigrated == 1)
        #expect(report.checkInsMigrated == 1)
        let events = GRDBEventStore(database: db)
        let all = try await events.recentEvents(limit: 10)
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.category == .symptom })
        #expect(all.contains { $0.subtype == "Back pain" && $0.value == 5 }) // check-in inherits name
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd /Users/leo/Desktop/FoodIntolerances
xcodebuild -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:"Food IntolerancesTests/SwiftDataMigratorTests" 2>&1 | tail -10
```
Expected: compile FAILURE — `cannot find 'SwiftDataMigrator' in scope`

- [ ] **Step 3: Implement the migrator**

`Models/SwiftDataMigrator.swift`:

```swift
import Foundation
import SwiftData
import HealthGraphCore

/// One-time SwiftData -> Health Graph migration. Reads the legacy store,
/// never writes to it. Runs behind a completion flag; DEBUG screen can force.
struct SwiftDataMigrator {

    struct Report: Codable, Equatable {
        var logEntriesMigrated = 0
        var trackedItemsMigrated = 0
        var avoidedItemsMigrated = 0
        var cabinetItemsMigrated = 0
        var ongoingSymptomsMigrated = 0
        var checkInsMigrated = 0
        var protocolsMigrated = 0
        var eventsCreated = 0
        var objectsCreated = 0
        var attachmentsSaved = 0
    }

    static let completedFlagKey = "hg.migration.v1.completed"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedFlagKey)
    }

    @MainActor
    static func run(context: ModelContext, database: AppDatabase,
                    force: Bool = false) async throws -> Report {
        guard force || !isCompleted else { return Report() }

        let events = GRDBEventStore(database: database)
        let objects = GRDBObjectStore(database: database)
        var report = Report()
        let tz = TimeZone.current.identifier

        // --- LogEntry -> events ---
        for entry in try context.fetch(FetchDescriptor<LogEntry>()) {
            let ts = combine(day: entry.date, time: entry.timeOfDay)
            let deletedAt: Date? = entry.isActive ? nil : Date()
            var meta: [String: String] = [:]
            if !entry.notes.isEmpty { meta["notes"] = entry.notes }
            if !entry.category.isEmpty { meta["legacyCategory"] = entry.category }
            if !entry.moonPhase.isEmpty { meta["moonPhase"] = entry.moonPhase }
            meta["atmosphericPressure"] = entry.atmosphericPressure
            meta["suddenChange"] = String(entry.suddenChange)
            if !entry.season.isEmpty { meta["season"] = entry.season }
            meta["isMercuryRetrograde"] = String(entry.isMercuryRetrograde)
            if !entry.additionalContext.isEmpty { meta["additionalContext"] = entry.additionalContext }

            switch entry.itemType {
            case .symptom:
                var attachmentPath: String?
                if let photo = entry.symptomPhotoData {
                    attachmentPath = try? saveAttachment(photo, id: entry.id)
                    if attachmentPath != nil { report.attachmentsSaved += 1 }
                }
                let names = entry.symptoms.isEmpty ? [entry.itemName] : entry.symptoms
                for name in names {
                    var m = meta
                    if !entry.affectedAreas.isEmpty {
                        m["affectedAreas"] = entry.affectedAreas.joined(separator: "|")
                    }
                    if !entry.symptomTriggers.isEmpty {
                        m["symptomTriggers"] = entry.symptomTriggers.joined(separator: "|")
                    }
                    if !entry.contributingFactors.isEmpty {
                        m["contributingFactors"] = entry.contributingFactors.joined(separator: "|")
                    }
                    try await events.save(HealthEvent(
                        timestamp: ts, timezoneID: tz, endTimestamp: entry.endDate,
                        category: .symptom, subtype: name,
                        value: Double(entry.severity), source: .legacyImport,
                        metadata: encode(m), attachmentPath: attachmentPath,
                        deletedAt: deletedAt
                    ))
                    report.eventsCreated += 1
                }
                for treatment in entry.treatments {
                    let isSupplement = treatment.type.lowercased().contains("supp")
                    let kind: ObjectKind = isSupplement ? .supplement : .medication
                    let object = try await objects.findOrCreate(
                        name: treatment.name, kind: kind, metadata: nil)
                    var m: [String: String] = ["fromLogEntry": entry.id.uuidString]
                    if let dosage = treatment.dosage { m["dosage"] = dosage }
                    if let eff = treatment.effectiveness { m["effectiveness"] = String(eff) }
                    try await events.save(HealthEvent(
                        timestamp: treatment.startDate, timezoneID: tz,
                        endTimestamp: treatment.endDate,
                        category: isSupplement ? .supplement : .medication,
                        subtype: treatment.name, objectID: object.id,
                        source: .legacyImport, metadata: encode(m)
                    ))
                    report.eventsCreated += 1
                }
            case .foodDrink:
                let foodName = entry.foodDrinkItem ?? entry.itemName
                let object = try await objects.findOrCreate(
                    name: foodName, kind: .food, metadata: nil)
                try await events.save(HealthEvent(
                    timestamp: ts, timezoneID: tz, category: .food,
                    subtype: foodName, objectID: object.id,
                    source: .legacyImport, metadata: encode(meta),
                    deletedAt: deletedAt
                ))
                report.eventsCreated += 1
            }
            report.logEntriesMigrated += 1
        }

        // --- TrackedItem -> objects ---
        for item in try context.fetch(FetchDescriptor<TrackedItem>()) {
            let kind: ObjectKind
            switch item.type {
            case .supplement: kind = .supplement
            case .medication: kind = .medication
            case .food: kind = .food
            }
            var m: [String: String] = [:]
            if let brand = item.brand { m["brand"] = brand }
            if !item.notes.isEmpty { m["notes"] = item.notes }
            let object = try await objects.findOrCreate(
                name: item.name, kind: kind, metadata: encode(m))
            if !item.isActive {
                try await objects.setArchived(id: object.id, true)
            }
            report.trackedItemsMigrated += 1
        }

        // --- AvoidedItem -> objects ---
        for item in try context.fetch(FetchDescriptor<AvoidedItem>()) {
            let kind: ObjectKind
            switch item.type {
            case .food, .drink: kind = .food
            case .supplement: kind = .supplement
            case .activity: kind = .activity
            }
            var m: [String: String] = ["avoided": "true",
                                       "isRecommended": String(item.isRecommended)]
            if let reason = item.reason { m["reason"] = reason }
            _ = try await objects.findOrCreate(name: item.name, kind: kind, metadata: encode(m))
            report.avoidedItemsMigrated += 1
        }

        // --- CabinetItem -> objects ---
        for item in try context.fetch(FetchDescriptor<CabinetItem>()) {
            let category = (item.category ?? "").lowercased()
            let kind: ObjectKind = category.contains("med") ? .medication
                : category.contains("device") ? .device : .supplement
            var m: [String: String] = [:]
            if let v = item.dosage { m["dosage"] = v }
            if let v = item.ingredients { m["ingredients"] = v }
            if let v = item.quantity { m["quantity"] = v }
            if let v = item.usageNotes { m["usageNotes"] = v }
            if let v = item.currentStock { m["currentStock"] = String(v) }
            if let v = item.refillThreshold { m["refillThreshold"] = String(v) }
            m["refillNotificationEnabled"] = String(item.refillNotificationEnabled)
            m["usageCount"] = String(item.usageCount)
            _ = try await objects.findOrCreate(name: item.name, kind: kind, metadata: encode(m))
            report.cabinetItemsMigrated += 1
        }

        // --- OngoingSymptom + SymptomCheckIn -> events ---
        var episodeNames: [UUID: String] = [:]
        for symptom in try context.fetch(FetchDescriptor<OngoingSymptom>()) {
            episodeNames[symptom.id] = symptom.name
            var m: [String: String] = ["episodeID": symptom.id.uuidString,
                                       "isOpen": String(symptom.isOpen)]
            if !symptom.notes.isEmpty { m["notes"] = symptom.notes }
            if let pid = symptom.usedProtocolID { m["usedProtocolID"] = pid.uuidString }
            try await events.save(HealthEvent(
                timestamp: symptom.startDate, timezoneID: tz,
                endTimestamp: symptom.endDate, category: .symptom,
                subtype: symptom.name, source: .legacyImport, metadata: encode(m)
            ))
            report.eventsCreated += 1
            report.ongoingSymptomsMigrated += 1
        }
        for checkIn in try context.fetch(FetchDescriptor<SymptomCheckIn>()) {
            var m: [String: String] = ["episodeID": checkIn.parentSymptomID.uuidString]
            if !checkIn.notes.isEmpty { m["notes"] = checkIn.notes }
            if !checkIn.protocolUsed.isEmpty { m["protocolUsed"] = checkIn.protocolUsed }
            try await events.save(HealthEvent(
                timestamp: checkIn.date, timezoneID: tz, category: .symptom,
                subtype: episodeNames[checkIn.parentSymptomID] ?? "check-in",
                value: Double(checkIn.severity), source: .legacyImport,
                metadata: encode(m)
            ))
            report.eventsCreated += 1
            report.checkInsMigrated += 1
        }

        // --- TherapyProtocol -> objects ---
        for proto in try context.fetch(FetchDescriptor<TherapyProtocol>()) {
            var m: [String: String] = [
                "instructions": proto.instructions,
                "frequency": proto.frequency,
                "duration": proto.duration,
                "status": proto.status
            ]
            if let eff = proto.protocolEffectiveness { m["effectiveness"] = String(eff) }
            if let symptoms = proto.symptoms, !symptoms.isEmpty {
                m["symptoms"] = symptoms.joined(separator: "|")
            }
            if let tags = proto.tags, !tags.isEmpty {
                m["tags"] = tags.joined(separator: "|")
            }
            _ = try await objects.findOrCreate(
                name: proto.title, kind: .careProtocol, metadata: encode(m))
            report.protocolsMigrated += 1
        }

        report.objectsCreated = try await objects.count()

        if !force {
            UserDefaults.standard.set(true, forKey: completedFlagKey)
        }
        return report
    }

    // MARK: - Helpers

    static func combine(day: Date, time: Date?) -> Date {
        guard let time else { return day }
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0,
                        second: 0, of: day) ?? day
    }

    static func encode(_ dict: [String: String]) -> Data? {
        dict.isEmpty ? nil : try? JSONEncoder().encode(dict)
    }

    static func saveAttachment(_ data: Data, id: UUID) throws -> String {
        let dir = try HealthGraphProvider.attachmentsDirectory()
        let file = dir.appendingPathComponent("\(id.uuidString).jpg")
        try data.write(to: file)
        return "HealthGraph/attachments/\(id.uuidString).jpg"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /Users/leo/Desktop/FoodIntolerances
xcodebuild -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:"Food IntolerancesTests/SwiftDataMigratorTests" 2>&1 | tail -10
```
Expected: `** TEST SUCCEEDED **` (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add Models/SwiftDataMigrator.swift "Food IntolerancesTests/SwiftDataMigratorTests.swift"
git commit -m "feat(app): one-time SwiftData -> Health Graph migrator behind flag"
```

---

### Task 10: Debug screen + final verification

**Files:**
- Create: `Views/HealthGraphDebugView.swift`
- Modify: `MoreView.swift` (add a DEBUG-only entry)

**Interfaces:**
- Consumes: `HealthGraphProvider.shared`, `GRDBEventStore`, `GRDBObjectStore`, `GRDBRelationshipStore`, `SwiftDataMigrator`.
- Produces: nothing downstream — Phase 0's only UI, DEBUG builds only.

- [ ] **Step 1: Create the debug screen**

`Views/HealthGraphDebugView.swift`:

```swift
#if DEBUG
import SwiftUI
import SwiftData
import HealthGraphCore

/// DEBUG-only inspector for the Health Graph database. Phase 0's only UI.
struct HealthGraphDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var eventCount = 0
    @State private var objectCount = 0
    @State private var relationshipCount = 0
    @State private var recent: [HealthEvent] = []
    @State private var report: SwiftDataMigrator.Report?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var database: AppDatabase { HealthGraphProvider.shared }

    var body: some View {
        List {
            Section("Health Graph") {
                LabeledContent("Events", value: "\(eventCount)")
                LabeledContent("Objects", value: "\(objectCount)")
                LabeledContent("Relationships", value: "\(relationshipCount)")
                LabeledContent("Migration flag",
                               value: SwiftDataMigrator.isCompleted ? "completed" : "not run")
            }
            Section("Actions") {
                Button(isWorking ? "Working…" : "Run SwiftData migration (force)") {
                    Task { await migrate() }
                }
                .disabled(isWorking)
                Button("Load synthetic dataset (400 days)") {
                    Task { await loadSynthetic() }
                }
                .disabled(isWorking)
            }
            if let report {
                Section("Last migration report") {
                    Text(reportText(report)).font(.caption.monospaced())
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            Section("Last 20 events") {
                ForEach(recent) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.category.rawValue) · \(event.subtype ?? "—")")
                        Text("\(event.timestamp.formatted()) · \(event.source.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Health Graph Debug")
        .task { await refresh() }
    }

    private func refresh() async {
        do {
            eventCount = try await GRDBEventStore(database: database).count()
            objectCount = try await GRDBObjectStore(database: database).count()
            relationshipCount = try await GRDBRelationshipStore(database: database).count()
            recent = try await GRDBEventStore(database: database).recentEvents(limit: 20)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func migrate() async {
        isWorking = true
        defer { isWorking = false }
        do {
            report = try await SwiftDataMigrator.run(
                context: modelContext, database: database, force: true)
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func loadSynthetic() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let config = SyntheticConfig(
                startDate: Date().addingTimeInterval(-400 * 86_400),
                days: 400, seed: 42,
                patterns: [PlantedPattern(
                    exposureName: "dairy", exposureCategory: .food,
                    outcomeSubtype: "bloating", lagHours: 12, lagJitterHours: 3,
                    followProbability: 0.7, exposureProbabilityPerDay: 0.5
                )],
                outcomeBaseRatePerDay: 0.05,
                noiseFoodsPerDay: 1...3
            )
            try await SyntheticDataGenerator.generate(config: config).insert(into: database)
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func reportText(_ r: SwiftDataMigrator.Report) -> String {
        """
        logEntries: \(r.logEntriesMigrated)  tracked: \(r.trackedItemsMigrated)
        avoided: \(r.avoidedItemsMigrated)  cabinet: \(r.cabinetItemsMigrated)
        ongoing: \(r.ongoingSymptomsMigrated)  checkIns: \(r.checkInsMigrated)
        protocols: \(r.protocolsMigrated)
        events created: \(r.eventsCreated)  objects total: \(r.objectsCreated)
        attachments: \(r.attachmentsSaved)
        """
    }
}
#endif
```

- [ ] **Step 2: Add the entry point in MoreView**

Open `MoreView.swift`, locate its main `List`/menu content, and add this snippet as the last section (adjusting only indentation; if MoreView is not inside a `NavigationStack`/`NavigationView`, wrap the link's destination in one):

```swift
#if DEBUG
Section("Developer") {
    NavigationLink("Health Graph Debug") {
        HealthGraphDebugView()
    }
}
#endif
```

- [ ] **Step 3: Full verification — package tests, app tests, build**

Run:
```bash
cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3
cd /Users/leo/Desktop/FoodIntolerances
xcodebuild -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:"Food IntolerancesTests/SwiftDataMigratorTests" 2>&1 | tail -3
```
Expected: package `Test run with 25 tests passed`; app `** TEST SUCCEEDED **`.

- [ ] **Step 4: Manual smoke test (human or simulator-driving agent)**

Launch the app in the simulator, open More → Health Graph Debug: counts show 0; tap "Load synthetic dataset" → Events count jumps to several hundred and the last-20 list fills; tap "Run SwiftData migration (force)" → report appears with legacy counts.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add Views/HealthGraphDebugView.swift MoreView.swift
git commit -m "feat(app): DEBUG Health Graph inspector with migration and synthetic data"
```

---

## Done criteria (Phase 0 exit)

- `swift test` in `HealthGraphCore`: 25 tests green.
- App test target: 3 migrator tests green; app builds and runs.
- Debug screen shows event/object counts; synthetic dataset loads; forced migration produces a plausible report against Leo's real data (verified manually).
- The SwiftData store is untouched (app still runs on it — feature work moves to the graph in Phase 1).
- Spec deltas recorded: `EventSource.legacyImport`, `ObjectKind.activity`, `ObjectKind.careProtocol = "protocol"` (spec §4 updated alongside this plan).
