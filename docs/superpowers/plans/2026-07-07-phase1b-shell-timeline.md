# Phase 1B: App Shell + Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the legacy tab shell with the calm-clinical 4-tab + center-capture navigation and ship a fully working Timeline over the event graph 1A populated — day-grouped feed, category color/icon coding, filter chips, FTS search, per-day severity sparklines, event detail with soft delete + undo — plus a minimal live Home, honest Insights/Health placeholders, and the 1A carried follow-ups.

**Architecture:** All new pure logic (keyset pagination, FTS search, day grouping, severity series, display formatting) lives in `HealthGraphCore` (migration v3 + store methods + a `Timeline/` folder), unit-tested via `swift test`. The app contributes SwiftUI only: a design-token layer (`HealthTheme`, `CategoryStyle`), a custom tab shell (`HealthOSRootView` + `HealthOSTabBar`), and feature views under `Views/HealthOS/` (synced folder — no pbxproj edits needed for new files). The legacy `MainTabView` app stays fully functional behind a "Legacy app" gateway in the Health tab until 1C/1D port its features. Approved scope decisions (Leo, 2026-07-07): new shell becomes root NOW; Home is minimal-but-live; FTS search ships in 1B.

**Tech Stack:** Swift (language mode 5), SwiftUI (iOS 26 SDK), GRDB 7 (FTS5), Swift Testing (package + app unit tests), existing HealthGraphCore ingestion stack.

## Global Constraints

- Repo root: `/Users/leo/Desktop/FoodIntolerances`. App project: `Food Intolerances.xcodeproj` (note the space). Scheme: `Food Intolerances`. Deployment floor: **iOS 26.0** (raised in 1A).
- App build/test destination: iPhone 17 / iOS 26.5 simulator — `-destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF'`.
- App test runs MUST pass `-parallel-testing-enabled NO`. Known pre-existing issue (documented in `SwiftDataMigratorTests.swift`): `migratesObjectsFromAvoidedCabinetAndProtocols` crashes the test process inside Apple's SwiftData teardown. Expected app-suite result: that ONE test crashes, everything else passes. Report per-test results, never a bare "TEST FAILED".
- Package tests: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`. Suite entering this plan: **71 tests / 11 suites**.
- Schema changes ONLY inside numbered GRDB migrations (this plan adds `v3`). Never `ALTER TABLE`/`CREATE` outside the migrator. `eraseDatabaseOnSchemaChange` (DEBUG) STAYS through 1B (removal is Plan 1C when manual capture makes data irreplaceable). Appending v3 does NOT erase existing on-device data — GRDB erases only when an already-registered migration's definition changes.
- Soft delete only: product code never hard-deletes from `health_events`. Timeline delete = `softDelete(id:)`; undo = `restore(id:)` (added in Task 2). Every read filters `deletedAt IS NULL`.
- No user-facing causal language anywhere. Timeline/Home/Insights copy is descriptive ("we observed", "your data shows nothing yet") — never "causes", "triggers", "will".
- Privacy: never log health values, subtypes, or names — log counts and category totals only.
- **Accessibility is a merge gate:** Dynamic Type everywhere (test at XXL), VoiceOver labels on every interactive element and on every color-coded mark (color is never the only channel — every category mark ships with icon + text), tap targets ≥ 44pt.
- **Design tokens are law:** every color in new UI comes from `HealthTheme` / `CategoryStyle` (Task 5). No `.blue`, no ad-hoc hex in views. Both light and dark ship in every task; preview both.
- Performance: Timeline must stay responsive at 100k+ events — keyset pagination (pages of 200), `LazyVStack`, FTS-backed search with `LIMIT`. No `fetchAll` of the whole table anywhere in app code.
- New app files go under `Views/`, `Models/`, or `Utilities/` (fileSystemSynchronizedGroups — auto-join the target). Repo-root files need manual pbxproj surgery: don't create any.
- Legacy code is untouched except where a task explicitly diffs it (`FoodIntolerancesApp.swift` root swap, `HealthGraphDebugView` ingestor fix, `MoreView` unchanged). The legacy app must keep building and running via the gateway.
- Verification commands pipe through `| tail` for brevity. On ANY failure, rerun without `| tail`.
- Commit after every task with the message given in its final step.

## Design tokens (frozen 2026-07-07 — validated, do not re-derive)

Palette validated with the dataviz six-checks validator against BOTH surfaces (all-pairs CVD: light min ΔE 14.0, dark 13.8, target ≥12 met; accent teal 4.57:1 on paper, 6.30:1 on dark — AA).

**Surfaces & ink** (light / dark):

| Token | Light | Dark |
|---|---|---|
| `paper` (app background) | `#FAF7F2` | `#15140F` |
| `card` | `#FFFFFF` | `#201E17` |
| `cardBorder` | `#E5DFD4` | `#35322A` |
| `ink` | `#1C1B18` | `#EDE9E0` |
| `inkSecondary` | `#6B6759` | `#A8A296` |
| `inkMuted` | `#8F8A7B` | `#7A756A` |
| `accent` (deep teal) | `#2E7D74` | `#4FA599` |
| `amber` (evidence/warm alerts — reserve; not a category color) | `#C77E32` | `#D89A55` |
| `dotMiss` (hollow evidence) | `#D8D2C6` | `#4A463C` |

**Category families** (8 slots ← 20 `EventCategory` cases; color NEVER appears without icon + label):

| Family | Categories | Light | Dark | SF Symbol (per category) |
|---|---|---|---|---|
| sleep | sleep | `#3D50B5` | `#5265D6` | `moon.zzz.fill` |
| movement | exercise | `#2893B4` | `#27A3C9` | `figure.run` |
| food | food | `#47702F` | `#4E7F2E` | `fork.knife` |
| doses | medication, supplement, peptide | `#7A4295` | `#8C55B5` | `pills.fill`, `leaf.fill`, `syringe.fill` |
| symptoms | symptom, illness, stool | `#C6815A` | `#CA8056` | `exclamationmark.circle`, `medical.thermometer`, `toilet.fill` |
| body | vitals, bodyMetric, lab, cycle | `#B04A5A` | `#C36070` | `waveform.path.ecg`, `scalemass.fill`, `testtube.2`, `drop.circle.fill` |
| mind | mood, stress | `#904374` | `#B14B8C` | `face.smiling`, `brain.head.profile` |
| context (neutral) | environment, travel, doctorVisit, protocolMarker, note | `#8A8272` | `#A29B8A` | `cloud.sun.fill`, `airplane`, `stethoscope`, `checklist`, `note.text` |

Notes recorded from validation: light `#C6815A` sits at 2.94:1 on paper — legal via the relief rule because every mark has an adjacent icon+label; dark-mode tritan min is 9.9 (informational; protan/deutan both ≥13.8). The `amber` token is deliberately distinct from the symptoms family so evidence dots never impersonate a category.

**Type:** serif display via `Font.system(_:design: .serif)` (New York) for screen titles + section headers; SF (default) for body/UI; `design: .monospaced` ONLY for lab values (none render in 1B). Always semantic text styles (`.largeTitle`, `.title3`, `.body`, `.subheadline`, `.footnote`, `.caption`) — never fixed sizes — so Dynamic Type works.

**Shape & spacing:** card corner radius 12; hairline card border (1px) + shadow `.black.opacity(0.04), radius 3, y 1`; spacing scale 4/8/12/16/24/32.

**Signature element (the one bold thing):** the Timeline **day spine** — a hairline vertical rule down each day group's leading edge; every event row attaches a rounded category-colored tick (3×16pt; duration events 3×28pt). Time runs down the spine; category is the tick; everything else stays quiet.

**Screen wireframes (approved direction, UI spec §2):**

```
Timeline                              Home (1B minimal)
┌────────────────────────────┐       ┌────────────────────────────┐
│ Timeline            (serif)│       │ Monday, July 7      (serif)│
│ [search field............] │       │ Good morning               │
│ (Sleep)(Movement)(Food)... │       │ ┌────────────────────────┐ │
│ ── Today ── ✦sparkline ─── │       │ │ 😴 7h 32m   👣 8,214   │ │
│ ┃▌ 🌙 Core sleep    5:12AM │       │ │ last night  today      │ │
│ ┃▌ 🏃 Running  32m  7:04AM │       │ └────────────────────────┘ │
│ ┃▌ ⚠︎ Headache  ●5  11:20AM│       │ ┌────────────────────────┐ │
│ ── Yesterday ─ ✦spark ──── │       │ │ Your history is in.    │ │
│ ┃▌ ...                     │       │ │ 135k events · 14 months│ │
│ (loads more as you scroll) │       │ └────────────────────────┘ │
└────────────────────────────┘       │  [insights empty state]    │
 Home Timeline [+] Insights Health   └────────────────────────────┘
```

---

### Task 1: Project hygiene — remove the unused app-target GRDB link

**Files:**
- Modify: `Food Intolerances.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces: an app target whose only package products are `HealthGraphCore` and `SwiftAA`. No API changes. (Carried 1A follow-up: the app reaches GRDB only through HealthGraphCore.)

Background: 1A's final review flagged that the app target still links the `GRDB` package product directly even though nothing in the app imports GRDB (verify first — that's Step 1). The pbxproj has four GRDB-for-app-target artifacts: the `PBXBuildFile` line ("GRDB in Frameworks"), its entry in the app target's Frameworks build phase, the `XCSwiftPackageProductDependency` object, and its listing in the app target's `packageProductDependencies`. The `XCRemoteSwiftPackageReference` for GRDB.swift STAYS — HealthGraphCore resolves GRDB through the workspace.

- [ ] **Step 1: Verify nothing in the app imports GRDB**

Run:
```bash
grep -rn "import GRDB" --include="*.swift" /Users/leo/Desktop/FoodIntolerances --exclude-dir=HealthGraphCore
```
Expected: no output. If ANY file matches, STOP — report to the controller instead of editing the project.

- [ ] **Step 2: Locate the four pbxproj entries**

Run:
```bash
grep -n "GRDB" "/Users/leo/Desktop/FoodIntolerances/Food Intolerances.xcodeproj/project.pbxproj"
```
Expected (line numbers may drift — match by content):
- a `PBXBuildFile` line like `C1346EB4… /* GRDB in Frameworks */ = {isa = PBXBuildFile; productRef = 41B6D886… /* GRDB */; };`
- that same UUID inside the app target's `PBXFrameworksBuildPhase` `files = (…)` list
- `41B6D886… /* GRDB */,` inside the app target's `packageProductDependencies = (…)` list
- an `XCSwiftPackageProductDependency` block `41B6D886… /* GRDB */ = { isa = XCSwiftPackageProductDependency; package = …; productName = GRDB; };`
- the `XCRemoteSwiftPackageReference "GRDB.swift"` block and its entry in the project's `packageReferences` — **these two STAY**.

- [ ] **Step 3: Remove exactly the four app-target entries**

Edit the pbxproj: delete (1) the `PBXBuildFile` GRDB line, (2) the GRDB line in the app target's Frameworks build-phase `files` list, (3) the GRDB line in the app target's `packageProductDependencies`, (4) the whole `XCSwiftPackageProductDependency` GRDB block. Do NOT touch the test targets' entries (they have none for GRDB) or the package reference.

- [ ] **Step 4: Verify the app still builds**

Run:
```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add "Food Intolerances.xcodeproj/project.pbxproj" && git commit -m "chore: remove unused app-target GRDB product link (1A follow-up)"
```

---

### Task 2: Package — timeline pagination + restore

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift` (append)

**Interfaces:**
- Consumes: Phase 0/1A package as merged (`AppDatabase`, `HealthEvent`, `GRDBEventStore`).
- Produces (used by Tasks 8, 9, 11):

```swift
public struct TimelineCursor: Equatable, Sendable {
    public let timestamp: Date
    public let id: UUID
    public init(timestamp: Date, id: UUID)
}
// New protocol requirements on EventStore + GRDBEventStore implementations:
func eventsPage(before cursor: TimelineCursor?, limit: Int,
                categories: Set<EventCategory>?, sources: Set<EventSource>?) async throws -> [HealthEvent]
func restore(id: UUID) async throws
```

Semantics to implement exactly:
- `eventsPage` returns non-deleted events ordered `timestamp DESC, id DESC`, at most `limit` rows. `cursor == nil` → newest page. With a cursor, return strictly-older rows: `(timestamp < c.timestamp) OR (timestamp = c.timestamp AND id < c.id)` — id tiebreak uses the BLOB byte order of the UUID so paging never skips or repeats rows with equal timestamps. `categories`/`sources` `nil` or empty = no filter; non-empty = SQL `IN` on raw values.
- `restore(id:)` sets `deletedAt = NULL` for that row (the user-facing undo; imports still never resurrect — dedup checks `deletedAt` at ingest, and a restored row simply exists again).
- The caller derives the next cursor from the last returned event: `TimelineCursor(timestamp: last.timestamp, id: last.id)`.

- [ ] **Step 1: Write the failing tests**

Append to `HealthGraphCore/Tests/HealthGraphCoreTests/EventStoreTests.swift`, inside the existing suite struct:

