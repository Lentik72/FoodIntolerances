# Demo-data hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make demo/seed data on the Health Graph precisely and safely removable — marked, namespaced so it can never collide with real data, cleanable without deleting real rows, and honestly surfaced (and purged in Release).

**Architecture:** A nullable `syntheticBatch` column (migration v7) marks seeded rows on `health_events` and `health_objects`. A single `DemoBatch` helper is the one source of truth for batch identifiers and the `"demo:<batch>|"` namespace applied to demo dedup keys and demo object identity. A shared `DemoDataMaintenance` cleanup routine runs in two modes — a guarded **purge** (clear button / Release bootstrap) and an unconditional **reload** (seed buttons) — each wiping non-dismissed relationships in one transaction so derived findings rebuild cleanly. Insights gates dismissal and shows a DEBUG banner while demo data is present; Release purges synthetic rows synchronously at bootstrap.

**Tech Stack:** Swift 6, SwiftUI, GRDB (SQLite), Swift Testing (`import Testing`), the `HealthGraphCore` SPM package.

## Global Constraints

- **Marking:** a nullable `syntheticBatch TEXT` column on `health_events` and `health_objects`; `NULL` means real. No backfill — existing rows are real by definition.
- **Batch identifiers (exact):** `"synthetic"`, `"mood"`, `"outsideFactors"`, `"weather"`. One per seed button.
- **Namespace prefix (exact):** `"demo:<batch>|"`, applied to both demo event dedup keys and demo object `normalizedName`. Derived in exactly one place (`DemoBatch`), used for both the lookup key and the persisted row.
- **Object identity is NOT namespaced by extending the unique key.** SQLite treats `NULL`s as distinct in unique indexes, so `unique(normalizedName, kind, syntheticBatch)` would permit two real rows of the same name+kind. Prefix `normalizedName` instead; leave the `unique(normalizedName, kind)` invariant (`AppDatabase.swift:48`) untouched.
- **Cleanup is one transaction** in this order: (1) delete `relationships` except `status == 'userDismissed'`; (2) delete matching `health_events`; (3) delete matching `health_objects`. Order is fixed by the schema's real FKs (`health_events.objectID` → `.setNull` at `:59`; relationships' object refs → `.cascade` at `:77`,`:80`).
- **Purge mode** (clear button, Release purge) opens with an **existence guard across BOTH tables**: proceed only if a synthetic row matches in `health_events` OR `health_objects`; else touch nothing and return `didClean = false`.
- **Reload mode** (seed buttons) wipes non-dismissed relationships **unconditionally** (the incoming dataset shifts every baseline) and scoped-deletes only that batch's rows.
- **Recompute runs only when data changed:** after a reload's insert (always), or after a purge that returned `didClean == true`. The cleanup routine itself never recomputes.
- **Release purge:** always-compiled, active only in non-DEBUG. Runs the guarded purge **synchronously** during `HealthGraphProvider.shared` bootstrap, after migration and before the handle is returned. It does **not** schedule a recompute — the freshly-constructed `InsightsRefreshCoordinator` recomputes on its `lastRecomputeAt == nil` never-run branch (`RecomputePolicy.swift:7`) when Insights loads; a second recompute would race its `isRunning` single-flight (`InsightsRefreshCoordinator.swift:22-24`).
- **Dismissal is gated at both layers** while demo data exists: UI hides the action, and `InsightsViewModel.dismiss`/`undoDismiss` re-check the database and bail. `pendingUndo` is cleared when demo data becomes present.
- **Banner** (`#if DEBUG`): a persistent notice atop Insights while any synthetic row exists.
- **Migrations are append-only and immutable** (`AppDatabase.swift:31-35`). Add v7; never edit v1–v6.
- **The `syntheticBatch` column, `DemoBatch`, `DemoDataMaintenance`, and the Release purge are NOT `#if DEBUG`** — only the seed UI and the Insights banner are. Release must be able to purge.
- **Test env:** HealthGraphCore tests run with `swift test --package-path HealthGraphCore`. App tests run on the `iPhone 17 Pro` simulator (only runnable sim) with `-parallel-testing-enabled NO` (mandatory). A lone `SwiftDataMigratorTests` teardown crash is known/unrelated. New package files are picked up automatically by SPM; new app files by `PBXFileSystemSynchronizedRootGroup` — never hand-edit the `.pbxproj`. Never stage the cosmetic `.pbxproj` re-sort or the `UserInterfaceState.xcuserstate`.

---

## File Structure

**Create:**
- `HealthGraphCore/Sources/HealthGraphCore/Synthetic/DemoBatch.swift` — batch identifiers + the single namespace helper (dedup-key prefix, normalized-name prefix, event stamping). Always-compiled.
- `HealthGraphCore/Sources/HealthGraphCore/Database/DemoDataMaintenance.swift` — the cleanup routine (`SyntheticScope`, purge/reload, `hasSyntheticData`), async + sync entry points. Always-compiled.
- `HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticBatchMigrationTests.swift`
- `HealthGraphCore/Tests/HealthGraphCoreTests/DemoBatchTests.swift`
- `HealthGraphCore/Tests/HealthGraphCoreTests/BatchAwareObjectTests.swift`
- `HealthGraphCore/Tests/HealthGraphCoreTests/DemoDataMaintenanceTests.swift`

**Modify:**
- `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift` — add migration v7 (column on both tables + two partial indexes).
- `HealthGraphCore/Sources/HealthGraphCore/Models/HealthEvent.swift` — add `syntheticBatch: String?`.
- `HealthGraphCore/Sources/HealthGraphCore/Models/HealthObject.swift` — add `syntheticBatch: String?`.
- `HealthGraphCore/Sources/HealthGraphCore/Database/ObjectStore.swift` — `findOrCreate` gains defaulted `syntheticBatch:`.
- `HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift` — `generate`/`SyntheticDataset` thread a required `batch`.
- `Views/HealthGraphDebugView.swift` — seed buttons use reload mode + one recompute; new Clear button; hand-built seeds stamp+namespace.
- `Views/HealthOS/Insights/InsightsViewModel.swift` — dismissal gate + `demoDataLoaded` flag + `pendingUndo` clear.
- `Views/HealthOS/Insights/InsightsView.swift` — DEBUG banner; hide Dismiss while demo loaded.
- `Models/HealthGraphProvider.swift` — synchronous Release purge at bootstrap.

---

## Task 1: Schema v7 — `syntheticBatch` column, model fields, partial indexes

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Models/HealthEvent.swift:9-60`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Models/HealthObject.swift:9-32`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift:270` (insert new migration just before `return migrator`)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticBatchMigrationTests.swift`

