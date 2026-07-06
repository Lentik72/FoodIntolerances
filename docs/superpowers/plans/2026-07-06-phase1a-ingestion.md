# Phase 1A: Ingestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the Phase 0 event graph with real data: HealthKit backfill + live ingestion, Apple Health `export.zip` import, cross-source dedup, and environmental exposure events — plus the Phase 0 review follow-ups and the iOS 26 floor raise.

**Architecture:** All pure logic (sample mapping, dedup policy, export-XML parsing, environmental event synthesis) lives in the `HealthGraphCore` package under a new `Ingestion/` folder, fully unit-tested via `swift test`. The app target contributes only thin glue: `HealthKitIngestor` (HKHealthStore queries → package DTOs), a file importer, and an environmental emitter hooked to app-foreground. Dedup is DB-enforced via a new `dedupKey` column (migration v2) with a source-priority policy (live HealthKit > export file > everything else); duration events (sleep, workouts) merge by interval overlap. The debug screen gains an Ingestion panel — the verification surface until onboarding lands in Plan 1D.

**Tech Stack:** Swift (language mode 5), GRDB 7, Swift Testing, HealthKit (app target only), ZIPFoundation (package dependency, for export.zip), existing `EnvironmentalDataService` / `getMoonPhase` / `getCurrentSeason` / `MercuryRetrograde` services.

## Global Constraints

- Repo root: `/Users/leo/Desktop/FoodIntolerances`. App project: `Food Intolerances.xcodeproj` (note the space). Scheme: `Food Intolerances`.
- **Deployment floor is raised to iOS 26.0 by Task 3 of this plan** (approved decision 2026-07-06; zero users). From Task 3 onward, app build/test commands MUST use the iPhone 17 / iOS 26.5 simulator: `-destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF'`. Tasks 1–2 may still use the iPhone 16 Pro (`id=CE810590-810D-4CF8-B042-0CD70971D19D`).
- App test runs MUST pass `-parallel-testing-enabled NO`. Known pre-existing issue (documented in `SwiftDataMigratorTests.swift`): `migratesObjectsFromAvoidedCabinetAndProtocols` crashes the test process inside Apple's SwiftData teardown; under parallel execution the crash mis-reports sibling tests. Expected app-suite result: that ONE test crashes, everything else passes. Report per-test results, never a bare "TEST FAILED".
- Package tests: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`.
- Schema changes ONLY inside numbered GRDB migrations (`registerMigration("v2")`…). Never `ALTER TABLE` outside the migrator.
- Soft delete only: product code never hard-deletes from `health_events`. The ingest pipeline's "replace" path soft-deletes superseded rows. (`AppDatabase.eraseAllRows()` from Task 1 is the sanctioned DEBUG-tooling exception.)
- All events carry a `timezoneID` (IANA identifier). HealthKit samples use `HKMetadataKeyTimeZone` when present, else `TimeZone.current.identifier`.
- Source priority for dedup (spec §5.5): `healthKit` (rank 3) > `healthExportFile` (rank 2) > everything else (rank 1). Equal rank on the same dedupKey = update in place (idempotent recompute). A user's soft-delete always wins: re-imports never resurrect a deleted event.
- `eraseDatabaseOnSchemaChange` (DEBUG) STAYS in place for this plan — ingested data is fully reconstructible (re-backfill / re-import). Its removal is scheduled for Plan 1C, when manual capture makes graph data irreplaceable.
- No user-facing causal language anywhere (debug copy included).
- Privacy: never log health values, subtypes, or names — log counts and category totals only.
- Performance budget (spec §17): 1-year backfill ≈ 2 min on mid-range hardware with visible progress. Ingest in batches of 500 events, one DB transaction per batch.
- Verification commands pipe through `| tail` for brevity. On ANY failure, rerun without `| tail`.
- Commit after every task with the message given in its final step.

---

### Task 1: Phase 0 hardening — package

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift` (append extension)
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/AppDatabaseTests.swift`
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/RecordRoundtripTests.swift`
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/ObjectStoreTests.swift`
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticDataTests.swift`

**Interfaces:**
- Consumes: Phase 0 package as merged (`AppDatabase`, records, stores).
- Produces: `AppDatabase.eraseAllRows() async throws` — used by Task 2's debug-view change. No other API changes.

Background: these are the "fix soon after merge" findings from the Phase 0 whole-branch review — schema CHECK constraints and soft-delete round-trips had zero test coverage, `findOrCreate`'s metadata-preservation behavior (which the migrator depends on) was unpinned, the synthetic base-rate test used the host timezone, and the debug screen needed a package-side erase API so the app target can stop calling GRDB directly.

- [ ] **Step 1: Write the failing tests**

Append to `HealthGraphCore/Tests/HealthGraphCoreTests/AppDatabaseTests.swift`, inside `struct AppDatabaseTests`:

```swift
    @Test func relationshipCheckConstraintsRejectEmptyEndpoints() throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        // No fromObjectID/fromCategory: violates the "one endpoint per side" CHECK.
        let bad = Relationship(
            toCategory: "symptom", type: .possibleTrigger,
            firstSeen: now, lastSeen: now, lastRecomputed: now
        )
        #expect(throws: DatabaseError.self) {
            try db.dbWriter.write { try bad.insert($0) }
        }
    }

    @Test func eraseAllRowsEmptiesEveryTable() async throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        // async test context -> GRDB resolves to the async write/read overloads,
        // so both calls need `await` (unlike the sync throws-tests above).
        try await db.dbWriter.write { d in
            try HealthObject(kind: .food, name: "milk", createdAt: now).insert(d)
            try HealthEvent(timestamp: now, category: .food, subtype: "milk",
                            source: .manual, createdAt: now).insert(d)
            try Relationship(fromCategory: "food", toCategory: "symptom",
                             type: .possibleTrigger, firstSeen: now,
                             lastSeen: now, lastRecomputed: now).insert(d)
        }
        try await db.eraseAllRows()
        let counts = try await db.dbWriter.read { d in
            try (HealthEvent.fetchCount(d), HealthObject.fetchCount(d), Relationship.fetchCount(d))
        }
        #expect(counts == (0, 0, 0))
    }
```

Append to `HealthGraphCore/Tests/HealthGraphCoreTests/RecordRoundtripTests.swift`, inside `struct RecordRoundtripTests`:

```swift
    @Test func softDeletedEventRoundtripsWithDeletedAt() throws {
        let db = try AppDatabase.inMemory()
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let event = HealthEvent(
            timestamp: t, category: .symptom, subtype: "headache",
            source: .manual, createdAt: t, deletedAt: t.addingTimeInterval(60)
        )
        try db.dbWriter.write { try event.insert($0) }
        let fetched = try db.dbWriter.read { try HealthEvent.fetchOne($0, key: event.id) }
        #expect(fetched == event)
        #expect(fetched?.deletedAt == t.addingTimeInterval(60))
    }
```

Append to `HealthGraphCore/Tests/HealthGraphCoreTests/ObjectStoreTests.swift`, inside the test struct:

```swift
    @Test func findOrCreateMatchKeepsExistingMetadata() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        let original = try JSONEncoder().encode(["brand": "NOW Foods"])
        let first = try await store.findOrCreate(name: "Zinc 25mg", kind: .supplement,
                                                 metadata: original)
        // The migrator and ingest paths depend on this: a match returns the
        // EXISTING object untouched — later metadata never overwrites earlier.
        let second = try await store.findOrCreate(name: "zinc", kind: .supplement,
                                                  metadata: try JSONEncoder().encode(["brand": "other"]))
        #expect(second.id == first.id)
        #expect(second.metadata == original)
        let refetched = try await store.object(id: first.id)
        #expect(refetched?.metadata == original)
    }
```

- [ ] **Step 2: Pin the synthetic base-rate test to UTC**

In `HealthGraphCore/Tests/HealthGraphCoreTests/SyntheticDataTests.swift`, replace:

```swift
        // base rate on non-exposure days stays low
        let cal = Calendar(identifier: .gregorian)
```

with:

```swift
        // base rate on non-exposure days stays low
        // (UTC-pinned: the generator emits UTC timestamps; a host-local
        // calendar would shift day boundaries and make the test result
        // depend on the machine's timezone)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
```

- [ ] **Step 3: Run tests to verify the new ones fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -12`
Expected: compile FAILURE — `value of type 'AppDatabase' has no member 'eraseAllRows'`. (The other three new tests are valid but can't run until this compiles.)

- [ ] **Step 4: Implement eraseAllRows**

Append to `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift` (after the closing brace of `struct AppDatabase`):

```swift

#if DEBUG
extension AppDatabase {
    /// Dev/debug tooling: hard-deletes every row in every table. The single
    /// sanctioned exception to the soft-delete rule — exists so the app's
    /// DEBUG screens never need to import GRDB directly. #if DEBUG-gated
    /// (same pattern as eraseDatabaseOnSchemaChange above) so it does not
    /// exist in Release builds of the package at all.
    public func eraseAllRows() async throws {
        try await dbWriter.write { db in
            try HealthEvent.deleteAll(db)
            try Relationship.deleteAll(db)
            try HealthObject.deleteAll(db)
        }
    }
}
#endif
```

(`swift test` and app Debug builds compile the package in Debug configuration, so the tests and the DEBUG-only debug view both see it; Release builds exclude both the method and its only caller.)

- [ ] **Step 5: Run the full package suite**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 30 tests in 7 suites passed` (26 prior + 4 new).

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "test(core): pin CHECK constraints, soft-delete roundtrip, findOrCreate metadata; add eraseAllRows"
```

---

### Task 2: Phase 0 hardening — app target

**Files:**
- Modify: `Models/SwiftDataMigrator.swift`
- Modify: `Views/HealthGraphDebugView.swift`
- Modify: `Food IntolerancesTests/SwiftDataMigratorTests.swift`

**Interfaces:**
- Consumes: `AppDatabase.eraseAllRows()` (Task 1).
- Produces: `SwiftDataMigrator.run(context:database:force:attachmentsDirectory:)` — new optional last parameter, default preserves current behavior. Nothing later in this plan consumes it; it exists to make migrator tests hermetic.

Background: the whole-branch review flagged (a) the migrator writes attachments into the real Application Support directory even in tests, (b) the idempotence guarantee is pinned by a single-entity fixture, (c) the debug view imports GRDB directly (forcing the app target's direct GRDB link), and (d) three debug-view paper cuts (missing `attachmentFailures` in the report text, a confusing "not run" flag row after forced runs, stale error banners).

- [ ] **Step 1: Broaden the idempotence fixture (failing first — it fails until Step 3's signature change compiles)**

In `Food IntolerancesTests/SwiftDataMigratorTests.swift`, replace the entire `forcedMigrationIsIdempotent` test with:

```swift
    @Test func forcedMigrationIsIdempotent() async throws {
        // Multi-entity fixture: one of each proven-crash-safe legacy model.
        // (TherapyProtocol/AvoidedItem/CabinetItem are deliberately excluded —
        // see the KNOWN ISSUE comment on migratesObjectsFromAvoidedCabinetAndProtocols;
        // their idempotence rides the same deterministic-UUID mechanism.)
        let context = try makeContext()
        context.insert(LogEntry(
            itemName: "Headache", itemType: .symptom, category: "Neurological",
            symptoms: ["Headache"], severity: 5, notes: "",
            date: Date(timeIntervalSince1970: 1_740_010_000),
            moonPhase: "", atmosphericPressure: "Normal",
            suddenChange: false, isMercuryRetrograde: false, season: "Winter",
            treatments: [Treatment(
                type: "Medication", name: "Ibuprofen",
                startDate: Date(timeIntervalSince1970: 1_740_012_000),
                endDate: nil, dosage: "400mg", effectiveness: 4, notes: nil)]
        ))
        context.insert(LogEntry(
            itemName: "Lunch", itemType: .foodDrink, category: "Food",
            symptoms: [], severity: 1, notes: "",
            date: Date(timeIntervalSince1970: 1_740_000_000),
            moonPhase: "", atmosphericPressure: "Normal",
            suddenChange: false, isMercuryRetrograde: false, season: "Winter",
            foodDrinkItem: "Cheese sandwich"
        ))
        context.insert(TrackedItem(name: "Magnesium", type: .supplement))
        let ongoing = OngoingSymptom(
            name: "Back pain", startDate: Date(timeIntervalSince1970: 1_740_000_000))
        context.insert(ongoing)
        context.insert(SymptomCheckIn(
            parentSymptomID: ongoing.id,
            date: Date(timeIntervalSince1970: 1_740_086_400), severity: 5))
        try context.save()

        let db = try AppDatabase.inMemory()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try await SwiftDataMigrator.run(
            context: context, database: db, force: true, attachmentsDirectory: dir)
        let eventsAfterFirst = try await GRDBEventStore(database: db).count()
        let objectsAfterFirst = try await GRDBObjectStore(database: db).count()
        #expect(eventsAfterFirst == 5) // symptom + treatment + food + ongoing + check-in

        _ = try await SwiftDataMigrator.run(
            context: context, database: db, force: true, attachmentsDirectory: dir)
        let eventsAfterSecond = try await GRDBEventStore(database: db).count()
        let objectsAfterSecond = try await GRDBObjectStore(database: db).count()
        #expect(eventsAfterSecond == eventsAfterFirst) // deterministic ids: upsert, never duplicate
        #expect(objectsAfterSecond == objectsAfterFirst)
    }
```

- [ ] **Step 1b: Add the failing treatments-on-food-entries test**

Phase 0's whole-branch review flagged that treatments attached to `.foodDrink` entries are silently dropped (the treatments loop lives inside `case .symptom` only) — an acknowledged latent data-loss path. Append to `SwiftDataMigratorTests`:

```swift
    @Test func migratesTreatmentsOnFoodDrinkEntries() async throws {
        let context = try makeContext()
        context.insert(LogEntry(
            itemName: "Dinner", itemType: .foodDrink, category: "Food",
            symptoms: [], severity: 1, notes: "",
            date: Date(timeIntervalSince1970: 1_740_000_000),
            moonPhase: "", atmosphericPressure: "Normal",
            suddenChange: false, isMercuryRetrograde: false, season: "Winter",
            foodDrinkItem: "Curry",
            treatments: [Treatment(
                type: "Medication", name: "Antacid",
                startDate: Date(timeIntervalSince1970: 1_740_003_600),
                endDate: nil, dosage: "10mg", effectiveness: 3, notes: nil)]
        ))
        try context.save()

        let db = try AppDatabase.inMemory()
        let report = try await SwiftDataMigrator.run(context: context, database: db, force: true)

        #expect(report.eventsCreated == 2) // food + its treatment
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.contains { $0.category == .medication && $0.subtype == "Antacid" })
    }