```swift
    @Test func eventsPagePaginatesDescendingWithoutSkipsOrDupes() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        // 7 events; two share one timestamp to exercise the id tiebreak.
        var all: [HealthEvent] = []
        for i in 0..<5 {
            all.append(HealthEvent(timestamp: base.addingTimeInterval(Double(i) * 3600),
                                   category: .food, subtype: "meal\(i)", source: .manual, createdAt: base))
        }
        let sharedTS = base.addingTimeInterval(6 * 3600)
        all.append(HealthEvent(timestamp: sharedTS, category: .symptom, subtype: "headache",
                               value: 5, unit: "severity", source: .manual, createdAt: base))
        all.append(HealthEvent(timestamp: sharedTS, category: .symptom, subtype: "nausea",
                               value: 3, unit: "severity", source: .manual, createdAt: base))
        try await store.save(all)

        var seen: [UUID] = []
        var cursor: TimelineCursor? = nil
        while true {
            let page = try await store.eventsPage(before: cursor, limit: 3, categories: nil, sources: nil)
            if page.isEmpty { break }
            #expect(page.count <= 3)
            seen.append(contentsOf: page.map(\.id))
            cursor = TimelineCursor(timestamp: page.last!.timestamp, id: page.last!.id)
        }
        #expect(seen.count == 7)                      // no skips
        #expect(Set(seen).count == 7)                 // no dupes
        // Descending timestamps across the whole walk
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.timestamp) })
        let stamps = seen.map { byID[$0]! }
        #expect(stamps == stamps.sorted(by: >))
    }

    @Test func eventsPageAppliesCategoryAndSourceFilters() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save([
            HealthEvent(timestamp: base, category: .sleep, subtype: "asleepCore", source: .healthKit, createdAt: base),
            HealthEvent(timestamp: base.addingTimeInterval(60), category: .food, subtype: "milk", source: .manual, createdAt: base),
            HealthEvent(timestamp: base.addingTimeInterval(120), category: .exercise, subtype: "running", source: .healthKit, createdAt: base),
        ])
        let sleepOnly = try await store.eventsPage(before: nil, limit: 10, categories: [.sleep], sources: nil)
        #expect(sleepOnly.map(\.subtype) == ["asleepCore"])
        let hkOnly = try await store.eventsPage(before: nil, limit: 10, categories: nil, sources: [.healthKit])
        #expect(Set(hkOnly.map(\.category)) == Set([.sleep, .exercise]))
        let both = try await store.eventsPage(before: nil, limit: 10, categories: [.food], sources: [.healthKit])
        #expect(both.isEmpty)
    }

    @Test func eventsPageExcludesSoftDeletedAndRestoreBringsBack() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let event = HealthEvent(timestamp: base, category: .note, source: .manual, createdAt: base)
        try await store.save(event)
        try await store.softDelete(id: event.id)
        let afterDelete = try await store.eventsPage(before: nil, limit: 10, categories: nil, sources: nil)
        #expect(afterDelete.isEmpty)
        try await store.restore(id: event.id)
        let afterRestore = try await store.eventsPage(before: nil, limit: 10, categories: nil, sources: nil)
        #expect(afterRestore.map(\.id) == [event.id])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE — `eventsPage`/`restore`/`TimelineCursor` don't exist yet.

- [ ] **Step 3: Implement**

In `HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift`:

Add near the top (file scope, above the protocol):

```swift
/// Keyset cursor for descending timeline pagination. Derive the next cursor
/// from the LAST event of the previous page.
public struct TimelineCursor: Equatable, Sendable {
    public let timestamp: Date
    public let id: UUID
    public init(timestamp: Date, id: UUID) {
        self.timestamp = timestamp
        self.id = id
    }
}
```

Add to the `EventStore` protocol:

```swift
    /// Newest-first page for the timeline. `cursor == nil` = newest page.
    /// Strictly-older-than-cursor keyset: (timestamp, id) DESC. Excludes soft-deleted.
    func eventsPage(before cursor: TimelineCursor?, limit: Int,
                    categories: Set<EventCategory>?, sources: Set<EventSource>?) async throws -> [HealthEvent]
    /// User-facing undo of a soft delete.
    func restore(id: UUID) async throws
```

Add to `GRDBEventStore`:

```swift
    public func eventsPage(before cursor: TimelineCursor?, limit: Int,
                           categories: Set<EventCategory>?, sources: Set<EventSource>?) async throws -> [HealthEvent] {
        try await dbWriter.read { db in
            var conditions: [String] = ["deletedAt IS NULL"]
            var arguments: [(any DatabaseValueConvertible)?] = []
            if let cursor {
                conditions.append("(timestamp < ? OR (timestamp = ? AND id < ?))")
                arguments.append(cursor.timestamp)
                arguments.append(cursor.timestamp)
                arguments.append(cursor.id.databaseValue)
            }
            if let categories, !categories.isEmpty {
                let marks = Array(repeating: "?", count: categories.count).joined(separator: ",")
                conditions.append("category IN (\(marks))")
                arguments.append(contentsOf: categories.map(\.rawValue).sorted())
            }
            if let sources, !sources.isEmpty {
                let marks = Array(repeating: "?", count: sources.count).joined(separator: ",")
                conditions.append("source IN (\(marks))")
                arguments.append(contentsOf: sources.map(\.rawValue).sorted())
            }
            let sql = """
                SELECT * FROM health_events
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY timestamp DESC, id DESC
                LIMIT ?
                """
            arguments.append(limit)
            return try HealthEvent.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    public func restore(id: UUID) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "UPDATE health_events SET deletedAt = NULL WHERE id = ?",
                           arguments: [id.databaseValue])
        }
    }
```

Note: `id` is stored as a 16-byte BLOB; `UUID.databaseValue` in GRDB encodes the same byte order used by the PK, so `id < ?` compares consistently. If the existing file's soft-delete/other methods use a different arguments style, match the file's established idiom — but keep the WHERE/ORDER semantics exactly as specified.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 74 tests in 11 suites passed` (71 + 3 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add HealthGraphCore && git commit -m "feat(core): keyset timeline pagination with category/source filters; restore(id:) undo"
```

---

### Task 3: Package — FTS5 search (migration v3)

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift` (append migration v3)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift` (search API)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/AppDatabaseTests.swift`, `EventStoreTests.swift` (append)

**Interfaces:**
- Consumes: Task 2's file state.
- Produces (used by Task 9):

```swift
// New protocol requirement on EventStore + GRDBEventStore:
func searchEvents(matching query: String, limit: Int) async throws -> [HealthEvent]
```

Design (locked): migration `v3` creates an **external-content FTS5 table** over `health_events(subtype, category)` with sync triggers and backfills existing rows. Search scope in 1B is subtype + category raw value ("headache", "running", "sleep") — user-typed text (notes, meals, object names) arrives with capture in 1C and will extend the index then. Raw user input is NEVER passed to `MATCH` directly: it is tokenized to alphanumerics and each token gets a `*` prefix suffix (`"head"` → `head*`), joined with implicit AND. Empty/symbol-only queries return `[]` without touching FTS. Results order `timestamp DESC`, exclude soft-deleted, `LIMIT` applied.

- [ ] **Step 1: Write the failing tests**

Append to `AppDatabaseTests.swift`:

```swift
    @Test func v3CreatesFTSTableAndTriggersAndBackfills() throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try db.dbWriter.write { d in
            try HealthEvent(timestamp: now, category: .symptom, subtype: "headache",
                            source: .manual, createdAt: now).insert(d)
        }
        let ftsCount = try db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT count(*) FROM health_events_fts WHERE health_events_fts MATCH 'headache'") ?? -1
        }
        #expect(ftsCount == 1)
        // Trigger keeps FTS in sync on UPDATE
        try db.dbWriter.write { d in
            try d.execute(sql: "UPDATE health_events SET subtype = 'migraine'")
        }
        let after = try db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT count(*) FROM health_events_fts WHERE health_events_fts MATCH 'migraine'") ?? -1
        }
        #expect(after == 1)
    }
```

Append to `EventStoreTests.swift`:

```swift
    @Test func searchEventsMatchesPrefixAndCategoryAndSkipsDeleted() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let headache = HealthEvent(timestamp: base, category: .symptom, subtype: "headache",
                                   value: 5, unit: "severity", source: .manual, createdAt: base)
        let run = HealthEvent(timestamp: base.addingTimeInterval(60), category: .exercise,
                              subtype: "running", source: .healthKit, createdAt: base)
        let sleepStage = HealthEvent(timestamp: base.addingTimeInterval(120), category: .sleep,
                                     subtype: "asleepCore", source: .healthKit, createdAt: base)
        try await store.save([headache, run, sleepStage])

        // Prefix match on subtype
        #expect(try await store.searchEvents(matching: "head", limit: 10).map(\.id) == [headache.id])
        // Category raw value matches too
        #expect(try await store.searchEvents(matching: "sleep", limit: 10).map(\.id) == [sleepStage.id])
        // Injection-shaped input is sanitized to plain tokens, never executed as FTS
        // syntax. `run" *` reduces to the single prefix term "run" → matches `running`.
        #expect(try await store.searchEvents(matching: "run\" *", limit: 10).map(\.id) == [run.id])
        // Operator/symbol-only input yields no matching token (tokens are ANDed prefixes;
        // "or" matches nothing here) → empty result, and crucially NO FTS syntax error.
        #expect(try await store.searchEvents(matching: "\" OR ", limit: 10).isEmpty)
        // Empty and symbol-only queries return nothing
        #expect(try await store.searchEvents(matching: "   ", limit: 10).isEmpty)
        // Soft-deleted rows never surface
        try await store.softDelete(id: headache.id)
        #expect(try await store.searchEvents(matching: "head", limit: 10).isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE (`searchEvents` missing) — the AppDatabase test would also fail (`no such table: health_events_fts`).

- [ ] **Step 3: Implement migration v3**

In `AppDatabase.swift`, inside `migrator`, append AFTER the `v2` registration (same style):

```swift
        migrator.registerMigration("v3") { db in
            // External-content FTS5 index over subtype + category.
            // Scope is deliberately narrow in 1B; capture (1C) extends it to
            // user-typed text. unicode61 default tokenizer; camelCase subtypes
            // index as single tokens ("asleepCore" -> asleepcore) — prefix
            // queries still reach them ("asleep*").
            try db.execute(sql: """
                CREATE VIRTUAL TABLE health_events_fts USING fts5(
                    subtype, category,
                    content='health_events',
                    content_rowid='rowid'
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_events_fts_ai AFTER INSERT ON health_events BEGIN
                    INSERT INTO health_events_fts(rowid, subtype, category)
                    VALUES (new.rowid, new.subtype, new.category);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_events_fts_ad AFTER DELETE ON health_events BEGIN
                    INSERT INTO health_events_fts(health_events_fts, rowid, subtype, category)
                    VALUES ('delete', old.rowid, old.subtype, old.category);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_events_fts_au AFTER UPDATE ON health_events BEGIN
                    INSERT INTO health_events_fts(health_events_fts, rowid, subtype, category)
                    VALUES ('delete', old.rowid, old.subtype, old.category);
                    INSERT INTO health_events_fts(rowid, subtype, category)
                    VALUES (new.rowid, new.subtype, new.category);
                END
                """)
            // Backfill rows that predate the index.
            try db.execute(sql: """
                INSERT INTO health_events_fts(rowid, subtype, category)
                SELECT rowid, subtype, category FROM health_events
                """)
        }
```

- [ ] **Step 4: Implement searchEvents**

Add to the `EventStore` protocol:

```swift
    /// FTS-backed prefix search over subtype + category. Sanitizes input;
    /// empty/symbol-only queries return []. Newest first, soft-deleted excluded.
    func searchEvents(matching query: String, limit: Int) async throws -> [HealthEvent]
```

Add to `GRDBEventStore`:

```swift
    public func searchEvents(matching query: String, limit: Int) async throws -> [HealthEvent] {
        // Tokenize to alphanumerics; each token becomes a quoted prefix term.
        let tokens = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        let match = tokens.map { "\"\($0)\"*" }.joined(separator: " ")
        return try await dbWriter.read { db in
            try HealthEvent.fetchAll(db, sql: """
                SELECT he.* FROM health_events he
                JOIN health_events_fts f ON f.rowid = he.rowid
                WHERE health_events_fts MATCH ?
                  AND he.deletedAt IS NULL
                ORDER BY he.timestamp DESC
                LIMIT ?
                """, arguments: [match, limit])
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 76 tests in 11 suites passed`.

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add HealthGraphCore && git commit -m "feat(core): FTS5 search over events (migration v3, sync triggers, sanitized prefix queries)"
```

---

### Task 4: Package — TimelineDayBuilder + EventDisplay

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift`
- Create: `HealthGraphCore/Sources/HealthGraphCore/Timeline/EventDisplay.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift` (new)

**Interfaces:**
- Consumes: `HealthEvent`, `EventCategory` (Phase 0).
- Produces (used by Tasks 8, 10, 11, 12):

```swift
public struct SeverityPoint: Equatable, Sendable {
    public let time: Date
    public let value: Double     // 1–10 severity
}
public struct TimelineDay: Identifiable, Equatable, Sendable {
    public let dayStart: Date                 // local-midnight in the builder's tz
    public let events: [HealthEvent]          // newest first within the day
    public let severityPoints: [SeverityPoint] // chronological, symptom events with a value
    public var id: Date { dayStart }
}
public enum TimelineDayBuilder {
    /// Groups a NEWEST-FIRST event slice into days (newest day first) using
    /// the given timezone. Appending pages re-runs the builder over the full
    /// accumulated slice (idempotent, order-preserving).
    public static func days(from events: [HealthEvent], timeZone: TimeZone) -> [TimelineDay]
}
public enum EventDisplay {
    /// "Core sleep", "Running", "Headache", "Resting heart rate", "Blood pressure (systolic)"…
    public static func title(for event: HealthEvent) -> String
    /// Compact value line: "7h 32m", "severity 5", "72 bpm", "81.4 kg", "1,004 hPa", "8,214 steps" — nil when the event carries nothing to show.
    public static func valueLine(for event: HealthEvent) -> String?
    /// "7h 32m" / "45m" / "32s"-free (minutes floor) duration formatting.
    public static func durationString(minutes: Double) -> String
}
```

Behavior to implement exactly:
- **Day grouping**: an event belongs to the day containing its `timestamp` in `timeZone` (Gregorian). Duration events are NOT split across days in 1B — they group by start timestamp. (Phase 2's engine does tz-exact lag math; the timeline shows capture-local days.)
- **severityPoints**: from `category == .symptom && value != nil`, ascending by time.
- **title(for:)**: explicit map for known subtypes; unmapped subtypes fall back to camelCase-splitting with first letter capitalized (`"asleepCore"` → `"Asleep core"` is WRONG — the explicit map must cover all sleep stages; the fallback is only for genuinely unknown strings, e.g. a manual food name `"oat milk latte"` → `"Oat milk latte"`). Explicit map (complete):
  - sleep: `inBed` "In bed", `asleepUnspecified` "Asleep", `awake` "Awake", `asleepCore` "Core sleep", `asleepDeep` "Deep sleep", `asleepREM` "REM sleep"
  - exercise: `steps` "Steps", plus canonical workout names title-cased with spaces (`strengthTraining` "Strength training", `hiit` "HIIT", `stairClimbing` "Stair climbing", `paddleSports` "Paddle sports", `martialArts` "Martial arts", `coreTraining` "Core training"; single-word ones just capitalize)
  - vitals: `restingHeartRate` "Resting heart rate", `heartRate` "Heart rate", `hrv` "HRV", `respiratoryRate` "Respiratory rate", `bloodPressureSystolic` "Blood pressure (systolic)", `bloodPressureDiastolic` "Blood pressure (diastolic)"
  - bodyMetric: `weight` "Weight"
  - food daily stats: `dietaryEnergy` "Energy", `dietaryProtein` "Protein", `dietaryCarbs` "Carbs", `dietaryFat` "Fat", `dietarySugar` "Sugar", `dietarySodium` "Sodium"
  - cycle: `menstrualFlow` "Menstrual flow"; stress: `mindfulness` "Mindfulness"
  - environment: `pressure` "Air pressure", `pressureDrop` "Pressure drop", `moonPhase` "Moon phase", `mercuryRetrograde` "Mercury retrograde", `season` "Season"
  - nil subtype → capitalized category rawValue ("Note").
- **valueLine(for:)**: category-aware:
  - duration events with unit "min" → `durationString(minutes:)` ("7h 32m", "45m")
  - `unit == "severity"` → "severity N" (Int-formatted)
  - `unit == "count"` → grouped integer + " steps" when subtype == "steps", else grouped integer
  - kcal/g/mg/bpm/ms/kg/hPa/mmHg/"breaths/min" → "%.0f"/"%.1f" (kg one decimal, others zero) + " " + unit
  - environment moonPhase/season → the metadata value ("Waxing gibbous", "Summer") decoded from `[String:String]` JSON (`"phase"`/`"season"` keys)
  - `unit == "level"` (menstrualFlow) → "light"/"medium"/"heavy" for 1/2/3, else nil
  - everything else with a value → "%g" + optional unit; no value + no mapped metadata → nil.
- **durationString(minutes:)**: `< 60` → "45m"; otherwise "7h 32m" (minutes floor, no zero-padding, omit "0m" → "7h").

- [ ] **Step 1: Write the failing tests**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import HealthGraphCore

struct TimelineDayBuilderTests {
    let tz = TimeZone(identifier: "America/New_York")!
    // 22:00 EDT and 06:00 EDT the next day — straddle local midnight
    let lateNight = Date(timeIntervalSince1970: 1_783_216_800)  // 2026-07-04 22:00 EDT
    let nextMorning = Date(timeIntervalSince1970: 1_783_245_600) // 2026-07-05 06:00 EDT

    @Test func groupsByLocalDayNewestFirst() {
        let older = HealthEvent(timestamp: lateNight, category: .food, subtype: "dinner",
                                source: .manual, createdAt: lateNight)
        let newer = HealthEvent(timestamp: nextMorning, category: .symptom, subtype: "headache",
                                value: 5, unit: "severity", source: .manual, createdAt: nextMorning)
        let days = TimelineDayBuilder.days(from: [newer, older], timeZone: tz)
        #expect(days.count == 2)
        #expect(days[0].events.map(\.id) == [newer.id])   // newest day first
        #expect(days[1].events.map(\.id) == [older.id])
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        #expect(days[0].dayStart == cal.startOfDay(for: nextMorning))
    }

    @Test func severityPointsAreChronologicalSymptomValuesOnly() {
        let s1 = HealthEvent(timestamp: nextMorning, category: .symptom, subtype: "headache",
                             value: 5, unit: "severity", source: .manual, createdAt: nextMorning)
        let s2 = HealthEvent(timestamp: nextMorning.addingTimeInterval(3600), category: .symptom,
                             subtype: "nausea", value: 3, unit: "severity", source: .manual,
                             createdAt: nextMorning)
        let unrated = HealthEvent(timestamp: nextMorning.addingTimeInterval(7200), category: .symptom,
                                  subtype: "fatigue", source: .manual, createdAt: nextMorning)
        let food = HealthEvent(timestamp: nextMorning.addingTimeInterval(300), category: .food,
                               subtype: "eggs", value: 2, source: .manual, createdAt: nextMorning)
        let days = TimelineDayBuilder.days(from: [unrated, s2, food, s1], timeZone: tz)
        #expect(days.count == 1)
        #expect(days[0].severityPoints.map(\.value) == [5, 3])         // chronological, symptoms with value only
        #expect(days[0].severityPoints[0].time < days[0].severityPoints[1].time)
    }

    @Test func displayTitlesCoverKnownSubtypesAndFallBack() {
        func event(_ cat: EventCategory, _ sub: String?) -> HealthEvent {
            HealthEvent(timestamp: lateNight, category: cat, subtype: sub,
                        source: .healthKit, createdAt: lateNight)
        }
        #expect(EventDisplay.title(for: event(.sleep, "asleepCore")) == "Core sleep")
        #expect(EventDisplay.title(for: event(.sleep, "asleepREM")) == "REM sleep")
        #expect(EventDisplay.title(for: event(.exercise, "strengthTraining")) == "Strength training")
        #expect(EventDisplay.title(for: event(.exercise, "hiit")) == "HIIT")
        #expect(EventDisplay.title(for: event(.vitals, "restingHeartRate")) == "Resting heart rate")
        #expect(EventDisplay.title(for: event(.environment, "mercuryRetrograde")) == "Mercury retrograde")
        #expect(EventDisplay.title(for: event(.food, "oat milk latte")) == "Oat milk latte")
        #expect(EventDisplay.title(for: event(.note, nil)) == "Note")
    }

    @Test func valueLinesFormatByUnit() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        func event(_ cat: EventCategory, _ sub: String?, _ value: Double?, _ unit: String?,
                   end: Date? = nil, metadata: [String: String]? = nil) -> HealthEvent {
            HealthEvent(timestamp: base, endTimestamp: end, category: cat, subtype: sub,
                        value: value, unit: unit, source: .healthKit,
                        metadata: metadata.map { try! JSONEncoder().encode($0) }, createdAt: base)
        }
        #expect(EventDisplay.valueLine(for: event(.sleep, "asleepCore", 452, "min",
                                                  end: base.addingTimeInterval(452 * 60))) == "7h 32m")
        #expect(EventDisplay.valueLine(for: event(.symptom, "headache", 5, "severity")) == "severity 5")
        #expect(EventDisplay.valueLine(for: event(.exercise, "steps", 8214, "count")) == "8,214 steps")
        #expect(EventDisplay.valueLine(for: event(.bodyMetric, "weight", 81.4, "kg")) == "81.4 kg")
        #expect(EventDisplay.valueLine(for: event(.vitals, "restingHeartRate", 52, "bpm")) == "52 bpm")
        #expect(EventDisplay.valueLine(for: event(.environment, "moonPhase", nil, nil,
                                                  metadata: ["phase": "Waxing gibbous"])) == "Waxing gibbous")
        #expect(EventDisplay.valueLine(for: event(.cycle, "menstrualFlow", 2, "level")) == "medium")
        #expect(EventDisplay.valueLine(for: event(.note, nil, nil, nil)) == nil)
        #expect(EventDisplay.durationString(minutes: 45) == "45m")
        #expect(EventDisplay.durationString(minutes: 420) == "7h")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE — the `Timeline/` types don't exist.