**Interfaces:**
- Consumes: `AppDatabase.inMemory()`, `AppDatabase.migrator`, GRDB `Database`.
- Produces: `HealthEvent.syntheticBatch: String?` and `HealthObject.syntheticBatch: String?` (both default `nil`); migration `"v7"` adding column `syntheticBatch TEXT` to `health_events` and `health_objects`, plus partial indexes `idx_events_syntheticBatch` and `idx_objects_syntheticBatch`.

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticBatchMigrationTests.swift`:

```swift
import Testing
import GRDB
@testable import HealthGraphCore

@Suite struct SyntheticBatchMigrationTests {

    @Test func columnsExistAndDefaultToNilForPreExistingRows() async throws {
        let db = try AppDatabase.inMemory()
        // A row inserted through the normal path carries no batch.
        let store = GRDBEventStore(database: db)
        try await store.save(HealthEvent(timestamp: Date(), category: .symptom,
                                         subtype: "headache", source: .manual))
        let fetched = try await store.recentEvents(limit: 1)
        #expect(fetched.count == 1)
        #expect(fetched[0].syntheticBatch == nil)

        let obj = try await GRDBObjectStore(database: db)
            .findOrCreate(name: "Coffee", kind: .food, metadata: nil)
        #expect(obj.syntheticBatch == nil)
    }

    @Test func partialIndexesExistOnBothTables() throws {
        let db = try AppDatabase.inMemory()
        try db.dbWriter.read { database in
            let names = try String.fetchAll(database, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'index' AND name IN
                ('idx_events_syntheticBatch','idx_objects_syntheticBatch')
                ORDER BY name
                """)
            #expect(names == ["idx_events_syntheticBatch", "idx_objects_syntheticBatch"])
            // Both are partial (conditioned on the column being non-null).
            let sqls = try String.fetchAll(database, sql: """
                SELECT sql FROM sqlite_master WHERE type = 'index'
                AND name IN ('idx_events_syntheticBatch','idx_objects_syntheticBatch')
                """)
            for s in sqls { #expect(s.contains("syntheticBatch IS NOT NULL")) }
        }
    }

    @Test func migrationIsIdempotentAndColumnReadsNil() throws {
        // Two AppDatabase instances over the same queue must both migrate cleanly
        // (the migrator is append-only), and the column reads nil for a row that
        // never set it — proving v7 is additive, not destructive.
        let queue = try DatabaseQueue()
        _ = try AppDatabase(queue)                    // migrates through v7
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO health_events (id, timestamp, timezoneID, category, source, confidence, createdAt)
                VALUES (randomblob(16), 0, 'UTC', 'symptom', 'manual', 1.0, 0)
                """)
        }
        _ = try AppDatabase(queue)                    // re-migrate: no-op, must not throw
        let batch = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT syntheticBatch FROM health_events LIMIT 1")
        }
        #expect(batch == nil)
    }
}
```

`AppDatabase(_ dbWriter:)` is already `public` (`AppDatabase.swift:9`) and runs the full migrator in its init, and `AppDatabase.dbWriter` is `public let` (`:7`), so both the index test's `db.dbWriter.read` and this test compile against the existing surface — no new accessor is needed.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter SyntheticBatchMigrationTests`
Expected: FAIL — compile errors (`syntheticBatch` column/property and the `idx_*_syntheticBatch` indexes do not exist yet).

- [ ] **Step 3: Add the model fields**

In `HealthGraphCore/Sources/HealthGraphCore/Models/HealthEvent.swift`, add the stored property after `deletedAt` (keep it last so Codable column order is stable), and a defaulted init param.

Property block — add after `public var deletedAt: Date?` (line 23):
```swift
    /// Non-nil marks a demo/seed row and names its batch (`DemoBatch`). NULL = real.
    public var syntheticBatch: String?
```
Init — add as the final parameter (after `deletedAt: Date? = nil`):
```swift
        syntheticBatch: String? = nil,
```
and the final assignment (after `self.deletedAt = deletedAt`):
```swift
        self.syntheticBatch = syntheticBatch
```

In `HealthGraphCore/Sources/HealthGraphCore/Models/HealthObject.swift`, add after `public var createdAt: Date` (line 15):
```swift
    /// Non-nil marks a demo/seed object and names its batch. NULL = real.
    public var syntheticBatch: String?
```
Init — add as the final parameter (after `createdAt: Date = Date()`):
```swift
        syntheticBatch: String? = nil,
```
and the final assignment (after `self.createdAt = createdAt`):
```swift
        self.syntheticBatch = syntheticBatch
```

- [ ] **Step 4: Add migration v7**

In `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift`, register v7 immediately below the existing v6 registration (after line 268, before `return migrator` at line 270). Do NOT touch v1–v6 — the migrator is append-only and their bodies are frozen (`AppDatabase.swift:31-35`).

```swift
        migrator.registerMigration("v7") { db in
            // Demo-data hygiene: mark seeded rows so they are precisely removable.
            // Nullable, no backfill — every existing row is real by definition.
            try db.alter(table: "health_events") { t in
                t.add(column: "syntheticBatch", .text)
            }
            try db.alter(table: "health_objects") { t in
                t.add(column: "syntheticBatch", .text)
            }
            // Partial indexes: proportional to demo rows, not the whole table.
            try db.execute(sql: """
                CREATE INDEX idx_events_syntheticBatch
                ON health_events(syntheticBatch) WHERE syntheticBatch IS NOT NULL
                """)
            try db.execute(sql: """
                CREATE INDEX idx_objects_syntheticBatch
                ON health_objects(syntheticBatch) WHERE syntheticBatch IS NOT NULL
                """)
        }
```

No test-only accessor is required: the Step 1 tests drive everything through the public `AppDatabase(_:)` init (which runs the full migrator) and the public `dbWriter`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path HealthGraphCore --filter SyntheticBatchMigrationTests`
Expected: PASS — 3 tests (`columnsExistAndDefaultToNilForPreExistingRows`, `partialIndexesExistOnBothTables`, `migrationIsIdempotentAndColumnReadsNil`).

- [ ] **Step 6: Run the full package suite to confirm no regressions**

Run: `swift test --package-path HealthGraphCore`
Expected: PASS — existing suites unaffected (adding a nullable column + defaulted init params is source-compatible).

- [ ] **Step 7: Commit**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Models/HealthEvent.swift" \
        "HealthGraphCore/Sources/HealthGraphCore/Models/HealthObject.swift" \
        "HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticBatchMigrationTests.swift"
git commit -m "feat(graph): v7 syntheticBatch column + model fields + partial indexes"
```

---