```

(If `LogEntry`'s initializer orders `foodDrinkItem`/`treatments` differently than written here, match the real parameter order — both labels exist; see `migratesFoodEntryAndTreatments` and `migratesSymptomLogEntry` for the two labels used together.)

- [ ] **Step 2: Make the attachment test hermetic**

In the same file, replace the body of `savesAttachmentFileToDisk` from `let db = try AppDatabase.inMemory()` through the end of the test with:

```swift
        let db = try AppDatabase.inMemory()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let report = try await SwiftDataMigrator.run(
            context: context, database: db, force: true, attachmentsDirectory: dir)

        #expect(report.attachmentsSaved == 1)
        #expect(report.attachmentFailures == 0)
        let file = dir.appendingPathComponent("\(entry.id.uuidString).jpg")
        #expect(FileManager.default.fileExists(atPath: file.path))
```

- [ ] **Step 3: Inject the attachments directory in the migrator**

In `Models/SwiftDataMigrator.swift`:

1. Change the `run` signature — the existing declaration is preceded by `@MainActor` on its own line; KEEP `@MainActor` (the migrator drives a main-actor-bound SwiftData `ModelContext`):

```swift
    @MainActor
    static func run(
        context: ModelContext,
        database: AppDatabase,
        force: Bool = false,
        attachmentsDirectory: URL? = nil
    ) async throws -> Report {
```

2. The single `saveAttachment` call site inside `run` is (currently line ~72):

```swift
                        attachmentPath = try saveAttachment(photo, id: entry.id)
```

Change it to:

```swift
                        attachmentPath = try saveAttachment(photo, id: entry.id,
                                                            directory: attachmentsDirectory)
```

3. Replace the `saveAttachment` helper with:

```swift
    /// Writes attachment data and returns the canonical relative path stored
    /// on the event. `directory` overrides the write location (tests);
    /// the stored path is unchanged — it is defined relative to
    /// Application Support regardless of where the bytes land.
    static func saveAttachment(_ data: Data, id: UUID, directory: URL?) throws -> String {
        let dir = try directory ?? HealthGraphProvider.attachmentsDirectory()
        let file = dir.appendingPathComponent("\(id.uuidString).jpg")
        try data.write(to: file)
        return "HealthGraph/attachments/\(id.uuidString).jpg"
    }
```

- [ ] **Step 3b: Migrate treatments for ALL entry types**

In `Models/SwiftDataMigrator.swift`, inside the LogEntry loop, the treatments block currently sits inside `case .symptom` (it begins `for (index, treatment) in entry.treatments.enumerated() {` and ends 18 lines later with `report.eventsCreated += 1` followed by `}`). MOVE that entire `for (index, treatment) ...` block out of the `case .symptom` branch: place it immediately AFTER the closing brace of the `switch entry.itemType` statement and BEFORE `report.logEntriesMigrated += 1`, so treatments migrate for both symptom and foodDrink entries. The block only references `entry` — no other captured state — so it moves verbatim. Deterministic ids (`logEntry:{id}:treatment:{index}`) are unchanged, so re-running stays idempotent.

- [ ] **Step 4: Debug view — use eraseAllRows, drop the GRDB import, fix the three paper cuts**

In `Views/HealthGraphDebugView.swift`:

1. Delete the line `import GRDB`.
2. Replace the body of `resetDatabase()`'s `do` block's first statement — the whole `_ = try await database.dbWriter.write { db in ... }` block — with:

```swift
            try await database.eraseAllRows()
```

3. In `refresh()`, `migrate()`, `loadSynthetic()`, and `resetDatabase()`, add as the FIRST line of each function body:

```swift
        errorMessage = nil
```

(For `migrate`, `loadSynthetic`, `resetDatabase` put it immediately before `isWorking = true`.)

4. Replace the migration-flag row:

```swift
                LabeledContent("Migration flag",
                               value: SwiftDataMigrator.isCompleted ? "completed" : "not run")
```

with:

```swift
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent("Migration flag",
                                   value: SwiftDataMigrator.isCompleted ? "completed" : "not run")
                    Text("Forced runs don't set the flag — 'not run' after a forced migration is expected.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
```

5. In `reportText(_:)`, change the last line of the string from:

```
        attachments: \(r.attachmentsSaved)
```

to:

```
        attachments: \(r.attachmentsSaved)  failures: \(r.attachmentFailures)
```

- [ ] **Step 5: Run the app suite (expect the documented crash pattern, everything else green)**

```bash
cd /Users/leo/Desktop/FoodIntolerances
xcodebuild -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,id=CE810590-810D-4CF8-B042-0CD70971D19D' \
  -parallel-testing-enabled NO \
  test -only-testing:"Food IntolerancesTests/SwiftDataMigratorTests" 2>&1 \
  | grep -E "Test .* (started|passed|failed)|Restarting|TEST"
```

Expected: 8 tests pass (including the broadened `forcedMigrationIsIdempotent` and the new `migratesTreatmentsOnFoodDrinkEntries`), `migratesObjectsFromAvoidedCabinetAndProtocols` crashes exactly as documented, overall `** TEST FAILED **` from that one crash. Also verify the package suite still passes: `cd HealthGraphCore && swift test 2>&1 | tail -1` → 30 tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add Models/SwiftDataMigrator.swift Views/HealthGraphDebugView.swift "Food IntolerancesTests/SwiftDataMigratorTests.swift"
git commit -m "refactor(app): hermetic migrator attachments, broadened idempotence fixture, debug view polish"
```

---

### Task 3: Raise the deployment floor to iOS 26

**Files:**
- Modify: `Food Intolerances.xcodeproj/project.pbxproj` (4 lines)
- Modify: `HealthGraphCore/Package.swift` (1 line)

**Interfaces:**
- Consumes: nothing.
- Produces: iOS 26.0 floor project-wide. Every later task may use iOS-26 APIs. All later app build/test commands use the iPhone 17 simulator `id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF`.

Approved decision (2026-07-06): the app has zero users; Plan 1D's on-device voice parsing (Apple Foundation Models) requires iOS 26, and a single code path beats availability-gating. No test can pin a build setting — this task is verified by building.

- [ ] **Step 1: Update the four deployment-target values**

In `Food Intolerances.xcodeproj/project.pbxproj` there are exactly four `IPHONEOS_DEPLOYMENT_TARGET` occurrences (two project-level at `18.0`, two on the Food IntolerancesTests target at `18.2`). Change all four values to `26.0`:

```bash
cd /Users/leo/Desktop/FoodIntolerances
grep -c "IPHONEOS_DEPLOYMENT_TARGET" "Food Intolerances.xcodeproj/project.pbxproj"  # expect 4
sed -i '' -e 's/IPHONEOS_DEPLOYMENT_TARGET = 18.0;/IPHONEOS_DEPLOYMENT_TARGET = 26.0;/g' \
          -e 's/IPHONEOS_DEPLOYMENT_TARGET = 18.2;/IPHONEOS_DEPLOYMENT_TARGET = 26.0;/g' \
  "Food Intolerances.xcodeproj/project.pbxproj"
grep -n "IPHONEOS_DEPLOYMENT_TARGET" "Food Intolerances.xcodeproj/project.pbxproj"   # expect 4 × 26.0
```

- [ ] **Step 2: Raise the package's iOS floor (requires a tools-version bump)**

In `HealthGraphCore/Package.swift`, make BOTH changes — `.iOS(.v26)` does not exist under `swift-tools-version: 6.0` (verified empirically on this toolchain; without the bump the manifest itself fails to compile and every later task is blocked):

1. Line 1: change `// swift-tools-version: 6.0` to `// swift-tools-version: 6.2`
2. Change:

```swift
    platforms: [.iOS(.v18), .macOS(.v15)],
```

to:

```swift
    platforms: [.iOS(.v26), .macOS(.v15)],
```

(macOS floor stays at 15 — it only gates `swift test` on the Mac and nothing in the package needs newer macOS APIs. `.swiftLanguageMode(.v5)`, GRDB 7, and ZIPFoundation are all valid under tools 6.2.)

- [ ] **Step 3: Verify both suites on the new floor**

```bash
cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -1
cd /Users/leo/Desktop/FoodIntolerances
xcodebuild -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' \
  build-for-testing 2>&1 | tail -3
```

Expected: 30 package tests pass; `** TEST BUILD SUCCEEDED **` on the iOS 26.5 simulator. If the app build surfaces new deprecation WARNINGS from legacy code under the 26.0 floor, note them in the report but do not fix legacy code in this task; new ERRORS are a blocker to report.

- [ ] **Step 4: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add "Food Intolerances.xcodeproj/project.pbxproj" HealthGraphCore/Package.swift
git commit -m "build: raise deployment floor to iOS 26 (app, tests, package)"
```

---

### Task 4: Migration v2 — dedupKey column + debug count queries

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Models/HealthEvent.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift`
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/AppDatabaseTests.swift`
- Modify: `HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift`

**Interfaces:**
- Consumes: Phase 0 schema v1.
- Produces: `health_events.dedupKey TEXT` column with partial unique index `idx_events_dedupKey`; `HealthEvent.dedupKey: String?` (init param, default `nil`); `EventStore.countsByCategory() async throws -> [String: Int]` and `countsBySource() async throws -> [String: Int]`. Tasks 5–11 rely on all three.

- [ ] **Step 1: Write the failing tests**

Append to `AppDatabaseTests`:

```swift
    @Test func v2AddsDedupKeyColumnAndUniqueIndex() throws {
        let db = try AppDatabase.inMemory()
        try db.dbWriter.read { d in
            let cols = try d.columns(in: "health_events").map(\.name)
            #expect(cols.contains("dedupKey"))
            let indexes = try d.indexes(on: "health_events").map(\.name)
            #expect(indexes.contains("idx_events_dedupKey"))
            #expect(indexes.contains("idx_events_category_subtype_timestamp"))
        }
    }

    @Test func dedupKeyUniqueIndexRejectsSecondInsert() throws {
        let db = try AppDatabase.inMemory()
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        try db.dbWriter.write { d in
            try HealthEvent(timestamp: t, category: .sleep, subtype: "asleepCore",
                            source: .healthKit, createdAt: t,
                            dedupKey: "sleep|asleepCore|29166666").insert(d)
        }
        #expect(throws: DatabaseError.self) {
            try db.dbWriter.write { d in
                try HealthEvent(timestamp: t, category: .sleep, subtype: "asleepCore",
                                source: .healthExportFile, createdAt: t,
                                dedupKey: "sleep|asleepCore|29166666").insert(d)
            }
        }
    }

    @Test func nilDedupKeysDoNotCollide() throws {
        let db = try AppDatabase.inMemory()
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        try db.dbWriter.write { d in
            try HealthEvent(timestamp: t, category: .food, source: .manual, createdAt: t).insert(d)
            try HealthEvent(timestamp: t, category: .food, source: .manual, createdAt: t).insert(d)
        }
        let count = try db.dbWriter.read { try HealthEvent.fetchCount($0) }
        #expect(count == 2) // partial index: NULL keys are exempt
    }
```

Append to `EventStoreTests` (inside the test struct):

```swift
    @Test func countsByCategoryAndSourceGroupCorrectly() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let deleted = HealthEvent(timestamp: t, category: .sleep, subtype: "asleepCore",
                                  source: .healthKit, createdAt: t)
        try await store.save([
            HealthEvent(timestamp: t, category: .food, subtype: "eggs", source: .manual, createdAt: t),
            HealthEvent(timestamp: t, category: .food, subtype: "milk", source: .healthKit, createdAt: t),
            deleted,
        ])
        try await store.softDelete(id: deleted.id)
        let byCategory = try await store.countsByCategory()
        let bySource = try await store.countsBySource()
        #expect(byCategory == ["food": 2]) // soft-deleted sleep event excluded
        #expect(bySource == ["manual": 1, "healthKit": 1])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -8`
Expected: compile FAILURE — `extra argument 'dedupKey' in call` and `no member 'countsByCategory'`.

- [ ] **Step 3: Implement**

1. In `AppDatabase.swift`, immediately after the closing brace of the `registerMigration("v1")` block (before `return migrator`), add:

```swift
        migrator.registerMigration("v2") { db in
            try db.alter(table: "health_events") { t in
                // Cross-source ingest dedup (spec §5.5). NULL = exempt (manual
                // and legacy events don't participate in import dedup).
                t.add(column: "dedupKey", .text)
            }
            // Partial unique index: SQLite treats NULLs as distinct anyway,
            // but the WHERE clause keeps the index small.
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_events_dedupKey
                ON health_events(dedupKey) WHERE dedupKey IS NOT NULL
                """)
            // Serves the ingest pipeline's duration-overlap query
            // (category + subtype + time range) at 100k+ events (spec §17).
            try db.create(index: "idx_events_category_subtype_timestamp",
                          on: "health_events",
                          columns: ["category", "subtype", "timestamp"])
        }
```

2. In `HealthEvent.swift`: add `public var dedupKey: String?` after `public var createdAt: Date`; add init parameter `dedupKey: String? = nil` after `createdAt: Date = Date()`; add `self.dedupKey = dedupKey` in the init body (keep `deletedAt` last in both lists).

2b. In `AppDatabase.swift`, change the struct declaration to `public struct AppDatabase: Sendable {` — GRDB 7's `DatabaseWriter` protocol is `Sendable`, so the conformance is free, and Task 11 passes an `AppDatabase` into a detached parsing task.

3. In `EventStore.swift`: add to the `EventStore` protocol:

```swift
    func countsByCategory() async throws -> [String: Int]
    func countsBySource() async throws -> [String: Int]
```

and to `GRDBEventStore`:

```swift
    public func countsByCategory() async throws -> [String: Int] {
        try await groupedCounts(column: "category")
    }

    public func countsBySource() async throws -> [String: Int] {
        try await groupedCounts(column: "source")
    }

    private func groupedCounts(column: String) async throws -> [String: Int] {
        try await dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT \(column) AS k, COUNT(*) AS c FROM health_events
                WHERE deletedAt IS NULL GROUP BY \(column)
                """)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["k"] as String, $0["c"] as Int) })
        }
    }
```

(`column` is only ever one of the two literals above — no injection surface.)

- [ ] **Step 4: Run the full package suite**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 34 tests in 7 suites passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): migration v2 dedupKey with partial unique index; grouped count queries"
```

---

### Task 5: IngestPipeline — source-priority dedup + interval merge

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/IngestPipeline.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/IngestPipelineTests.swift`

**Interfaces:**
- Consumes: `dedupKey` column (Task 4), `HealthEvent`, `AppDatabase`.
- Produces (all `public`, used by Tasks 7–11):
  - `struct IngestSummary: Equatable, Sendable { var inserted, updated, skipped, replaced: Int }`
  - `enum SourcePriority { static func rank(_ source: EventSource) -> Int }` — healthKit 3, healthExportFile 2, all else 1
  - `struct IngestPipeline { init(database: AppDatabase); func ingest(_ events: [HealthEvent]) async throws -> IngestSummary }`
  - `static func process(_ events: [HealthEvent], db: Database) throws -> IngestSummary` — the synchronous core, one transaction per call; the export parser (Task 7) calls this directly from its parse thread via `dbWriter.write`.