- [ ] **Step 3: Implement**

Create `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift`:

```swift
import Foundation

public struct SeverityPoint: Equatable, Sendable {
    public let time: Date
    public let value: Double
    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

public struct TimelineDay: Identifiable, Equatable, Sendable {
    public let dayStart: Date
    public let events: [HealthEvent]
    public let severityPoints: [SeverityPoint]
    public var id: Date { dayStart }
    public init(dayStart: Date, events: [HealthEvent], severityPoints: [SeverityPoint]) {
        self.dayStart = dayStart
        self.events = events
        self.severityPoints = severityPoints
    }
}

public enum TimelineDayBuilder {
    /// Groups a newest-first slice of events into local-calendar days,
    /// newest day first. Duration events group by their start timestamp.
    public static func days(from events: [HealthEvent], timeZone: TimeZone) -> [TimelineDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var order: [Date] = []
        var buckets: [Date: [HealthEvent]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.timestamp)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(event)
        }
        // Input is newest-first, so first-seen day order is already newest-first;
        // sort defensively in case a caller passes an unordered slice.
        return order.sorted(by: >).map { day in
            let dayEvents = buckets[day]!.sorted { ($0.timestamp, $0.id.uuidString) > ($1.timestamp, $1.id.uuidString) }
            let points = dayEvents
                .filter { $0.category == .symptom && $0.value != nil }
                .map { SeverityPoint(time: $0.timestamp, value: $0.value!) }
                .sorted { $0.time < $1.time }
            return TimelineDay(dayStart: day, events: dayEvents, severityPoints: points)
        }
    }
}
```

Create `HealthGraphCore/Sources/HealthGraphCore/Timeline/EventDisplay.swift`:

```swift
import Foundation

public enum EventDisplay {
    private static let titles: [String: String] = [
        // sleep
        "inBed": "In bed", "asleepUnspecified": "Asleep", "awake": "Awake",
        "asleepCore": "Core sleep", "asleepDeep": "Deep sleep", "asleepREM": "REM sleep",
        // exercise
        "steps": "Steps", "running": "Running", "walking": "Walking", "cycling": "Cycling",
        "swimming": "Swimming", "yoga": "Yoga", "strengthTraining": "Strength training",
        "hiit": "HIIT", "hiking": "Hiking", "pilates": "Pilates", "rowing": "Rowing",
        "elliptical": "Elliptical", "stairClimbing": "Stair climbing", "dance": "Dance",
        "tennis": "Tennis", "basketball": "Basketball", "soccer": "Soccer", "golf": "Golf",
        "paddleSports": "Paddle sports", "martialArts": "Martial arts",
        "coreTraining": "Core training", "other": "Workout",
        // vitals
        "restingHeartRate": "Resting heart rate", "heartRate": "Heart rate", "hrv": "HRV",
        "respiratoryRate": "Respiratory rate",
        "bloodPressureSystolic": "Blood pressure (systolic)",
        "bloodPressureDiastolic": "Blood pressure (diastolic)",
        // bodyMetric / cycle / stress
        "weight": "Weight", "menstrualFlow": "Menstrual flow", "mindfulness": "Mindfulness",
        // food daily stats
        "dietaryEnergy": "Energy", "dietaryProtein": "Protein", "dietaryCarbs": "Carbs",
        "dietaryFat": "Fat", "dietarySugar": "Sugar", "dietarySodium": "Sodium",
        // environment
        "pressure": "Air pressure", "pressureDrop": "Pressure drop", "moonPhase": "Moon phase",
        "mercuryRetrograde": "Mercury retrograde", "season": "Season",
    ]

    public static func title(for event: HealthEvent) -> String {
        guard let subtype = event.subtype, !subtype.isEmpty else {
            return event.category.rawValue.prefix(1).uppercased() + event.category.rawValue.dropFirst()
        }
        if let mapped = titles[subtype] { return mapped }
        // Unknown subtype (manual food names, HK symptom identifiers not in the map):
        // capitalize the first letter, split camelCase humps to spaces.
        var out = ""
        for (i, ch) in subtype.enumerated() {
            // `Character(ch.uppercased())` traps when a case change yields >1 grapheme
            // (e.g. "ß" → "SS"), reachable via user-typed food names in 1C — append the String.
            if i == 0 { out.append(contentsOf: ch.uppercased()) }
            else if ch.isUppercase { out.append(" "); out.append(contentsOf: ch.lowercased()) }
            else { out.append(ch) }
        }
        return out
    }

    public static func valueLine(for event: HealthEvent) -> String? {
        if event.category == .environment,
           let data = event.metadata,
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            if let phase = dict["phase"] { return phase }
            if let season = dict["season"] { return season }
        }
        guard let value = event.value else { return nil }
        switch event.unit {
        case "min": return durationString(minutes: value)
        case "severity": return "severity \(Int(value))"
        case "count":
            let grouped = Self.grouped(Int(value))
            return event.subtype == "steps" ? "\(grouped) steps" : grouped
        case "kg": return String(format: "%.1f kg", value)
        case "level":
            switch Int(value) {
            case 1: return "light"
            case 2: return "medium"
            case 3: return "heavy"
            default: return nil
            }
        case let unit? where ["kcal", "g", "mg", "bpm", "ms", "hPa", "mmHg", "breaths/min"].contains(unit):
            return String(format: "%.0f %@", value, unit)
        case let unit?: return "\(String(format: "%g", value)) \(unit)"
        case nil: return String(format: "%g", value)
        }
    }

    public static func durationString(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60, m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static func grouped(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        // Deterministic grouping regardless of host/simulator locale (tests assert
        // "8,214"). Locale-aware grouping is a later i18n item (see Carried forward).
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 80 tests in 12 suites passed` (76 + 4 new, new suite).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add HealthGraphCore && git commit -m "feat(core): TimelineDayBuilder day grouping + severity series; EventDisplay title/value formatting"
```

---

### Task 5: App — design tokens (`HealthTheme`) + category styles (`CategoryStyle`) + preview graph

**Files:**
- Create: `Views/HealthOS/Theme/HealthTheme.swift`
- Create: `Views/HealthOS/Theme/CategoryStyle.swift`
- Modify: `Food Intolerances/Assets.xcassets/AccentColor.colorset/Contents.json`

**Interfaces:**
- Consumes: `HealthGraphCore` (`EventCategory`).
- Produces (used by every later view task):

```swift
enum HealthTheme {
    // surfaces & ink (all adapt light/dark automatically)
    static let paper: Color; static let card: Color; static let cardBorder: Color
    static let ink: Color; static let inkSecondary: Color; static let inkMuted: Color
    static let accent: Color; static let amber: Color; static let dotMiss: Color
    // type
    static func screenTitle() -> Font       // .largeTitle serif semibold
    static func sectionHeader() -> Font     // .title3 serif semibold
    // shape
    static let cardCornerRadius: CGFloat    // 12
}
extension View {
    func hgCard() -> some View              // card bg + border + radius + faint shadow
}
enum CategoryFamily: String, CaseIterable, Identifiable {
    case sleep, movement, food, doses, symptoms, body, mind, context
    var id: String { rawValue }
    var label: String                        // "Sleep", "Movement", …
    var color: Color                         // family color (light/dark adaptive)
    var categories: Set<EventCategory>       // the categories this family covers
}
struct CategoryStyle {
    let color: Color                         // == family color
    let icon: String                         // SF Symbol name (per category)
    let family: CategoryFamily
    static func style(for category: EventCategory) -> CategoryStyle   // exhaustive switch
}
```

(View development uses the debug panel's "Load synthetic dataset (400 days)" action for realistic data — no preview-only seeding machinery in 1B.)

- [ ] **Step 1: Fill the AccentColor asset with the deep-teal accent**

Replace the contents of `Food Intolerances/Assets.xcassets/AccentColor.colorset/Contents.json` with:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x74", "green" : "0x7D", "red" : "0x2E" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x99", "green" : "0xA5", "red" : "0x4F" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 2: Create HealthTheme.swift**

```swift
import SwiftUI