## Task 2: `DemoBatch` — the single namespace helper

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Synthetic/DemoBatch.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/DemoBatchTests.swift`

**Interfaces:**
- Consumes: `NameNormalizer.normalize(_:)` (`NameNormalizer.swift:6`); `DedupKey.daily(_:_:dayStart:provenance:)` (`DedupKey.swift:24`); `HealthEvent`.
- Produces:
  - `DemoBatch.synthetic / .mood / .outsideFactors / .weather : String`
  - `DemoBatch.prefix(_ batch: String) -> String` → `"demo:\(batch)|"`
  - `DemoBatch.dedupKey(_ base: String, batch: String) -> String`
  - `DemoBatch.normalizedName(_ displayName: String, batch: String) -> String`
  - `DemoBatch.stamp(_ events: [HealthEvent], batch: String) -> [HealthEvent]` (sets `syntheticBatch` and namespaces any existing `dedupKey`)

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/DemoBatchTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct DemoBatchTests {

    @Test func prefixFormatIsExact() {
        #expect(DemoBatch.prefix("weather") == "demo:weather|")
    }

    @Test func demoDedupKeyNeverEqualsRealKeyForSameDay() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let real = DedupKey.daily(.environment, "temperature", dayStart: day,
                                  provenance: .observedCompletedDay)
        let demo = DemoBatch.dedupKey(real, batch: DemoBatch.weather)
        #expect(demo != real)
        #expect(demo.hasPrefix("demo:weather|"))
        #expect(demo.hasSuffix(real))
    }

    @Test func normalizedNameNamespacesTheNormalizedForm() {
        // "Coffee" normalizes to "coffee"; the demo form prefixes that.
        #expect(DemoBatch.normalizedName("Coffee", batch: DemoBatch.mood) == "demo:mood|coffee")
        #expect(NameNormalizer.normalize("Coffee") == "coffee")   // guards the assumption
    }

    @Test func stampSetsBatchAndNamespacesExistingDedupKeys() {
        let withKey = HealthEvent(timestamp: Date(), category: .environment,
                                  subtype: "humidity", source: .weatherAPI,
                                  dedupKey: "environment|humidity|day|1")
        let noKey = HealthEvent(timestamp: Date(), category: .symptom,
                                subtype: "headache", source: .manual)
        let out = DemoBatch.stamp([withKey, noKey], batch: DemoBatch.outsideFactors)
        #expect(out[0].syntheticBatch == "outsideFactors")
        #expect(out[0].dedupKey == "demo:outsideFactors|environment|humidity|day|1")
        #expect(out[1].syntheticBatch == "outsideFactors")
        #expect(out[1].dedupKey == nil)   // no key to namespace stays nil
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter DemoBatchTests`
Expected: FAIL — `DemoBatch` does not exist.

- [ ] **Step 3: Create `DemoBatch`**

Create `HealthGraphCore/Sources/HealthGraphCore/Synthetic/DemoBatch.swift`:

```swift
import Foundation

/// The single source of truth for demo/seed-data identity. Not `#if DEBUG`:
/// the marker column and the Release purge are always-compiled; only the seed
/// UI that produces demo rows is DEBUG.
///
/// Every demo row is marked with a batch id (`syntheticBatch`) and has its
/// dedup key and object identity namespaced with `prefix(batch)`, so a demo row
/// can never collide with — or overwrite — a real row.
public enum DemoBatch {
    public static let synthetic = "synthetic"
    public static let mood = "mood"
    public static let outsideFactors = "outsideFactors"
    public static let weather = "weather"

    /// The namespace applied to a demo row's dedup key and normalized name.
    public static func prefix(_ batch: String) -> String { "demo:\(batch)|" }

    /// A batch-scoped dedup key: the real key with the demo namespace in front.
    public static func dedupKey(_ base: String, batch: String) -> String {
        prefix(batch) + base
    }

    /// A batch-scoped normalized name. Normalizes the display name the SAME way
    /// `HealthObject` does, then prefixes — so the lookup key and the persisted
    /// key are computed identically and cannot diverge.
    public static func normalizedName(_ displayName: String, batch: String) -> String {
        prefix(batch) + NameNormalizer.normalize(displayName)
    }