Dedup policy (spec §5.5, binding):
1. Events with `dedupKey == nil` insert unconditionally.
2. Exact dedupKey match (including soft-deleted rows — the unique index spans them): if the existing row is soft-deleted, SKIP — a user's delete is never resurrected by re-import. Else compare ranks: lower incoming rank → skip; equal/higher → update in place (adopt existing `id` and `createdAt`; idempotent recompute).
3. No exact match but the event has an `endTimestamp` (duration): query non-deleted duration events of the same category+subtype overlapping the interval.
   - Any overlap with rank HIGHER than incoming → skip (the higher-priority source owns this window).
   - Highest overlapping rank EQUALS incoming (e.g. Watch and iPhone both writing sleep via live HealthKit): skip only when the incoming interval is FULLY covered by the union of the equal-rank overlaps; otherwise insert alongside them — coverage is never truncated. (Spec §5.5 "overlapping intervals merged": merged-as-coverage, not dropped. Phase 2's nightly aggregation must union same-subtype overlaps when summing durations — noted in Done criteria.)
   - ALL overlaps rank lower → soft-delete them and insert (counted as `replaced`).
4. A dedupKey seen twice within one call: second occurrence is skipped (protects the unique index mid-transaction).

- [ ] **Step 1: Write the failing tests**

`HealthGraphCore/Tests/HealthGraphCoreTests/IngestPipelineTests.swift`:

```swift
import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

struct IngestPipelineTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    func event(_ category: EventCategory = .vitals, subtype: String = "restingHeartRate",
               offset: TimeInterval = 0, end: TimeInterval? = nil, value: Double = 60,
               source: EventSource = .healthKit, key: String? = "k1") -> HealthEvent {
        HealthEvent(
            timestamp: t0.addingTimeInterval(offset),
            endTimestamp: end.map { t0.addingTimeInterval($0) },
            category: category, subtype: subtype, value: value,
            source: source, createdAt: t0, dedupKey: key
        )
    }

    @Test func insertsFreshEvents() async throws {
        let db = try AppDatabase.inMemory()
        let summary = try await IngestPipeline(database: db)
            .ingest([event(key: "a"), event(offset: 60, key: "b")])
        #expect(summary == IngestSummary(inserted: 2, updated: 0, skipped: 0, replaced: 0))
        #expect(try await GRDBEventStore(database: db).count() == 2)
    }

    @Test func equalRankUpdatesInPlace() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([event(value: 60)])
        let summary = try await pipeline.ingest([event(value: 62)])
        #expect(summary == IngestSummary(inserted: 0, updated: 1, skipped: 0, replaced: 0))
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.count == 1)
        #expect(all.first?.value == 62)
    }

    @Test func lowerRankIsSkipped() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([event(value: 60, source: .healthKit)])
        let summary = try await pipeline.ingest([event(value: 99, source: .healthExportFile)])
        #expect(summary == IngestSummary(inserted: 0, updated: 0, skipped: 1, replaced: 0))
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.first?.value == 60)
        #expect(all.first?.source == .healthKit)
    }

    @Test func higherRankReplacesInPlaceKeepingID() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([event(value: 60, source: .healthExportFile)])
        let originalID = try await GRDBEventStore(database: db).recentEvents(limit: 1).first!.id
        let summary = try await pipeline.ingest([event(value: 61, source: .healthKit)])
        #expect(summary.updated == 1)
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.count == 1)
        #expect(all.first?.id == originalID)
        #expect(all.first?.source == .healthKit)
    }

    @Test func userSoftDeleteIsNeverResurrected() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        let store = GRDBEventStore(database: db)
        _ = try await pipeline.ingest([event()])
        let id = try await store.recentEvents(limit: 1).first!.id
        try await store.softDelete(id: id)
        let summary = try await pipeline.ingest([event(value: 99)])
        #expect(summary == IngestSummary(inserted: 0, updated: 0, skipped: 1, replaced: 0))
        #expect(try await store.count() == 0) // still deleted
    }

    @Test func overlappingDurationSkippedWhenExistingRankHigher() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 0, end: 3600, source: .healthKit, key: "s1")])
        // export-file segment overlapping [0, 3600] with a different key
        let summary = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 600, end: 4200,
                  source: .healthExportFile, key: "s2")])
        #expect(summary == IngestSummary(inserted: 0, updated: 0, skipped: 1, replaced: 0))
        #expect(try await GRDBEventStore(database: db).count() == 1)
    }

    @Test func equalRankFullyCoveredOverlapIsSkipped() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 0, end: 7200, source: .healthKit, key: "s1")])
        // second device's segment lies entirely within existing coverage
        let summary = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 600, end: 3600,
                  source: .healthKit, key: "s2")])
        #expect(summary == IngestSummary(inserted: 0, updated: 0, skipped: 1, replaced: 0))
        #expect(try await GRDBEventStore(database: db).count() == 1)
    }

    @Test func equalRankPartialOverlapKeepsBothSegments() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 0, end: 3600, source: .healthKit, key: "s1")])
        // Watch 00:00–01:00 + iPhone 00:30–02:00: the 01:00–02:00 coverage
        // must not be dropped
        let summary = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 1800, end: 7200,
                  source: .healthKit, key: "s2")])
        #expect(summary == IngestSummary(inserted: 1, updated: 0, skipped: 0, replaced: 0))
        #expect(try await GRDBEventStore(database: db).count() == 2)
    }

    @Test func overlappingDurationReplacedWhenIncomingRankHigher() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 0, end: 3600,
                  source: .healthExportFile, key: "s1")])
        let summary = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 600, end: 4200,
                  source: .healthKit, key: "s2")])
        #expect(summary.replaced == 1)
        let store = GRDBEventStore(database: db)
        #expect(try await store.count() == 1) // old segment soft-deleted, new one live
        #expect(try await store.rawCountIncludingDeleted() == 2)
        #expect(try await store.recentEvents(limit: 1).first?.source == .healthKit)
    }

    @Test func nonOverlappingDurationsCoexist() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([
            event(.sleep, subtype: "asleepCore", offset: 0, end: 3600, source: .healthKit, key: "s1"),
            event(.sleep, subtype: "asleepCore", offset: 7200, end: 10800, source: .healthKit, key: "s2")])
        #expect(try await GRDBEventStore(database: db).count() == 2)
    }

    @Test func duplicateKeyWithinOneBatchIsSkipped() async throws {
        let db = try AppDatabase.inMemory()
        let summary = try await IngestPipeline(database: db)
            .ingest([event(value: 60), event(value: 61)]) // same key "k1"
        #expect(summary == IngestSummary(inserted: 1, updated: 0, skipped: 1, replaced: 0))
    }

    @Test func reingestingSameBatchIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        let batch = [event(key: "a"), event(offset: 60, key: "b"),
                     event(.sleep, subtype: "asleepCore", offset: 0, end: 3600, key: "c")]
        _ = try await pipeline.ingest(batch)
        let second = try await pipeline.ingest(batch)
        #expect(second.inserted == 0)
        #expect(try await GRDBEventStore(database: db).count() == 3)
    }

    @Test func nilKeyEventsAlwaysInsert() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest([event(key: nil), event(key: nil)])
        #expect(try await GRDBEventStore(database: db).count() == 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'IngestPipeline' in scope`.

- [ ] **Step 3: Implement the pipeline**

`HealthGraphCore/Sources/HealthGraphCore/Ingestion/IngestPipeline.swift`:

```swift
import Foundation
import GRDB

/// Outcome counters for one ingest call.
public struct IngestSummary: Equatable, Sendable {
    public var inserted: Int
    public var updated: Int
    public var skipped: Int
    public var replaced: Int

    public init(inserted: Int = 0, updated: Int = 0, skipped: Int = 0, replaced: Int = 0) {
        self.inserted = inserted
        self.updated = updated
        self.skipped = skipped
        self.replaced = replaced
    }

    public static func + (l: IngestSummary, r: IngestSummary) -> IngestSummary {
        IngestSummary(inserted: l.inserted + r.inserted, updated: l.updated + r.updated,
                      skipped: l.skipped + r.skipped, replaced: l.replaced + r.replaced)
    }
}

/// Spec §5.5 source priority: live HealthKit > export file > everything else.
public enum SourcePriority {
    public static func rank(_ source: EventSource) -> Int {
        switch source {
        case .healthKit: return 3
        case .healthExportFile: return 2
        default: return 1
        }
    }
}

/// Idempotent, source-priority-aware event ingestion (spec §5.5).
/// See the dedup policy comment on `process` for the exact rules.
public struct IngestPipeline: Sendable {
    public static let batchSize = 500
    let dbWriter: any DatabaseWriter

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    /// Async entry point: batches of `batchSize`, one transaction each.
    public func ingest(_ events: [HealthEvent]) async throws -> IngestSummary {
        var total = IngestSummary()
        var index = 0
        while index < events.count {
            let batch = Array(events[index ..< min(index + Self.batchSize, events.count)])
            total = total + (try await dbWriter.write { db in
                try Self.process(batch, db: db)
            })
            index += Self.batchSize
        }
        return total
    }

    /// Synchronous core — runs inside one GRDB transaction. Exposed so the
    /// export parser's (synchronous) streaming loop can flush batches without
    /// hopping executors.
    ///
    /// Policy, in order:
    /// 1. `dedupKey == nil` → insert (manual/legacy events don't dedup).
    /// 2. Exact dedupKey match (soft-deleted rows included — the unique index
    ///    spans them): deleted → skip (user deletes are never resurrected);
    ///    incoming rank lower → skip; else update in place, keeping the
    ///    existing row's `id` and `createdAt`.
    /// 3. Duration events (endTimestamp != nil) with no exact match: overlap
    ///    against live duration events of the same category+subtype. Any
    ///    overlap with rank ≥ incoming → skip; otherwise soft-delete the
    ///    lower-rank overlaps and insert (`replaced`).
    /// 4. A dedupKey repeated within the call → later occurrence skipped.
    public static func process(_ events: [HealthEvent], db: Database) throws -> IngestSummary {
        var summary = IngestSummary()
        var seenKeys = Set<String>()

        let keys = events.compactMap(\.dedupKey)
        let existingRows = keys.isEmpty ? [] : try HealthEvent
            .filter(keys.contains(Column("dedupKey")))
            .fetchAll(db) // deliberately includes soft-deleted rows
        var existingByKey = Dictionary(existingRows.map { ($0.dedupKey!, $0) },
                                       uniquingKeysWith: { a, _ in a })

        for var event in events {
            guard let key = event.dedupKey else {
                try event.insert(db)
                summary.inserted += 1
                continue
            }
            guard seenKeys.insert(key).inserted else {
                summary.skipped += 1
                continue
            }
            if let existing = existingByKey[key] {
                if existing.deletedAt != nil {
                    summary.skipped += 1
                    continue
                }
                if SourcePriority.rank(event.source) < SourcePriority.rank(existing.source) {
                    summary.skipped += 1
                    continue
                }
                event.id = existing.id
                event.createdAt = existing.createdAt
                try event.save(db)
                existingByKey[key] = event
                summary.updated += 1
                continue
            }
            if let end = event.endTimestamp {
                let overlapping = try HealthEvent
                    .filter(Column("deletedAt") == nil)
                    .filter(Column("category") == event.category.rawValue)
                    .filter(Column("subtype") == event.subtype)
                    .filter(Column("endTimestamp") != nil)
                    .filter(Column("timestamp") < end)
                    .filter(Column("endTimestamp") > event.timestamp)
                    .fetchAll(db)
                let rank = SourcePriority.rank(event.source)
                let maxExistingRank = overlapping.map { SourcePriority.rank($0.source) }.max()
                if let maxExistingRank, maxExistingRank > rank {
                    summary.skipped += 1
                    continue
                }
                if let maxExistingRank, maxExistingRank == rank {
                    // Two equal-rank sources (e.g. Watch + iPhone via live
                    // HealthKit) recorded overlapping-but-different segments:
                    // drop the incoming one only if it adds no coverage;
                    // otherwise keep both — coverage is never truncated.
                    let peers = overlapping.filter { SourcePriority.rank($0.source) == rank }
                    if Self.isInterval(from: event.timestamp, to: end, coveredBy: peers) {
                        summary.skipped += 1
                    } else {
                        try event.insert(db)
                        summary.inserted += 1
                    }
                    continue
                }
                if overlapping.isEmpty {
                    try event.insert(db)
                    summary.inserted += 1
                } else {
                    for old in overlapping {
                        try db.execute(
                            sql: "UPDATE health_events SET deletedAt = ? WHERE id = ?",
                            arguments: [Date(), old.id])
                    }
                    try event.insert(db)
                    summary.replaced += 1
                }
                continue
            }
            try event.insert(db)
            summary.inserted += 1
        }
        return summary
    }

    /// True when [start, end] is fully covered by the union of the given
    /// events' intervals.
    static func isInterval(from start: Date, to end: Date,
                           coveredBy events: [HealthEvent]) -> Bool {
        let intervals = events
            .compactMap { e -> (Date, Date)? in
                guard let eEnd = e.endTimestamp else { return nil }
                return (e.timestamp, eEnd)
            }
            .sorted { $0.0 < $1.0 }
        var cursor = start
        for (s, e) in intervals {
            if s > cursor { return false }
            if e > cursor { cursor = e }
            if cursor >= end { return true }
        }
        return cursor >= end
    }
}
```

- [ ] **Step 4: Run the full package suite**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 47 tests in 8 suites passed` (34 + 13 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): IngestPipeline with source-priority dedup and interval merge"
```

---

### Task 6: HealthKit sample mapper — DTOs, mapping tables, dedup keys

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/DedupKey.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/HealthKitSampleMapper.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/HealthKitSampleMapperTests.swift`

**Interfaces:**
- Consumes: `HealthEvent`, `EventCategory`, `EventSource` (Task 4's `dedupKey` init param).
- Produces (all `public`; consumed by Tasks 7, 8, 9):
  - `enum DedupKey` — `point(_:_:_:)`, `duration(_:_:start:end:)`, `daily(_:_:dayStart:)`
  - DTOs: `QuantitySampleData`, `CategorySampleData`, `WorkoutData`, `DailyStatData` (plain value types — **HealthKit itself is never imported in the package**; the app target converts HK objects to these)
  - `enum HealthKitSampleMapper` with `map(_:source:)` overloads for each DTO returning `HealthEvent?` (nil = unmapped/skip), plus:
    - `static var perSampleQuantityIdentifiers: Set<String>`
    - `static var dailyStatIdentifiers: Set<String>` (with `static func dailyStatOptions(for identifier: String) -> DailyStatAggregation` where `public enum DailyStatAggregation { case sum, average }`)
    - `static var categoryIdentifiers: Set<String>` and `static let symptomIdentifiers: Set<String>`
    - `static func categoryValue(fromExportString: String) -> Int?` (export.xml writes category values as strings)

Mapping tables (binding — the implementer transcribes these exactly):

| HK identifier (per-sample quantity) | category | subtype | unit stored |
|---|---|---|---|
| `HKQuantityTypeIdentifierRestingHeartRate` | vitals | restingHeartRate | bpm |
| `HKQuantityTypeIdentifierBodyMass` | bodyMetric | weight | kg |
| `HKQuantityTypeIdentifierBloodPressureSystolic` | vitals | bloodPressureSystolic | mmHg |
| `HKQuantityTypeIdentifierBloodPressureDiastolic` | vitals | bloodPressureDiastolic | mmHg |

| HK identifier (daily statistic) | category | subtype | unit | aggregation |
|---|---|---|---|---|
| `HKQuantityTypeIdentifierStepCount` | exercise | steps | count | sum |
| `HKQuantityTypeIdentifierHeartRate` | vitals | heartRate | bpm | average |
| `HKQuantityTypeIdentifierHeartRateVariabilitySDNN` | vitals | hrv | ms | average |
| `HKQuantityTypeIdentifierRespiratoryRate` | vitals | respiratoryRate | breaths/min | average |
| `HKQuantityTypeIdentifierDietaryEnergyConsumed` | food | dietaryEnergy | kcal | sum |
| `HKQuantityTypeIdentifierDietaryProtein` | food | dietaryProtein | g | sum |
| `HKQuantityTypeIdentifierDietaryCarbohydrates` | food | dietaryCarbs | g | sum |
| `HKQuantityTypeIdentifierDietaryFatTotal` | food | dietaryFat | g | sum |
| `HKQuantityTypeIdentifierDietarySugar` | food | dietarySugar | g | sum |
| `HKQuantityTypeIdentifierDietarySodium` | food | dietarySodium | mg | sum |

(The five dietary rows cover MyFitnessPal-style macro sync per spec §5.1 "dietary entries". Named food items via `HKCorrelationTypeIdentifierFood` are deliberately NOT imported in 1A — meal capture in Plans 1C/1D is the primary named-food path; noted in Done criteria.)

Daily-stat events are **duration events**: `timestamp = dayStart`, `endTimestamp = dayStart + 86_400`, `dedupKey = DedupKey.daily(...)` — so cross-source day-boundary drift is absorbed by Task 5's interval-overlap merging.

Category samples: `HKCategoryTypeIdentifierSleepAnalysis` → sleep, subtype from stage raw value (0 inBed, 1 asleepUnspecified, 2 awake, 3 asleepCore, 4 asleepDeep, 5 asleepREM), `value` = duration in minutes, duration event. `HKCategoryTypeIdentifierMindfulSession` → stress/mindfulness, minutes, duration event. `HKCategoryTypeIdentifierMenstrualFlow` → cycle/menstrualFlow, point event, value: raw 2 (light) → 1, 3 (medium) → 2, 4 (heavy) → 3, raw 1 (unspecified) → nil value (present, unrated), raw 5 (none) → skip (return nil).

Symptom category identifiers (severity raw values: 0 unspecified → value nil; 1 notPresent → skip; 2 mild → 2; 3 moderate → 5; 4 severe → 8; subtype = identifier with `HKCategoryTypeIdentifier` prefix stripped and first letter lowercased, e.g. `headache`, `abdominalCramps`):

```
Headache, AbdominalCramps, Bloating, Nausea, Vomiting, Diarrhea, Constipation,
Heartburn, Fatigue, Dizziness, ChestTightnessOrPain, ShortnessOfBreath, Coughing,
Fever, Chills, SoreThroat, RunnyNose, SinusCongestion, MoodChanges, SleepChanges,
AppetiteChanges, HotFlashes, Acne, DrySkin, HairLoss, NightSweats, PelvicPain,
MemoryLapse, GeneralizedBodyAche, LowerBackPain, SkippedHeartbeat,
RapidPoundingOrFlutteringHeartbeat, BladderIncontinence, LossOfSmell, LossOfTaste,
Wheezing, BreastPain, VaginalDryness, Fainting
```

Workouts → exercise/`activityName` (already prefix-stripped, first letter lowercased by the caller), value = duration minutes, duration event, metadata JSON `{"kcal": "412", "distanceKm": "5.2"}` (keys omitted when nil).

All mapped events: `confidence: 1.0`, `timezoneID` from the DTO's optional field else `TimeZone.current.identifier`, `source` = the `source:` argument (`.healthKit` or `.healthExportFile`).

- [ ] **Step 1: Write the failing tests**

`HealthGraphCore/Tests/HealthGraphCoreTests/HealthKitSampleMapperTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct HealthKitSampleMapperTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func dedupKeyFormatsAreStable() {
        #expect(DedupKey.point(.symptom, "headache", t0) == "symptom|headache|29166666")
        #expect(DedupKey.duration(.sleep, "asleepCore", start: t0, end: t0.addingTimeInterval(3600))
                == "sleep|asleepCore|29166666|29166726")
        #expect(DedupKey.daily(.exercise, "steps", dayStart: t0) == "exercise|steps|day|29166666")
        #expect(DedupKey.point(.food, nil, t0) == "food||29166666")
    }

    @Test func mapsRestingHeartRateSample() {
        let e = HealthKitSampleMapper.map(
            QuantitySampleData(identifier: "HKQuantityTypeIdentifierRestingHeartRate",
                               start: t0, end: t0, value: 58, unit: "bpm", timezoneID: "Europe/Paris"),
            source: .healthKit)
        #expect(e?.category == .vitals)
        #expect(e?.subtype == "restingHeartRate")
        #expect(e?.value == 58)
        #expect(e?.unit == "bpm")
        #expect(e?.timezoneID == "Europe/Paris")
        #expect(e?.dedupKey == DedupKey.point(.vitals, "restingHeartRate", t0))
        #expect(e?.source == .healthKit)
    }

    @Test func convertsPoundsToKilograms() {
        let e = HealthKitSampleMapper.map(
            QuantitySampleData(identifier: "HKQuantityTypeIdentifierBodyMass",
                               start: t0, end: t0, value: 180, unit: "lb", timezoneID: nil),
            source: .healthExportFile)
        #expect(e?.category == .bodyMetric)
        #expect(e?.unit == "kg")
        #expect(abs((e?.value ?? 0) - 81.6466) < 0.001)
    }

    @Test func unknownIdentifierReturnsNil() {
        let e = HealthKitSampleMapper.map(
            QuantitySampleData(identifier: "HKQuantityTypeIdentifierVO2Max",
                               start: t0, end: t0, value: 40, unit: "mL/kg·min", timezoneID: nil),
            source: .healthKit)
        #expect(e == nil)
    }

    @Test func mapsSleepStageWithDurationMinutes() {
        let e = HealthKitSampleMapper.map(
            CategorySampleData(identifier: "HKCategoryTypeIdentifierSleepAnalysis",
                               start: t0, end: t0.addingTimeInterval(5400), value: 4, timezoneID: nil),
            source: .healthKit)
        #expect(e?.category == .sleep)
        #expect(e?.subtype == "asleepDeep")
        #expect(e?.value == 90) // minutes
        #expect(e?.endTimestamp == t0.addingTimeInterval(5400))
        #expect(e?.dedupKey == DedupKey.duration(.sleep, "asleepDeep",
                                                 start: t0, end: t0.addingTimeInterval(5400)))
    }

    @Test func mapsSymptomSeverities() {
        func severity(_ raw: Int) -> HealthEvent? {
            HealthKitSampleMapper.map(
                CategorySampleData(identifier: "HKCategoryTypeIdentifierHeadache",
                                   start: t0, end: t0, value: raw, timezoneID: nil),
                source: .healthKit)
        }
        #expect(severity(1) == nil)          // notPresent -> skip
        #expect(severity(0)?.value == nil)   // unspecified -> present, unrated
        #expect(severity(2)?.value == 2)     // mild
        #expect(severity(3)?.value == 5)     // moderate
        #expect(severity(4)?.value == 8)     // severe
        #expect(severity(2)?.category == .symptom)
        #expect(severity(2)?.subtype == "headache")
    }

    @Test func menstrualFlowMapsAndSkipsNone() {
        func flow(_ raw: Int) -> HealthEvent? {
            HealthKitSampleMapper.map(
                CategorySampleData(identifier: "HKCategoryTypeIdentifierMenstrualFlow",
                                   start: t0, end: t0, value: raw, timezoneID: nil),
                source: .healthKit)
        }
        #expect(flow(5) == nil)        // none
        #expect(flow(2)?.value == 1)   // light
        #expect(flow(4)?.value == 3)   // heavy
        #expect(flow(2)?.category == .cycle)
    }

    @Test func mapsWorkoutWithMetadata() throws {
        let e = HealthKitSampleMapper.map(
            WorkoutData(activityName: "running", start: t0,
                        end: t0.addingTimeInterval(1800), kcal: 412, distanceKm: 5.2,
                        timezoneID: nil),
            source: .healthKit)
        #expect(e?.category == .exercise)
        #expect(e?.subtype == "running")
        #expect(e?.value == 30)
        let meta = try JSONDecoder().decode([String: String].self, from: e?.metadata ?? Data())
        #expect(meta["kcal"] == "412")
        #expect(meta["distanceKm"] == "5.2")
    }

    @Test func dailyStatBecomesDayLongDurationEvent() {
        let e = HealthKitSampleMapper.map(
            DailyStatData(identifier: "HKQuantityTypeIdentifierStepCount",
                          dayStart: t0, value: 8200, timezoneID: nil),
            source: .healthKit)
        #expect(e?.category == .exercise)
        #expect(e?.subtype == "steps")
        #expect(e?.value == 8200)
        #expect(e?.endTimestamp == t0.addingTimeInterval(86_400))
        #expect(e?.dedupKey == DedupKey.daily(.exercise, "steps", dayStart: t0))
    }

    @Test func exportCategoryValueStringsResolve() {
        #expect(HealthKitSampleMapper.categoryValue(
            fromExportString: "HKCategoryValueSleepAnalysisAsleepDeep") == 4)
        #expect(HealthKitSampleMapper.categoryValue(
            fromExportString: "HKCategoryValueSeverityMild") == 2)
        #expect(HealthKitSampleMapper.categoryValue(
            fromExportString: "HKCategoryValueMenstrualFlowHeavy") == 4)
        #expect(HealthKitSampleMapper.categoryValue(fromExportString: "HKCategoryValueNotApplicable") == 0)
        #expect(HealthKitSampleMapper.categoryValue(fromExportString: "SomethingUnknown") == nil)
    }

    @Test func identifierSetsAreConsistent() {
        #expect(HealthKitSampleMapper.perSampleQuantityIdentifiers.count == 4)
        #expect(HealthKitSampleMapper.dailyStatIdentifiers.count == 10)
        #expect(HealthKitSampleMapper.symptomIdentifiers.contains("HKCategoryTypeIdentifierHeadache"))
        #expect(HealthKitSampleMapper.dailyStatOptions(
            for: "HKQuantityTypeIdentifierStepCount") == .sum)
        #expect(HealthKitSampleMapper.dailyStatOptions(
            for: "HKQuantityTypeIdentifierHeartRate") == .average)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'DedupKey' in scope`.

- [ ] **Step 3: Implement**

`HealthGraphCore/Sources/HealthGraphCore/Ingestion/DedupKey.swift`:

```swift
import Foundation