/// Calm-clinical design tokens (frozen 2026-07-07; validated against both
/// surfaces — see plan doc "Design tokens"). Every color in HealthOS views
/// comes from here or CategoryStyle. Never use ad-hoc colors in views.
enum HealthTheme {
    // MARK: surfaces & ink
    static let paper       = dyn(light: 0xFAF7F2, dark: 0x15140F)
    static let card        = dyn(light: 0xFFFFFF, dark: 0x201E17)
    static let cardBorder  = dyn(light: 0xE5DFD4, dark: 0x35322A)
    static let ink         = dyn(light: 0x1C1B18, dark: 0xEDE9E0)
    static let inkSecondary = dyn(light: 0x6B6759, dark: 0xA8A296)
    static let inkMuted    = dyn(light: 0x8F8A7B, dark: 0x7A756A)
    static let accent      = dyn(light: 0x2E7D74, dark: 0x4FA599)
    /// Evidence dots & warm alerts ONLY (Phase 2 insight cards). Never a category color.
    static let amber       = dyn(light: 0xC77E32, dark: 0xD89A55)
    static let dotMiss     = dyn(light: 0xD8D2C6, dark: 0x4A463C)

    // MARK: type — semantic styles only, so Dynamic Type scales everything
    static func screenTitle() -> Font { .system(.largeTitle, design: .serif, weight: .semibold) }
    static func sectionHeader() -> Font { .system(.title3, design: .serif, weight: .semibold) }

    // MARK: shape
    static let cardCornerRadius: CGFloat = 12

    // MARK: helpers
    private static func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// Standard calm-clinical card: white/warm-dark surface, hairline border,
    /// 12pt radius, faint shadow.
    func hgCard() -> some View {
        self
            .background(HealthTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(HealthTheme.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}
```

- [ ] **Step 3: Create CategoryStyle.swift**

```swift
import SwiftUI
import HealthGraphCore

/// The 8 color families covering all 20 EventCategory cases.
/// Palette validated (all-pairs CVD light ΔE ≥ 14.0 / dark ≥ 13.8);
/// color NEVER appears without an icon + text label beside it.
enum CategoryFamily: String, CaseIterable, Identifiable {
    case sleep, movement, food, doses, symptoms, body, mind, context

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleep: "Sleep"
        case .movement: "Movement"
        case .food: "Food"
        case .doses: "Doses"
        case .symptoms: "Symptoms"
        case .body: "Body"
        case .mind: "Mind"
        case .context: "Context"
        }
    }

    var color: Color {
        switch self {
        case .sleep:    dyn(light: 0x3D50B5, dark: 0x5265D6)
        case .movement: dyn(light: 0x2893B4, dark: 0x27A3C9)
        case .food:     dyn(light: 0x47702F, dark: 0x4E7F2E)
        case .doses:    dyn(light: 0x7A4295, dark: 0x8C55B5)
        case .symptoms: dyn(light: 0xC6815A, dark: 0xCA8056)
        case .body:     dyn(light: 0xB04A5A, dark: 0xC36070)
        case .mind:     dyn(light: 0x904374, dark: 0xB14B8C)
        case .context:  dyn(light: 0x8A8272, dark: 0xA29B8A)
        }
    }

    var categories: Set<EventCategory> {
        switch self {
        case .sleep: [.sleep]
        case .movement: [.exercise]
        case .food: [.food]
        case .doses: [.medication, .supplement, .peptide]
        case .symptoms: [.symptom, .illness, .stool]
        case .body: [.vitals, .bodyMetric, .lab, .cycle]
        case .mind: [.mood, .stress]
        case .context: [.environment, .travel, .doctorVisit, .protocolMarker, .note]
        }
    }

    private func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: CGFloat((dark >> 16) & 0xFF) / 255, green: CGFloat((dark >> 8) & 0xFF) / 255,
                          blue: CGFloat(dark & 0xFF) / 255, alpha: 1)
                : UIColor(red: CGFloat((light >> 16) & 0xFF) / 255, green: CGFloat((light >> 8) & 0xFF) / 255,
                          blue: CGFloat(light & 0xFF) / 255, alpha: 1)
        })
    }
}

struct CategoryStyle {
    let color: Color
    let icon: String
    let family: CategoryFamily

    static func style(for category: EventCategory) -> CategoryStyle {
        let (family, icon): (CategoryFamily, String) = switch category {
        case .sleep: (.sleep, "moon.zzz.fill")
        case .exercise: (.movement, "figure.run")
        case .food: (.food, "fork.knife")
        case .medication: (.doses, "pills.fill")
        case .supplement: (.doses, "leaf.fill")
        case .peptide: (.doses, "syringe.fill")
        case .symptom: (.symptoms, "exclamationmark.circle")
        case .illness: (.symptoms, "medical.thermometer")
        case .stool: (.symptoms, "toilet.fill")
        case .vitals: (.body, "waveform.path.ecg")
        case .bodyMetric: (.body, "scalemass.fill")
        case .lab: (.body, "testtube.2")
        case .cycle: (.body, "drop.circle.fill")
        case .mood: (.mind, "face.smiling")
        case .stress: (.mind, "brain.head.profile")
        case .environment: (.context, "cloud.sun.fill")
        case .travel: (.context, "airplane")
        case .doctorVisit: (.context, "stethoscope")
        case .protocolMarker: (.context, "checklist")
        case .note: (.context, "note.text")
        }
        return CategoryStyle(color: family.color, icon: icon, family: family)
    }
}
```

Note the exhaustive `switch` with NO `default`: when a future phase adds an `EventCategory` case, this file fails to compile — that is intentional.

- [ ] **Step 4: Verify the app builds**

Run:
```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. (New files under `Views/` auto-join the target — no pbxproj edit.)

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS "Food Intolerances/Assets.xcassets/AccentColor.colorset/Contents.json" && git commit -m "feat(app): calm-clinical design tokens and category styles; teal accent asset"
```

---

### Task 6: App — shell components (tab bar, root view, placeholder tabs, capture placeholder)

**Files:**
- Create: `Views/HealthOS/Shell/HealthOSTab.swift`
- Create: `Views/HealthOS/Shell/HealthOSTabBar.swift`
- Create: `Views/HealthOS/Shell/HealthOSRootView.swift`
- Create: `Views/HealthOS/Shell/CapturePlaceholderSheet.swift`
- Create: `Views/HealthOS/Home/HomeView.swift` (skeleton this task; Task 12 makes it live)
- Create: `Views/HealthOS/Insights/InsightsPlaceholderView.swift` (skeleton; Task 13 fills)
- Create: `Views/HealthOS/Health/HealthTabView.swift` (skeleton; Task 13 fills)
- Create: `Views/HealthOS/Timeline/TimelineView.swift` (skeleton; Task 8 fills)

**Interfaces:**
- Consumes: Task 5 tokens.
- Produces (used by Task 7): `HealthOSRootView()` — self-contained root view; reads the same environment objects the legacy root uses (none required by the skeleton). `enum HealthOSTab: String, CaseIterable { case home, timeline, insights, health }`.

Design (locked): a CUSTOM bottom bar (not `TabView`) — an `HStack` of 4 tab buttons with a raised 56pt center [+] circle button (accent fill, white symbol, subtle shadow), on a paper-tone bar with a hairline top border. Center button opens `CapturePlaceholderSheet` (medium detent) — honest copy about 1C, styled with the category buttons ghosted. Long-press [+] does the same in 1B (voice arrives in 1D). One-handed reach per spec §7: bar sits at the bottom safe area.

- [ ] **Step 1: Create HealthOSTab.swift**

```swift
import SwiftUI

/// The four content tabs of the Health OS shell. Named distinctly from the
/// legacy `Tab` enums (TabEnum.swift, TabManager.Tab) to avoid collisions.
enum HealthOSTab: String, CaseIterable, Identifiable {
    case home, timeline, insights, health

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Home"
        case .timeline: "Timeline"
        case .insights: "Insights"
        case .health: "Health"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .timeline: "list.bullet.rectangle"
        case .insights: "sparkles"
        case .health: "heart.text.square"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: "house.fill"
        case .timeline: "list.bullet.rectangle.fill"
        case .insights: "sparkles"
        case .health: "heart.text.square.fill"
        }
    }
}
```

- [ ] **Step 2: Create HealthOSTabBar.swift**

```swift
import SwiftUI

/// Custom bottom bar: Home · Timeline · [+] · Insights · Health.
/// The center capture button is raised and always reachable one-handed.
struct HealthOSTabBar: View {
    @Binding var selection: HealthOSTab
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.home)
            tabButton(.timeline)
            captureButton
            tabButton(.insights)
            tabButton(.health)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .background(
            HealthTheme.paper
                .overlay(Rectangle().frame(height: 1).foregroundStyle(HealthTheme.cardBorder), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ tab: HealthOSTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20))
                Text(tab.label)
                    .font(.caption2)
            }
            .foregroundStyle(selection == tab ? HealthTheme.accent : HealthTheme.inkMuted)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
    }

    private var captureButton: some View {
        Button(action: onCapture) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(HealthTheme.accent))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .offset(y: -10)
        .accessibilityLabel("Capture")
        .accessibilityHint("Log a symptom, meal, dose, or note")
    }
}
```

- [ ] **Step 3: Create CapturePlaceholderSheet.swift**

```swift
import SwiftUI

/// 1B placeholder for the smart capture sheet (arrives in Plan 1C; voice in 1D).
/// Honest empty state: shows the shape of what's coming, captures nothing yet.
struct CapturePlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let upcoming: [(icon: String, label: String)] = [
        ("exclamationmark.circle", "Symptom"),
        ("fork.knife", "Meal"),
        ("pills.fill", "Dose"),
        ("camera", "Photo"),
        ("note.text", "Note"),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(HealthTheme.cardBorder).frame(width: 36, height: 5).padding(.top, 8)
            Text("Capture")
                .font(HealthTheme.sectionHeader())
                .foregroundStyle(HealthTheme.ink)
            Text("Logging arrives with the next update. Everything you see in the timeline is already flowing in from Apple Health.")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 16) {
                ForEach(upcoming, id: \.label) { item in
                    VStack(spacing: 6) {
                        Image(systemName: item.icon).font(.system(size: 22))
                        Text(item.label).font(.caption2)
                    }
                    .foregroundStyle(HealthTheme.inkMuted)
                    .frame(width: 60, height: 64)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coming soon: symptom, meal, dose, photo, and note capture")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HealthTheme.paper)
    }
}
```

- [ ] **Step 4: Create the three skeleton tab views**

`Views/HealthOS/Home/HomeView.swift`:

```swift
import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Your day will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
    }
}
```

`Views/HealthOS/Insights/InsightsPlaceholderView.swift`:

```swift
import SwiftUI

struct InsightsPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Insights")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Patterns will appear here once the evidence engine arrives.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
    }
}
```

`Views/HealthOS/Health/HealthTabView.swift`:

```swift
import SwiftUI

struct HealthTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Health")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Cabinet, protocols, labs, and reports will live here.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
    }
}
```

`Views/HealthOS/Timeline/TimelineView.swift` (skeleton; Task 8 replaces the body):

```swift
import SwiftUI

struct TimelineView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Timeline")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Your unified health feed loads here.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
    }
}
```

- [ ] **Step 5: Create HealthOSRootView.swift**

```swift
import SwiftUI

/// Root of the Health OS shell: 4 content tabs + center capture.
/// Replaces MainTabView as the app root (Task 7); the legacy app stays
/// reachable from the Health tab until its features are ported.
struct HealthOSRootView: View {
    @State private var selection: HealthOSTab = .home
    @State private var showingCapture = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tab(.home) { HomeView() }
                tab(.timeline) { TimelineView() }
                tab(.insights) { InsightsPlaceholderView() }
                tab(.health) { HealthTabView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HealthOSTabBar(selection: $selection) { showingCapture = true }
        }
        .background(HealthTheme.paper.ignoresSafeArea())
        .sheet(isPresented: $showingCapture) {
            CapturePlaceholderSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        }
    }

    /// Keeps EVERY tab mounted and toggles visibility, rather than a `switch`
    /// that gives each tab a distinct structural identity — a `switch` tears
    /// the inactive tab down, destroying its `@StateObject` view-model (paging,
    /// filters, search text, scroll position) on every tab change. Mounting all
    /// four preserves that state and makes tab switches instant. Hidden tabs are
    /// non-interactive and hidden from VoiceOver.
    @ViewBuilder
    private func tab<Content: View>(_ which: HealthOSTab,
                                    @ViewBuilder _ content: () -> Content) -> some View {
        let isActive = selection == which
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }
}