    /// Marks events as belonging to `batch` and namespaces any dedup key they
    /// already carry. Events without a dedup key keep `nil` (nothing to collide).
    public static func stamp(_ events: [HealthEvent], batch: String) -> [HealthEvent] {
        events.map { event in
            var e = event
            e.syntheticBatch = batch
            if let key = e.dedupKey { e.dedupKey = dedupKey(key, batch: batch) }
            return e
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path HealthGraphCore --filter DemoBatchTests`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Synthetic/DemoBatch.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/DemoBatchTests.swift"
git commit -m "feat(graph): DemoBatch namespace helper (single source of truth)"
```

---

## Task 3: Batch-aware `findOrCreate` + thread `batch` through the generator (P0 object identity)

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/ObjectStore.swift:5` (protocol), `:19-32` (impl)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift:79-99` (`SyntheticDataset`), `:104` (`generate`)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/BatchAwareObjectTests.swift`

**Interfaces:**
- Consumes: `DemoBatch.normalizedName(_:batch:)`, `DemoBatch.stamp(_:batch:)`, `NameNormalizer.normalize(_:)`, `HealthObject`, `GRDBObjectStore`, `GRDBEventStore`.
- Produces:
  - `ObjectStore.findOrCreate(name:kind:metadata:syntheticBatch:)` — new final defaulted param `syntheticBatch: String? = nil`. When non-nil, the lookup filters on `DemoBatch.normalizedName(name, batch:)` and the persisted row stores that `normalizedName` and `syntheticBatch`.
  - `SyntheticDataGenerator.generate(config:batch:)` — new **required** `batch: String`; every event is stamped via `DemoBatch.stamp`.
  - `SyntheticDataset` gains `public var batch: String`; `insert(into:)` passes it to `findOrCreate`.

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/BatchAwareObjectTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct BatchAwareObjectTests {

    @Test func demoObjectCoexistsWithRealObjectOfSameNameAndKind() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)

        let real = try await store.findOrCreate(name: "Coffee", kind: .food, metadata: nil)
        let demo = try await store.findOrCreate(name: "Coffee", kind: .food, metadata: nil,
                                                syntheticBatch: DemoBatch.mood)

        #expect(real.id != demo.id)                       // distinct rows
        #expect(real.syntheticBatch == nil)
        #expect(demo.syntheticBatch == "mood")
        #expect(real.normalizedName == "coffee")
        #expect(demo.normalizedName == "demo:mood|coffee")
        #expect(real.name == "Coffee" && demo.name == "Coffee")   // display unchanged
        #expect(try await store.count() == 2)             // real row untouched, not merged
    }

    @Test func demoFindOrCreateReusesItsOwnBatchRow() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        let a = try await store.findOrCreate(name: "Magnesium", kind: .supplement, metadata: nil,
                                             syntheticBatch: DemoBatch.mood)
        let b = try await store.findOrCreate(name: "Magnesium", kind: .supplement, metadata: nil,
                                             syntheticBatch: DemoBatch.mood)
        #expect(a.id == b.id)                             // same batch → reuse, no duplicate
        #expect(try await store.count() == 1)
    }

    @Test func generatedDatasetInsertsBatchScopedObjectsAndStampedEvents() async throws {
        let db = try AppDatabase.inMemory()
        // Seed a real "Coffee" first so the demo must NOT merge into it.
        _ = try await GRDBObjectStore(database: db)
            .findOrCreate(name: "Coffee", kind: .food, metadata: nil)

        let config = SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 0), days: 10, seed: 1,
            patterns: [PlantedPattern(exposureName: "Coffee", exposureCategory: .food,
                                      outcomeSubtype: "mood", lagHours: 4, lagJitterHours: 2,
                                      followProbability: 0.8, exposureProbabilityPerDay: 0.6)],
            outcomeBaseRatePerDay: 0, noiseFoodsPerDay: 0...0)
        try await SyntheticDataGenerator.generate(config: config, batch: DemoBatch.mood)
            .insert(into: db)

        // The real Coffee is still present and unmarked; a demo Coffee exists too.
        let coffees = try await GRDBObjectStore(database: db).objects(kind: .food, includeArchived: true)
            .filter { $0.name == "Coffee" }
        #expect(coffees.count == 2)
        #expect(coffees.contains { $0.syntheticBatch == nil })
        #expect(coffees.contains { $0.syntheticBatch == "mood" })

        // Every seeded event is marked.
        let events = try await GRDBEventStore(database: db)
            .events(in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.syntheticBatch == "mood" })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter BatchAwareObjectTests`
Expected: FAIL — `findOrCreate` has no `syntheticBatch:` param and `generate` has no `batch:` param.

- [ ] **Step 3: Add `syntheticBatch` to the `ObjectStore` protocol and impl**

In `HealthGraphCore/Sources/HealthGraphCore/Database/ObjectStore.swift`, change the protocol requirement (line 5):
```swift
    func findOrCreate(name: String, kind: ObjectKind, metadata: Data?,
                      syntheticBatch: String?) async throws -> HealthObject
```
Replace the impl (lines 19-32):
```swift
    public func findOrCreate(name: String, kind: ObjectKind, metadata: Data?,
                             syntheticBatch: String? = nil) async throws -> HealthObject {
        // One computation of the identity key, used for BOTH the lookup and the
        // persisted row, so a demo object can never merge into a real one.
        let normalized = syntheticBatch
            .map { DemoBatch.normalizedName(name, batch: $0) }
            ?? NameNormalizer.normalize(name)
        return try await dbWriter.write { db in
            if let existing = try HealthObject
                .filter(Column("normalizedName") == normalized)
                .filter(Column("kind") == kind.rawValue)
                .fetchOne(db) {
                return existing
            }
            var object = HealthObject(kind: kind, name: name, metadata: metadata)
            object.normalizedName = normalized       // override the init's real-name normalization
            object.syntheticBatch = syntheticBatch
            try object.insert(db)
            return object
        }
    }
```

The four real callers (`CaptureService.swift:71,82`; `SwiftDataMigrator.swift:109,123,153,173,193,271`) omit the new argument and rely on the `= nil` default — no change needed there.

- [ ] **Step 4: Thread `batch` through the generator**

In `HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift`:

Add the stored `batch` to `SyntheticDataset` (after `public var events: [HealthEvent]`, line 81):
```swift
    public var batch: String
```
Update `insert(into:)`'s `findOrCreate` call (lines 89-90) to pass the batch:
```swift
            let saved = try await objectStore.findOrCreate(
                name: object.name, kind: object.kind, metadata: object.metadata,
                syntheticBatch: batch)
```
Change `generate` to require `batch` and stamp events. Replace the signature (line 104):
```swift
    public static func generate(config: SyntheticConfig, batch: String) -> SyntheticDataset {
```
At the end of `generate`, where it currently returns the dataset, stamp the events and pass the batch. Find the final `return SyntheticDataset(objects: objects, events: events)` and replace with:
```swift
        return SyntheticDataset(objects: objects,
                                events: DemoBatch.stamp(events, batch: batch),
                                batch: batch)
```
(If `generate` returns via a different final expression, wrap `events` in `DemoBatch.stamp(events, batch: batch)` and add `batch: batch` there.)

- [ ] **Step 5: Update existing generator tests to pass a batch**

`SyntheticDataTests.swift` and `SyntheticMoodPatternTests.swift` call `SyntheticDataGenerator.generate(config:)`. Add `, batch: DemoBatch.synthetic` to each call so they compile. Run `swift test --package-path HealthGraphCore --filter SyntheticData` to find the exact call sites, then add the argument. Their assertions are unaffected — the batch only marks rows.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --package-path HealthGraphCore --filter BatchAwareObjectTests`
Expected: PASS — 3 tests.

Run: `swift test --package-path HealthGraphCore`
Expected: PASS — full suite green (generator tests updated to pass a batch).

- [ ] **Step 7: Commit**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Database/ObjectStore.swift" \
        "HealthGraphCore/Sources/HealthGraphCore/Synthetic/SyntheticDataGenerator.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/BatchAwareObjectTests.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticDataTests.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticMoodPatternTests.swift"
git commit -m "feat(graph): batch-aware findOrCreate + generator threads a required batch"
```

---

## Task 4: `DemoDataMaintenance` — cleanup routine (purge/reload modes) + `hasSyntheticData`

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Database/DemoDataMaintenance.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/DemoDataMaintenanceTests.swift`

**Interfaces:**
- Consumes: `AppDatabase.dbWriter`, GRDB `Database`, `RelStatus.userDismissed` (rawValue `"userDismissed"`).
- Produces (all on `AppDatabase`, all always-compiled):
  - `enum SyntheticScope { case all; case batch(String) }`
  - `func purgeSyntheticData(scope: SyntheticScope) async throws -> Bool` (`@discardableResult`) — purge mode, both-table existence guard, returns `didClean`.
  - `func purgeSyntheticDataSync(scope: SyntheticScope) throws -> Bool` (`@discardableResult`) — synchronous variant for bootstrap.
  - `func resetForSeedReload(batch: String) async throws` — reload mode: unconditional relationship wipe + scoped delete of the batch.
  - `func hasSyntheticData() async throws -> Bool`

- [ ] **Step 1: Write the failing test**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/DemoDataMaintenanceTests.swift`:

```swift
import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

@Suite struct DemoDataMaintenanceTests {

    // Helpers ---------------------------------------------------------------

    private func seedEvent(_ db: AppDatabase, batch: String?, subtype: String) async throws {
        try await GRDBEventStore(database: db).save(
            HealthEvent(timestamp: Date(), category: .symptom, subtype: subtype,
                        source: .manual, syntheticBatch: batch))
    }
    private func seedObject(_ db: AppDatabase, batch: String?, name: String) async throws {
        _ = try await GRDBObjectStore(database: db)
            .findOrCreate(name: name, kind: .food, metadata: nil, syntheticBatch: batch)
    }
    private func insertRelationship(_ db: AppDatabase, status: RelStatus) throws {
        try db.dbWriter.write { database in
            try database.execute(sql: """
                INSERT INTO relationships
                (id, fromCategory, toCategory, type, evidenceCount, contradictionCount,
                 confidence, firstSeen, lastSeen, lastRecomputed, status)
                VALUES (randomblob(16), 'food', 'symptom', 'possibleTrigger', 1, 0,
                        0.9, 0, 0, 0, ?)
                """, arguments: [status.rawValue])
        }
    }
    private func relationshipCount(_ db: AppDatabase) throws -> Int {
        try db.dbWriter.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM relationships") ?? 0 }
    }
    private func eventCount(_ db: AppDatabase) async throws -> Int {
        try await GRDBEventStore(database: db).count()
    }
    private func objectCount(_ db: AppDatabase) throws -> Int {
        try db.dbWriter.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM health_objects") ?? 0 }
    }

    // Tests -----------------------------------------------------------------

    @Test func purgeOnCleanDatabaseIsANoOpAndReturnsFalse() async throws {
        let db = try AppDatabase.inMemory()
        try await seedEvent(db, batch: nil, subtype: "headache")   // real event
        try insertRelationship(db, status: .active)                // real active edge
        let before = try relationshipCount(db)

        let didClean = try await db.purgeSyntheticData(scope: .all)

        #expect(didClean == false)
        #expect(try relationshipCount(db) == before)               // NOT wiped — the P0 guard
        #expect(try await eventCount(db) == 1)
    }

    @Test func purgeWithSyntheticRowsRemovesThemAndNonDismissedRelationships() async throws {
        let db = try AppDatabase.inMemory()
        try await seedEvent(db, batch: nil, subtype: "realHeadache")
        try await seedEvent(db, batch: DemoBatch.weather, subtype: "demoMigraine")
        try await seedObject(db, batch: DemoBatch.weather, name: "DemoFood")
        try await seedObject(db, batch: nil, name: "RealFood")
        try insertRelationship(db, status: .active)
        try insertRelationship(db, status: .userDismissed)

        let didClean = try await db.purgeSyntheticData(scope: .all)

        #expect(didClean == true)
        #expect(try await eventCount(db) == 1)                     // only the real event remains
        #expect(try objectCount(db) == 1)                          // only RealFood remains
        #expect(try relationshipCount(db) == 1)                    // dismissed preserved, active wiped
        try db.dbWriter.read { database in
            let status = try String.fetchOne(database, sql: "SELECT status FROM relationships LIMIT 1")
            #expect(status == "userDismissed")
        }
    }

    @Test func purgeGuardFiresOnObjectOnlyOrphan() async throws {
        let db = try AppDatabase.inMemory()
        try await seedObject(db, batch: DemoBatch.mood, name: "OrphanObject")   // objects only
        #expect(try await db.purgeSyntheticData(scope: .all) == true)
        #expect(try objectCount(db) == 0)
    }

    @Test func purgeGuardFiresOnEventOnlyOrphan() async throws {
        let db = try AppDatabase.inMemory()
        try await seedEvent(db, batch: DemoBatch.mood, subtype: "orphanEvent")  // events only
        #expect(try await db.purgeSyntheticData(scope: .all) == true)
        #expect(try await eventCount(db) == 0)
    }

    @Test func batchScopedPurgeLeavesOtherBatchesAndRealRows() async throws {
        let db = try AppDatabase.inMemory()
        try await seedEvent(db, batch: nil, subtype: "real")
        try await seedEvent(db, batch: DemoBatch.mood, subtype: "moodEvent")
        try await seedEvent(db, batch: DemoBatch.weather, subtype: "weatherEvent")

        let didClean = try await db.purgeSyntheticData(scope: .batch(DemoBatch.mood))

        #expect(didClean == true)
        let events = try await GRDBEventStore(database: db)
            .events(in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        #expect(Set(events.map { $0.subtype }) == ["real", "weatherEvent"])
    }

    @Test func reloadModeWipesRelationshipsEvenWhenItsBatchIsAbsent() async throws {
        let db = try AppDatabase.inMemory()
        try insertRelationship(db, status: .active)
        try insertRelationship(db, status: .userDismissed)
        // No rows of batch "weather" exist yet — reload must still wipe non-dismissed edges.
        try await db.resetForSeedReload(batch: DemoBatch.weather)
        #expect(try relationshipCount(db) == 1)                    // active wiped, dismissed kept
    }

    @Test func reloadModeDeletesOnlyItsOwnBatchRows() async throws {
        let db = try AppDatabase.inMemory()
        try await seedEvent(db, batch: DemoBatch.mood, subtype: "moodEvent")
        try await seedEvent(db, batch: DemoBatch.weather, subtype: "weatherEvent")
        try await db.resetForSeedReload(batch: DemoBatch.weather)
        let events = try await GRDBEventStore(database: db)
            .events(in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        #expect(events.map { $0.subtype } == ["moodEvent"])        // weather batch gone, mood kept
    }

    @Test func hasSyntheticDataReflectsPresence() async throws {
        let db = try AppDatabase.inMemory()
        #expect(try await db.hasSyntheticData() == false)
        try await seedEvent(db, batch: DemoBatch.weather, subtype: "x")
        #expect(try await db.hasSyntheticData() == true)
    }

    @Test func syncPurgeMatchesAsyncBehaviour() throws {
        let db = try AppDatabase.inMemory()
        // No synthetic rows → sync purge is a no-op returning false, relationships intact.
        try insertRelationship(db, status: .active)
        #expect(try db.purgeSyntheticDataSync(scope: .all) == false)
        #expect(try relationshipCount(db) == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path HealthGraphCore --filter DemoDataMaintenanceTests`
Expected: FAIL — `SyntheticScope`, `purgeSyntheticData`, `resetForSeedReload`, `hasSyntheticData` do not exist.

- [ ] **Step 3: Implement the cleanup routine**

Create `HealthGraphCore/Sources/HealthGraphCore/Database/DemoDataMaintenance.swift`:

```swift
import Foundation
import GRDB

/// Which synthetic rows a maintenance operation targets.
public enum SyntheticScope: Sendable {
    case all                 // syntheticBatch IS NOT NULL
    case batch(String)       // syntheticBatch = ?
}

public extension AppDatabase {

    /// PURGE MODE (clear button, Release purge). Existence-guarded across BOTH
    /// tables: if no row matches the scope in `health_events` OR `health_objects`,
    /// nothing is touched and `false` is returned. This guard is load-bearing —
    /// without it every ordinary (no-demo) launch would wipe real relationships.
    /// When rows match, in one transaction: wipe non-dismissed relationships,
    /// delete matching events, delete matching objects. Returns whether it acted.
    @discardableResult
    func purgeSyntheticData(scope: SyntheticScope) async throws -> Bool {
        try await dbWriter.write { db in try Self.purge(db, scope: scope) }
    }

    /// Synchronous variant for bootstrap (the Release purge runs before the
    /// database handle is exposed, where no `await` is available).
    @discardableResult
    func purgeSyntheticDataSync(scope: SyntheticScope) throws -> Bool {
        try dbWriter.write { db in try Self.purge(db, scope: scope) }
    }

    /// RELOAD MODE (seed buttons). Unconditionally wipes non-dismissed
    /// relationships (the incoming dataset shifts every baseline) and deletes
    /// only this batch's existing rows. No guard, no return — the caller always
    /// inserts a fresh dataset and recomputes afterward.
    func resetForSeedReload(batch: String) async throws {
        try await dbWriter.write { db in
            try Self.wipeNonDismissedRelationships(db)
            try Self.deleteSyntheticRows(db, scope: .batch(batch))
        }
    }

    /// True if any synthetic row exists (drives the banner and the dismissal gate).
    func hasSyntheticData() async throws -> Bool {
        try await dbWriter.read { db in try Self.syntheticRowsExist(db, scope: .all) }
    }

    // MARK: - Shared internals

    private static func purge(_ db: Database, scope: SyntheticScope) throws -> Bool {
        guard try syntheticRowsExist(db, scope: scope) else { return false }
        try wipeNonDismissedRelationships(db)
        try deleteSyntheticRows(db, scope: scope)
        return true
    }

    /// The scope's WHERE clause and its bound argument (if any).
    private static func clause(_ scope: SyntheticScope) -> (sql: String, args: StatementArguments) {
        switch scope {
        case .all:            return ("syntheticBatch IS NOT NULL", [])
        case .batch(let b):   return ("syntheticBatch = ?", [b])
        }
    }

    /// Existence guard across BOTH tables (an interrupted seed can leave an
    /// object-only or event-only orphan; a one-table check would skip the purge).
    private static func syntheticRowsExist(_ db: Database, scope: SyntheticScope) throws -> Bool {
        let (where_, args) = clause(scope)
        let inEvents = try Bool.fetchOne(db,
            sql: "SELECT EXISTS(SELECT 1 FROM health_events WHERE \(where_))", arguments: args) ?? false
        if inEvents { return true }
        return try Bool.fetchOne(db,
            sql: "SELECT EXISTS(SELECT 1 FROM health_objects WHERE \(where_))", arguments: args) ?? false
    }

    private static func wipeNonDismissedRelationships(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM relationships WHERE status <> ?",
                       arguments: [RelStatus.userDismissed.rawValue])
    }

    /// Events before objects: the `objectID` FK is `.setNull`, so deleting demo
    /// events first prevents any real event that referenced a demo object from
    /// being stranded with a nulled link mid-transaction.
    private static func deleteSyntheticRows(_ db: Database, scope: SyntheticScope) throws {
        let (where_, args) = clause(scope)
        try db.execute(sql: "DELETE FROM health_events WHERE \(where_)", arguments: args)
        try db.execute(sql: "DELETE FROM health_objects WHERE \(where_)", arguments: args)
    }
}
```

Note: the interpolated `\(where_)` values are compile-time constants (`"syntheticBatch IS NOT NULL"` / `"syntheticBatch = ?"`), never user input — no injection surface; the batch value is always bound via `arguments`.

Atomicity is structural, not tested by fault injection: each entry point wraps its whole sequence in a single GRDB `write`, which runs in one deferred transaction — any thrown error rolls the entire sequence back. The spec's "failure partway through rolls back" requirement is satisfied by construction (there is no seam to force a mid-transaction failure without a contrived hook, so no flaky rollback test is added).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path HealthGraphCore --filter DemoDataMaintenanceTests`
Expected: PASS — 10 tests, including both-table orphan guards and the P0 clean-database no-op.

- [ ] **Step 5: Run the full package suite**

Run: `swift test --package-path HealthGraphCore`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add "HealthGraphCore/Sources/HealthGraphCore/Database/DemoDataMaintenance.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/DemoDataMaintenanceTests.swift"
git commit -m "feat(graph): DemoDataMaintenance — guarded purge / unconditional reload, both-table guard"
```

---

## Task 5: Seed buttons use reload mode + one recompute; add the Clear button

**Files:**
- Modify: `Views/HealthGraphDebugView.swift:46-67` (Actions section), `:195-247` (`loadSynthetic`, `loadMoodDemo`), `:256-328` (`loadOutsideFactorsDemo`), `:342-560` (`loadWeatherDemo`)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/DemoDataMaintenanceTests.swift` (add one reload-idempotence test — deterministic, at the store layer, not the UI)

**Interfaces:**
- Consumes: `AppDatabase.resetForSeedReload(batch:)`, `AppDatabase.purgeSyntheticData(scope:)`, `DemoBatch.*`, `DemoBatch.stamp(_:batch:)`, `SyntheticDataGenerator.generate(config:batch:)`, `EvidenceEngine.recompute(asOf:)`, `GRDBEventStore.save(_:)`.
- Produces: no new API — wires the debug UI to the Task 3/4 surfaces.

- [ ] **Step 1: Write the failing test (reload idempotence at the store layer)**

Add to `DemoDataMaintenanceTests.swift`:

```swift
    @Test func reloadThenInsertTwiceLeavesOneDatasetsWorthOfRows() async throws {
        let db = try AppDatabase.inMemory()
        let config = SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 0), days: 5, seed: 3,
            patterns: [PlantedPattern(exposureName: "Coffee", exposureCategory: .food,
                                      outcomeSubtype: "mood", lagHours: 4, lagJitterHours: 1,
                                      followProbability: 0.8, exposureProbabilityPerDay: 0.6)],
            outcomeBaseRatePerDay: 0, noiseFoodsPerDay: 0...0)

        func seedOnce() async throws {
            try await db.resetForSeedReload(batch: DemoBatch.mood)
            try await SyntheticDataGenerator.generate(config: config, batch: DemoBatch.mood).insert(into: db)
        }
        try await seedOnce()
        let afterFirst = try await GRDBEventStore(database: db).count()
        try await seedOnce()                                   // second "tap"
        let afterSecond = try await GRDBEventStore(database: db).count()
        #expect(afterSecond == afterFirst)                     // reload replaced, did not append
    }
```

- [ ] **Step 2: Run the characterization test**

Run: `swift test --package-path HealthGraphCore --filter DemoDataMaintenanceTests/reloadThenInsertTwiceLeavesOneDatasetsWorthOfRows`
Expected: PASS. This is a **characterization test**, not a red-first test: Task 4 already built the reload capability, and this pins the idempotence the UI wiring in Steps 3–5 depends on (a second "tap" must replace, not append). If it FAILS, the reload semantics regressed — stop and fix Task 4's `resetForSeedReload` before wiring the UI.

- [ ] **Step 3: Rewrite the generator-based seed handlers**

In `Views/HealthGraphDebugView.swift`, replace the `loadSynthetic` body's insert line and add reload + recompute-once. Change the `try await SyntheticDataGenerator.generate(config: config).insert(into: database)` line (in `loadSynthetic`, ~line 211) to:

```swift
            try await database.resetForSeedReload(batch: DemoBatch.synthetic)
            try await SyntheticDataGenerator.generate(config: config, batch: DemoBatch.synthetic)
                .insert(into: database)
            _ = try await EvidenceEngine(database: database).recompute(asOf: Date())
```

In `loadMoodDemo`, replace its insert + recompute (lines ~241-242):
```swift
            try await database.resetForSeedReload(batch: DemoBatch.mood)
            try await SyntheticDataGenerator.generate(config: config, batch: DemoBatch.mood)
                .insert(into: database)
            _ = try await EvidenceEngine(database: database).recompute(asOf: Date())
```
(`loadMoodDemo` already recomputes; ensure there is exactly ONE `recompute` call after the insert — remove the pre-existing one at line 242 and use the block above.)

- [ ] **Step 4: Rewrite the hand-built seed handlers to reload + stamp + recompute-once**

In `loadOutsideFactorsDemo`, replace the save + recompute (lines ~322-323):
```swift
            try await database.resetForSeedReload(batch: DemoBatch.outsideFactors)
            try await GRDBEventStore(database: database)
                .save(DemoBatch.stamp(events, batch: DemoBatch.outsideFactors))
            _ = try await EvidenceEngine(database: database).recompute(asOf: Date())
```

In `loadWeatherDemo`, replace the save + recompute (lines ~554-555):
```swift
            try await database.resetForSeedReload(batch: DemoBatch.weather)
            try await GRDBEventStore(database: database)
                .save(DemoBatch.stamp(events, batch: DemoBatch.weather))
            _ = try await EvidenceEngine(database: database).recompute(asOf: Date())
```

`DemoBatch.stamp` sets `syntheticBatch` on every event AND namespaces the `DedupKey.daily(...)` keys the hand-built seeds already assign — so the demo environment rows can no longer collide with the real observed-weather backfill.

- [ ] **Step 5: Add the Clear button**

In the "Actions" `Section` (after the synthetic/demo load buttons, before the `Reset Health Graph DB` button, ~line 62), add:

```swift
                Button("Clear demo data (keeps real data)", role: .destructive) {
                    Task {
                        errorMessage = nil
                        isWorking = true
                        defer { isWorking = false }
                        do {
                            let didClean = try await database.purgeSyntheticData(scope: .all)
                            if didClean {
                                _ = try await EvidenceEngine(database: database).recompute(asOf: Date())
                            }
                            await refresh()
                        } catch {
                            errorMessage = String(describing: error)
                        }
                    }
                }
                .disabled(isWorking)
```

The existing `Reset Health Graph DB` button is unchanged.

- [ ] **Step 6: Build the app to confirm the debug view compiles**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Run the store-layer reload test**

Run: `swift test --package-path HealthGraphCore --filter DemoDataMaintenanceTests`
Expected: PASS — all cleanup + reload-idempotence tests.

- [ ] **Step 8: Commit**

```bash
git add "Views/HealthGraphDebugView.swift" \
        "HealthGraphCore/Tests/HealthGraphCoreTests/DemoDataMaintenanceTests.swift"
git commit -m "feat(debug): seed buttons reload+recompute-once; add Clear demo data button"
```

---

## Task 6: Dismissal gating (both layers) + `demoDataLoaded` flag

**Files:**
- Modify: `Views/HealthOS/Insights/InsightsViewModel.swift:6-8` (add flag), `:22-38` (`load`), `:40-60` (`dismiss`/`undoDismiss`)
- Test: `Food IntolerancesTests/InsightsDismissalGateTests.swift` (create)

**Interfaces:**
- Consumes: `AppDatabase.hasSyntheticData()`.
- Produces: `InsightsViewModel.demoDataLoaded: Bool` (`@Published`), a dismissal gate in `dismiss`/`undoDismiss`, and a `pendingUndo` clear when demo data is present.

- [ ] **Step 1: Write the failing test**

Create `Food IntolerancesTests/InsightsDismissalGateTests.swift`:

```swift
import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct InsightsDismissalGateTests {

    private func makeActiveEdge(_ db: AppDatabase) throws -> UUID {
        let id = UUID()
        try db.dbWriter.write { database in
            try database.execute(sql: """
                INSERT INTO relationships
                (id, fromCategory, toCategory, type, evidenceCount, contradictionCount,
                 confidence, firstSeen, lastSeen, lastRecomputed, status, edgeKey)
                VALUES (?, 'food', 'symptom', 'possibleTrigger', 5, 0, 0.9, 0, 0, 0, 'active', 'k1')
                """, arguments: [id.uuidString])
        }
        return id
    }
    private func status(_ db: AppDatabase, _ id: UUID) throws -> String? {
        try db.dbWriter.read { try String.fetchOne($0,
            sql: "SELECT status FROM relationships WHERE id = ?", arguments: [id.uuidString]) }
    }

    @Test func dismissIsBlockedWhileDemoDataExists() async throws {
        let db = try AppDatabase.inMemory()
        let id = try makeActiveEdge(db)
        // Mark the DB as holding demo data.
        try await GRDBEventStore(database: db).save(
            HealthEvent(timestamp: Date(), category: .symptom, subtype: "x",
                        source: .manual, syntheticBatch: DemoBatch.mood))

        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 0) })
        await vm.dismiss(InsightCardModel.stub(id: id))     // see Step 3 note on the stub

        #expect(try status(db, id) == "active")             // NOT dismissed
    }

    @Test func undoIsBlockedAndPendingUndoClearedWhileDemoDataExists() async throws {
        let db = try AppDatabase.inMemory()
        let id = try makeActiveEdge(db)
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 0) })
        vm.pendingUndo = .init(id: id, priorStatus: .active)
        // Demo data arrives.
        try await GRDBEventStore(database: db).save(
            HealthEvent(timestamp: Date(), category: .symptom, subtype: "x",
                        source: .manual, syntheticBatch: DemoBatch.mood))
        await vm.undoDismiss()
        #expect(vm.pendingUndo == nil)                      // cleared, no write
        #expect(try status(db, id) == "active")
    }

    @Test func demoDataLoadedFlagTracksPresence() async throws {
        let db = try AppDatabase.inMemory()
        let vm = InsightsViewModel(database: db, now: { Date(timeIntervalSince1970: 0) })
        await vm.load()
        #expect(vm.demoDataLoaded == false)
        try await GRDBEventStore(database: db).save(
            HealthEvent(timestamp: Date(), category: .symptom, subtype: "x",
                        source: .manual, syntheticBatch: DemoBatch.weather))
        await vm.load()
        #expect(vm.demoDataLoaded == true)
    }
}
```

Note on `InsightCardModel.stub(id:)`: if `InsightCardModel` has no ergonomic test initializer, the dismiss test can instead call a small seam. To avoid inventing UI model construction, prefer testing `dismiss` via the relationship id directly: if `InsightCardModel` exposes `id: UUID`, build one with its real initializer using minimal fields. If that is awkward, delete `dismissIsBlockedWhileDemoDataExists` from this file and instead assert the gate through `demoDataLoaded` + a direct `relStore` check; the `undo` and `flag` tests already pin the gate behavior. Choose the smallest construction that compiles.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/InsightsDismissalGateTests" -parallel-testing-enabled NO`
Expected: FAIL — `demoDataLoaded` does not exist and the gate is not present.

- [ ] **Step 3: Add the flag and the gate**

In `Views/HealthOS/Insights/InsightsViewModel.swift`, add the published flag after `pendingUndo` (line 7):
```swift
    @Published private(set) var demoDataLoaded = false
```

In `load()`, after computing `feed` (after the `feed = InsightsFeed.build(...)` line, ~line 37), add:
```swift
        let demo = (try? await database.hasSyntheticData()) ?? false
        if demo { pendingUndo = nil }        // a queued undo would target a rebuilt id
        demoDataLoaded = demo
```

Guard `dismiss` — add as the first line of the method body (before the `guard var r = ...`, line 41):
```swift
        // Demo data present: dismissal is disabled (a dismissed demo edge could later
        // suppress a genuine edge sharing its edgeKey). Re-checked here, not just in the
        // UI, to close the stale-card race.
        if (try? await database.hasSyntheticData()) == true { return }
```

Guard `undoDismiss` — add as the first line (before `guard let undo = ...`, line 55):
```swift
        if (try? await database.hasSyntheticData()) == true { pendingUndo = nil; return }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Food IntolerancesTests/InsightsDismissalGateTests" -parallel-testing-enabled NO`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Views/HealthOS/Insights/InsightsViewModel.swift" \
        "Food IntolerancesTests/InsightsDismissalGateTests.swift"
git commit -m "feat(insights): gate dismissal/undo at the view-model layer while demo data exists"
```

---

## Task 7: Insights DEBUG banner + hide Dismiss while demo loaded

**Files:**
- Modify: `Views/HealthOS/Insights/InsightsView.swift:11-49` (body — add banner), and the card row where the Dismiss action lives (search for the dismiss button in this file)

**Interfaces:**
- Consumes: `InsightsViewModel.demoDataLoaded`.
- Produces: no new API — a `#if DEBUG` banner and a UI-level Dismiss suppression.

- [ ] **Step 1: Add the banner (DEBUG only)**

In `Views/HealthOS/Insights/InsightsView.swift`, inside the top-level `VStack(alignment: .leading, spacing: 24)` (line 52), add as the first child:
```swift
                #if DEBUG
                if vm.demoDataLoaded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Demo data loaded")
                            .font(.subheadline.weight(.semibold))
                        Text("These findings — including ones from your real data — are not trustworthy while demo data is present. Clear it from Health Graph Debug.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                #endif
```

- [ ] **Step 2: Hide the Dismiss action while demo data is loaded**

Search `Views/HealthOS/Insights/InsightsView.swift` for the Dismiss control (the button/swipe action that calls `vm.dismiss`). Wrap its declaration so it only renders when `!vm.demoDataLoaded`. For example, if it is a button:
```swift
                if !vm.demoDataLoaded {
                    Button("Dismiss") { Task { await vm.dismiss(card) } }
                }
```
If it is a `.swipeActions` modifier, guard the same way around the action's content. The model-layer gate from Task 6 is the real safety net; this removes the affordance so the user never taps a no-op.

- [ ] **Step 3: Build to confirm it compiles and renders**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add "Views/HealthOS/Insights/InsightsView.swift"
git commit -m "feat(insights): DEBUG demo-data banner + hide Dismiss while demo loaded"
```

---

## Task 8: Release purge at bootstrap

**Files:**
- Modify: `Models/HealthGraphProvider.swift:6-17`

**Interfaces:**
- Consumes: `AppDatabase.purgeSyntheticDataSync(scope:)`.
- Produces: a non-DEBUG synchronous purge in `HealthGraphProvider.shared`, before the handle is returned.

- [ ] **Step 1: Add the synchronous purge to the provider**

In `Models/HealthGraphProvider.swift`, change the `shared` closure so it purges in Release before returning. Replace `return try AppDatabase.open(at: url)` (line 13) with:
```swift
            let db = try AppDatabase.open(at: url)
            #if !DEBUG
            // Guarantee fabricated demo rows never reach a shipped build. Runs
            // synchronously here, after migration and before this handle is
            // returned, so no reader observes the pre-purge state. The guard makes
            // it a true no-op on the common case (a DB that never held demo data).
            // No recompute is scheduled: the freshly constructed
            // InsightsRefreshCoordinator recomputes on its lastRecomputeAt==nil
            // never-run branch when Insights loads; a second here could race its
            // single-flight guard.
            _ = try? db.purgeSyntheticDataSync(scope: .all)
            #endif
            return db
```

- [ ] **Step 2: Build both configurations**

Run: `xcodebuild build -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED (Debug — the `#if !DEBUG` block is excluded but must still parse).

Run: `xcodebuild build -scheme "Food Intolerances" -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED (Release — the purge call is compiled and type-checked).

- [ ] **Step 3: Verify the purge path with a core test**

The purge logic is already covered by `DemoDataMaintenanceTests.syncPurgeMatchesAsyncBehaviour` (Task 4). Re-run to confirm the sync entry point behaves:

Run: `swift test --package-path HealthGraphCore --filter DemoDataMaintenanceTests/syncPurgeMatchesAsyncBehaviour`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add "Models/HealthGraphProvider.swift"
git commit -m "feat(release): purge synthetic rows synchronously at bootstrap (non-DEBUG)"
```

---

## Final Verification

- [ ] **Full package suite:** `swift test --package-path HealthGraphCore` → all green.
- [ ] **Full app suite:** `xcodebuild test -scheme "Food Intolerances" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO` → only the known `SwiftDataMigratorTests` teardown crash; zero individual test-case failures.
- [ ] **Device gate (manual, DEBUG build):**
  1. Load each demo → Insights shows the banner; Dismiss is gone.
  2. Tap a seed twice → counts (Health Graph Debug) match one tap.
  3. Clear demo data → real rows remain, banner gone, findings recomputed from real data only.
  4. Seed weather demo alongside real observed weather → no row-count collision on the shared days (namespaced dedup keys).