/// Stable cross-source dedup keys (spec §5.5): timestamps rounded to the
/// minute. NEVER change these formats — they are persisted in the DB and
/// re-imports must keep matching historical rows.
public enum DedupKey {
    static func minute(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }

    public static func point(_ category: EventCategory, _ subtype: String?, _ timestamp: Date) -> String {
        "\(category.rawValue)|\(subtype ?? "")|\(minute(timestamp))"
    }

    public static func duration(_ category: EventCategory, _ subtype: String?,
                                start: Date, end: Date) -> String {
        "\(category.rawValue)|\(subtype ?? "")|\(minute(start))|\(minute(end))"
    }

    public static func daily(_ category: EventCategory, _ subtype: String?, dayStart: Date) -> String {
        "\(category.rawValue)|\(subtype ?? "")|day|\(minute(dayStart))"
    }
}
```

`HealthGraphCore/Sources/HealthGraphCore/Ingestion/HealthKitSampleMapper.swift` — implement the DTOs and tables exactly as specified in the Interfaces block above. Skeleton with the exact table entries:

```swift
import Foundation

// Plain value types: the package never imports HealthKit. The app target
// (and the export parser) convert their sources into these.

public struct QuantitySampleData: Sendable {
    public let identifier: String
    public let start: Date
    public let end: Date
    public let value: Double
    public let unit: String
    public let timezoneID: String?
    public init(identifier: String, start: Date, end: Date,
                value: Double, unit: String, timezoneID: String?) {
        self.identifier = identifier; self.start = start; self.end = end
        self.value = value; self.unit = unit; self.timezoneID = timezoneID
    }
}

public struct CategorySampleData: Sendable {
    public let identifier: String
    public let start: Date
    public let end: Date
    public let value: Int
    public let timezoneID: String?
    public init(identifier: String, start: Date, end: Date, value: Int, timezoneID: String?) {
        self.identifier = identifier; self.start = start; self.end = end
        self.value = value; self.timezoneID = timezoneID
    }
}

public struct WorkoutData: Sendable {
    public let activityName: String
    public let start: Date
    public let end: Date
    public let kcal: Double?
    public let distanceKm: Double?
    public let timezoneID: String?
    public init(activityName: String, start: Date, end: Date,
                kcal: Double?, distanceKm: Double?, timezoneID: String?) {
        self.activityName = activityName; self.start = start; self.end = end
        self.kcal = kcal; self.distanceKm = distanceKm; self.timezoneID = timezoneID
    }
}

public struct DailyStatData: Sendable {
    public let identifier: String
    public let dayStart: Date
    public let value: Double
    public let timezoneID: String?
    public init(identifier: String, dayStart: Date, value: Double, timezoneID: String?) {
        self.identifier = identifier; self.dayStart = dayStart
        self.value = value; self.timezoneID = timezoneID
    }
}

public enum DailyStatAggregation: Sendable, Equatable { case sum, average }

public enum HealthKitSampleMapper {
    // (category, subtype, canonical unit)
    private static let quantityTable: [String: (EventCategory, String, String)] = [
        "HKQuantityTypeIdentifierRestingHeartRate": (.vitals, "restingHeartRate", "bpm"),
        "HKQuantityTypeIdentifierBodyMass": (.bodyMetric, "weight", "kg"),
        "HKQuantityTypeIdentifierBloodPressureSystolic": (.vitals, "bloodPressureSystolic", "mmHg"),
        "HKQuantityTypeIdentifierBloodPressureDiastolic": (.vitals, "bloodPressureDiastolic", "mmHg"),
    ]