#Preview("Shell — light") {
    HealthOSRootView()
}

#Preview("Shell — dark") {
    HealthOSRootView().preferredColorScheme(.dark)
}
```

- [ ] **Step 6: Verify the app builds**

Run:
```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS && git commit -m "feat(app): Health OS shell — custom tab bar with center capture, root view, tab skeletons"
```

---

### Task 7: App — root swap, foreground lifecycle, debug-ingestor fix, legacy gateway

**Files:**
- Modify: `FoodIntolerancesApp.swift`
- Modify: `Views/HealthGraphDebugView.swift`
- Modify: `Views/HealthOS/Health/HealthTabView.swift`
- Modify: `Views/HealthOS/Shell/HealthOSRootView.swift` (Step 3: wrap the Health tab in a `NavigationStack`)

**Interfaces:**
- Consumes: `HealthOSRootView` (Task 6); existing env objects (`healthKitIngestor`, `environmentalService`, `tabManager`, `logItemViewModel`, `healthKitManager`).
- Produces: the app boots into `HealthOSRootView`; legacy `MainTabView` opens full-screen from the Health tab; `EnvironmentalEventEmitter.emitIfNeeded` runs on EVERY foreground (scenePhase), not just first launch; the debug panel uses the app-injected ingestor (1A fix-soon item — observer queries no longer die with the transient debug-view instance).
- **Accepted scope decision (1B):** the legacy onboarding `fullScreenCover` lives in `MainTabView`, so after the root swap it no longer runs at first launch — it now appears only the first time the legacy gateway is opened. This is acceptable for 1B (zero real users); the real Health-OS onboarding ships in 1D. Stated here so it's an explicit decision, not a silent regression.

- [ ] **Step 1: Swap the root view and add the scenePhase hook in FoodIntolerancesApp.swift**

In `FoodIntolerancesApp.swift`:

(a) Add the scene-phase environment property alongside the existing `@StateObject` declarations:

```swift
    @Environment(\.scenePhase) private var scenePhase
```

(b) In `body`, replace `MainTabView()` with `HealthOSRootView()`. KEEP every existing modifier that follows it — `.environmentObject(...)` × 4, the inline `.modelContainer(for: [...])`, `.resetSwiftDataCache()`, `.onAppear` diagnostics, and both `.task` blocks (first-launch observer registration + environmental emit). The legacy views presented from the gateway still consume all of them through the environment.

(c) Attach the foreground hook to the root view, after the existing `.task` modifiers:

```swift
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await EnvironmentalEventEmitter.emitIfNeeded(service: environmentalService) }
            }
```

(`emitIfNeeded` is once-per-day guarded internally — calling it on every foreground is cheap and closes the "app left running overnight" gap where the launch-only `.task` never fires again.)

- [ ] **Step 2: Debug panel uses the injected ingestor**

In `Views/HealthGraphDebugView.swift`, replace:

```swift
    @StateObject private var ingestor = HealthKitIngestor()
```

with:

```swift
    @EnvironmentObject private var ingestor: HealthKitIngestor
```

(The app injects `healthKitIngestor` at the root; sheets and navigation destinations inherit it. This closes the 1A finding: observer queries registered from the debug panel previously lived on a transient instance and died when the view went away.)

- [ ] **Step 3: Add the legacy gateway + debug entry to the Health tab**

Replace the body of `Views/HealthOS/Health/HealthTabView.swift` created in Task 6 with:

```swift
import SwiftUI

struct HealthTabView: View {
    @State private var showingLegacyApp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Health")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Cabinet, protocols, labs, and reports will live here.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)

                VStack(spacing: 0) {
                    Button {
                        showingLegacyApp = true
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(HealthTheme.accent)
                            Text("Open legacy app")
                                .foregroundStyle(HealthTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint("Opens the previous app interface")
                    #if DEBUG
                    Divider().padding(.leading, 16)
                    NavigationLink {
                        HealthGraphDebugView()
                    } label: {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundStyle(HealthTheme.accent)
                            Text("Health Graph Debug")
                                .foregroundStyle(HealthTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    #endif
                }
                .hgCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
        .fullScreenCover(isPresented: $showingLegacyApp) {
            // MainTabView already hosts its OWN NavigationStack (MainTabView.swift).
            // Present it bare — a second NavigationStack would stack an empty nav bar
            // above the legacy chrome. Float a Done control in the top-trailing safe area.
            MainTabView()
                .overlay(alignment: .topTrailing) {
                    Button("Done") { showingLegacyApp = false }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.trailing, 12)
                        .padding(.top, 6)
                        .accessibilityLabel("Close legacy app")
                }
        }
    }
}
```

AND wrap the Health tab's content in a `NavigationStack` so the debug `NavigationLink` works: in `HealthOSRootView` (Task 6 file), change the Health tab line from `tab(.health) { HealthTabView() }` to `tab(.health) { NavigationStack { HealthTabView() } }`.

- [ ] **Step 4: Run the app test suite**

Run:
```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO 2>&1 | tail -12
```
Expected: the documented pattern — everything passes except the ONE known `migratesObjectsFromAvoidedCabinetAndProtocols` crash. UI launch tests must pass against the NEW shell.

- [ ] **Step 5: Manual smoke (simulator)**

Boot the app in the simulator (`xcrun simctl launch` via a build-and-run, or Xcode). Verify: app opens on Home with the new shell; all 4 tabs switch; [+] presents the capture placeholder; Health → "Open legacy app" shows the old MainTabView with working tabs and Done returns; Health → Health Graph Debug opens and its actions render. Report what you saw.

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add FoodIntolerancesApp.swift Views/HealthGraphDebugView.swift Views/HealthOS && git commit -m "feat(app): Health OS shell becomes root; foreground env emit; debug panel uses injected ingestor; legacy gateway"
```

---

### Task 8: App — TimelineViewModel (paging, filters, search, delete/undo) + tests

**Files:**
- Create: `Views/HealthOS/Timeline/TimelineViewModel.swift`
- Test: `Food IntolerancesTests/TimelineViewModelTests.swift` (new)

**Interfaces:**
- Consumes: `EventStore`/`GRDBEventStore`, `TimelineCursor`, `TimelineDay(Builder)`, `searchEvents` (Tasks 2–4), `CategoryFamily` (Task 5).
- Produces (used by Tasks 9, 10, 11):

```swift
enum SourceFilter: String, CaseIterable, Identifiable {
    case appleHealth, importedFile, environment, manual
    var id: String { rawValue }
    var label: String            // "Apple Health", "Imported file", "Environment", "Manual"
    var sources: Set<EventSource>
}
@MainActor final class TimelineViewModel: ObservableObject {
    @Published private(set) var days: [TimelineDay]
    @Published private(set) var isLoading: Bool
    @Published private(set) var hasMore: Bool
    @Published var activeFamilies: Set<CategoryFamily>   // empty = all
    @Published var activeSources: Set<SourceFilter>      // empty = all
    @Published var searchText: String
    @Published private(set) var isSearchActive: Bool
    @Published private(set) var pendingUndo: HealthEvent?
    init(store: any EventStore, timeZone: TimeZone = .current, pageSize: Int = 200)
    func loadInitial() async
    func loadMore() async            // browse mode only; appends next page
    func refresh() async             // pull-to-refresh: reset to newest
    func filtersChanged() async      // reset pagination, reload with filters
    func searchTextChanged() async   // debounced by the VIEW; runs search or exits search mode
    func delete(_ event: HealthEvent) async   // soft delete + arm 5s undo
    func undoDelete() async
    func dismissUndo()
}
```

Semantics (locked):
- **Browse mode**: pages of `pageSize` via `eventsPage(before:limit:categories:sources:)`; category filter = union of `activeFamilies`' `categories` (nil when empty); source filter = union of `activeSources`' `sources` (nil when empty). Days rebuilt from the FULL accumulated slice each page. `hasMore = (returned page count == pageSize)`.
- **Search mode** (`searchText` non-blank): `searchEvents(matching:limit:400)`, then client-side family/source filtering, then day-grouping. `hasMore = false` in search mode. Clearing the text returns to the accumulated browse slice.
- **Delete/undo**: remove from the local slice immediately + `store.softDelete`; `pendingUndo` holds the event for the toast; an internal `Task.sleep(for: .seconds(5))` clears it (cancel the previous timer when re-armed). `undoDelete` → `store.restore(id:)`, re-insert locally (sorted position), rebuild days.
- All members touched by views are `@Published`; the class is `@MainActor`; store calls hop off via `await`.

- [ ] **Step 1: Write the failing tests**

Create `Food IntolerancesTests/TimelineViewModelTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct TimelineViewModelTests {
    private func makeStore() throws -> (AppDatabase, GRDBEventStore) {
        let db = try AppDatabase.inMemory()
        return (db, GRDBEventStore(database: db))
    }
    private func seed(_ store: GRDBEventStore, count: Int, category: EventCategory = .food,
                      source: EventSource = .manual, startingAt: Date = Date(timeIntervalSince1970: 1_750_000_000)) async throws -> [HealthEvent] {
        var events: [HealthEvent] = []
        for i in 0..<count {
            events.append(HealthEvent(timestamp: startingAt.addingTimeInterval(Double(i) * 1800),
                                      category: category, subtype: "item\(i)", source: source,
                                      createdAt: startingAt))
        }
        try await store.save(events)
        return events
    }

    @Test func loadInitialPagesAndGroupsThenLoadMoreAppendsWithoutDupes() async throws {
        let (_, store) = try makeStore()
        _ = try await seed(store, count: 45)
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 20)
        await vm.loadInitial()
        #expect(vm.hasMore)
        let firstCount = vm.days.flatMap(\.events).count
        #expect(firstCount == 20)
        await vm.loadMore()
        await vm.loadMore()
        let ids = vm.days.flatMap(\.events).map(\.id)
        #expect(ids.count == 45)
        #expect(Set(ids).count == 45)
        #expect(!vm.hasMore)
    }

    @Test func familyFilterLimitsCategories() async throws {
        let (_, store) = try makeStore()
        _ = try await seed(store, count: 3, category: .sleep, source: .healthKit)
        _ = try await seed(store, count: 3, category: .food, source: .manual,
                           startingAt: Date(timeIntervalSince1970: 1_750_100_000))
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        vm.activeFamilies = [.sleep]
        await vm.filtersChanged()
        let cats = Set(vm.days.flatMap(\.events).map(\.category))
        #expect(cats == Set([.sleep]))
    }

    @Test func searchModeGroupsMatchesAndClearingReturnsToBrowse() async throws {
        let (_, store) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save([
            HealthEvent(timestamp: base, category: .symptom, subtype: "headache",
                        value: 5, unit: "severity", source: .manual, createdAt: base),
            HealthEvent(timestamp: base.addingTimeInterval(60), category: .food, subtype: "toast",
                        source: .manual, createdAt: base),
        ])
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        await vm.loadInitial()
        vm.searchText = "head"
        await vm.searchTextChanged()
        #expect(vm.isSearchActive)
        #expect(vm.days.flatMap(\.events).map(\.subtype) == ["headache"])
        vm.searchText = ""
        await vm.searchTextChanged()
        #expect(!vm.isSearchActive)
        #expect(vm.days.flatMap(\.events).count == 2)
    }

    @Test func deleteRemovesLocallyAndUndoRestores() async throws {
        let (_, store) = try makeStore()
        let events = try await seed(store, count: 3)
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        await vm.loadInitial()
        let victim = events[1]
        await vm.delete(victim)
        #expect(vm.pendingUndo?.id == victim.id)
        #expect(!vm.days.flatMap(\.events).map(\.id).contains(victim.id))
        // persisted too
        #expect(try await store.eventsPage(before: nil, limit: 10, categories: nil, sources: nil).count == 2)
        await vm.undoDelete()
        #expect(vm.pendingUndo == nil)
        #expect(vm.days.flatMap(\.events).count == 3)
        #expect(try await store.eventsPage(before: nil, limit: 10, categories: nil, sources: nil).count == 3)
    }
}
```

- [ ] **Step 2: Run the app tests to verify they fail**

Run:
```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO -only-testing:"Food IntolerancesTests/TimelineViewModelTests" 2>&1 | tail -5
```
Expected: compile FAILURE — `TimelineViewModel` doesn't exist.

- [ ] **Step 3: Implement TimelineViewModel.swift**

Create `Views/HealthOS/Timeline/TimelineViewModel.swift`:

```swift
import Foundation
import HealthGraphCore
import UIKit   // UIAccessibility.isVoiceOverRunning — extends the undo window under VoiceOver

enum SourceFilter: String, CaseIterable, Identifiable {
    case appleHealth, importedFile, environment, manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleHealth: "Apple Health"
        case .importedFile: "Imported file"
        case .environment: "Environment"
        case .manual: "Manual"
        }
    }

    var sources: Set<EventSource> {
        switch self {
        case .appleHealth: [.healthKit]
        case .importedFile: [.healthExportFile, .labImport, .legacyImport]
        case .environment: [.weatherAPI]
        case .manual: [.manual, .photo, .voice, .appIntent]
        }
    }
}

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published private(set) var days: [TimelineDay] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true
    @Published var activeFamilies: Set<CategoryFamily> = []
    @Published var activeSources: Set<SourceFilter> = []
    @Published var searchText = ""
    @Published private(set) var isSearchActive = false
    @Published private(set) var pendingUndo: HealthEvent?

    private let store: any EventStore
    private let timeZone: TimeZone
    private let pageSize: Int
    private var browseEvents: [HealthEvent] = []
    private var cursor: TimelineCursor?
    private var undoTimer: Task<Void, Never>?

    init(store: any EventStore, timeZone: TimeZone = .current, pageSize: Int = 200) {
        self.store = store
        self.timeZone = timeZone
        self.pageSize = pageSize
    }

    private var categoryFilter: Set<EventCategory>? {
        guard !activeFamilies.isEmpty else { return nil }
        return activeFamilies.reduce(into: Set<EventCategory>()) { $0.formUnion($1.categories) }
    }

    private var sourceFilter: Set<EventSource>? {
        guard !activeSources.isEmpty else { return nil }
        return activeSources.reduce(into: Set<EventSource>()) { $0.formUnion($1.sources) }
    }

    func loadInitial() async {
        guard browseEvents.isEmpty else { return }
        await reloadFromScratch()
    }

    func refresh() async {
        await reloadFromScratch()
    }

    func filtersChanged() async {
        if isSearchActive {
            await runSearch()
        } else {
            await reloadFromScratch()
        }
    }

    func loadMore() async {
        guard !isSearchActive, hasMore, !isLoading else { return }
        await loadPage()
    }

    func searchTextChanged() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isSearchActive = false
            days = TimelineDayBuilder.days(from: browseEvents, timeZone: timeZone)
        } else {
            await runSearch()
        }
    }

    func delete(_ event: HealthEvent) async {
        do {
            try await store.softDelete(id: event.id)
        } catch {
            return // row untouched; keep UI consistent with the store
        }
        browseEvents.removeAll { $0.id == event.id }
        days = days.compactMap { day in
            guard day.events.contains(where: { $0.id == event.id }) else { return day }
            let remaining = day.events.filter { $0.id != event.id }
            guard !remaining.isEmpty else { return nil }
            return TimelineDayBuilder.days(from: remaining, timeZone: timeZone).first
        }
        armUndo(event)
    }

    func undoDelete() async {
        guard let event = pendingUndo else { return }
        undoTimer?.cancel()
        pendingUndo = nil
        do {
            try await store.restore(id: event.id)
        } catch {
            return
        }
        let insertAt = browseEvents.firstIndex {
            ($0.timestamp, $0.id.uuidString) < (event.timestamp, event.id.uuidString)
        } ?? browseEvents.endIndex
        browseEvents.insert(event, at: insertAt)
        if !isSearchActive {
            days = TimelineDayBuilder.days(from: browseEvents, timeZone: timeZone)
        }
    }

    func dismissUndo() {
        undoTimer?.cancel()
        pendingUndo = nil
    }

    // MARK: private

    private func reloadFromScratch() async {
        cursor = nil
        browseEvents = []
        hasMore = true
        await loadPage()
    }

    private func loadPage() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await store.eventsPage(before: cursor, limit: pageSize,
                                                  categories: categoryFilter, sources: sourceFilter)
            if let last = page.last {
                cursor = TimelineCursor(timestamp: last.timestamp, id: last.id)
            }
            hasMore = page.count == pageSize
            browseEvents.append(contentsOf: page)
            days = TimelineDayBuilder.days(from: browseEvents, timeZone: timeZone)
        } catch {
            hasMore = false
        }
    }

    private func runSearch() async {
        isLoading = true
        defer { isLoading = false }
        isSearchActive = true
        do {
            var results = try await store.searchEvents(matching: searchText, limit: 400)
            if let categoryFilter { results = results.filter { categoryFilter.contains($0.category) } }
            if let sourceFilter { results = results.filter { sourceFilter.contains($0.source) } }
            days = TimelineDayBuilder.days(from: results, timeZone: timeZone)
        } catch {
            days = []
        }
    }

    private func armUndo(_ event: HealthEvent) {
        undoTimer?.cancel()
        pendingUndo = event
        // The toast is the ONLY safety net (no confirm dialogs). VoiceOver users
        // need far longer than 5s to reach and activate the Undo action.
        let window: Duration = UIAccessibility.isVoiceOverRunning ? .seconds(20) : .seconds(5)
        undoTimer = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self?.pendingUndo = nil
        }
    }
}
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run the Step 2 command again.
Expected: `TimelineViewModelTests` — 4/4 pass.

- [ ] **Step 5: Run the FULL app suite + package suite (regression)**

```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO 2>&1 | tail -12
cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3
```
Expected: app = documented pattern (only the known SwiftData crash) with 4 new passes; package = 80/80.

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS "Food IntolerancesTests/TimelineViewModelTests.swift" && git commit -m "feat(app): TimelineViewModel — keyset paging, family/source filters, FTS search mode, delete with undo"
```

---

### Task 9: App — Timeline feed UI (day spine, rows, chips, search, empty states)

**Files:**
- Modify: `Views/HealthOS/Timeline/TimelineView.swift` (replace Task 6 skeleton)
- Create: `Views/HealthOS/Timeline/TimelineEventRow.swift`
- Create: `Views/HealthOS/Timeline/TimelineDayHeader.swift`
- Create: `Views/HealthOS/Timeline/TimelineFilterBar.swift`
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Models/HealthEvent.swift` (add `Hashable` — Step 4)

**Interfaces:**
- Consumes: `TimelineViewModel` (Task 8), `HealthTheme`/`CategoryStyle` (Task 5), `EventDisplay`/`TimelineDay` (Task 4), `HealthGraphProvider.shared`.
- Produces: the working Timeline tab. Also (used by Tasks 10, 11): `TimelineDayHeader(day:)` gains the sparkline slot in Task 10; rows call `onTap: (HealthEvent) -> Void` which Task 11 routes to detail.

Layout (locked): screen = serif title, search field (card-styled `TextField`), one horizontal chip row (families then sources, multi-select toggles), then the feed: `ScrollView > LazyVStack(spacing: 0)` — per day: `TimelineDayHeader` then rows. **Day spine**: every row reserves a 20pt leading gutter containing a continuous 1pt vertical hairline (`HealthTheme.cardBorder`); the row's category tick (3pt wide, rounded, `style.color`; height 16pt point events / 28pt duration events) sits centered on the spine. Infinite scroll: a `ProgressView` sentinel at the bottom fires `loadMore()` on appear. Pull-to-refresh via `.refreshable`. Time column: `.footnote` muted, `Date.FormatStyle.dateTime.hour().minute()`.

- [ ] **Step 1: Create TimelineEventRow.swift**

```swift
import SwiftUI
import HealthGraphCore

struct TimelineEventRow: View {
    let event: HealthEvent
    let onTap: (HealthEvent) -> Void

    private var style: CategoryStyle { .style(for: event.category) }
    private var isDuration: Bool { event.endTimestamp != nil }

    var body: some View {
        Button {
            onTap(event)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // day spine gutter + category tick
                ZStack {
                    Rectangle()
                        .fill(HealthTheme.cardBorder)
                        .frame(width: 1)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(style.color)
                        .frame(width: 3, height: isDuration ? 28 : 16)
                }
                .frame(width: 20)
                Image(systemName: style.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(style.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(EventDisplay.title(for: event))
                        .font(.body)
                        .foregroundStyle(HealthTheme.ink)
                        .lineLimit(2)
                    if let line = EventDisplay.valueLine(for: event) {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.inkSecondary)
                    }
                }
                Spacer(minLength: 8)
                Text(event.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
            }
            .padding(.trailing, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Shows event details")
    }

    private var accessibilitySummary: String {
        var parts = [style.family.label, EventDisplay.title(for: event)]
        if let line = EventDisplay.valueLine(for: event) { parts.append(line) }
        parts.append(event.timestamp.formatted(.dateTime.hour().minute()))
        return parts.joined(separator: ", ")
    }
}
```

- [ ] **Step 2: Create TimelineDayHeader.swift**

```swift
import SwiftUI
import HealthGraphCore

struct TimelineDayHeader: View {
    let day: TimelineDay

    var body: some View {
        HStack(spacing: 8) {
            Text(dayTitle)
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .foregroundStyle(HealthTheme.ink)
            // Task 10 replaces this line with `SeveritySparkline(day: day)`.
            Spacer()
            Text("\(day.events.count)")
                .font(.caption)
                .foregroundStyle(HealthTheme.inkMuted)
                .accessibilityLabel("\(day.events.count) events")
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(day.dayStart) { return "Today" }
        if Calendar.current.isDateInYesterday(day.dayStart) { return "Yesterday" }
        return day.dayStart.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
```

- [ ] **Step 3: Create TimelineFilterBar.swift**

```swift
import SwiftUI

struct TimelineFilterBar: View {
    @ObservedObject var viewModel: TimelineViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CategoryFamily.allCases) { family in
                    chip(label: family.label, dotColor: family.color,
                         isOn: viewModel.activeFamilies.contains(family)) {
                        toggle(family: family)
                    }
                }
                Divider().frame(height: 20)
                ForEach(SourceFilter.allCases) { source in
                    chip(label: source.label, dotColor: nil,
                         isOn: viewModel.activeSources.contains(source)) {
                        toggle(source: source)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(label: String, dotColor: Color?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                }
                Text(label).font(.footnote)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(isOn ? HealthTheme.accent.opacity(0.14) : HealthTheme.card))
            .overlay(Capsule().strokeBorder(isOn ? HealthTheme.accent : HealthTheme.cardBorder, lineWidth: 1))
            .foregroundStyle(isOn ? HealthTheme.accent : HealthTheme.inkSecondary)
            .frame(minHeight: 44)          // meet the 44pt tap-target gate…
            .contentShape(Rectangle())     // …with the full band tappable (pill stays compact)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityHint("Filters the timeline")
    }

    private func toggle(family: CategoryFamily) {
        if viewModel.activeFamilies.contains(family) {
            viewModel.activeFamilies.remove(family)
        } else {
            viewModel.activeFamilies.insert(family)
        }
        Task { await viewModel.filtersChanged() }
    }

    private func toggle(source: SourceFilter) {
        if viewModel.activeSources.contains(source) {
            viewModel.activeSources.remove(source)
        } else {
            viewModel.activeSources.insert(source)
        }
        Task { await viewModel.filtersChanged() }
    }
}
```

- [ ] **Step 4: Make `HealthEvent` Hashable (one-line package change)**

`navigationDestination(for: HealthEvent.self)` requires `Hashable`, and a retroactive conformance in the app would be illegal/fragile — it belongs on the type. In `HealthGraphCore/Sources/HealthGraphCore/Models/HealthEvent.swift`, add `Hashable` to the conformance list of the `HealthEvent` declaration (next to `Equatable`; synthesis handles the rest). Then:

```bash
cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3
```
Expected: 80/80 still passing.

- [ ] **Step 5: Replace TimelineView.swift**

```swift
import SwiftUI
import HealthGraphCore

struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel(
        store: GRDBEventStore(database: HealthGraphProvider.shared))
    @State private var searchDebounce: Task<Void, Never>?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 12) {
                header
                TimelineFilterBar(viewModel: viewModel)
                feed
            }
            .background(HealthTheme.paper)
            .navigationDestination(for: HealthEvent.self) { event in
                // Task 11 replaces this with EventDetailView(event:viewModel:)
                Text(EventDisplay.title(for: event))
            }
        }
        .task { await viewModel.loadInitial() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
                .padding(.top, 8)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HealthTheme.inkMuted)
                TextField("Search your history", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.searchText) { _, _ in
                        searchDebounce?.cancel()
                        searchDebounce = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await viewModel.searchTextChanged()
                        }
                    }
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                        Task { await viewModel.searchTextChanged() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(HealthTheme.inkMuted)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .hgCard()
        }
        .padding(.horizontal, 16)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.days.isEmpty && !viewModel.isLoading {
                    emptyState.padding(.top, 60)
                }
                ForEach(viewModel.days) { day in
                    TimelineDayHeader(day: day)
                    ForEach(day.events) { event in
                        TimelineEventRow(event: event) { tapped in
                            path.append(tapped)
                        }
                        .padding(.leading, 16)
                    }
                }
                if viewModel.hasMore && !viewModel.days.isEmpty {
                    ProgressView()
                        .padding(.vertical, 24)
                        .onAppear { Task { await viewModel.loadMore() } }
                }
            }
            .padding(.bottom, 12)
        }
        .refreshable { await viewModel.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.isSearchActive ? "magnifyingglass" : "list.bullet.rectangle")
                .font(.system(size: 32))
                .foregroundStyle(HealthTheme.inkMuted)
            Text(viewModel.isSearchActive
                 ? "Nothing matches that search."
                 : "Your timeline is empty. Connect Apple Health from the Health tab and your data flows in automatically.")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
```

- [ ] **Step 6: Build, then run the full app suite**

```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' 2>&1 | tail -3
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO 2>&1 | tail -8
```
Expected: BUILD SUCCEEDED; app suite = documented pattern.

- [ ] **Step 7: Manual smoke (simulator) — REQUIRED, report findings**

Launch in the simulator. Load the debug panel (Health tab → Health Graph Debug) → "Load synthetic dataset (400 days)". Then open Timeline and verify: day groups render newest-first with the spine + colored ticks; scrolling to the bottom keeps loading pages smoothly; searching "bloat" narrows to bloating symptom events; a family chip (e.g. Food) filters; clearing chips restores; dark mode (simulator appearance toggle) keeps everything legible; Dynamic Type XXL (Settings → Accessibility) doesn't clip rows.

- [ ] **Step 8: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS HealthGraphCore && git commit -m "feat(app): Timeline feed — day spine, category ticks, filter chips, FTS search, infinite scroll"
```

---

### Task 10: App — per-day severity sparkline

**Files:**
- Create: `Views/HealthOS/Timeline/SeveritySparkline.swift`
- Modify: `Views/HealthOS/Timeline/TimelineDayHeader.swift` (mount the sparkline)
- Test: `Food IntolerancesTests/SparklineGeometryTests.swift` (new)

**Interfaces:**
- Consumes: `TimelineDay`/`SeverityPoint` (Task 4), `CategoryFamily.symptoms.color` (Task 5).
- Produces: `SeveritySparkline(day: TimelineDay)` view + `enum SparklineGeometry { static func points(for: [SeverityPoint], dayStart: Date, in size: CGSize) -> [CGPoint] }`.

Spec (dataviz mark rules): 2pt line in the symptoms family color, round caps; a 3pt-radius dot on the LAST point only (selective labeling, not a dot per point); fixed y-domain 0–10 (severity scale is absolute — days must be comparable); x = fraction of the 24h day; renders ONLY when the day has ≥ 2 severity points (a single point is not a trend). The mark is decorative reinforcement, never the sole channel: the VoiceOver label carries the numbers.

- [ ] **Step 1: Write the failing geometry test**

Create `Food IntolerancesTests/SparklineGeometryTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

struct SparklineGeometryTests {
    @Test func mapsTimeOfDayToXAndSeverityToInvertedY() {
        let dayStart = Date(timeIntervalSince1970: 1_750_032_000)
        let noon = dayStart.addingTimeInterval(12 * 3600)
        let points = [
            SeverityPoint(time: dayStart, value: 0),     // x=0, y=bottom
            SeverityPoint(time: noon, value: 5),          // x=mid, y=middle
            SeverityPoint(time: dayStart.addingTimeInterval(86_400), value: 10), // x=end, y=top
        ]
        let mapped = SparklineGeometry.points(for: points, dayStart: dayStart,
                                              in: CGSize(width: 100, height: 20))
        #expect(mapped[0] == CGPoint(x: 0, y: 20))
        #expect(mapped[1] == CGPoint(x: 50, y: 10))
        #expect(mapped[2] == CGPoint(x: 100, y: 0))
    }

    @Test func clampsOutOfDayTimesIntoBounds() {
        let dayStart = Date(timeIntervalSince1970: 1_750_032_000)
        let after = SeverityPoint(time: dayStart.addingTimeInterval(90_000), value: 12)
        let mapped = SparklineGeometry.points(for: [after], dayStart: dayStart,
                                              in: CGSize(width: 100, height: 20))
        #expect(mapped[0].x == 100)   // clamped to day end
        #expect(mapped[0].y == 0)     // clamped to max severity
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO -only-testing:"Food IntolerancesTests/SparklineGeometryTests" 2>&1 | tail -5
```
Expected: compile FAILURE (`SparklineGeometry` missing).

- [ ] **Step 3: Implement SeveritySparkline.swift**

```swift
import SwiftUI
import HealthGraphCore

enum SparklineGeometry {
    /// Maps severity points into view coordinates: x = fraction of the 24h day,
    /// y = severity 0–10 inverted (10 at the top). Out-of-range inputs clamp.
    static func points(for points: [SeverityPoint], dayStart: Date, in size: CGSize) -> [CGPoint] {
        points.map { p in
            let dayFraction = min(max(p.time.timeIntervalSince(dayStart) / 86_400, 0), 1)
            let severityFraction = min(max(p.value / 10, 0), 1)
            return CGPoint(x: size.width * dayFraction,
                           y: size.height * (1 - severityFraction))
        }
    }
}

/// Inline per-day severity trend. Renders only for days with >= 2 rated
/// symptom events; the accessibility label carries the actual numbers.
struct SeveritySparkline: View {
    let day: TimelineDay

    var body: some View {
        if day.severityPoints.count >= 2 {
            Canvas { context, size in
                let pts = SparklineGeometry.points(for: day.severityPoints,
                                                   dayStart: day.dayStart, in: size)
                var path = Path()
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.addLine(to: p) }
                let color = CategoryFamily.symptoms.color
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3,
                                                        width: 6, height: 6)),
                                 with: .color(color))
                }
            }
            .frame(width: 64, height: 16)
            .accessibilityLabel(summary)
        }
    }

    private var summary: String {
        let values = day.severityPoints.map(\.value)
        let peak = values.max() ?? 0
        return "\(values.count) rated symptoms, severity \(Int(values.min() ?? 0)) to \(Int(peak))"
    }
}
```

- [ ] **Step 4: Mount it in TimelineDayHeader**

In `TimelineDayHeader.swift`, replace the marker comment line `// Task 10 replaces this line with \`SeveritySparkline(day: day)\`.` (it sits between `Text(dayTitle)` and `Spacer()`) with:

```swift
            SeveritySparkline(day: day)
```

(SwiftUI renders nothing when the guard inside fails — no conditional needed at the call site.)

- [ ] **Step 5: Run the geometry tests, then build**

Run the Step 2 command → 2/2 pass. Then:
```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS "Food IntolerancesTests/SparklineGeometryTests.swift" && git commit -m "feat(app): per-day severity sparkline in timeline day headers"
```

---

### Task 11: App — event detail + soft delete with undo toast

**Files:**
- Create: `Views/HealthOS/Timeline/EventDetailView.swift`
- Modify: `Views/HealthOS/Timeline/TimelineView.swift` (route destination; mount the undo toast)

**Interfaces:**
- Consumes: `TimelineViewModel.delete/undoDelete/dismissUndo/pendingUndo` (Task 8), `EventDisplay` (Task 4), tokens (Task 5).
- Produces: `EventDetailView(event: HealthEvent, viewModel: TimelineViewModel)`.

Behavior (locked): detail shows what/when/source/details/created; **Delete** is a destructive-styled button that calls `viewModel.delete(event)` and dismisses — NO confirmation dialog (spec §7: undo, never confirm). The undo toast lives in `TimelineView` as a bottom overlay whenever `pendingUndo != nil`: "Event deleted — Undo" (button). Editing is explicitly deferred: a quiet footnote "Editing arrives with capture, in the next update." Imported events state their provenance ("From Apple Health"); parse confidence renders only when `< 1` (all 1A imports are 1.0; voice/photo captures later will vary).

- [ ] **Step 1: Create EventDetailView.swift**

```swift
import SwiftUI
import HealthGraphCore

struct EventDetailView: View {
    let event: HealthEvent
    @ObservedObject var viewModel: TimelineViewModel
    @Environment(\.dismiss) private var dismiss

    private var style: CategoryStyle { .style(for: event.category) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                whenCard
                sourceCard
                if !metadataRows.isEmpty { detailsCard }
                deleteButton
                Text("Editing arrives with capture, in the next update.")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(16)
        }
        .background(HealthTheme.paper)
        .navigationTitle(EventDisplay.title(for: event))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: style.icon)
                .font(.system(size: 24))
                .foregroundStyle(style.color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(style.color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(EventDisplay.title(for: event))
                    .font(HealthTheme.sectionHeader())
                    .foregroundStyle(HealthTheme.ink)
                HStack(spacing: 6) {
                    Circle().fill(style.color).frame(width: 8, height: 8)
                    Text(style.family.label)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkSecondary)
                    if let line = EventDisplay.valueLine(for: event) {
                        Text("·").foregroundStyle(HealthTheme.inkMuted)
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.inkSecondary)
                    }
                }
            }
        }
    }

    private var whenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Time", event.timestamp.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
            if let end = event.endTimestamp {
                row("Until", end.formatted(.dateTime.hour().minute()))
            }
            if event.timezoneID != TimeZone.current.identifier {
                row("Time zone", event.timezoneID)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Source", sourceLabel)
            if event.confidence < 1 {
                row("Parse confidence", event.confidence.formatted(.percent.precision(.fractionLength(0))))
            }
            row("Added", event.createdAt.formatted(.dateTime.month().day().year()))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(metadataRows, id: \.0) { key, value in
                row(key, value)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            let target = event
            Task {
                await viewModel.delete(target)
            }
            dismiss()
        } label: {
            Text("Delete event")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Removes the event. You can undo for a few seconds afterwards.")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(HealthTheme.ink)
            Spacer(minLength: 0)
        }
    }

    private var sourceLabel: String {
        switch event.source {
        case .healthKit: "Apple Health"
        case .healthExportFile: "Apple Health export file"
        case .weatherAPI: "Environment service"
        case .manual: "Manual entry"
        case .photo: "Photo capture"
        case .voice: "Voice capture"
        case .labImport: "Lab import"
        case .appIntent: "Siri / Shortcut"
        case .legacyImport: "Migrated from the previous app"
        }
    }

    private var metadataRows: [(String, String)] {
        guard let data = event.metadata,
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [] }
        let labels = ["kcal": "Calories", "distanceKm": "Distance (km)",
                      "phase": "Moon phase", "season": "Season"]
        return dict.sorted { $0.key < $1.key }
            .map { (labels[$0.key] ?? $0.key, $0.value) }
    }
}
```

- [ ] **Step 2: Route the navigation destination and mount the undo toast**

In `TimelineView.swift`:

(a) Replace the placeholder destination:

```swift
            .navigationDestination(for: HealthEvent.self) { event in
                EventDetailView(event: event, viewModel: viewModel)
            }
```

(b) Add the toast overlay to the outer `VStack` (attach after `.background(HealthTheme.paper)`):

```swift
            .overlay(alignment: .bottom) {
                if let pending = viewModel.pendingUndo {
                    HStack(spacing: 12) {
                        Text("Event deleted")
                            .font(.subheadline)
                            .foregroundStyle(HealthTheme.ink)
                        Button("Undo") {
                            Task { await viewModel.undoDelete() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HealthTheme.accent)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .hgCard()
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Event deleted")
                    .accessibilityAction(named: "Undo") { Task { await viewModel.undoDelete() } }
                    .id(pending.id)
                }
            }
            .animation(.easeOut(duration: 0.2), value: viewModel.pendingUndo)
```

- [ ] **Step 3: Build + full app suite**

```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO 2>&1 | tail -8
```
Expected: documented pattern (only the known crash).

- [ ] **Step 4: Manual smoke (simulator) — REQUIRED**

With synthetic data loaded: tap a timeline row → detail renders every card; Delete → returns to feed, row gone, toast shows; Undo → row back in place; let the toast time out (5s) on a second delete → toast clears itself; deleted event stays gone after an app relaunch.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS && git commit -m "feat(app): event detail with provenance; soft delete with undo toast (no confirm dialogs)"
```

---

### Task 12: App — minimal live Home

**Files:**
- Modify: `Views/HealthOS/Home/HomeView.swift` (replace skeleton)
- Create: `Views/HealthOS/Home/HomeViewModel.swift`
- Test: `Food IntolerancesTests/HomeViewModelTests.swift` (new)

**Interfaces:**
- Consumes: `EventStore.events(in:category:)`, `countsByCategory()` (Phase 0), `EventDisplay.durationString` (Task 4), tokens (Task 5).
- Produces: the live Home tab (greeting + passive strip + backfill summary card + quiet what's-next section).

Semantics (locked):
- **Sleep, last night**: `events(in: DateInterval(start: yesterday 18:00 local, end: today 12:00 local), category: .sleep)`, sum `value` (minutes) over subtypes `asleepCore/asleepDeep/asleepREM/asleepUnspecified` (NOT `inBed`/`awake`) → `EventDisplay.durationString`. Nil when empty → strip shows "—" with "no sleep data yet".
- **Steps, today**: `events(in: today local day, category: .exercise)` first event with `subtype == "steps"` → grouped integer. Nil → "—".
- **Backfill summary card** (spec §2 Home: "first-week only"): shown when total event count > 0 AND NOT dismissed AND still within 7 days of first Home appearance. Content from `countsByCategory()`: "Your history is in." + "N events across M categories — you're not starting from zero." (NO claim of an engine that reads it — that arrives in Phase 2; honesty rule) + dismiss (xmark) sets `hg.home.backfillCardDismissed`. First-seen date persisted under `hg.home.backfillFirstSeen`; the card auto-expires after 7 days even if never dismissed. No causal language, no percentages.
- Refresh on `.task` and `.refreshable`.

- [ ] **Step 1: Write the failing tests**

Create `Food IntolerancesTests/HomeViewModelTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct HomeViewModelTests {
    @Test func sumsAsleepStagesAcrossMidnightAndSkipsInBed() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let tz = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let todayNoon = cal.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let lastNight = cal.startOfDay(for: Date()).addingTimeInterval(-2 * 3600) // 22:00 yesterday
        try await store.save([
            HealthEvent(timestamp: lastNight, endTimestamp: lastNight.addingTimeInterval(4 * 3600),
                        category: .sleep, subtype: "asleepCore", value: 240, unit: "min",
                        source: .healthKit, createdAt: lastNight),
            HealthEvent(timestamp: lastNight.addingTimeInterval(4 * 3600),
                        endTimestamp: lastNight.addingTimeInterval(6 * 3600),
                        category: .sleep, subtype: "asleepREM", value: 120, unit: "min",
                        source: .healthKit, createdAt: lastNight),
            HealthEvent(timestamp: lastNight, endTimestamp: lastNight.addingTimeInterval(8 * 3600),
                        category: .sleep, subtype: "inBed", value: 480, unit: "min",
                        source: .healthKit, createdAt: lastNight),
        ])
        let vm = HomeViewModel(store: store, timeZone: tz, now: { todayNoon })
        await vm.refresh()
        #expect(vm.sleepSummary == "6h")          // 240 + 120 min; inBed excluded
    }