    private static let dailyTable: [String: (EventCategory, String, String, DailyStatAggregation)] = [
        "HKQuantityTypeIdentifierStepCount": (.exercise, "steps", "count", .sum),
        "HKQuantityTypeIdentifierHeartRate": (.vitals, "heartRate", "bpm", .average),
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": (.vitals, "hrv", "ms", .average),
        "HKQuantityTypeIdentifierRespiratoryRate": (.vitals, "respiratoryRate", "breaths/min", .average),
        "HKQuantityTypeIdentifierDietaryEnergyConsumed": (.food, "dietaryEnergy", "kcal", .sum),
        "HKQuantityTypeIdentifierDietaryProtein": (.food, "dietaryProtein", "g", .sum),
        "HKQuantityTypeIdentifierDietaryCarbohydrates": (.food, "dietaryCarbs", "g", .sum),
        "HKQuantityTypeIdentifierDietaryFatTotal": (.food, "dietaryFat", "g", .sum),
        "HKQuantityTypeIdentifierDietarySugar": (.food, "dietarySugar", "g", .sum),
        "HKQuantityTypeIdentifierDietarySodium": (.food, "dietarySodium", "mg", .sum),
    ]

    private static let sleepStages: [Int: String] = [
        0: "inBed", 1: "asleepUnspecified", 2: "awake",
        3: "asleepCore", 4: "asleepDeep", 5: "asleepREM",
    ]

    public static let symptomIdentifiers: Set<String> = Set([
        "Headache", "AbdominalCramps", "Bloating", "Nausea", "Vomiting", "Diarrhea",
        "Constipation", "Heartburn", "Fatigue", "Dizziness", "ChestTightnessOrPain",
        "ShortnessOfBreath", "Coughing", "Fever", "Chills", "SoreThroat", "RunnyNose",
        "SinusCongestion", "MoodChanges", "SleepChanges", "AppetiteChanges", "HotFlashes",
        "Acne", "DrySkin", "HairLoss", "NightSweats", "PelvicPain", "MemoryLapse",
        "GeneralizedBodyAche", "LowerBackPain", "SkippedHeartbeat",
        "RapidPoundingOrFlutteringHeartbeat", "BladderIncontinence", "LossOfSmell",
        "LossOfTaste", "Wheezing", "BreastPain", "VaginalDryness", "Fainting",
    ].map { "HKCategoryTypeIdentifier\($0)" })

    public static var perSampleQuantityIdentifiers: Set<String> { Set(quantityTable.keys) }
    public static var dailyStatIdentifiers: Set<String> { Set(dailyTable.keys) }
    public static var categoryIdentifiers: Set<String> {
        symptomIdentifiers.union([
            "HKCategoryTypeIdentifierSleepAnalysis",
            "HKCategoryTypeIdentifierMindfulSession",
            "HKCategoryTypeIdentifierMenstrualFlow",
        ])
    }

    public static func dailyStatOptions(for identifier: String) -> DailyStatAggregation {
        dailyTable[identifier]?.3 ?? .sum
    }
    // ... map(_:source:) overloads and categoryValue(fromExportString:) below
}
```

The four `map` overloads follow the tables and rules in the Interfaces block, with these implementation notes:
- Unit conversion for quantities: incoming `unit` strings `"lb"` → value × 0.45359237, unit `"kg"`; `"g"` for bodyMass → ÷ 1000 → `"kg"`; `"count/min"` → `"bpm"` or `"breaths/min"` per the table's canonical unit; `"s"` for HRV → × 1000 → `"ms"`; `"kJ"` → × 0.239006 → `"kcal"`; `"Cal"`/`"kcal"` → `"kcal"`; for the `"mg"`-canonical row (dietarySodium), `"g"` → × 1000 → `"mg"`; anything already canonical passes through. Unknown units: keep value, store the canonical unit anyway, set `confidence: 0.8` (flagged, not dropped).
- Severity mapping helper for symptoms: `[0: nil, 2: 2, 3: 5, 4: 8]`, raw 1 returns `nil` (skip the whole sample).
- Symptom subtype: strip the `HKCategoryTypeIdentifier` prefix, lowercase the first character.
- `categoryValue(fromExportString:)` table: `"HKCategoryValueNotApplicable": 0`, `"HKCategoryValueSleepAnalysisInBed": 0`, `"HKCategoryValueSleepAnalysisAsleep": 1`, `"HKCategoryValueSleepAnalysisAsleepUnspecified": 1`, `"HKCategoryValueSleepAnalysisAwake": 2`, `"HKCategoryValueSleepAnalysisAsleepCore": 3`, `"HKCategoryValueSleepAnalysisAsleepDeep": 4`, `"HKCategoryValueSleepAnalysisAsleepREM": 5`, `"HKCategoryValueSeverityUnspecified": 0`, `"HKCategoryValueSeverityNotPresent": 1`, `"HKCategoryValueSeverityMild": 2`, `"HKCategoryValueSeverityModerate": 3`, `"HKCategoryValueSeveritySevere": 4`, `"HKCategoryValueMenstrualFlowUnspecified": 1`, `"HKCategoryValueMenstrualFlowLight": 2`, `"HKCategoryValueMenstrualFlowMedium": 3`, `"HKCategoryValueMenstrualFlowHeavy": 4`, `"HKCategoryValueMenstrualFlowNone": 5`; unknown → `nil`.
- Workout metadata: encode `[String: String]` with `JSONEncoder`, formatting numbers via `"\(Int(kcal))"` for kcal and `String(format: "%.1f", distanceKm)` for distance.

- [ ] **Step 4: Run the full package suite**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 58 tests in 9 suites passed` (47 + 11 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): HealthKit sample mapper with dedup keys and mapping tables"
```

---

### Task 7: Apple Health export parser (zip + streaming XML)

**Files:**
- Modify: `HealthGraphCore/Package.swift` (add ZIPFoundation)
- Create: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/ExportArchive.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/AppleHealthExportParser.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/AppleHealthExportParserTests.swift`