    @Test func readsTodaysStepsDailyStat() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let tz = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let today = cal.startOfDay(for: Date())
        try await store.save(HealthEvent(timestamp: today, endTimestamp: today.addingTimeInterval(86_400),
                                         category: .exercise, subtype: "steps", value: 8214,
                                         unit: "count", source: .healthKit, createdAt: today))
        let vm = HomeViewModel(store: store, timeZone: tz, now: { today.addingTimeInterval(13 * 3600) })
        await vm.refresh()
        #expect(vm.stepsSummary == "8,214")
        #expect(vm.sleepSummary == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO -only-testing:"Food IntolerancesTests/HomeViewModelTests" 2>&1 | tail -5
```
Expected: compile FAILURE (`HomeViewModel` missing).

- [ ] **Step 3: Implement HomeViewModel.swift**

```swift
import Foundation
import HealthGraphCore

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var sleepSummary: String?
    @Published private(set) var stepsSummary: String?
    @Published private(set) var backfillSummary: (events: Int, categories: Int)?

    private let store: any EventStore
    private let timeZone: TimeZone
    private let now: () -> Date
    private static let dismissKey = "hg.home.backfillCardDismissed"
    private static let firstSeenKey = "hg.home.backfillFirstSeen"

    init(store: any EventStore, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.timeZone = timeZone
        self.now = now
    }

    func refresh() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now())

        // Sleep: 18:00 yesterday -> 12:00 today, asleep stages only.
        let sleepWindow = DateInterval(start: today.addingTimeInterval(-6 * 3600),
                                       end: today.addingTimeInterval(12 * 3600))
        let asleep: Set<String> = ["asleepCore", "asleepDeep", "asleepREM", "asleepUnspecified"]
        if let sleepEvents = try? await store.events(in: sleepWindow, category: .sleep) {
            let minutes = sleepEvents
                .filter { asleep.contains($0.subtype ?? "") }
                .compactMap(\.value)
                .reduce(0, +)
            sleepSummary = minutes > 0 ? EventDisplay.durationString(minutes: minutes) : nil
        }

        // Steps: today's daily stat.
        let dayWindow = DateInterval(start: today, end: today.addingTimeInterval(86_400))
        if let exercise = try? await store.events(in: dayWindow, category: .exercise),
           let steps = exercise.first(where: { $0.subtype == "steps" })?.value {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            // Deterministic grouping regardless of locale (tests assert "8,214").
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.usesGroupingSeparator = true
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            stepsSummary = formatter.string(from: NSNumber(value: Int(steps)))
        } else {
            stepsSummary = nil
        }

        // Backfill summary card: first-week-only welcome (spec §2), dismissible.
        let defaults = UserDefaults.standard
        let firstSeen = (defaults.object(forKey: Self.firstSeenKey) as? Date) ?? {
            let stamp = now()
            defaults.set(stamp, forKey: Self.firstSeenKey)
            return stamp
        }()
        let withinFirstWeek = now().timeIntervalSince(firstSeen) < 7 * 86_400
        if !defaults.bool(forKey: Self.dismissKey), withinFirstWeek,
           let counts = try? await store.countsByCategory() {
            let total = counts.values.reduce(0, +)
            backfillSummary = total > 0 ? (total, counts.filter { $0.value > 0 }.count) : nil
        } else {
            backfillSummary = nil
        }
    }

    func dismissBackfillCard() {
        UserDefaults.standard.set(true, forKey: Self.dismissKey)
        backfillSummary = nil
    }
}
```

- [ ] **Step 4: Replace HomeView.swift**

```swift
import SwiftUI
import HealthGraphCore

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel(
        store: GRDBEventStore(database: HealthGraphProvider.shared))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                greeting
                passiveStrip
                if let summary = viewModel.backfillSummary {
                    backfillCard(summary)
                }
                whatsNext
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
            Text(timeOfDayGreeting)
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
        }
        .padding(.top, 8)
    }

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var passiveStrip: some View {
        HStack(spacing: 0) {
            stat(icon: "moon.zzz.fill", color: CategoryFamily.sleep.color,
                 value: viewModel.sleepSummary ?? "—", label: "last night")
            Divider().padding(.vertical, 8)
            stat(icon: "figure.run", color: CategoryFamily.movement.color,
                 value: viewModel.stepsSummary ?? "—", label: "steps today")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .hgCard()
    }

    private func stat(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HealthTheme.ink)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(HealthTheme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func backfillCard(_ summary: (events: Int, categories: Int)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your history is in.")
                    .font(HealthTheme.sectionHeader())
                    .foregroundStyle(HealthTheme.ink)
                Text("\(summary.events.formatted()) events across \(summary.categories) categories — you're not starting from zero.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            Spacer()
            Button {
                viewModel.dismissBackfillCard()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(16)
        .hgCard()
    }

    private var whatsNext: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's next")
                .font(HealthTheme.sectionHeader())
                .foregroundStyle(HealthTheme.ink)
            Text("Capture and insights arrive in the next updates. Meanwhile, your timeline is filling itself.")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
        }
        .padding(.top, 8)
    }
}
```

- [ ] **Step 5: Run the new tests + full suites**

Step 2 command → 2/2 pass. Then the full app suite (documented pattern) and `swift test` (80/80).

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS "Food IntolerancesTests/HomeViewModelTests.swift" && git commit -m "feat(app): minimal live Home — sleep/steps passive strip, backfill summary card"
```

---

### Task 13: App — Insights placeholder with live coverage + Health tab hub

**Files:**
- Modify: `Views/HealthOS/Insights/InsightsPlaceholderView.swift` (replace skeleton)
- Modify: `Views/HealthOS/Health/HealthTabView.swift` (add the "coming" rows above the gateway card)

**Interfaces:**
- Consumes: `countsByCategory()` (Phase 0), `CategoryFamily` (Task 5).
- Produces: final 1B content for both tabs.

Insights (locked copy — descriptive, zero causal language): serif title; card "The engine isn't watching yet — but your data is ready." with per-family coverage rows (family dot + label + grouped count), families with 0 events at the bottom grayed; footer line "When the evidence engine arrives, patterns will appear here with the observations behind them." Every count row VoiceOver-labeled.

Health tab: above the Task 7 card, a "Coming here" card with five ghosted rows (icon + name + one-line description): Cabinet ("meds, supplements, peptides — stock and refills"), Protocols & experiments ("adherence and outcomes"), Labs ("trends per analyte, imports"), Health confidence ("how complete your data is"), Doctor report ("a PDF your practitioner can actually read"). Ghosted = `HealthTheme.inkMuted` foreground, no chevron, not tappable, `.accessibilityLabel("<name>, coming soon")`.

- [ ] **Step 1: Implement both views** (full code below — replace the bodies)

`InsightsPlaceholderView.swift`:

```swift
import SwiftUI
import HealthGraphCore

struct InsightsPlaceholderView: View {
    @State private var familyCounts: [(family: CategoryFamily, count: Int)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Insights")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("The engine isn't watching yet — but your data is ready.")
                        .font(HealthTheme.sectionHeader())
                        .foregroundStyle(HealthTheme.ink)
                    ForEach(familyCounts, id: \.family) { entry in
                        HStack(spacing: 8) {
                            Circle().fill(entry.count > 0 ? entry.family.color : HealthTheme.dotMiss)
                                .frame(width: 10, height: 10)
                            Text(entry.family.label)
                                .font(.subheadline)
                                .foregroundStyle(entry.count > 0 ? HealthTheme.ink : HealthTheme.inkMuted)
                            Spacer()
                            Text(entry.count > 0 ? entry.count.formatted() : "none yet")
                                .font(.subheadline)
                                .foregroundStyle(HealthTheme.inkSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(entry.family.label): \(entry.count) events")
                    }
                    Text("When the evidence engine arrives, patterns will appear here with the observations behind them.")
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkMuted)
                        .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hgCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
        .task { await loadCounts() }
    }

    private func loadCounts() async {
        let store = GRDBEventStore(database: HealthGraphProvider.shared)
        guard let raw = try? await store.countsByCategory() else { return }
        let counts = raw.reduce(into: [CategoryFamily: Int]()) { acc, pair in
            guard let category = EventCategory(rawValue: pair.key) else { return }
            acc[CategoryStyle.style(for: category).family, default: 0] += pair.value
        }
        familyCounts = CategoryFamily.allCases
            .map { (family: $0, count: counts[$0] ?? 0) }
            .sorted { ($0.count > 0 ? 0 : 1, $0.family.rawValue) < ($1.count > 0 ? 0 : 1, $1.family.rawValue) }
    }
}
```

`HealthTabView.swift` — insert a "Coming here" card between the intro `Text` and the gateway card:

```swift
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(comingRows, id: \.name) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.body)
                                Text(item.detail).font(.caption)
                            }
                            Spacer()
                            Text("Soon").font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(HealthTheme.dotMiss.opacity(0.4)))
                        }
                        .foregroundStyle(HealthTheme.inkMuted)
                        .padding(16)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.name), coming soon")
                        if item.name != comingRows.last?.name {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .hgCard()
```

with this property on the struct:

```swift
    private let comingRows: [(icon: String, name: String, detail: String)] = [
        ("cabinet", "Cabinet", "meds, supplements, peptides — stock and refills"),
        ("checklist", "Protocols & experiments", "adherence and outcomes"),
        ("testtube.2", "Labs", "trends per analyte, imports"),
        ("chart.bar", "Health confidence", "how complete your data is"),
        ("doc.text", "Doctor report", "a PDF your practitioner can actually read"),
    ]
```

- [ ] **Step 2: Build + manual smoke**

Build (expect SUCCEEDED). In the simulator with synthetic data: Insights shows real per-family counts with food/symptoms populated; Health shows the coming rows ghosted above the working gateway/debug card; VoiceOver reads "Cabinet, coming soon".

- [ ] **Step 3: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS && git commit -m "feat(app): Insights coverage placeholder; Health tab hub with coming rows"
```

---

### Task 14: Whole-branch verification + human checkpoint

**Files:** none (verification only).

- [ ] **Step 1: Full suites, exact counts**

```bash
cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO 2>&1 | tail -12
```
Expected: package **80 tests / 12 suites** all passing; app suite = prior tests + TimelineViewModelTests (4) + SparklineGeometryTests (2) + HomeViewModelTests (2), with exactly the ONE documented SwiftData crash. Report per-test numbers.

- [ ] **Step 2: Done-criteria walk (report each)**

1. App boots into the new shell; all four tabs + capture placeholder work.
2. Timeline renders real ingested data day-grouped with spine + ticks; infinite scroll works; pull-to-refresh works.
3. Filter chips (families + sources) narrow the feed server-side; search narrows via FTS; both compose.
4. Severity sparkline appears on days with ≥2 rated symptoms; VoiceOver label present.
5. Event detail shows provenance; delete works with undo toast; no confirm dialogs anywhere.
6. Home shows real last-night sleep + today steps + dismissible backfill card.
7. Insights/Health placeholders honest and live where promised.
8. Legacy app fully reachable and functional via the gateway; debug panel works from the Health tab and uses the injected ingestor.
9. Both appearance modes legible; XXL Dynamic Type survives on ALL five new surfaces (Timeline, Home, Insights, Health hub, capture placeholder) plus event detail — no clipping; VoiceOver labels on rows/chips/stats and an activatable Undo action on the toast.
10. No causal language anywhere in new copy; no health values in logs.
11. Cold-launch time into the new shell is subjectively instant on Leo's device (product spec §17 budget: < 1.5s) — flag if the root swap regressed it.

- [ ] **Step 3: HUMAN CHECKPOINT — hand to Leo for on-device verification**

Build to Leo's iPhone. Ask him to check, on his real ~136k event graph (all sources; the Timeline pages over the full graph, not just the ~36k HealthKit slice): cold-launch feel (should be near-instant — the root view changed this phase); Timeline scroll smoothness (deep scroll into weeks past — if it degrades, the O(n) full-slice day rebuild in Task 8 is the prime suspect, see Carried forward); search latency; delete/undo on a real event (including the longer VoiceOver undo window); dark mode at night; the shell feel one-handed; and that live HealthKit ingestion + environmental emit still deliver next morning. Findings feed fixes before merge (1A precedent: fix loops from checkpoint rounds).

- [ ] **Step 4: Dispatch the whole-branch review** (controller does this per subagent-driven-development.)

## Carried forward (NOT this plan)

- Capture sheet becomes real in Plan 1C (this plan ships the placeholder); FTS index extends to user-typed text (notes, meals, object names) in 1C alongside capture; `eraseDatabaseOnSchemaChange` removal stays scheduled for 1C.
- Voice capture, App Intents, onboarding, chunked/resumable off-main export import: Plan 1D (hard requirement recorded from the 1A checkpoint).
- Legacy screen ports (cabinet → Health tab, trends → Insights, etc.) land feature-by-feature in 1C/1D; the gateway row is removed when the last feature ports.
- MoreView "Import/Export" no-op stub and the duplicated Info.plist HealthKit usage-string sources (pbxproj INFOPLIST_KEY_* vs Info.plist) — flag for the 1D/Phase 6 hygiene pass.
- 1A fix-soon items NOT covered here (export daily-stat unit conversion honesty, T7 attribute-missing counter, T11 temp-file cleanup, error-log levels on observer paths): triage into 1C's hardening task.

Deferred from 1B by the three-lens audit (2026-07-07), each with rationale:
- **"Every number tappable to see its source" (UI spec §7)** — deferred. In 1B the numbers (Home sleep/steps, backfill count, Insights family counts) have no provenance layer to drill into yet; "where it came from" resolves to the Timeline, which is already a top-level tab. Real tap-to-source lands when numbers carry evidence provenance (Phase 2) — wiring it now would force hoisting `TimelineViewModel` to the shell and cross-tab filter injection, out of scope for 1B.
- **Severity filter chip (UI spec §2 lists category/severity/source)** — deferred to 1C. 1B ships category-family + source chips. Rated-symptom data exists today, but a "Rated ≥ N" control is capture-era UX and pairs better with the 1C symptom-capture surface. Named here so it's an explicit deferral, not a silent drop.
- **External-content FTS5 rowid stability under `VACUUM`** — `health_events` has a BLOB PK (no INTEGER alias), so a future `VACUUM` could renumber rowids and desync the FTS index. Nothing vacuums today; add a rebuild-or-avoid note to the 1C hardening pass.
- **Number/unit formatting is pinned to en_US** in 1B (`EventDisplay.grouped`, Home steps → comma grouping; metric-only kg/hPa). Locale-aware grouping AND the metric/imperial user preference (product spec §17) arrive with a Profile/Settings surface (1C/later i18n pass).
- **Timeline day rebuild is O(n) per page** (`TimelineDayBuilder.days` over the full accumulated slice each page/mutation, on `@MainActor`). Fine at Leo's ~136k full graph and the pageSize-200 cadence; if Task 14's deep-scroll checkpoint shows jank, the fallback is incremental day-append (build only the new page's days and merge the boundary day). Noted, not pre-optimized.
- **UI spec amendment** — the frozen 8-family CVD-validated palette (and consequent family-level filter chips) supersedes §6's literal "one hue per category" and resolves §8's "color-blind-safe palette" open item. Fold this back into `2026-07-04-ui-design.md` as an amendment when the spec is next touched.