**Interfaces:**
- Consumes: `HealthKitSampleMapper` (Task 6), `IngestPipeline.process(_:db:)` (Task 5).
- Produces (consumed by Task 11's import button):
  - `enum ExportArchive { static func extractExportXML(from zipURL: URL) throws -> URL }` — unzips into a unique temp directory, returns the `export.xml` URL; throws `ExportArchiveError.exportXMLNotFound` if absent.
  - `struct ExportParseResult: Sendable { let summary: IngestSummary; let recordsRead: Int; let recordsSkipped: Int }`
  - `final class AppleHealthExportParser: NSObject { init(database: AppDatabase); func parse(xmlAt url: URL, progress: (@Sendable (Int) -> Void)?) throws -> ExportParseResult }` — synchronous by design (callers wrap in `Task.detached`); flushes 500-event batches through `IngestPipeline.process` inside `dbWriter.write`, so memory stays flat for multi-hundred-MB exports.

Export format facts (binding): `export.zip` contains `apple_health_export/export.xml`. Records look like `<Record type="HKQuantityTypeIdentifierBodyMass" sourceName="..." unit="lb" value="180" startDate="2024-01-01 08:00:00 -0500" endDate="2024-01-01 08:00:00 -0500"/>`; category records carry string values (`value="HKCategoryValueSleepAnalysisAsleepDeep"`); workouts are `<Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="30.5" durationUnit="min" totalDistance="5.2" totalDistanceUnit="km" totalEnergyBurned="412" totalEnergyBurnedUnit="Cal" startDate="..." endDate="...">`. Date format: `yyyy-MM-dd HH:mm:ss Z` (fixed `en_US_POSIX` locale).

Daily-stat identifiers (steps, heartRate, hrv, respiratoryRate, dietaryEnergy) are NOT emitted per-record — the parser accumulates them per local calendar day during the stream (sum or average per `dailyStatOptions(for:)`) and emits day events (via `HealthKitSampleMapper.map(DailyStatData…)`, source `.healthExportFile`) in a final flush. Day bucketing uses `Calendar.current.startOfDay` — the same convention Task 8 uses for live stats, so the two sources produce overlapping day intervals that Task 5's merge policy resolves.

- [ ] **Step 1: Add the ZIPFoundation dependency**

In `HealthGraphCore/Package.swift`: add to `dependencies`:

```swift
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
```

and add `.product(name: "ZIPFoundation", package: "ZIPFoundation"),` to BOTH targets' `dependencies` arrays — the `HealthGraphCore` target AND the `HealthGraphCoreTests` test target (the zip-fixture tests `import ZIPFoundation` for `FileManager.zipItem`).

Run `cd HealthGraphCore && swift build 2>&1 | tail -2` — expected: resolves ZIPFoundation, `Build complete!`.

- [ ] **Step 2: Write the failing tests**

`HealthGraphCore/Tests/HealthGraphCoreTests/AppleHealthExportParserTests.swift`:

```swift
import Testing
import Foundation
import ZIPFoundation
@testable import HealthGraphCore

struct AppleHealthExportParserTests {
    static let fixtureXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <HealthData locale="en_US">
     <ExportDate value="2026-07-01 10:00:00 -0400"/>
     <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Health" unit="lb" \
    value="180" startDate="2026-06-01 08:00:00 -0400" endDate="2026-06-01 08:00:00 -0400"/>
     <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Watch" \
    value="HKCategoryValueSleepAnalysisAsleepDeep" \
    startDate="2026-06-01 01:00:00 -0400" endDate="2026-06-01 02:30:00 -0400"/>
     <Record type="HKCategoryTypeIdentifierHeadache" sourceName="Health" \
    value="HKCategoryValueSeverityModerate" \
    startDate="2026-06-01 11:00:00 -0400" endDate="2026-06-01 11:00:00 -0400"/>
     <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Phone" unit="count" \
    value="4000" startDate="2026-06-01 09:00:00 -0400" endDate="2026-06-01 09:10:00 -0400"/>
     <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Phone" unit="count" \
    value="4200" startDate="2026-06-01 15:00:00 -0400" endDate="2026-06-01 15:10:00 -0400"/>
     <Record type="HKQuantityTypeIdentifierVO2Max" sourceName="Watch" unit="mL/min·kg" \
    value="41" startDate="2026-06-01 09:00:00 -0400" endDate="2026-06-01 09:00:00 -0400"/>
     <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="30" \
    durationUnit="min" totalDistance="5.2" totalDistanceUnit="km" totalEnergyBurned="412" \
    totalEnergyBurnedUnit="Cal" startDate="2026-06-01 07:00:00 -0400" \
    endDate="2026-06-01 07:30:00 -0400">
     </Workout>
    </HealthData>
    """

    func writeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).xml")
        try Self.fixtureXML.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func parsesFixtureIntoEvents() async throws {
        let db = try AppDatabase.inMemory()
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try AppleHealthExportParser(database: db).parse(xmlAt: url, progress: nil)

        // bodyMass + sleep + headache + workout + 1 daily steps event = 5
        #expect(result.summary.inserted == 5)
        #expect(result.recordsSkipped == 1) // VO2Max unmapped
        let store = GRDBEventStore(database: db)
        let byCategory = try await store.countsByCategory()
        #expect(byCategory["bodyMetric"] == 1)
        #expect(byCategory["sleep"] == 1)
        #expect(byCategory["symptom"] == 1)
        #expect(byCategory["exercise"] == 2) // workout + daily steps

        let all = try await store.recentEvents(limit: 10)
        let steps = all.first { $0.subtype == "steps" }
        #expect(steps?.value == 8200) // summed across the day
        #expect(steps?.endTimestamp != nil)
        let weight = all.first { $0.subtype == "weight" }
        #expect(abs((weight?.value ?? 0) - 81.6466) < 0.001)
        #expect(all.allSatisfy { $0.source == .healthExportFile })
        #expect(all.allSatisfy { $0.dedupKey != nil })
    }

    @Test func reparsingIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let parser = AppleHealthExportParser(database: db)
        _ = try parser.parse(xmlAt: url, progress: nil)
        let second = try parser.parse(xmlAt: url, progress: nil)
        #expect(second.summary.inserted == 0)
        #expect(try await GRDBEventStore(database: db).count() == 5)
    }

    @Test func extractsExportXMLFromZip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("apple_health_export"), withIntermediateDirectories: true)
        let xmlURL = dir.appendingPathComponent("apple_health_export/export.xml")
        try Self.fixtureXML.write(to: xmlURL, atomically: true, encoding: .utf8)
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        try FileManager.default.zipItem(
            at: dir.appendingPathComponent("apple_health_export"), to: zipURL)
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: zipURL)
        }
        let extracted = try ExportArchive.extractExportXML(from: zipURL)
        let content = try String(contentsOf: extracted, encoding: .utf8)
        #expect(content.contains("HKQuantityTypeIdentifierBodyMass"))
    }

    @Test func zipWithoutExportXMLThrows() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        try FileManager.default.zipItem(at: file, to: zipURL)
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: zipURL)
        }
        #expect(throws: ExportArchiveError.self) {
            _ = try ExportArchive.extractExportXML(from: zipURL)
        }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'AppleHealthExportParser' in scope`.

- [ ] **Step 4: Implement**

`HealthGraphCore/Sources/HealthGraphCore/Ingestion/ExportArchive.swift`:

```swift
import Foundation
import ZIPFoundation

public enum ExportArchiveError: Error, Equatable {
    case exportXMLNotFound
}

public enum ExportArchive {
    /// Extracts `export.xml` from an Apple Health `export.zip` into a unique
    /// temp directory and returns its URL. The caller owns cleanup of the
    /// returned file's parent directory.
    public static func extractExportXML(from zipURL: URL) throws -> URL {
        let archive = try Archive(url: zipURL, accessMode: .read)
        guard let entry = archive.first(where: { $0.path.hasSuffix("export.xml") }) else {
            throw ExportArchiveError.exportXMLNotFound
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent("export.xml")
        _ = try archive.extract(entry, to: destination)
        return destination
    }
}
```

`HealthGraphCore/Sources/HealthGraphCore/Ingestion/AppleHealthExportParser.swift`:

```swift
import Foundation
import GRDB

public struct ExportParseResult: Sendable {
    public let summary: IngestSummary
    public let recordsRead: Int
    public let recordsSkipped: Int
}

/// Streaming parser for Apple Health `export.xml` (spec §5.2). Synchronous by
/// design: XMLParser drives a sync delegate, and each 500-event batch flushes
/// through `IngestPipeline.process` inside a blocking `dbWriter.write` — flat
/// memory for multi-hundred-MB exports. Callers wrap in `Task.detached`.
public final class AppleHealthExportParser: NSObject, XMLParserDelegate {
    private let dbWriter: any DatabaseWriter
    private var buffer: [HealthEvent] = []
    private var summary = IngestSummary()
    private var recordsRead = 0
    private var recordsSkipped = 0
    private var progress: (@Sendable (Int) -> Void)?
    private var parseError: Error?

    // per-day accumulators for daily-stat identifiers:
    // key = "identifier|dayEpochMinute", value = (dayStart, sum, count)
    private var dailyAccumulator: [String: (dayStart: Date, sum: Double, count: Int)] = [:]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()

    public init(database: AppDatabase) {
        self.dbWriter = database.dbWriter
    }

    public func parse(xmlAt url: URL, progress: (@Sendable (Int) -> Void)?) throws -> ExportParseResult {
        // Reset per-call state: the same parser instance may parse repeatedly
        // (idempotent re-imports must not report cumulative counters).
        summary = IngestSummary()
        recordsRead = 0
        recordsSkipped = 0
        buffer = []
        dailyAccumulator = [:]
        parseError = nil
        self.progress = progress
        guard let stream = InputStream(url: url) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let parser = XMLParser(stream: stream)
        parser.delegate = self
        parser.parse()
        if let parseError { throw parseError }
        if let xmlError = parser.parserError { throw xmlError }
        flushDailyAccumulators()
        try flushBuffer()
        return ExportParseResult(summary: summary, recordsRead: recordsRead,
                                 recordsSkipped: recordsSkipped)
    }

    public func parser(_ parser: XMLParser, didStartElement name: String,
                       namespaceURI: String?, qualifiedName: String?,
                       attributes attrs: [String: String]) {
        do {
            switch name {
            case "Record": try handleRecord(attrs)
            case "Workout": try handleWorkout(attrs)
            default: return
            }
        } catch {
            parseError = error
            parser.abortParsing()
        }
    }

    private func handleRecord(_ attrs: [String: String]) throws {
        guard let type = attrs["type"],
              let start = attrs["startDate"].flatMap(Self.dateFormatter.date(from:)),
              let end = attrs["endDate"].flatMap(Self.dateFormatter.date(from:)) else { return }
        recordsRead += 1

        if HealthKitSampleMapper.dailyStatIdentifiers.contains(type) {
            guard let value = attrs["value"].flatMap(Double.init) else { recordsSkipped += 1; return }
            let dayStart = Calendar.current.startOfDay(for: start)
            let key = "\(type)|\(Int(dayStart.timeIntervalSince1970 / 60))"
            var acc = dailyAccumulator[key] ?? (dayStart, 0, 0)
            acc.sum += value
            acc.count += 1
            dailyAccumulator[key] = acc
            return
        }
        if HealthKitSampleMapper.perSampleQuantityIdentifiers.contains(type) {
            guard let value = attrs["value"].flatMap(Double.init), let unit = attrs["unit"] else {
                recordsSkipped += 1; return
            }
            append(HealthKitSampleMapper.map(
                QuantitySampleData(identifier: type, start: start, end: end,
                                   value: value, unit: unit, timezoneID: nil),
                source: .healthExportFile))
            return
        }
        if HealthKitSampleMapper.categoryIdentifiers.contains(type) {
            guard let raw = attrs["value"],
                  let intValue = HealthKitSampleMapper.categoryValue(fromExportString: raw) else {
                recordsSkipped += 1; return
            }
            append(HealthKitSampleMapper.map(
                CategorySampleData(identifier: type, start: start, end: end,
                                   value: intValue, timezoneID: nil),
                source: .healthExportFile))
            return
        }
        recordsSkipped += 1
    }

    private func handleWorkout(_ attrs: [String: String]) throws {
        guard let rawType = attrs["workoutActivityType"],
              let start = attrs["startDate"].flatMap(Self.dateFormatter.date(from:)),
              let end = attrs["endDate"].flatMap(Self.dateFormatter.date(from:)) else { return }
        recordsRead += 1
        var name = rawType.replacingOccurrences(of: "HKWorkoutActivityType", with: "")
        name = name.prefix(1).lowercased() + name.dropFirst()
        append(HealthKitSampleMapper.map(
            WorkoutData(activityName: name, start: start, end: end,
                        kcal: attrs["totalEnergyBurned"].flatMap(Double.init),
                        distanceKm: attrs["totalDistance"].flatMap(Double.init),
                        timezoneID: nil),
            source: .healthExportFile))
    }

    private func append(_ event: HealthEvent?) {
        guard let event else { recordsSkipped += 1; return }
        buffer.append(event)
        if buffer.count >= IngestPipeline.batchSize {
            do { try flushBuffer() } catch { parseError = error }
        }
    }

    private func flushDailyAccumulators() {
        for (key, acc) in dailyAccumulator.sorted(by: { $0.key < $1.key }) {
            let identifier = String(key.split(separator: "|")[0])
            let value: Double
            switch HealthKitSampleMapper.dailyStatOptions(for: identifier) {
            case .sum: value = acc.sum
            case .average: value = acc.count > 0 ? acc.sum / Double(acc.count) : 0
            }
            if let event = HealthKitSampleMapper.map(
                DailyStatData(identifier: identifier, dayStart: acc.dayStart,
                              value: value, timezoneID: nil),
                source: .healthExportFile) {
                buffer.append(event)
            }
        }
        dailyAccumulator = [:]
    }

    private func flushBuffer() throws {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer = []
        let batchSummary = try dbWriter.write { db in
            try IngestPipeline.process(batch, db: db)
        }
        summary = summary + batchSummary
        progress?(recordsRead)
    }
}
```

Implementation note: `try Archive(url:accessMode:)` is the correct throwing initializer in the resolving ZIPFoundation version (0.9.20) — compile-verified; the deprecated failable variant coexists without ambiguity.

- [ ] **Step 5: Run the full package suite**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 62 tests in 10 suites passed` (58 + 4 new).

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore
git commit -m "feat(core): streaming Apple Health export parser with zip extraction"
```

---

### Task 8: HealthKitIngestor — authorization + one-year backfill

**Files:**
- Create: `Models/HealthKitIngestor.swift` (app target — synchronized group picks it up)

**Interfaces:**
- Consumes: `HealthKitSampleMapper` DTOs + identifier sets (Task 6), `IngestPipeline` (Task 5), `HealthGraphProvider.shared`.
- Produces (consumed by Tasks 9 and 11):
  - `@MainActor final class HealthKitIngestor: ObservableObject`
  - `struct BackfillProgress { var completedSteps: Int; var totalSteps: Int; var currentStep: String; var eventsIngested: Int }`
  - `@Published var progress: BackfillProgress?`, `@Published var isRunning: Bool`
  - `func requestAuthorization() async throws`
  - `func backfill(years: Int = 1) async throws -> IngestSummary` — persists per-type `HKQueryAnchor`s (UserDefaults `hg.hk.anchor.<identifier>`) so Task 9's live ingestion resumes where backfill ended; sets `hg.hk.backfillCompleted = true` on success.
  - `static func anchorKey(_ identifier: String) -> String`

No unit tests in this task: HKHealthStore cannot be exercised in a simulator-hosted unit test without seeded data, and all mapping/dedup logic it feeds is already package-tested (Tasks 5–6). Verification is compile + the Task 11 on-device checkpoint. Keep every method thin — anything with logic beyond HK plumbing belongs in the package.

- [ ] **Step 1: Implement**

`Models/HealthKitIngestor.swift`:

```swift
import Foundation
import HealthKit
import HealthGraphCore

struct BackfillProgress {
    var completedSteps: Int
    var totalSteps: Int
    var currentStep: String
    var eventsIngested: Int
}

/// HealthKit → event graph ingestion (spec §5.1). Thin HK plumbing only:
/// all mapping and dedup logic lives in HealthGraphCore (package-tested).
@MainActor
final class HealthKitIngestor: ObservableObject {
    @Published var isRunning = false
    @Published var progress: BackfillProgress?

    private let healthStore = HKHealthStore()
    private let database: AppDatabase
    private let pipeline: IngestPipeline

    static let backfillCompletedKey = "hg.hk.backfillCompleted"

    init(database: AppDatabase = HealthGraphProvider.shared) {
        self.database = database
        self.pipeline = IngestPipeline(database: database)
    }

    static func anchorKey(_ identifier: String) -> String { "hg.hk.anchor.\(identifier)" }

    // MARK: - Types

    static var perSampleTypes: [HKSampleType] {
        var types: [HKSampleType] = []
        for id in HealthKitSampleMapper.perSampleQuantityIdentifiers {
            if let t = HKObjectType.quantityType(forIdentifier: .init(rawValue: id)) { types.append(t) }
        }
        for id in HealthKitSampleMapper.categoryIdentifiers {
            if let t = HKObjectType.categoryType(forIdentifier: .init(rawValue: id)) { types.append(t) }
        }
        types.append(HKObjectType.workoutType())
        return types
    }

    static var dailyStatTypes: [HKQuantityType] {
        HealthKitSampleMapper.dailyStatIdentifiers.compactMap {
            HKObjectType.quantityType(forIdentifier: .init(rawValue: $0))
        }
    }

    static var readTypes: Set<HKObjectType> {
        Set(perSampleTypes as [HKObjectType]).union(Set(dailyStatTypes as [HKObjectType]))
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: - Backfill

    func backfill(years: Int = 1) async throws -> IngestSummary {
        isRunning = true
        defer { isRunning = false; progress = nil }
        let start = Calendar.current.date(byAdding: .year, value: -years, to: Date())!
        let window = HKQuery.predicateForSamples(withStart: start, end: Date())
        var total = IngestSummary()
        let steps = Self.perSampleTypes.count + Self.dailyStatTypes.count
        var done = 0

        for type in Self.perSampleTypes {
            progress = BackfillProgress(completedSteps: done, totalSteps: steps,
                                        currentStep: type.identifier,
                                        eventsIngested: total.inserted + total.updated)
            total = total + (try await backfillSampleType(type, predicate: window))
            done += 1
        }
        for type in Self.dailyStatTypes {
            progress = BackfillProgress(completedSteps: done, totalSteps: steps,
                                        currentStep: type.identifier,
                                        eventsIngested: total.inserted + total.updated)
            total = total + (try await ingestDailyStats(for: type, from: start, to: Date()))
            done += 1
        }
        UserDefaults.standard.set(true, forKey: Self.backfillCompletedKey)
        return total
    }

    /// Anchored pagination so live ingestion (started later) resumes from the
    /// exact point backfill reached. Batches of 1000.
    private func backfillSampleType(_ type: HKSampleType,
                                    predicate: NSPredicate) async throws -> IngestSummary {
        var summary = IngestSummary()
        var anchor: HKQueryAnchor? = nil
        while true {
            let (samples, newAnchor) = try await fetchAnchored(
                type: type, predicate: predicate, anchor: anchor, limit: 1000)
            anchor = newAnchor
            if !samples.isEmpty {
                summary = summary + (try await pipeline.ingest(samples.compactMap(Self.mapSample)))
            }
            if samples.count < 1000 { break }
        }
        persistAnchor(anchor, for: type.identifier)
        return summary
    }

    func fetchAnchored(type: HKSampleType, predicate: NSPredicate?,
                       anchor: HKQueryAnchor?, limit: Int) async throws -> ([HKSample], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type, predicate: predicate, anchor: anchor, limit: limit
            ) { _, samples, _, newAnchor, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples ?? [], newAnchor)) }
            }
            healthStore.execute(query)
        }
    }

    func persistAnchor(_ anchor: HKQueryAnchor?, for identifier: String) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(
                withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: Self.anchorKey(identifier))
    }

    func loadAnchor(for identifier: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: Self.anchorKey(identifier)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    // MARK: - Daily statistics

    func ingestDailyStats(for type: HKQuantityType, from start: Date,
                          to end: Date) async throws -> IngestSummary {
        let identifier = type.identifier
        let aggregation = HealthKitSampleMapper.dailyStatOptions(for: identifier)
        let options: HKStatisticsOptions = aggregation == .sum ? .cumulativeSum : .discreteAverage
        let dayStart = Calendar.current.startOfDay(for: start)

        let collection: HKStatisticsCollection = try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: options,
                anchorDate: dayStart,
                intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, result, error in
                if let error { cont.resume(throwing: error) }
                else if let result { cont.resume(returning: result) }
                else { cont.resume(throwing: CocoaError(.featureUnsupported)) }
            }
            healthStore.execute(query)
        }

        var events: [HealthEvent] = []
        collection.enumerateStatistics(from: dayStart, to: end) { stats, _ in
            let quantity = aggregation == .sum ? stats.sumQuantity() : stats.averageQuantity()
            guard let quantity else { return }
            let value = quantity.doubleValue(for: Self.hkUnit(for: identifier))
            if let event = HealthKitSampleMapper.map(
                DailyStatData(identifier: identifier, dayStart: stats.startDate,
                              value: value, timezoneID: nil),
                source: .healthKit) {
                events.append(event)
            }
        }
        return try await pipeline.ingest(events)
    }

    // MARK: - HK → DTO conversion

    static func hkUnit(for identifier: String) -> HKUnit {
        switch identifier {
        case "HKQuantityTypeIdentifierStepCount": return .count()
        case "HKQuantityTypeIdentifierHeartRate",
             "HKQuantityTypeIdentifierRestingHeartRate",
             "HKQuantityTypeIdentifierRespiratoryRate":
            return HKUnit.count().unitDivided(by: .minute())
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            return .secondUnit(with: .milli)
        case "HKQuantityTypeIdentifierBodyMass": return .gramUnit(with: .kilo)
        case "HKQuantityTypeIdentifierBloodPressureSystolic",
             "HKQuantityTypeIdentifierBloodPressureDiastolic":
            return .millimeterOfMercury()
        case "HKQuantityTypeIdentifierDietaryEnergyConsumed": return .kilocalorie()
        case "HKQuantityTypeIdentifierDietaryProtein",
             "HKQuantityTypeIdentifierDietaryCarbohydrates",
             "HKQuantityTypeIdentifierDietaryFatTotal",
             "HKQuantityTypeIdentifierDietarySugar": return .gram()
        case "HKQuantityTypeIdentifierDietarySodium": return .gramUnit(with: .milli)
        default: return .count()
        }
    }

    static func unitString(for identifier: String) -> String {
        switch identifier {
        case "HKQuantityTypeIdentifierStepCount": return "count"
        case "HKQuantityTypeIdentifierHeartRate",
             "HKQuantityTypeIdentifierRestingHeartRate": return "bpm"
        case "HKQuantityTypeIdentifierRespiratoryRate": return "breaths/min"
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": return "ms"
        case "HKQuantityTypeIdentifierBodyMass": return "kg"
        case "HKQuantityTypeIdentifierBloodPressureSystolic",
             "HKQuantityTypeIdentifierBloodPressureDiastolic": return "mmHg"
        case "HKQuantityTypeIdentifierDietaryEnergyConsumed": return "kcal"
        case "HKQuantityTypeIdentifierDietaryProtein",
             "HKQuantityTypeIdentifierDietaryCarbohydrates",
             "HKQuantityTypeIdentifierDietaryFatTotal",
             "HKQuantityTypeIdentifierDietarySugar": return "g"
        case "HKQuantityTypeIdentifierDietarySodium": return "mg"
        default: return "count"
        }
    }

    static func mapSample(_ sample: HKSample) -> HealthEvent? {
        let timezoneID = sample.metadata?[HKMetadataKeyTimeZone] as? String
        if let workout = sample as? HKWorkout {
            var name = workout.workoutActivityType.hgActivityName
            name = name.prefix(1).lowercased() + name.dropFirst()
            let kcal = workout.statistics(
                for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?
                .doubleValue(for: .kilocalorie())
            let distance = workout.statistics(
                for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?
                .doubleValue(for: .meterUnit(with: .kilo))
            return HealthKitSampleMapper.map(
                WorkoutData(activityName: name, start: workout.startDate, end: workout.endDate,
                            kcal: kcal, distanceKm: distance, timezoneID: timezoneID),
                source: .healthKit)
        }
        if let quantity = sample as? HKQuantitySample {
            let id = quantity.quantityType.identifier
            return HealthKitSampleMapper.map(
                QuantitySampleData(identifier: id, start: quantity.startDate, end: quantity.endDate,
                                   value: quantity.quantity.doubleValue(for: hkUnit(for: id)),
                                   unit: unitString(for: id), timezoneID: timezoneID),
                source: .healthKit)
        }
        if let category = sample as? HKCategorySample {
            return HealthKitSampleMapper.map(
                CategorySampleData(identifier: category.categoryType.identifier,
                                   start: category.startDate, end: category.endDate,
                                   value: category.value, timezoneID: timezoneID),
                source: .healthKit)
        }
        return nil
    }
}

extension HKWorkoutActivityType {
    /// Common activity names; everything else falls back to "other".
    var hgActivityName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "StrengthTraining"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hiking: return "Hiking"
        case .pilates: return "Pilates"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "StairClimbing"
        case .dance: return "Dance"
        case .tennis: return "Tennis"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .golf: return "Golf"
        case .paddleSports: return "PaddleSports"
        case .martialArts: return "MartialArts"
        case .coreTraining: return "CoreTraining"
        default: return "Other"
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/leo/Desktop/FoodIntolerances
xcodebuild -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' \
  build-for-testing 2>&1 | tail -3
```

Expected: `** TEST BUILD SUCCEEDED **`. Also `cd HealthGraphCore && swift test 2>&1 | tail -1` still passes (no package changes; sanity only).

- [ ] **Step 3: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add Models/HealthKitIngestor.swift
git commit -m "feat(app): HealthKit ingestor with authorization and anchored one-year backfill"
```

---

### Task 9: Live HealthKit ingestion — observers + background delivery

**Files:**
- Modify: `Models/HealthKitIngestor.swift`
- Modify: `FoodIntolerancesApp.swift`

**Interfaces:**
- Consumes: Task 8's ingestor (anchors, `fetchAnchored`, `mapSample`, `ingestDailyStats`).
- Produces: `HealthKitIngestor.startObserving()` — registers observer queries + background delivery for every read type; called at app launch when `hg.hk.backfillCompleted` is set. Task 11's checkpoint verifies registration doesn't crash; true background delivery is only fully verifiable on a physical device over time (noted in the checkpoint).

- [ ] **Step 1: Add observation to the ingestor**

Append inside `HealthKitIngestor` (before the `// MARK: - HK → DTO conversion` section):

```swift
    // MARK: - Live ingestion

    private var observerQueries: [HKObserverQuery] = []

    /// Registers observer queries + background delivery for all read types.
    /// Idempotent per process (re-calling replaces the query list).
    func startObserving() {
        guard HKHealthStore.isHealthDataAvailable(),
              UserDefaults.standard.bool(forKey: Self.backfillCompletedKey) else { return }
        for query in observerQueries { healthStore.stop(query) }
        observerQueries = []

        for type in Self.perSampleTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) {
                [weak self] _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor [weak self] in
                    await self?.ingestNewSamples(for: type)
                    completion()
                }
            }
            healthStore.execute(query)
            observerQueries.append(query)
            healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
        for type in Self.dailyStatTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) {
                [weak self] _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor [weak self] in
                    await self?.recomputeRecentDailyStats(for: type)
                    completion()
                }
            }
            healthStore.execute(query)
            observerQueries.append(query)
            healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    /// Incremental anchored fetch from the persisted anchor.
    private func ingestNewSamples(for type: HKSampleType) async {
        do {
            let (samples, newAnchor) = try await fetchAnchored(
                type: type, predicate: nil,
                anchor: loadAnchor(for: type.identifier), limit: HKObjectQueryNoLimit)
            if !samples.isEmpty {
                _ = try await pipeline.ingest(samples.compactMap(Self.mapSample))
            }
            persistAnchor(newAnchor, for: type.identifier)
        } catch {
            // Observer fires again on the next change; never log health data.
            Logger.error("HK live ingest failed for a sample type", category: .data)
        }
    }

    /// Daily-stat types have no anchors: recompute the trailing 2 days —
    /// dedupKeys make the re-ingest an idempotent same-day update.
    private func recomputeRecentDailyStats(for type: HKQuantityType) async {
        let start = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        do {
            _ = try await ingestDailyStats(for: type, from: start, to: Date())
        } catch {
            Logger.error("HK daily-stat recompute failed", category: .data)
        }
    }
```

(`Logger.error(_:category:)` and the `.data` category exist in the project's `Logger` — verified against the source.)

- [ ] **Step 1b: Add the background-delivery entitlement**

`enableBackgroundDelivery` requires the `com.apple.developer.healthkit.background-delivery` entitlement; without it every registration fails silently (verified: the current entitlements file has only `com.apple.developer.healthkit`). In `Food Intolerances/Food_Intolerances.entitlements` (a plain XML plist), add inside the top-level `<dict>`:

```xml
	<key>com.apple.developer.healthkit.background-delivery</key>
	<true/>
```

- [ ] **Step 2: Start observation at launch**

In `FoodIntolerancesApp.swift`: add a `@StateObject private var healthKitIngestor = HealthKitIngestor()` alongside the existing `@StateObject` properties, inject it with `.environmentObject(healthKitIngestor)` where the other environment objects are injected, and add to the injected view's modifiers:

```swift
                .task { healthKitIngestor.startObserving() }
```

(`startObserving()` self-gates on the backfill-completed flag, so this is a no-op until the user has run a backfill from the debug panel — or, in Plan 1D, onboarding.)

- [ ] **Step 3: Verify it builds**

Same build-for-testing command as Task 8 Step 2. Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add Models/HealthKitIngestor.swift FoodIntolerancesApp.swift "Food Intolerances/Food_Intolerances.entitlements"
git commit -m "feat(app): live HealthKit ingestion via observer queries and background delivery"
```

---

### Task 10: Environmental exposure events

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift`
- Create: `Models/EnvironmentalEventEmitter.swift` (app target)
- Modify: `FoodIntolerancesApp.swift`

**Interfaces:**
- Consumes: `IngestPipeline`, `DedupKey` (package); existing app services `EnvironmentalDataService` (`currentPressure`, `previousPressure`, `requestRefreshWithCooldown()`), free functions `getMoonPhase(for:)`, `getCurrentSeason(for:)`, `MercuryRetrograde.isRetrograde(on:)`.
- Produces:
  - Package: `struct EnvironmentalReading` + `enum EnvironmentalEventFactory { static let pressureDropThresholdHPa = 6.0; static func events(for reading: EnvironmentalReading) -> [HealthEvent] }`
  - App: `enum EnvironmentalEventEmitter` with `static func emitIfNeeded(database: AppDatabase, service: EnvironmentalDataService) async` (once-per-calendar-day guard; hooked to app foreground) and `static func backfillDerived(days: Int = 365, database: AppDatabase) async throws -> IngestSummary` (historical moon/season/retrograde — pure functions of the date, so a year of exposure history is free; spec §5's whole point is killing the cold start. No historical pressure — the weather API has no history. Consumed by Task 11's debug button.)

Event synthesis rules (spec §6.6 — these are ordinary exposures; honest null results are a feature):
- Daily pressure reading: category `environment`, subtype `pressure`, value = hPa, unit `hPa`, dedupKey `DedupKey.daily(.environment, "pressure", dayStart)`.
- Pressure drop: subtype `pressureDrop`, value = drop magnitude in hPa, emitted only when `previous - current >= 6.0` (the existing `EnvironmentalThresholds` convention), dedupKey daily.
- Moon phase: subtype `moonPhase`, value nil, metadata `{"phase": "<cleaned name>"}` (input name stripped of non-letter/non-space characters and whitespace-trimmed — the legacy `getMoonPhase` returns emoji-suffixed strings), dedupKey daily.
- Mercury retrograde: subtype `mercuryRetrograde`, value nil, emitted ONLY on retrograde days (absence of the event = not retrograde; the engine's base-rate math needs exactly this), dedupKey daily.
- Season: subtype `season`, value nil, metadata `{"season": "<name>"}` — emitted DAILY, not just on transitions (spec §6.6 lists season as an ordinary continuous exposure alongside pressure and moon phase; the engine needs daily presence to correlate against season generally).
- All events: `source: .weatherAPI`, point events at `reading.date`, `timezoneID = reading.timezoneID`. Nil pressure (no API key / no network / historical backfill) → no pressure or pressureDrop events; the rest still emit. Nil moon/season strings → those events skipped.

- [ ] **Step 1: Write the failing tests**

`HealthGraphCore/Tests/HealthGraphCoreTests/EnvironmentalEventFactoryTests.swift`:

```swift
import Testing
import Foundation
@testable import HealthGraphCore

struct EnvironmentalEventFactoryTests {
    let noon = Date(timeIntervalSince1970: 1_750_075_200)

    func reading(date: Date? = nil, pressure: Double? = 1013, previous: Double? = 1015,
                 moon: String? = "Full Moon 🌕", season: String? = "Summer",
                 retrograde: Bool = false) -> EnvironmentalReading {
        EnvironmentalReading(
            date: date ?? noon, pressureHPa: pressure, previousPressureHPa: previous,
            moonPhaseName: moon, season: season,
            isMercuryRetrograde: retrograde, timezoneID: "UTC")
    }

    @Test func emitsPressureMoonAndSeasonOnAQuietDay() throws {
        let events = EnvironmentalEventFactory.events(for: reading())
        #expect(events.count == 3) // pressure + moonPhase + season; no drop, no retrograde
        #expect(events.allSatisfy { $0.category == .environment })
        #expect(events.allSatisfy { $0.source == .weatherAPI })
        #expect(events.allSatisfy { $0.dedupKey != nil })
        let pressure = events.first { $0.subtype == "pressure" }
        #expect(pressure?.value == 1013)
        #expect(pressure?.unit == "hPa")
        let moon = try #require(events.first { $0.subtype == "moonPhase" })
        let moonMeta = try JSONDecoder().decode([String: String].self, from: moon.metadata ?? Data())
        #expect(moonMeta["phase"] == "Full Moon") // emoji stripped
        let season = try #require(events.first { $0.subtype == "season" })
        let seasonMeta = try JSONDecoder().decode([String: String].self, from: season.metadata ?? Data())
        #expect(seasonMeta["season"] == "Summer") // daily exposure, not a transition marker
    }

    @Test func emitsPressureDropAtThreshold() {
        let events = EnvironmentalEventFactory.events(for: reading(pressure: 1004, previous: 1010))
        let drop = events.first { $0.subtype == "pressureDrop" }
        #expect(drop?.value == 6)
        let noDrop = EnvironmentalEventFactory.events(for: reading(pressure: 1005, previous: 1010))
        #expect(!noDrop.contains { $0.subtype == "pressureDrop" })
    }

    @Test func emitsRetrogradeOnlyWhenTrue() {
        #expect(EnvironmentalEventFactory.events(for: reading(retrograde: true))
            .contains { $0.subtype == "mercuryRetrograde" })
        #expect(!EnvironmentalEventFactory.events(for: reading(retrograde: false))
            .contains { $0.subtype == "mercuryRetrograde" })
    }

    @Test func nilPressureSkipsPressureEventsOnly() {
        // historical backfill shape: no pressure available, derived signals still emit
        let events = EnvironmentalEventFactory.events(for: reading(pressure: nil, previous: nil))
        #expect(!events.contains { $0.subtype == "pressure" })
        #expect(!events.contains { $0.subtype == "pressureDrop" })
        #expect(events.contains { $0.subtype == "moonPhase" })
        #expect(events.contains { $0.subtype == "season" })
    }

    @Test func distinctDaysProduceDistinctDailyKeys() {
        let dayOne = EnvironmentalEventFactory.events(for: reading())
        let dayTwo = EnvironmentalEventFactory.events(
            for: reading(date: noon.addingTimeInterval(86_400)))
        let keysOne = Set(dayOne.compactMap(\.dedupKey))
        let keysTwo = Set(dayTwo.compactMap(\.dedupKey))
        #expect(keysOne.isDisjoint(with: keysTwo)) // backfill loop never collides across days
    }

    @Test func dailyKeysMakeReemissionIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest(EnvironmentalEventFactory.events(for: reading()))
        _ = try await pipeline.ingest(EnvironmentalEventFactory.events(for: reading(pressure: 1012)))
        let store = GRDBEventStore(database: db)
        #expect(try await store.count() == 3) // same day: updated, not duplicated
        let pressure = try await store.recentEvents(limit: 10).first { $0.subtype == "pressure" }
        #expect(pressure?.value == 1012) // latest reading wins (equal rank -> update)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'EnvironmentalReading' in scope`.

- [ ] **Step 3: Implement the factory**

`HealthGraphCore/Sources/HealthGraphCore/Ingestion/EnvironmentalEventFactory.swift`:

```swift
import Foundation

/// One day's environmental readings, gathered by the app layer.
public struct EnvironmentalReading: Sendable {
    public let date: Date
    public let pressureHPa: Double?
    public let previousPressureHPa: Double?
    public let moonPhaseName: String?
    public let season: String?
    public let isMercuryRetrograde: Bool
    public let timezoneID: String

    public init(date: Date, pressureHPa: Double?, previousPressureHPa: Double?,
                moonPhaseName: String?, season: String?,
                isMercuryRetrograde: Bool, timezoneID: String) {
        self.date = date
        self.pressureHPa = pressureHPa
        self.previousPressureHPa = previousPressureHPa
        self.moonPhaseName = moonPhaseName
        self.season = season
        self.isMercuryRetrograde = isMercuryRetrograde
        self.timezoneID = timezoneID
    }
}

/// Synthesizes environment exposure events (spec §6.6). Ordinary exposures to
/// the engine — if the data shows no association, the app will say so.
public enum EnvironmentalEventFactory {
    public static let pressureDropThresholdHPa = 6.0

    public static func events(for r: EnvironmentalReading) -> [HealthEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: r.timezoneID) ?? .current
        let dayStart = cal.startOfDay(for: r.date)
        var events: [HealthEvent] = []

        func event(_ subtype: String, value: Double? = nil, unit: String? = nil,
                   metadata: [String: String]? = nil) -> HealthEvent {
            HealthEvent(
                timestamp: r.date, timezoneID: r.timezoneID,
                category: .environment, subtype: subtype,
                value: value, unit: unit, source: .weatherAPI,
                metadata: metadata.flatMap { try? JSONEncoder().encode($0) },
                dedupKey: DedupKey.daily(.environment, subtype, dayStart: dayStart)
            )
        }

        if let pressure = r.pressureHPa {
            events.append(event("pressure", value: pressure, unit: "hPa"))
            if let previous = r.previousPressureHPa,
               previous - pressure >= pressureDropThresholdHPa {
                events.append(event("pressureDrop", value: previous - pressure, unit: "hPa"))
            }
        }
        if let moon = r.moonPhaseName {
            let cleaned = moon.filter { $0.isLetter || $0.isWhitespace }
                .trimmingCharacters(in: .whitespaces)
            events.append(event("moonPhase", metadata: ["phase": cleaned]))
        }
        if r.isMercuryRetrograde {
            events.append(event("mercuryRetrograde"))
        }
        if let season = r.season {
            // Daily exposure — the engine correlates against season presence,
            // not just the four transition days a year.
            events.append(event("season", metadata: ["season": season]))
        }
        return events
    }
}
```

- [ ] **Step 4: Run the package suite**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 70 tests in 11 suites passed` (64 + 6 new; the Task 7 fix loop added two error-path parser tests).

- [ ] **Step 5: Implement the app emitter**

`Models/EnvironmentalEventEmitter.swift`:

```swift
import Foundation
import HealthGraphCore

/// Emits daily environment exposure events on app foreground (spec §6.6).
/// Once per calendar day; dedupKeys make accidental re-runs idempotent
/// (same-day re-emission updates the pressure value in place).
enum EnvironmentalEventEmitter {
    static let lastEmitDayKey = "hg.env.lastEmitDay"

    static func emitIfNeeded(database: AppDatabase = HealthGraphProvider.shared,
                             service: EnvironmentalDataService) async {
        let today = ISO8601DateFormatter.hgDayString(from: Date())
        guard UserDefaults.standard.string(forKey: lastEmitDayKey) != today else { return }

        _ = await service.requestRefreshWithCooldown()
        let now = Date()
        let reading = EnvironmentalReading(
            date: now,
            pressureHPa: service.currentPressure > 0 ? service.currentPressure : nil,
            previousPressureHPa: service.previousPressure > 0 ? service.previousPressure : nil,
            moonPhaseName: getMoonPhase(for: now),
            season: getCurrentSeason(for: now),
            isMercuryRetrograde: MercuryRetrograde.isRetrograde(on: now),
            timezoneID: TimeZone.current.identifier
        )
        do {
            _ = try await IngestPipeline(database: database)
                .ingest(EnvironmentalEventFactory.events(for: reading))
            UserDefaults.standard.set(today, forKey: lastEmitDayKey)
        } catch {
            Logger.info("Environmental emit failed; will retry on next foreground", category: .data)
        }
    }

    /// Historical backfill of the date-derived signals (moon phase, season,
    /// Mercury retrograde) — pure functions of the date, so a year of exposure
    /// history is free (spec §5 cold-start rationale). No historical pressure:
    /// the weather API has no history. Idempotent via daily dedupKeys.
    /// NOTE: MercuryRetrograde.periods covers 2025–2026 only; days before its
    /// table simply emit no retrograde events (correct absence semantics).
    static func backfillDerived(days: Int = 365,
                                database: AppDatabase = HealthGraphProvider.shared) async throws -> IngestSummary {
        let pipeline = IngestPipeline(database: database)
        let tz = TimeZone.current.identifier
        var events: [HealthEvent] = []
        let noonToday = Calendar.current.date(
            bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        for dayOffset in 1...days {
            let date = noonToday.addingTimeInterval(-Double(dayOffset) * 86_400)
            let reading = EnvironmentalReading(
                date: date, pressureHPa: nil, previousPressureHPa: nil,
                moonPhaseName: getMoonPhase(for: date),
                season: getCurrentSeason(for: date),
                isMercuryRetrograde: MercuryRetrograde.isRetrograde(on: date),
                timezoneID: tz
            )
            events.append(contentsOf: EnvironmentalEventFactory.events(for: reading))
        }
        return try await pipeline.ingest(events)
    }
}

extension ISO8601DateFormatter {
    static func hgDayString(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: date)
    }
}
```

In `FoodIntolerancesApp.swift`, on the same view that got the `.task` in Task 9, add (using the app's existing `environmentalService` `@StateObject`):

```swift
                .task { await EnvironmentalEventEmitter.emitIfNeeded(service: environmentalService) }
```

- [ ] **Step 6: Verify app build + package suite**

Build-for-testing on the iPhone 17 destination → `** TEST BUILD SUCCEEDED **`; `swift test` → 66 passing.

- [ ] **Step 7: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add HealthGraphCore Models/EnvironmentalEventEmitter.swift FoodIntolerancesApp.swift
git commit -m "feat: daily environmental exposure events (pressure, moon, retrograde, season)"
```

---

### Task 11: Debug ingestion panel + final verification — ⚠️ HUMAN CHECKPOINT

**Files:**
- Modify: `Views/HealthGraphDebugView.swift`

**Interfaces:**
- Consumes: everything above — `HealthKitIngestor`, `ExportArchive`, `AppleHealthExportParser`, `EnvironmentalEventEmitter`, `countsByCategory()`/`countsBySource()`.
- Produces: the Phase 1A verification surface (replaced by real onboarding in Plan 1D).

- [ ] **Step 1: Add the Ingestion section to the debug view**

In `Views/HealthGraphDebugView.swift`:

1. Add state and the ingestor near the other `@State` properties:

```swift
    @StateObject private var ingestor = HealthKitIngestor()
    @State private var countsByCategory: [String: Int] = [:]
    @State private var countsBySource: [String: Int] = [:]
    @State private var lastIngestSummary: String?
    @State private var showingImporter = false
```

2. Add `import UniformTypeIdentifiers` below the existing imports.

3. Insert a new section after the "Actions" section:

```swift
            Section("Ingestion") {
                Button("Request HealthKit access") {
                    Task {
                        errorMessage = nil
                        do { try await ingestor.requestAuthorization() }
                        catch { errorMessage = String(describing: error) }
                    }
                }
                Button(ingestor.isRunning ? "Backfilling…" : "Backfill HealthKit (1 year)") {
                    Task {
                        errorMessage = nil
                        do {
                            let summary = try await ingestor.backfill()
                            lastIngestSummary = summ(summary)
                            ingestor.startObserving()
                            await refresh()
                        } catch { errorMessage = String(describing: error) }
                    }
                }
                .disabled(ingestor.isRunning)
                if let p = ingestor.progress {
                    Text("\(p.completedSteps)/\(p.totalSteps) · \(p.currentStep) · \(p.eventsIngested) events")
                        .font(.caption.monospaced())
                }
                Button("Import export.zip / export.xml…") { showingImporter = true }
                Button("Emit environmental events now") {
                    Task {
                        errorMessage = nil
                        // clear the day guard so the button always works
                        UserDefaults.standard.removeObject(
                            forKey: EnvironmentalEventEmitter.lastEmitDayKey)
                        await EnvironmentalEventEmitter.emitIfNeeded(
                            service: EnvironmentalDataService())
                        await refresh()
                    }
                }
                Button("Backfill environmental history (1 year)") {
                    Task {
                        errorMessage = nil
                        do {
                            let summary = try await EnvironmentalEventEmitter.backfillDerived()
                            lastIngestSummary = summ(summary)
                            await refresh()
                        } catch { errorMessage = String(describing: error) }
                    }
                }
                if let lastIngestSummary {
                    Text(lastIngestSummary).font(.caption.monospaced())
                }
            }
            Section("Counts by source") {
                ForEach(countsBySource.sorted(by: { $0.key < $1.key }), id: \.key) { key, n in
                    LabeledContent(key, value: "\(n)")
                }
            }
            Section("Counts by category") {
                ForEach(countsByCategory.sorted(by: { $0.key < $1.key }), id: \.key) { key, n in
                    LabeledContent(key, value: "\(n)")
                }
            }
```

4. Add the file importer to the `List` (after `.task { await refresh() }`):

```swift
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.zip, .xml],
                      allowsMultipleSelection: false) { result in
            Task { await importExport(result) }
        }
```

5. Add the helpers:

```swift
    private func summ(_ s: IngestSummary) -> String {
        "inserted \(s.inserted) · updated \(s.updated) · skipped \(s.skipped) · replaced \(s.replaced)"
    }

    private func importExport(_ result: Result<[URL], Error>) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            guard let picked = try result.get().first else { return }
            guard picked.startAccessingSecurityScopedResource() else {
                errorMessage = "No permission to read the selected file"
                return
            }
            defer { picked.stopAccessingSecurityScopedResource() }
            // copy out of the security scope so parsing can run detached
            let local = FileManager.default.temporaryDirectory
                .appendingPathComponent(picked.lastPathComponent)
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.copyItem(at: picked, to: local)
            let xmlURL = picked.pathExtension.lowercased() == "zip"
                ? try ExportArchive.extractExportXML(from: local)
                : local
            let db = database
            let parseResult = try await Task.detached(priority: .userInitiated) {
                try AppleHealthExportParser(database: db).parse(xmlAt: xmlURL, progress: nil)
            }.value
            lastIngestSummary = summ(parseResult.summary)
                + " · read \(parseResult.recordsRead) · unmapped \(parseResult.recordsSkipped)"
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }
```

6. Extend `refresh()` — after the `recent = ...` line add:

```swift
            countsByCategory = try await GRDBEventStore(database: database).countsByCategory()
            countsBySource = try await GRDBEventStore(database: database).countsBySource()
```

- [ ] **Step 2: Full verification — both suites**

```bash
cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -1
cd /Users/leo/Desktop/FoodIntolerances
xcodebuild -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" \
  -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' \
  -parallel-testing-enabled NO \
  test -only-testing:"Food IntolerancesTests/SwiftDataMigratorTests" 2>&1 \
  | grep -E "Test .* (started|passed|failed)|Restarting|TEST"
```

Expected: 70 package tests pass; app suite shows the documented 8-pass/1-crash pattern.

- [ ] **Step 3: HUMAN CHECKPOINT — on-device smoke test (~10 minutes)**

The agent stops here and hands to Leo. On the physical iPhone (or the iPhone 17 simulator after adding sample data in the Health app):

1. Build & run. More → Health Graph Debug.
2. "Request HealthKit access" → grant everything.
3. "Backfill HealthKit (1 year)" → progress line ticks through types; afterwards "Counts by source" shows a `healthKit` row and "Counts by category" shows plausible sleep/exercise/vitals totals. **Note the elapsed time** — the spec budget is ~2 minutes on mid-range hardware; report the number (over ~3 minutes = a finding). Tap backfill AGAIN → `lastIngestSummary` shows updated/skipped, inserted ≈ 0, and totals unchanged (idempotence, live).
4. Export your Health data (Health app → profile picture → Export All Health Data). On a physical device: save to Files (or AirDrop to the Mac and back). On the simulator: choose Save to Files directly. Then "Import export.zip…" → summary shows mostly `skipped` (live HealthKit outranks the export) and totals barely move.
5. "Emit environmental events now" → an `environment` category row appears (pressure/moonPhase/season). Then "Backfill environmental history (1 year)" → the environment count jumps by roughly 700–1,100 (365 × moon+season, plus retrograde days); run it twice — second run inserts ≈ 0.
6. Background-delivery spot check (optional, over days): log a workout on the watch/phone with the app backgrounded; the event should appear without opening the debug screen first.

Record what you saw; anything off = a finding for the fix loop before the branch closes.

- [ ] **Step 4: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances
git add Views/HealthGraphDebugView.swift
git commit -m "feat(app): debug ingestion panel — backfill, export import, environmental emit"
```

---

## Done criteria (Phase 1A exit)

- Package suite ≈ 70 tests green (`swift test`), zero warnings; app builds and its migrator suite shows the documented 8-pass/1-known-crash pattern under `-parallel-testing-enabled NO`.
- Deployment floor is iOS 26.0 everywhere; the package floor is `.iOS(.v26)` under `swift-tools-version: 6.2`.
- Migration v2 (`dedupKey` + partial unique index + `idx_events_category_subtype_timestamp`) is the ONLY schema change, registered in the migrator.
- One-year HealthKit backfill runs from the debug panel with visible progress, is idempotent on re-run, and its elapsed time is recorded against the spec's ~2-minute budget (verified live at the human checkpoint).
- `export.zip` import round-trips through zip extraction + streaming parse and defers to live-HealthKit rows (mostly `skipped` on overlap).
- Environmental events emit daily with per-day dedup (season as a daily exposure); the derived signals (moon/season/retrograde) backfill a year of history idempotently.
- Treatments now migrate for ALL legacy entry types (the Phase 0 review's acknowledged data-loss path on `.foodDrink` entries is closed and pinned by a test).
- No health values, names, or subtypes in logs. No user-facing causal language. Soft-delete discipline intact (pipeline replaces via soft-delete; `eraseAllRows` is `#if DEBUG`-gated package tooling).
- Phase 0 review follow-ups closed: CHECK-constraint + soft-delete-roundtrip + findOrCreate-metadata tests exist; migrator attachments are injectable and tests hermetic; broadened idempotence fixture; debug view no longer imports GRDB.
- Decision recorded — data protection stays at the iOS default (`completeUntilFirstUserAuthentication`) for the HealthGraph store: `.completeUnlessOpen` (suggested in the Phase 0 review) would break background HealthKit delivery, which must open the DB while the device is locked. Revisit at Phase 6 alongside encrypted backup.
- Phase 2 contract note: same-subtype equal-rank duration events MAY overlap (two devices); nightly aggregation must union intervals when summing durations.
- Carried forward (NOT this plan): removing `eraseDatabaseOnSchemaChange` (Plan 1C, when manual capture ships); removing the now-unused app-target GRDB product link from the pbxproj (Plan 1B, first project-file-touching task); onboarding backfill UX + named-food `HKCorrelationTypeIdentifierFood` import consideration (Plan 1D); batching the SwiftData migrator's per-event writes (runs once per user — revisit only if the Task 11 checkpoint shows the forced migration is slow on-device).
