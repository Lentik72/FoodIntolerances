# Phase 1C: Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the center **[+]** real — a fast, chip-first capture sheet that logs symptoms, meals, doses (medication/supplement/peptide), and notes directly into the HealthGraphCore event graph, plus edit-in-detail for existing events, FTS search over user-typed text, and the migration/hardening cleanups that live capture requires.

**Architecture:** All pure capture logic (write conventions, find-or-create-object + linked-event composition, chip ranking, symptom catalog, FTS-v4 object search) lives in `HealthGraphCore` under `swift test`. The app contributes SwiftUI only: a real capture sheet under `Views/HealthOS/Capture/`, an edit path on `EventDetailView`, a small shared refresh coordinator so a capture writes-through to the mounted Timeline/Home tabs, and an `onAccent` design token. Manual capture writes via `GRDBEventStore.save` with `dedupKey = nil` (bypassing `IngestPipeline` — dedup is import-only). Removing `eraseDatabaseOnSchemaChange` makes the graph the source of truth, so migrations become strictly append-only from here on.

**Tech Stack:** Swift (language mode 5), SwiftUI (iOS 26 SDK), GRDB 7 (FTS5), Swift Testing, existing HealthGraphCore stack (`EventStore`/`ObjectStore`, `AppDatabase` migrator).

## Global Constraints

- Repo root: `/Users/leo/Desktop/FoodIntolerances`. App project: `Food Intolerances.xcodeproj` (note the space). Scheme: `Food Intolerances`. Deployment floor **iOS 26.0**.
- App build/test destination: iPhone 17 / iOS 26.5 simulator — `-destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF'`.
- App test runs MUST pass `-parallel-testing-enabled NO`. Known pre-existing issue (documented in `SwiftDataMigratorTests.swift`): `migratesObjectsFromAvoidedCabinetAndProtocols` crashes the test process inside Apple's SwiftData teardown. Expected app-suite result: that ONE test crashes, everything else passes. Report per-test results, never a bare "TEST FAILED".
- App-target test module is `Food_Intolerances` (underscore). New app tests live under `Food IntolerancesTests/` (folder has a space) and `@testable import Food_Intolerances`. Package tests live under `HealthGraphCore/Tests/HealthGraphCoreTests/` and `@testable import HealthGraphCore`.
- Package tests: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test`. Suite entering this plan: **80 tests / 12 suites**. Swift Testing: plain `struct XTests {}` (no `@Suite`), `@Test func … async throws`, `#expect(...)`, in-memory DB via `try AppDatabase.inMemory()`. Use deterministic dates (`Date(timeIntervalSince1970: 1_750_000_000)`) and pass explicit `createdAt` where a test round-trips through GRDB.
- **Migrations are APPEND-ONLY and IMMUTABLE.** This plan removes `eraseDatabaseOnSchemaChange` (Task 5). After that, NEVER edit a shipped migration body (`v1`/`v2`/`v3`) — GRDB does not checksum bodies, so editing one silently drifts the schema on existing installs. Every schema change is a new numbered migration. This plan adds only `v4`.
- **Manual capture bypasses dedup.** Capture writes a `HealthEvent` with `dedupKey = nil` via `GRDBEventStore.save` (NOT `IngestPipeline.ingest`). `dedupKey == nil` events are exempt from the partial unique index and never collide — this is the intended, existing behavior for manual/legacy entries.
- **Soft delete only** (unchanged from 1B): product code never hard-deletes `health_events`; every read filters `deletedAt IS NULL`. Undo restores. Editing an event = re-`save` the mutated struct with the same `id` (upsert; the FTS `_au` trigger resyncs the index).
- **No user-facing causal language** anywhere. Capture/edit copy is descriptive.
- **Design tokens are law:** every color from `HealthTheme` / `CategoryStyle`. This plan ADDS `HealthTheme.onAccent` (Task 6) — content drawn on the accent fill uses it; no more hardcoded `.white`.
- **Accessibility is a merge gate:** Dynamic Type (semantic text styles, test at XXL), VoiceOver labels on every interactive element, tap targets ≥ 44pt, color never the only channel (every category mark ships with icon + text).
- **Severity scale is 1–10** (the graph convention the 1B sparkline/`EventDisplay` already assume: `unit == "severity"`, `value` 1–10, domain 0–10). The legacy 1–5 scale is NOT used.
- **Privacy:** never log health values, subtypes, names, or note text. Log counts/categories only.
- Verification commands pipe through `| tail` for brevity. On ANY failure, rerun without `| tail`.
- New app files go under `Views/` (fileSystemSynchronizedGroups — auto-join the target, no pbxproj edits). New package files go under `HealthGraphCore/Sources/HealthGraphCore/`. Create no repo-root files.
- Commit after every task with the message given in its final step.

## Capture conventions (frozen — do not re-derive)

How each capture type becomes a `HealthEvent` (+ optional `HealthObject`). `source: .manual`, `dedupKey: nil`, `timestamp` = the user-chosen time (default now), `confidence: 1.0` for all manual capture.

| Type | `category` | `subtype` | `value` / `unit` | `objectID` | `metadata` |
|---|---|---|---|---|---|
| Symptom | `.symptom` | canonical symptom key (camelCase, e.g. `"headache"`) | severity 1–10 / `"severity"` (nil value = present-unrated) | nil | nil (or `{"note":…}` when the user adds a note) |
| Meal | `.food` | food name as typed (free text, e.g. `"oat milk latte"`) | nil / nil | `.food` object (find-or-create by name) | nil |
| Dose | `.medication` \| `.supplement` \| `.peptide` | substance name as typed | amount / unit (`"mg"`,`"mcg"`,`"iu"`,`"ml"`,`"tablet"`,`"capsule"`,`"drop"`,`"spray"`) | matching-kind object (find-or-create) | `{"route":…}` when set |
| Note | `.note` | the note text (free text — this is what FTS indexes and what `EventDisplay` renders) | nil / nil | nil | nil |

Notes on the conventions:
- **Searchability is free for subtype.** v3 FTS already indexes `subtype`, so meal names, note text, and dose substance names are searchable the moment they're written. Task 4 adds v4 only to also search by **object name** (so "vitamin d" finds every dose linked to that object even when the typed subtype differs).
- **Symptom keys are canonical.** The capture UI maps a display name ("Headache") to a canonical camelCase key ("headache") so severity series and future dedup group correctly. `EventDisplay.title` already reverses this for display.
- **Find-or-create is idempotent.** Logging "Magnesium" twice reuses the one `.supplement` object (`ObjectStore.findOrCreate` keys on `(normalizedName, kind)`).

## Refresh architecture (frozen)

The keep-alive shell mounts all four tabs, and the capture sheet is presented from `HealthOSRootView` with no reference to the tabs' private `@StateObject` view-models. A capture must write-through to the visible feed. Solution (Task 7): a tiny `@MainActor final class CaptureCoordinator: ObservableObject` with `@Published private(set) var lastCaptureAt: Date?` injected as an `@EnvironmentObject` at the app root. `saveCompleted()` stamps it; `TimelineView`/`HomeView`/`InsightsPlaceholderView` each `.onChange(of: coordinator.lastCaptureAt)` → refresh. This reuses the exact pattern the `scenePhase` foreground-refresh hooks already use (1B), and needs no VM lifting.

## Capture interaction (frozen — Leo, 2026-07-13)

Fast, tap-to-log capture with undo-not-confirm (UI §3/§7; the ≤3-tap repeat-log goal):
- **Chips log instantly.** Tapping a recent-item chip logs immediately — meal by name, dose at that substance's last amount/unit (looked up from recent events), note has no chips.
- **Symptoms get a quick severity step.** Tapping a symptom chip reveals a compact 1–10 severity row; tapping a number logs at that severity. So a symptom stays always-rated (Leo's call), at one extra tap.
- **New items use the form.** Searching/typing a not-a-chip item shows the full form (symptom: slider + note; dose: amount + unit + route) with a **Log** button. "Full form only when something is new" (§3).
- **Undo, never confirm.** The `CaptureSheet` owns a bottom **Undo toast** shown after every log ("Logged {title} · Undo"). Undo `softDelete`s the just-logged event and refreshes. The sheet does NOT auto-dismiss — you log several things, then swipe down.
- **Mechanism:** each capture subview receives an `onLogged: (HealthEvent) -> Void` closure. On a successful `CaptureService` write it calls `onLogged(event)` (it does NOT dismiss or call the coordinator). The sheet's `onLogged` handler fires `coordinator.saveCompleted()` (tab refresh) + arms the undo toast.

## Design tokens delta

Task 6 adds one token to `HealthTheme`: `onAccent` (`#FFFFFF` / `#FFFFFF` — white reads on both accent shades; kept a token so future accent-content is consistent and themeable). Replaces the hardcoded `.foregroundStyle(.white)` at `HealthOSTabBar.swift:47` and is used by every accent-filled capture control.

---

### Task 1: Package — capture write conventions + `CaptureService`

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Capture/CaptureService.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/CaptureServiceTests.swift` (new)

**Interfaces:**
- Consumes: `AppDatabase`, `GRDBEventStore` (`save`), `GRDBObjectStore` (`findOrCreate`), `HealthEvent`, `HealthObject`, `EventCategory`, `ObjectKind`.
- Produces (used by app Tasks 9–13):

```swift
public struct CaptureService: Sendable {
    public init(database: AppDatabase)
    /// Symptom: category .symptom, canonical camelCase subtype, severity 1–10 (nil = unrated), unit "severity".
    @discardableResult
    public func logSymptom(canonicalKey: String, severity: Int?, at timestamp: Date,
                           note: String?) async throws -> HealthEvent
    /// Meal/food: category .food, subtype = name as typed, links a find-or-create .food object.
    @discardableResult
    public func logMeal(name: String, at timestamp: Date) async throws -> HealthEvent
    /// Dose: category = kind's matching EventCategory, subtype = substance, value/unit = amount, links object.
    @discardableResult
    public func logDose(substance: String, kind: DoseKind, amount: Double?, unit: String?,
                        route: String?, at timestamp: Date) async throws -> HealthEvent
    /// Note: category .note, subtype = the text.
    @discardableResult
    public func logNote(text: String, at timestamp: Date) async throws -> HealthEvent
}
public enum DoseKind: String, CaseIterable, Sendable {
    case medication, supplement, peptide
    public var objectKind: ObjectKind { … }     // .medication/.supplement/.peptide
    public var eventCategory: EventCategory { … } // .medication/.supplement/.peptide
}
```

Semantics to implement exactly:
- All writes: `source: .manual`, `dedupKey: nil`, `confidence: 1.0`, `timezoneID` default.
- `logSymptom`: `HealthEvent(timestamp:, category: .symptom, subtype: canonicalKey, value: severity.map(Double.init), unit: severity == nil ? nil : "severity", source: .manual)`. When `note` is non-empty, set `metadata` = JSON `["note": note]`.
- `logMeal`: `object = try await objectStore.findOrCreate(name: name, kind: .food, metadata: nil)`; then `HealthEvent(timestamp:, category: .food, subtype: name, objectID: object.id, source: .manual)`.
- `logDose`: `object = findOrCreate(name: substance, kind: kind.objectKind, metadata: nil)`; `HealthEvent(timestamp:, category: kind.eventCategory, subtype: substance, objectID: object.id, value: amount, unit: unit, source: .manual, metadata: route.map { JSON ["route": $0] })`.
- `logNote`: `HealthEvent(timestamp:, category: .note, subtype: text, source: .manual)`.
- Each method calls `eventStore.save(event)` then returns the event. Trim whitespace on names/text; treat empty as an error is out of scope — the UI guards non-empty (document it).

- [ ] **Step 1: Write the failing tests**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/CaptureServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import HealthGraphCore

struct CaptureServiceTests {
    let base = Date(timeIntervalSince1970: 1_750_000_000)

    private func make() throws -> (AppDatabase, CaptureService, GRDBEventStore, GRDBObjectStore) {
        let db = try AppDatabase.inMemory()
        return (db, CaptureService(database: db), GRDBEventStore(database: db), GRDBObjectStore(database: db))
    }

    @Test func logSymptomWritesSeverityEvent() async throws {
        let (_, capture, store, _) = try make()
        let event = try await capture.logSymptom(canonicalKey: "headache", severity: 6, at: base, note: nil)
        #expect(event.category == .symptom)
        #expect(event.subtype == "headache")
        #expect(event.value == 6)
        #expect(event.unit == "severity")
        #expect(event.source == .manual)
        #expect(event.dedupKey == nil)
        #expect(event.confidence == 1.0)   // manual capture is full-confidence
        let page = try await store.eventsPage(before: nil, limit: 10, categories: nil, sources: nil)
        #expect(page.map(\.id) == [event.id])
    }

    @Test func logSymptomUnratedHasNoValueAndNoteGoesToMetadata() async throws {
        let (_, capture, _, _) = try make()
        let event = try await capture.logSymptom(canonicalKey: "nausea", severity: nil, at: base, note: "after lunch")
        #expect(event.value == nil)
        #expect(event.unit == nil)
        let dict = try JSONDecoder().decode([String: String].self, from: #require(event.metadata))
        #expect(dict["note"] == "after lunch")
    }

    @Test func logMealCreatesFoodObjectAndLinks() async throws {
        let (_, capture, _, objects) = try make()
        let event = try await capture.logMeal(name: "Oat milk latte", at: base)
        #expect(event.category == .food)
        #expect(event.subtype == "Oat milk latte")
        let obj = try await objects.object(id: #require(event.objectID))
        #expect(obj?.kind == .food)
        #expect(obj?.name == "Oat milk latte")
        // Logging the same meal reuses the one object (find-or-create).
        let again = try await capture.logMeal(name: "oat milk latte", at: base.addingTimeInterval(60))
        #expect(again.objectID == event.objectID)
        #expect(try await objects.count() == 1)
    }

    @Test func logDoseLinksMatchingKindObjectWithAmountUnitAndRoute() async throws {
        let (_, capture, _, objects) = try make()
        let event = try await capture.logDose(substance: "Semaglutide", kind: .peptide,
                                              amount: 0.25, unit: "mg", route: "subQ", at: base)
        #expect(event.category == .peptide)
        #expect(event.subtype == "Semaglutide")
        #expect(event.value == 0.25)
        #expect(event.unit == "mg")
        let obj = try await objects.object(id: #require(event.objectID))
        #expect(obj?.kind == .peptide)
        let dict = try JSONDecoder().decode([String: String].self, from: #require(event.metadata))
        #expect(dict["route"] == "subQ")
    }

    @Test func logNoteStoresTextInSubtype() async throws {
        let (_, capture, store, _) = try make()
        let event = try await capture.logNote(text: "Felt wired after coffee", at: base)
        #expect(event.category == .note)
        #expect(event.subtype == "Felt wired after coffee")
        // Searchable immediately via the v3 FTS over subtype.
        #expect(try await store.searchEvents(matching: "wired", limit: 10).map(\.id) == [event.id])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE — `CaptureService`/`DoseKind` don't exist.

- [ ] **Step 3: Implement**

Create `HealthGraphCore/Sources/HealthGraphCore/Capture/CaptureService.swift`:

```swift
import Foundation

/// Kinds of substance a dose can be logged against.
public enum DoseKind: String, CaseIterable, Sendable {
    case medication, supplement, peptide

    public var objectKind: ObjectKind {
        switch self {
        case .medication: .medication
        case .supplement: .supplement
        case .peptide: .peptide
        }
    }
    public var eventCategory: EventCategory {
        switch self {
        case .medication: .medication
        case .supplement: .supplement
        case .peptide: .peptide
        }
    }
}

/// Composes ObjectStore.findOrCreate + EventStore.save for manual capture.
/// All manual capture is source == .manual, dedupKey == nil (import-dedup exempt).
public struct CaptureService: Sendable {
    // Store AppDatabase (which IS Sendable) rather than the GRDB*Store structs
    // (public, not-declared-Sendable) so `CaptureService: Sendable` is warning-free.
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }
    private var eventStore: GRDBEventStore { GRDBEventStore(database: database) }
    private var objectStore: GRDBObjectStore { GRDBObjectStore(database: database) }

    private static func metadata(_ pairs: [String: String]) -> Data? {
        pairs.isEmpty ? nil : try? JSONEncoder().encode(pairs)
    }

    @discardableResult
    public func logSymptom(canonicalKey: String, severity: Int?, at timestamp: Date,
                           note: String?) async throws -> HealthEvent {
        var meta: [String: String] = [:]
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meta["note"] = note
        }
        let event = HealthEvent(
            timestamp: timestamp, category: .symptom,
            subtype: canonicalKey,
            value: severity.map(Double.init),
            unit: severity == nil ? nil : "severity",
            source: .manual, metadata: Self.metadata(meta), dedupKey: nil)
        try await eventStore.save(event)
        return event
    }

    @discardableResult
    public func logMeal(name: String, at timestamp: Date) async throws -> HealthEvent {
        let object = try await objectStore.findOrCreate(name: name, kind: .food, metadata: nil)
        let event = HealthEvent(
            timestamp: timestamp, category: .food, subtype: name,
            objectID: object.id, source: .manual, dedupKey: nil)
        try await eventStore.save(event)
        return event
    }

    @discardableResult
    public func logDose(substance: String, kind: DoseKind, amount: Double?, unit: String?,
                        route: String?, at timestamp: Date) async throws -> HealthEvent {
        let object = try await objectStore.findOrCreate(name: substance, kind: kind.objectKind, metadata: nil)
        var meta: [String: String] = [:]
        if let route, !route.isEmpty { meta["route"] = route }
        let event = HealthEvent(
            timestamp: timestamp, category: kind.eventCategory, subtype: substance,
            objectID: object.id, value: amount, unit: unit,
            source: .manual, metadata: Self.metadata(meta), dedupKey: nil)
        try await eventStore.save(event)
        return event
    }

    @discardableResult
    public func logNote(text: String, at timestamp: Date) async throws -> HealthEvent {
        let event = HealthEvent(
            timestamp: timestamp, category: .note, subtype: text,
            source: .manual, dedupKey: nil)
        try await eventStore.save(event)
        return event
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 85 tests in 13 suites passed` (80 + 5 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add HealthGraphCore && git commit -m "feat(core): CaptureService — manual symptom/meal/dose/note write conventions over the event+object graph"
```

---

### Task 2: Package — `SymptomCatalog` (ported names) + canonical keys

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomCatalog.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/SymptomCatalogTests.swift` (new)

**Interfaces:**
- Consumes: nothing.
- Produces (used by Tasks 3, 10):

```swift
public struct SymptomDefinition: Equatable, Sendable {
    public let displayName: String   // "Headache"
    public let canonicalKey: String  // "headache" — the HealthEvent.subtype
    public let regionId: String      // "head", "abdomen", … (for later body-map; carried now)
}
public enum SymptomCatalog {
    public static let all: [SymptomDefinition]                 // deduped by canonicalKey, sorted by displayName
    public static func canonicalKey(for displayName: String) -> String   // maps a typed/display name → key
    public static func displayName(for canonicalKey: String) -> String   // reverse for a known key; else title-cased
    public static func search(_ query: String) -> [SymptomDefinition]    // case/space-insensitive contains, ranked
}
```

Semantics:
- Port the legacy catalog from `/Users/leo/Desktop/FoodIntolerances/SymptomCatalog.swift` (`rawSymptoms`, ~131 `SymptomDefinition(name:regionId:category:)`). Convert each to `SymptomDefinition(displayName: name, canonicalKey: canonicalize(name), regionId: regionId)`. Drop the legacy `SymptomCategory` (unused by the graph).
- `canonicalize(_:)`: lowercase, split on non-alphanumerics, uppercase-first each subsequent word, join → camelCase (e.g. "Sinus Pain" → "sinusPain", "Headache" → "headache"). This matches `EventDisplay.title`'s expectations (which splits camelCase back to words).
- `canonicalKey(for:)`: if the display name matches a catalog entry (case-insensitive), return its key; else canonicalize the input (a brand-new symptom the user typed).
- `search`: filter `all` by `displayName` containing the query (case/whitespace-insensitive); rank prefix matches before mid-string; empty query → `[]`.

- [ ] **Step 1: Write the failing tests**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/SymptomCatalogTests.swift`:

```swift
import Foundation
import Testing
@testable import HealthGraphCore

struct SymptomCatalogTests {
    @Test func catalogIsNonEmptyAndDeduped() {
        #expect(SymptomCatalog.all.count >= 100)
        let keys = SymptomCatalog.all.map(\.canonicalKey)
        #expect(Set(keys).count == keys.count)   // no dupes
    }
    @Test func canonicalKeyRoundTripsWithEventDisplay() {
        #expect(SymptomCatalog.canonicalKey(for: "Headache") == "headache")
        #expect(SymptomCatalog.canonicalKey(for: "Sinus Pain") == "sinusPain")
        // A brand-new symptom the user types canonicalizes the same way.
        #expect(SymptomCatalog.canonicalKey(for: "Weird New Thing") == "weirdNewThing")
    }
    @Test func searchIsCaseInsensitiveAndRanksPrefix() {
        let hits = SymptomCatalog.search("head")
        #expect(hits.contains { $0.displayName == "Headache" })
        #expect(SymptomCatalog.search("   ").isEmpty)
    }
    @Test func displayNameReversesKnownKeyElseTitleCases() {
        #expect(SymptomCatalog.displayName(for: "headache") == "Headache")
        #expect(SymptomCatalog.displayName(for: "sinusPain") == "Sinus Pain")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE — `SymptomCatalog` missing.

- [ ] **Step 3: Implement**

Read the legacy catalog first: `Read /Users/leo/Desktop/FoodIntolerances/SymptomCatalog.swift` lines 69–238 to copy the `(name, regionId)` pairs. Create `HealthGraphCore/Sources/HealthGraphCore/Capture/SymptomCatalog.swift`:

```swift
import Foundation

public struct SymptomDefinition: Equatable, Sendable {
    public let displayName: String
    public let canonicalKey: String
    public let regionId: String
    public init(displayName: String, canonicalKey: String, regionId: String) {
        self.displayName = displayName
        self.canonicalKey = canonicalKey
        self.regionId = regionId
    }
}

public enum SymptomCatalog {
    /// (displayName, regionId) ported verbatim from the legacy app's SymptomCatalog.rawSymptoms.
    /// Keep this list append-only-safe: canonicalKey is derived, so renames change the key.
    private static let raw: [(String, String)] = [
        ("Headache", "head"), ("Migraine", "head"), ("Sinus Pain", "head"),
        ("Vertigo", "head"), ("Dizziness", "head"), ("Eye Pain", "head"),
        ("Anxiety", "head"), ("Stress", "head"), ("Depression", "head"),
        // … PORT ALL ~131 (name, regionId) pairs from SymptomCatalog.swift:69-238 here …
        ("Skin Rash", "skin"), ("Insect Bite", "skin"),
    ]

    public static let all: [SymptomDefinition] = {
        var seen = Set<String>()
        var out: [SymptomDefinition] = []
        for (name, region) in raw {
            let key = canonicalize(name)
            guard seen.insert(key).inserted else { continue }
            out.append(SymptomDefinition(displayName: name, canonicalKey: key, regionId: region))
        }
        return out.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }()

    public static func canonicalKey(for displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hit = all.first(where: { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return hit.canonicalKey
        }
        return canonicalize(trimmed)
    }

    public static func displayName(for canonicalKey: String) -> String {
        if let hit = all.first(where: { $0.canonicalKey == canonicalKey }) { return hit.displayName }
        // Fallback: split camelCase, capitalize first letter (mirrors EventDisplay.title).
        var out = ""
        for (i, ch) in canonicalKey.enumerated() {
            if i == 0 { out.append(contentsOf: ch.uppercased()) }
            else if ch.isUppercase { out.append(" "); out.append(ch) }
            else { out.append(ch) }
        }
        return out
    }

    public static func search(_ query: String) -> [SymptomDefinition] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let matches = all.filter { $0.displayName.lowercased().contains(q) }
        return matches.sorted { a, b in
            let ap = a.displayName.lowercased().hasPrefix(q), bp = b.displayName.lowercased().hasPrefix(q)
            if ap != bp { return ap }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    private static func canonicalize(_ name: String) -> String {
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard let first = words.first else { return "" }
        return ([first] + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }).joined()
    }
}
```

**Implementer note:** the `raw` array MUST contain all ~131 pairs from the legacy file — the ellipsis above is a placeholder for THIS task's implementer to fill by copying `SymptomCatalog.swift:69-238`. Do not ship the abbreviated list.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 89 tests in 14 suites passed` (85 + 4 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add HealthGraphCore && git commit -m "feat(core): port symptom catalog with canonical keys + search"
```

---

### Task 3: Package — `ChipRanker` (frequency × recency × time-of-day)

**Files:**
- Create: `HealthGraphCore/Sources/HealthGraphCore/Capture/ChipRanker.swift`
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/ChipRankerTests.swift` (new)

**Interfaces:**
- Consumes: `HealthEvent`.
- Produces (used by Tasks 10–12):

```swift
public enum ChipRanker {
    /// Ranks the distinct (category, subtype) pairs in `history` for quick-log chips.
    /// Score = frequency (log-damped) × recency (exponential, ~14-day half-life)
    ///       × time-of-day affinity (share of this item's logs within ±2h of `now`'s hour).
    /// Returns the top `limit`, highest first. `history` is any recent event slice.
    public static func rank(history: [HealthEvent], category: EventCategory, now: Date,
                            timeZone: TimeZone, limit: Int) -> [String]   // subtypes
}
```

Semantics:
- Consider only non-deleted events with `category == category` and a non-nil `subtype`.
- Group by `subtype`. For each: `frequency = log2(1 + count)`; `recency = exp(-ageDays_ofMostRecent / 14)`; `todAffinity = 0.5 + 0.5 * (fraction of this subtype's events whose local hour is within 2 of now's local hour)`. Score = product. Rank desc, tiebreak by most-recent timestamp desc, take `limit`.

- [ ] **Step 1: Write the failing tests**

Create `HealthGraphCore/Tests/HealthGraphCoreTests/ChipRankerTests.swift`:

```swift
import Foundation
import Testing
@testable import HealthGraphCore

struct ChipRankerTests {
    let tz = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_750_000_000)   // fixed
    private func ev(_ sub: String, _ t: Date) -> HealthEvent {
        HealthEvent(timestamp: t, category: .symptom, subtype: sub, source: .manual, createdAt: t)
    }
    @Test func frequentAndRecentRanksAboveRareOld() {
        let hist = [
            ev("headache", now.addingTimeInterval(-3600)),
            ev("headache", now.addingTimeInterval(-2 * 86_400)),
            ev("headache", now.addingTimeInterval(-3 * 86_400)),
            ev("nausea", now.addingTimeInterval(-40 * 86_400)),   // old, rare
        ]
        let ranked = ChipRanker.rank(history: hist, category: .symptom, now: now, timeZone: tz, limit: 5)
        #expect(ranked.first == "headache")
        #expect(ranked.contains("nausea"))
    }
    @Test func filtersCategoryAndRespectsLimit() {
        let hist = [
            ev("headache", now), ev("nausea", now),
            HealthEvent(timestamp: now, category: .food, subtype: "eggs", source: .manual, createdAt: now),
        ]
        let ranked = ChipRanker.rank(history: hist, category: .symptom, now: now, timeZone: tz, limit: 1)
        #expect(ranked.count == 1)
        #expect(!ranked.contains("eggs"))
    }
    @Test func emptyHistoryReturnsEmpty() {
        #expect(ChipRanker.rank(history: [], category: .food, now: now, timeZone: tz, limit: 5).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: compile FAILURE — `ChipRanker` missing.

- [ ] **Step 3: Implement**

Create `HealthGraphCore/Sources/HealthGraphCore/Capture/ChipRanker.swift`:

```swift
import Foundation

public enum ChipRanker {
    public static func rank(history: [HealthEvent], category: EventCategory, now: Date,
                            timeZone: TimeZone, limit: Int) -> [String] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let nowHour = cal.component(.hour, from: now)
        let relevant = history.filter { $0.category == category && $0.deletedAt == nil && $0.subtype != nil }
        var byKey: [String: [HealthEvent]] = [:]
        for e in relevant { byKey[e.subtype!, default: []].append(e) }
        func hourDistance(_ h: Int) -> Int { let d = abs(h - nowHour); return min(d, 24 - d) }
        let scored: [(String, Double, Date)] = byKey.map { key, events in
            let count = events.count
            let mostRecent = events.map(\.timestamp).max() ?? now
            let ageDays = max(0, now.timeIntervalSince(mostRecent) / 86_400)
            let frequency = log2(1 + Double(count))
            let recency = exp(-ageDays / 14)
            let near = events.filter { hourDistance(cal.component(.hour, from: $0.timestamp)) <= 2 }.count
            let tod = 0.5 + 0.5 * (Double(near) / Double(count))
            return (key, frequency * recency * tod, mostRecent)
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }
            .prefix(limit).map(\.0)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 92 tests in 15 suites passed` (89 + 3 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add HealthGraphCore && git commit -m "feat(core): ChipRanker — frequency × recency × time-of-day quick-log ranking"
```

---

### Task 4: Package — FTS v4 over object names + object-aware search

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift` (append migration `v4`)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/EventStore.swift` (`searchEvents` also matches linked object names)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/AppDatabaseTests.swift`, `EventStoreTests.swift` (append)

**Interfaces:**
- Consumes: Task 1 state (events linking objects).
- Produces: `searchEvents(matching:limit:)` now also returns events whose linked `HealthObject.name` matches (in addition to the existing subtype/category match). No signature change.

Design (locked): add `health_objects_fts` — an external-content FTS5 table over `health_objects(name)` with sync triggers + backfill (mirrors v3's shape). `searchEvents` unions the existing subtype/category match with events whose `objectID` is a `health_objects_fts` match. v3's `health_events_fts` is untouched (append-only rule).

- [ ] **Step 1: Write the failing tests**

Append to `AppDatabaseTests.swift`:

```swift
    @Test func v4CreatesObjectFTSAndBackfills() throws {
        let db = try AppDatabase.inMemory()
        let obj = HealthObject(kind: .supplement, name: "Magnesium Glycinate")
        try db.dbWriter.write { d in try obj.insert(d) }
        let n = try db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT count(*) FROM health_objects_fts WHERE health_objects_fts MATCH 'magnesium'") ?? -1
        }
        #expect(n == 1)
        try db.dbWriter.write { d in try d.execute(sql: "UPDATE health_objects SET name = 'Zinc'") }
        let after = try db.dbWriter.read { d in
            try Int.fetchOne(d, sql: "SELECT count(*) FROM health_objects_fts WHERE health_objects_fts MATCH 'zinc'") ?? -1
        }
        #expect(after == 1)
    }
```

Append to `EventStoreTests.swift`:

```swift
    @Test func searchMatchesLinkedObjectNameNotJustSubtype() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let objects = GRDBObjectStore(database: db)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let obj = try await objects.findOrCreate(name: "Vitamin D3", kind: .supplement, metadata: nil)
        // Subtype is an abbreviation; the searchable full name lives on the object.
        let dose = HealthEvent(timestamp: base, category: .supplement, subtype: "D3",
                               objectID: obj.id, value: 2000, unit: "iu", source: .manual, createdAt: base)
        try await store.save(dose)
        #expect(try await store.searchEvents(matching: "vitamin", limit: 10).map(\.id) == [dose.id])
        // Subtype search still works.
        #expect(try await store.searchEvents(matching: "d3", limit: 10).map(\.id) == [dose.id])
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: FAILURE — `no such table: health_objects_fts`; the object-name search returns `[]`.

- [ ] **Step 3: Implement migration v4**

In `AppDatabase.swift`, inside `migrator`, append AFTER the `v3` registration (same style — DO NOT edit v1/v2/v3):

```swift
        migrator.registerMigration("v4") { db in
            // External-content FTS over object names, so "search your history" finds
            // events by their linked substance/food name, not only the typed subtype.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE health_objects_fts USING fts5(
                    name, content='health_objects', content_rowid='rowid')
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_objects_fts_ai AFTER INSERT ON health_objects BEGIN
                    INSERT INTO health_objects_fts(rowid, name) VALUES (new.rowid, new.name);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_objects_fts_ad AFTER DELETE ON health_objects BEGIN
                    INSERT INTO health_objects_fts(health_objects_fts, rowid, name)
                    VALUES ('delete', old.rowid, old.name);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER health_objects_fts_au AFTER UPDATE ON health_objects BEGIN
                    INSERT INTO health_objects_fts(health_objects_fts, rowid, name)
                    VALUES ('delete', old.rowid, old.name);
                    INSERT INTO health_objects_fts(rowid, name) VALUES (new.rowid, new.name);
                END
                """)
            try db.execute(sql: """
                INSERT INTO health_objects_fts(rowid, name)
                SELECT rowid, name FROM health_objects
                """)
        }
```

- [ ] **Step 4: Implement object-aware search**

In `EventStore.swift`, `GRDBEventStore.searchEvents(matching:limit:)`, keep the tokenization/sanitizer unchanged; change the SQL to UNION the existing event-FTS match with events whose object matches. Replace the fetch body with:

```swift
        return try await dbWriter.read { db in
            try HealthEvent.fetchAll(db, sql: """
                SELECT he.* FROM health_events he
                WHERE he.deletedAt IS NULL AND (
                    he.rowid IN (SELECT rowid FROM health_events_fts WHERE health_events_fts MATCH ?)
                    OR he.objectID IN (
                        SELECT ho.id FROM health_objects ho
                        JOIN health_objects_fts f ON f.rowid = ho.rowid
                        WHERE health_objects_fts MATCH ?)
                )
                ORDER BY he.timestamp DESC
                LIMIT ?
                """, arguments: [match, match, limit])
        }
```

(`match` is the existing sanitized prefix string; pass it twice.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 94 tests in 15 suites passed` (92 + 2 new; no new suite — appended to existing files).

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add HealthGraphCore && git commit -m "feat(core): FTS5 v4 over object names; search matches linked substance/food names"
```

---

### Task 5: Package — remove `eraseDatabaseOnSchemaChange`; document append-only migrations

**Files:**
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Database/AppDatabase.swift` (remove the DEBUG flag, lines 31–39)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/AppDatabaseTests.swift` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: the graph is now the source of truth — schema changes never wipe user data. The DEBUG `eraseAllRows()` helper STAYS (it's the debug "Reset" path); only the auto-erase-on-schema-drift flag is removed.

Background: `AppDatabase.swift:31-39` sets `migrator.eraseDatabaseOnSchemaChange = true` under `#if DEBUG`, with an in-code directive to remove it before live capture. With capture shipping, an accidental edit to a shipped migration must FAIL loudly (a GRDB migration error), not silently wipe the user's graph.

- [ ] **Step 1: Write the failing test**

Append to `AppDatabaseTests.swift` — assert that reopening a DB with all migrations applied is a no-op (idempotent) and preserves rows (this passes today but pins the behavior we must keep after removing the flag):

```swift
    @Test func reopeningPreservesRowsAcrossMigrations() async throws {
        // Two AppDatabase instances over the same on-disk file: reopening runs the
        // migrator again and must NOT erase existing rows. NOTE: open(at:) takes a URL.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hg-1c-\(UInt64(1_750_000_000)).sqlite")
        try? FileManager.default.removeItem(at: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        do {
            let db = try AppDatabase.open(at: dir)
            try await GRDBEventStore(database: db).save(
                HealthEvent(timestamp: base, category: .note, subtype: "keep me", source: .manual, createdAt: base))
        }
        let db2 = try AppDatabase.open(at: dir)
        #expect(try await GRDBEventStore(database: db2).count() == 1)
    }
```

- [ ] **Step 2: Run to verify it passes today (guards the invariant), then remove the flag**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3` — the new test passes (the flag only erases on schema DRIFT, not on a clean reopen). This test is the safety net for the removal.

- [ ] **Step 3: Remove the flag**

In `AppDatabase.swift`, delete the entire `#if DEBUG … eraseDatabaseOnSchemaChange = true … #endif` block (lines ~31-39). Replace with a comment:

```swift
        // Migrations are append-only and immutable from Phase 1C on: the graph is the
        // source of truth, so a shipped migration body must never change (GRDB does not
        // checksum bodies). New schema = a new numbered migration. Editing v1..vN in place
        // would silently drift schemas on existing installs. `eraseDatabaseOnSchemaChange`
        // was removed here; the DEBUG-only `eraseAllRows()` remains for the debug Reset button.
```

- [ ] **Step 4: Run tests to verify all still pass**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3`
Expected: `Test run with 95 tests in 15 suites passed` (94 + 1 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add HealthGraphCore && git commit -m "chore(core): remove eraseDatabaseOnSchemaChange — graph is source of truth; migrations now append-only"
```

---

### Task 6: App — `HealthTheme.onAccent` token + note/dose display; fix hardcoded white

**Files:**
- Modify: `Views/HealthOS/Theme/HealthTheme.swift` (add `onAccent`)
- Modify: `Views/HealthOS/Shell/HealthOSTabBar.swift:47` (use the token)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/EventDisplay.swift` (`.note` title + dose value line)
- Test: `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift` (append EventDisplay cases)

**Interfaces:**
- Consumes: Task 1 conventions (note text in subtype; dose value/unit).
- Produces: `HealthTheme.onAccent: Color`; `EventDisplay.title` renders note text; `EventDisplay.valueLine` renders a dose as "0.25 mg".

Background: 1B's carry-forward — the capture `[+]` and any accent-filled button hardcode `.foregroundStyle(.white)`. And `EventDisplay` has no `.note` handling (a note would show the capitalized category "Note" as its title, hiding the text) and no explicit dose formatting.

- [ ] **Step 1: Write the failing EventDisplay tests**

Append to `TimelineDayBuilderTests.swift` (inside `TimelineDayBuilderTests`), reusing its `event(...)` helper style — add:

```swift
    @Test func noteAndDoseDisplay() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        func ev(_ cat: EventCategory, _ sub: String?, _ value: Double?, _ unit: String?) -> HealthEvent {
            HealthEvent(timestamp: base, category: cat, subtype: sub, value: value, unit: unit,
                        source: .manual, createdAt: base)
        }
        // A note shows its text as the title (not the category name).
        #expect(EventDisplay.title(for: ev(.note, "Felt wired after coffee", nil, nil)) == "Felt wired after coffee")
        // A multi-word symptom subtype title-cases consistently with SymptomCatalog.displayName.
        #expect(EventDisplay.title(for: ev(.symptom, "sinusPain", nil, nil)) == "Sinus Pain")
        // A dose shows amount + unit.
        #expect(EventDisplay.valueLine(for: ev(.peptide, "Semaglutide", 0.25, "mg")) == "0.25 mg")
        #expect(EventDisplay.valueLine(for: ev(.supplement, "Vitamin D3", 2000, "iu")) == "2000 iu")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -5`
Expected: FAILURE on TWO assertions that pin the fixes: the `sinusPain` title returns "Sinus pain" today (old lowercasing) not "Sinus Pain", and `0.25 mg` returns "0 mg" today ("mg" is in the `%.0f` bucket). The note-text title and "2000 iu" (already via the `%g` fallback) likely pass already — the two failing assertions drive the edit.

- [ ] **Step 3: Implement**

In `EventDisplay.swift`:
- `valueLine`: doses need decimal precision (0.25 mg), unlike the daily-stat units. Add, BEFORE the existing `%.0f`-unit bucket, a dose-aware case: when `event.source == .manual` OR the unit is a dose unit (`"mg","mcg","iu","ml","tablet","capsule","drop","spray"`), format with up-to-2 decimals trimmed:

```swift
        case let u? where ["mg","mcg","iu","ml","tablet","capsule","drop","spray"].contains(u):
            return "\(trimmed(value)) \(u)"
```
with a helper `private static func trimmed(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", v) }` (so 2000 → "2000", 0.25 → "0.25").
- `title`: two changes in `title(for:)`:
  1. **Note passthrough** — at the very top: `if event.category == .note, let s = event.subtype, !s.isEmpty { return s }` (a note's title IS its text).
  2. **Title-Case the camelCase fallback** so unmapped multi-word subtypes match `SymptomCatalog.displayName` ("sinusPain" → "Sinus Pain", not the current "Sinus pain"). In the fallback loop, the `ch.isUppercase` branch currently does `out.append(" "); out.append(contentsOf: ch.lowercased())` — change the second call to `out.append(ch)` (keep the capital). Single-word subtypes ("headache" → "Headache") are unaffected, and no existing test pins the old lowercasing.

In `HealthTheme.swift`, add after `dotMiss`:

```swift
    /// Content drawn on top of the accent fill (buttons, the capture [+]).
    static let onAccent = dyn(light: 0xFFFFFF, dark: 0xFFFFFF)
```

In `HealthOSTabBar.swift:47`, change `.foregroundStyle(.white)` → `.foregroundStyle(HealthTheme.onAccent)`.

- [ ] **Step 4: Run package tests, then build the app**

```bash
cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' 2>&1 | tail -3
```
Expected: package `96 tests in 15 suites passed` (95 + 1 new); `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add HealthGraphCore Views/HealthOS && git commit -m "feat(core+app): note/dose display formatting; HealthTheme.onAccent token replaces hardcoded white"
```

---

### Task 7: App — `CaptureCoordinator` (capture → tab refresh) + inject at root

**Files:**
- Create: `Views/HealthOS/Capture/CaptureCoordinator.swift`
- Modify: `FoodIntolerancesApp.swift` (inject the coordinator)
- Modify: `Views/HealthOS/Home/HomeView.swift`, `Views/HealthOS/Timeline/TimelineView.swift`, `Views/HealthOS/Insights/InsightsPlaceholderView.swift` (observe it → refresh)

**Interfaces:**
- Consumes: nothing.
- Produces: `CaptureCoordinator` (`@EnvironmentObject`), consumed by the capture sheet (Task 8) to signal a write, and by the three data tabs to refresh.

```swift
@MainActor final class CaptureCoordinator: ObservableObject {
    @Published private(set) var lastCaptureAt: Date?
    func saveCompleted()   // stamps lastCaptureAt = Date() (called after a capture writes)
}
```

Background: the keep-alive shell keeps tabs mounted, and the capture sheet (presented from `HealthOSRootView`) can't see the tabs' private VMs. This mirrors the 1B `scenePhase` foreground-refresh pattern: tabs `.onChange` a published signal and refresh.

- [ ] **Step 1: Create the coordinator**

Create `Views/HealthOS/Capture/CaptureCoordinator.swift`:

```swift
import Foundation

/// Bridges a capture write (in the sheet presented from the root) to the
/// keep-alive tabs, which can't otherwise observe it. Tabs refresh on change.
@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published private(set) var lastCaptureAt: Date?
    func saveCompleted() { lastCaptureAt = Date() }
}
```

- [ ] **Step 2: Inject at the app root**

In `FoodIntolerancesApp.swift`: add `@StateObject private var captureCoordinator = CaptureCoordinator()` alongside the other `@StateObject`s, and add `.environmentObject(captureCoordinator)` to the `HealthOSRootView()` modifier chain (next to the existing `.environmentObject(...)` calls — do NOT drop any existing modifier). ALSO add `.environmentObject(CaptureCoordinator())` to the two `#Preview` blocks in `HealthOSRootView.swift` — after Step 3 the mounted tabs require the coordinator, so the Xcode canvas would otherwise crash on render (the build gate is unaffected, but keep previews working).

- [ ] **Step 3: Tabs observe and refresh**

In each of `HomeView.swift`, `TimelineView.swift`, `InsightsPlaceholderView.swift`: add `@EnvironmentObject private var captureCoordinator: CaptureCoordinator` and, on the same container that has the existing `.onChange(of: scenePhase)`, add:

```swift
            .onChange(of: captureCoordinator.lastCaptureAt) { _, _ in
                Task { await <refresh> }   // HomeView/TimelineView: viewModel.refresh(); Insights: loadCounts()
            }
```

- [ ] **Step 4: Build**

```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. (No behavior change yet — `lastCaptureAt` stays nil until Task 8 wires the sheet.)

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add FoodIntolerancesApp.swift Views/HealthOS && git commit -m "feat(app): CaptureCoordinator — capture write-through refresh for the keep-alive tabs"
```

---

### Task 8: App — capture sheet shell + type router (replace the placeholder)

**Files:**
- Create: `Views/HealthOS/Capture/CaptureSheet.swift`
- Create: `Views/HealthOS/Capture/CaptureType.swift`
- Create skeletons (filled in Tasks 9–12): `Views/HealthOS/Capture/SymptomCaptureView.swift`, `MealCaptureView.swift`, `DoseCaptureView.swift`, `NoteCaptureView.swift`
- Modify: `Views/HealthOS/Shell/HealthOSRootView.swift` (present `CaptureSheet`, detents `[.medium, .large]`)
- Delete: `Views/HealthOS/Shell/CapturePlaceholderSheet.swift`

**Interfaces:**
- Consumes: `CaptureCoordinator` (Task 7), `CaptureService`/`HealthGraphProvider.shared`, tokens.
- Produces: `CaptureSheet` (the real center-[+] surface, owning the Undo toast); `enum CaptureType { case symptom, meal, dose, note }`. Each capture subview takes `@Binding var timestamp: Date` + `let onLogged: (HealthEvent) -> Void` and calls `onLogged(event)` after a successful write — it does NOT dismiss or touch the coordinator (the sheet does).

Design (locked): a `NavigationStack`-free sheet with a serif "Capture" title, a shared **when** control (a compact `DatePicker`, default now), a segmented type picker (Symptom · Meal · Dose · Note with their `CategoryStyle` icons), and the active type's capture view below. The sheet owns the type selection, the shared timestamp binding it passes down, and the bottom **Undo toast** (armed by every subview's `onLogged`). It does NOT auto-dismiss.

- [ ] **Step 1: Create `CaptureType.swift`**

```swift
import SwiftUI
import HealthGraphCore

enum CaptureType: String, CaseIterable, Identifiable {
    case symptom, meal, dose, note
    var id: String { rawValue }
    var label: String {
        switch self { case .symptom: "Symptom"; case .meal: "Meal"; case .dose: "Dose"; case .note: "Note" }
    }
    var icon: String {
        switch self {
        case .symptom: "exclamationmark.circle"
        case .meal: "fork.knife"
        case .dose: "pills.fill"
        case .note: "note.text"
        }
    }
}
```

- [ ] **Step 2: Create the four capture-subview skeletons**

Each takes a `Binding<Date>` for the shared timestamp AND a `let onLogged: (HealthEvent) -> Void` (Tasks 9–12 fill the body + call `onLogged`). Skeleton body just shows the type name. Example `SymptomCaptureView.swift`:

```swift
import SwiftUI
import HealthGraphCore

struct SymptomCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    var body: some View {
        Text("Symptom capture")
            .foregroundStyle(HealthTheme.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}
```

Create `MealCaptureView.swift`, `DoseCaptureView.swift`, `NoteCaptureView.swift` identically (swap the struct name + label text; each keeps the `timestamp` binding + `onLogged` closure).

- [ ] **Step 3: Create `CaptureSheet.swift`**

```swift
import SwiftUI
import HealthGraphCore

struct CaptureSheet: View {
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @State private var type: CaptureType = .symptom
    @State private var timestamp = Date()
    @State private var lastLogged: HealthEvent?
    @State private var toastTask: Task<Void, Never>?
    private let store = GRDBEventStore(database: HealthGraphProvider.shared)

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(HealthTheme.cardBorder).frame(width: 36, height: 5).padding(.top, 8)
            Text("Capture")
                .font(HealthTheme.sectionHeader())
                .foregroundStyle(HealthTheme.ink)

            Picker("Type", selection: $type) {
                ForEach(CaptureType.allCases) { t in
                    Label(t.label, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            DatePicker("When", selection: $timestamp, in: ...Date())
                .datePickerStyle(.compact)
                .padding(.horizontal, 16)

            Group {
                switch type {
                case .symptom: SymptomCaptureView(timestamp: $timestamp, onLogged: logged)
                case .meal: MealCaptureView(timestamp: $timestamp, onLogged: logged)
                case .dose: DoseCaptureView(timestamp: $timestamp, onLogged: logged)
                case .note: NoteCaptureView(timestamp: $timestamp, onLogged: logged)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Spacer(minLength: 0)
        }
        .background(HealthTheme.paper)
        .overlay(alignment: .bottom) { if let lastLogged { toast(lastLogged) } }
        .animation(.easeOut(duration: 0.2), value: lastLogged)
    }

    /// Called by every subview after a successful write: refresh the tabs + arm the undo toast.
    private func logged(_ event: HealthEvent) {
        coordinator.saveCompleted()
        lastLogged = event
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(for: .seconds(4)); lastLogged = nil }
    }

    private func undo(_ event: HealthEvent) {
        toastTask?.cancel()
        lastLogged = nil
        Task { try? await store.softDelete(id: event.id); coordinator.saveCompleted() }
    }

    private func toast(_ event: HealthEvent) -> some View {
        HStack(spacing: 12) {
            Text("Logged \(EventDisplay.title(for: event))")
                .font(.subheadline).foregroundStyle(HealthTheme.ink).lineLimit(1)
            Button("Undo") { undo(event) }
                .font(.subheadline.weight(.semibold)).foregroundStyle(HealthTheme.accent)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .padding(.horizontal, 20).padding(.vertical, 8).hgCard().padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Logged")
        .accessibilityAction(named: "Undo") { undo(event) }
        .id(event.id)
    }
}
```

- [ ] **Step 4: Present it from the root; remove the placeholder**

In `HealthOSRootView.swift`, change the capture sheet block to:

```swift
        .sheet(isPresented: $showingCapture) {
            CaptureSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
```
Then delete `Views/HealthOS/Shell/CapturePlaceholderSheet.swift` (`git rm`). The `CaptureCoordinator` is already in the environment (Task 7), so the subviews inherit it.

- [ ] **Step 5: Build**

```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild build -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. Tapping [+] now shows the real (skeleton) sheet with the type picker + when-control.

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git rm "Views/HealthOS/Shell/CapturePlaceholderSheet.swift" && git add Views/HealthOS/Capture "Views/HealthOS/Shell/HealthOSRootView.swift" && git commit -m "feat(app): real capture sheet shell — type picker + when control; retire the placeholder"
```

---

### Task 9: App — symptom capture (ranked chips + severity slider + search)

**Files:**
- Modify: `Views/HealthOS/Capture/SymptomCaptureView.swift` (replace skeleton)
- Test: `Food IntolerancesTests/CaptureFlowTests.swift` (new — a VM-level test of the ranked-chip + save wiring)

**Interfaces:**
- Consumes: `CaptureService.logSymptom`, `SymptomCatalog`, `ChipRanker`, `EventStore.recentEvents`, `CaptureCoordinator`, tokens.
- Produces: symptom capture that writes a severity event and refreshes.

Design (locked, per the "Capture interaction" section): a `@StateObject SymptomCaptureModel` loads recent symptom events (`store.recentEvents(limit: 300)`) → ranked chips via `ChipRanker.rank(history:category:.symptom, now:, timeZone:.current, limit: 8)` (each subtype → display via `SymptomCatalog.displayName`). Interaction: **tapping a chip sets `pendingKey`**, which swaps the UI to a compact **1–10 severity step**; tapping a number calls `model.log(key:severity:note:nil, at:)` and reports the event via `onLogged` (quick, always-rated repeat log). When no chip is pending: a search field filters `SymptomCatalog.search` (tap a result → `selectedNewKey`; or a typed non-catalog term → `newKey()` canonicalizes it), and a **new-symptom form** (severity `Slider(1...10)` + optional note + a **Log symptom** button) logs a brand-new symptom via `onLogged`. No `dismiss`/coordinator here — the sheet owns both.

- [ ] **Step 1: Write the failing model test**

Create `Food IntolerancesTests/CaptureFlowTests.swift`:

```swift
import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct CaptureFlowTests {
    private func db() throws -> AppDatabase { try AppDatabase.inMemory() }

    @Test func symptomModelRanksChipsAndLogsAtSeverity() async throws {
        let database = try db()
        let store = GRDBEventStore(database: database)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save([
            HealthEvent(timestamp: base, category: .symptom, subtype: "headache", value: 5, unit: "severity", source: .manual, createdAt: base),
            HealthEvent(timestamp: base, category: .symptom, subtype: "headache", value: 6, unit: "severity", source: .manual, createdAt: base),
            HealthEvent(timestamp: base, category: .symptom, subtype: "nausea", value: 3, unit: "severity", source: .manual, createdAt: base),
        ])
        let model = SymptomCaptureModel(database: database, now: { base })
        await model.loadChips()
        #expect(model.chipKeys.first == "headache")   // most frequent+recent
        // Chip → severity tap logs immediately; save strictly later so it sorts first.
        let e = await model.log(key: "headache", severity: 7, note: nil, at: base.addingTimeInterval(60))
        #expect(e?.value == 7)
        let page = try await store.eventsPage(before: nil, limit: 10, categories: [.symptom], sources: nil)
        #expect(page.count == 4)                       // 3 seeded + 1 logged
        #expect(page.first?.value == 7)                // the just-logged (newest) event
    }
    @Test func symptomNewKeyCanonicalizesTypedText() async throws {
        let model = SymptomCaptureModel(database: try db())
        model.searchText = "Sinus Pain"
        #expect(model.newKey() == "sinusPain")
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO -only-testing:"Food IntolerancesTests/CaptureFlowTests" 2>&1 | tail -5
```
Expected: compile FAILURE — `SymptomCaptureModel` missing.

- [ ] **Step 3: Implement the model + view**

Replace `Views/HealthOS/Capture/SymptomCaptureView.swift`:

```swift
import SwiftUI
import HealthGraphCore

@MainActor
final class SymptomCaptureModel: ObservableObject {
    @Published var chipKeys: [String] = []
    @Published var pendingKey: String?          // a chip tapped, awaiting a severity tap
    @Published var searchText: String = ""
    @Published var selectedNewKey: String?      // a searched/typed symptom for the full form
    @Published var severity: Double = 5
    @Published var note: String = ""

    private let store: GRDBEventStore
    private let capture: CaptureService
    private let now: () -> Date

    init(database: AppDatabase, now: @escaping () -> Date = Date.init) {
        self.store = GRDBEventStore(database: database)
        self.capture = CaptureService(database: database)
        self.now = now
    }

    var results: [SymptomDefinition] { SymptomCatalog.search(searchText) }

    func loadChips() async {
        guard let recent = try? await store.recentEvents(limit: 300) else { return }
        chipKeys = ChipRanker.rank(history: recent, category: .symptom, now: now(),
                                   timeZone: .current, limit: 8)
    }

    /// Canonical key for the full-form (new/searched) path — a picked result or typed text.
    func newKey() -> String? {
        if let selectedNewKey { return selectedNewKey }
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : SymptomCatalog.canonicalKey(for: t)
    }

    @discardableResult
    func log(key: String, severity: Int?, note: String?, at timestamp: Date) async -> HealthEvent? {
        do { return try await capture.logSymptom(canonicalKey: key, severity: severity, at: timestamp, note: note) }
        catch { return nil }
    }
}

struct SymptomCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    @StateObject private var model = SymptomCaptureModel(database: HealthGraphProvider.shared)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let key = model.pendingKey {
                    severityStep(for: key)          // chip tapped → quick 1-tap severity
                } else {
                    if !model.chipKeys.isEmpty { chipRow }
                    searchField
                    if !model.results.isEmpty { resultList }
                    if model.newKey() != nil { newSymptomForm }   // full form for a new symptom
                }
            }
            .padding(16)
        }
        .task { await model.loadChips() }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.chipKeys, id: \.self) { key in
                    chip(SymptomCatalog.displayName(for: key)) { model.pendingKey = key }
                }
            }
        }
    }

    private func severityStep(for key: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How bad is \(SymptomCatalog.displayName(for: key))?")
                    .font(.subheadline).foregroundStyle(HealthTheme.inkSecondary)
                Spacer()
                Button("Cancel") { model.pendingKey = nil }
                    .font(.footnote).foregroundStyle(HealthTheme.inkMuted).frame(minHeight: 44)
            }
            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { n in
                    Button {
                        Task {
                            if let e = await model.log(key: key, severity: n, note: nil, at: timestamp) {
                                onLogged(e); model.pendingKey = nil
                            }
                        }
                    } label: {
                        Text("\(n)").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 8).fill(HealthTheme.card))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CategoryFamily.symptoms.color.opacity(0.4), lineWidth: 1))
                            .foregroundStyle(HealthTheme.ink)
                    }
                    .accessibilityLabel("Severity \(n)")
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(HealthTheme.inkMuted)
            TextField("Search or add a symptom", text: $model.searchText)
                .onChange(of: model.searchText) { _, _ in model.selectedNewKey = nil }
        }
        .padding(12).hgCard()
    }

    private var resultList: some View {
        VStack(spacing: 0) {
            ForEach(model.results.prefix(6), id: \.canonicalKey) { def in
                Button {
                    model.selectedNewKey = def.canonicalKey; model.searchText = def.displayName
                } label: {
                    HStack { Text(def.displayName).foregroundStyle(HealthTheme.ink); Spacer() }
                        .padding(.vertical, 10).contentShape(Rectangle())
                }
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 12).hgCard()
    }

    private var newSymptomForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Severity: \(Int(model.severity))")
                    .font(.subheadline).foregroundStyle(HealthTheme.inkSecondary)
                Slider(value: $model.severity, in: 1...10, step: 1).tint(CategoryFamily.symptoms.color)
            }
            TextField("Note (optional)", text: $model.note, axis: .vertical).padding(12).hgCard()
            Button {
                guard let key = model.newKey() else { return }
                Task {
                    if let e = await model.log(key: key, severity: Int(model.severity),
                                               note: model.note.isEmpty ? nil : model.note, at: timestamp) {
                        onLogged(e); model.searchText = ""; model.selectedNewKey = nil; model.note = ""
                    }
                }
            } label: { Text("Log symptom").frame(maxWidth: .infinity).padding(.vertical, 12) }
                .buttonStyle(.borderedProminent).tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent).frame(minHeight: 44)
        }
    }

    private func chip(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.footnote)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(HealthTheme.card))
                .overlay(Capsule().strokeBorder(HealthTheme.cardBorder, lineWidth: 1))
                .foregroundStyle(HealthTheme.inkSecondary)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
```

- [ ] **Step 4: Run the model test, then the full app suite**

```bash
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO -only-testing:"Food IntolerancesTests/CaptureFlowTests" 2>&1 | tail -5
```
Expected: `CaptureFlowTests` passes. Then the full app suite (documented pattern).

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS/Capture "Food IntolerancesTests/CaptureFlowTests.swift" && git commit -m "feat(app): symptom capture — ranked chips, catalog search, severity slider"
```

---

### Task 10: App — meal capture (ranked food chips + name)

**Files:**
- Modify: `Views/HealthOS/Capture/MealCaptureView.swift` (replace skeleton)
- Test: `Food IntolerancesTests/CaptureFlowTests.swift` (append)

**Interfaces:**
- Consumes: `CaptureService.logMeal`, `ChipRanker` (category `.food`), `EventStore.recentEvents`, coordinator, tokens.
- Produces: meal capture writing a `.food` event + object.

Design: a `@StateObject MealCaptureModel` loads recent `.food` events → ranked chips (the food name is the subtype). A text field to type/confirm the food name; ranked chips fill it on tap. Save (disabled when empty) → `logMeal(name:)`.

- [ ] **Step 1: Append the failing test**

In `CaptureFlowTests.swift`, add:

```swift
    @Test func mealModelLogsFoodEventAndObject() async throws {
        let database = try db()
        let objects = GRDBObjectStore(database: database)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let model = MealCaptureModel(database: database)
        let e = await model.log(name: "Oat milk latte", at: base)
        #expect(e?.category == .food)
        #expect(try await objects.count() == 1)
    }
```

- [ ] **Step 2: Run to verify failure** (`MealCaptureModel` missing).

- [ ] **Step 3: Implement**

Replace `MealCaptureView.swift`:

```swift
import SwiftUI
import HealthGraphCore

@MainActor
final class MealCaptureModel: ObservableObject {
    @Published var name: String = ""
    @Published var chips: [String] = []
    private let store: GRDBEventStore
    private let capture: CaptureService
    private let now: () -> Date
    init(database: AppDatabase, now: @escaping () -> Date = Date.init) {
        store = GRDBEventStore(database: database); capture = CaptureService(database: database); self.now = now
    }
    func loadChips() async {
        guard let recent = try? await store.recentEvents(limit: 300) else { return }
        chips = ChipRanker.rank(history: recent, category: .food, now: now(), timeZone: .current, limit: 8)
    }
    @discardableResult
    func log(name: String, at timestamp: Date) async -> HealthEvent? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do { return try await capture.logMeal(name: trimmed, at: timestamp) } catch { return nil }
    }
}

struct MealCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    @StateObject private var model = MealCaptureModel(database: HealthGraphProvider.shared)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.chips, id: \.self) { food in
                                Button {            // chip tap logs immediately
                                    Task { if let e = await model.log(name: food, at: timestamp) { onLogged(e) } }
                                } label: {
                                    Text(food).font(.footnote)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(HealthTheme.card))
                                        .overlay(Capsule().strokeBorder(HealthTheme.cardBorder, lineWidth: 1))
                                        .foregroundStyle(HealthTheme.inkSecondary)
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .accessibilityLabel("Log \(food)")
                            }
                        }
                    }
                }
                TextField("What did you eat or drink?", text: $model.name)
                    .padding(12).hgCard()
                Button {
                    Task {
                        if let e = await model.log(name: model.name, at: timestamp) { onLogged(e); model.name = "" }
                    }
                } label: { Text("Log meal").frame(maxWidth: .infinity).padding(.vertical, 12) }
                    .buttonStyle(.borderedProminent).tint(HealthTheme.accent)
                    .foregroundStyle(HealthTheme.onAccent)
                    .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(minHeight: 44)
            }
            .padding(16)
        }
        .task { await model.loadChips() }
    }
}
```

- [ ] **Step 4: Run the appended test + full suite; expect pass.**
- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS/Capture "Food IntolerancesTests/CaptureFlowTests.swift" && git commit -m "feat(app): meal capture — ranked food chips + free-text name"
```

---

### Task 11: App — dose capture (substance + kind + amount/unit + route)

**Files:**
- Modify: `Views/HealthOS/Capture/DoseCaptureView.swift` (replace skeleton)
- Test: `Food IntolerancesTests/CaptureFlowTests.swift` (append)

**Interfaces:**
- Consumes: `CaptureService.logDose`, `DoseKind`, `ChipRanker`, coordinator, tokens.
- Produces: dose capture writing a `.medication/.supplement/.peptide` event + object.

Design: a `@StateObject DoseCaptureModel`. Kind segmented (Medication/Supplement/Peptide); ranked chips of recent substances of the selected kind (rank over the kind's event category); a substance name field; amount `TextField` (decimal) + unit `Menu` (`mg/mcg/iu/ml/tablet/capsule/drop/spray`); an optional route field (shown for peptide/medication). Save (disabled when substance empty) → `logDose`.

- [ ] **Step 1: Append the failing test**

```swift
    @Test func doseModelFormLogsLinkedPeptideEvent() async throws {
        let database = try db()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let model = DoseCaptureModel(database: database)
        model.kind = .peptide; model.substance = "Semaglutide"; model.amountText = "0.25"; model.unit = "mg"; model.route = "subQ"
        let e = await model.saveForm(at: base)
        #expect(e?.category == .peptide)
        #expect(e?.value == 0.25)
        #expect(e?.objectID != nil)
    }
    @Test func doseChipRepeatsLastAmountForSubstance() async throws {
        let database = try db()
        let store = GRDBEventStore(database: database)
        let objects = GRDBObjectStore(database: database)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let obj = try await objects.findOrCreate(name: "Vitamin D3", kind: .supplement, metadata: nil)
        try await store.save(HealthEvent(timestamp: base, category: .supplement, subtype: "Vitamin D3",
                                         objectID: obj.id, value: 2000, unit: "iu", source: .manual, createdAt: base))
        let model = DoseCaptureModel(database: database, now: { base })
        await model.loadChips()
        let e = await model.logChip(substance: "Vitamin D3", at: base.addingTimeInterval(60))
        #expect(e?.value == 2000)   // repeats the last logged amount
        #expect(e?.unit == "iu")
    }
```

- [ ] **Step 2: Run to verify failure** (`DoseCaptureModel` missing).

- [ ] **Step 3: Implement**

Replace `DoseCaptureView.swift`:

```swift
import SwiftUI
import HealthGraphCore

@MainActor
final class DoseCaptureModel: ObservableObject {
    @Published var kind: DoseKind = .supplement { didSet { Task { await loadChips() } } }
    @Published var substance: String = ""
    @Published var amountText: String = ""
    @Published var unit: String = "mg"
    @Published var route: String = ""
    @Published var chips: [String] = []
    static let units = ["mg", "mcg", "iu", "ml", "tablet", "capsule", "drop", "spray"]
    private let store: GRDBEventStore
    private let capture: CaptureService
    private let now: () -> Date
    private var recent: [HealthEvent] = []
    init(database: AppDatabase, now: @escaping () -> Date = Date.init) {
        store = GRDBEventStore(database: database); capture = CaptureService(database: database); self.now = now
    }
    func loadChips() async {
        recent = (try? await store.recentEvents(limit: 300)) ?? []
        chips = ChipRanker.rank(history: recent, category: kind.eventCategory, now: now(), timeZone: .current, limit: 8)
    }
    private func lastDose(for substance: String) -> (Double?, String?) {
        let hit = recent.first { $0.subtype == substance && [.medication, .supplement, .peptide].contains($0.category) }
        return (hit?.value, hit?.unit)
    }
    /// Chip tap: log this substance again at its last-used amount/unit.
    @discardableResult
    func logChip(substance: String, at timestamp: Date) async -> HealthEvent? {
        let (amount, u) = lastDose(for: substance)
        do { return try await capture.logDose(substance: substance, kind: kind, amount: amount, unit: u, route: nil, at: timestamp) }
        catch { return nil }
    }
    /// Form: log the typed substance/amount/unit/route.
    @discardableResult
    func saveForm(at timestamp: Date) async -> HealthEvent? {
        let name = substance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let amount = Double(amountText.replacingOccurrences(of: ",", with: "."))
        do {
            return try await capture.logDose(substance: name, kind: kind, amount: amount,
                                             unit: amount == nil ? nil : unit,
                                             route: route.isEmpty ? nil : route, at: timestamp)
        } catch { return nil }
    }
}

struct DoseCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    @StateObject private var model = DoseCaptureModel(database: HealthGraphProvider.shared)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Kind", selection: $model.kind) {
                    Text("Medication").tag(DoseKind.medication)
                    Text("Supplement").tag(DoseKind.supplement)
                    Text("Peptide").tag(DoseKind.peptide)
                }.pickerStyle(.segmented)

                if !model.chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.chips, id: \.self) { s in
                                Button {            // chip tap logs at the last-used amount/unit
                                    Task { if let e = await model.logChip(substance: s, at: timestamp) { onLogged(e) } }
                                } label: {
                                    Text(s).font(.footnote).padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(HealthTheme.card))
                                        .overlay(Capsule().strokeBorder(HealthTheme.cardBorder, lineWidth: 1))
                                        .foregroundStyle(HealthTheme.inkSecondary)
                                        .frame(minHeight: 44).contentShape(Rectangle())
                                }.accessibilityLabel("Log \(s)")
                            }
                        }
                    }
                }
                TextField("Substance name", text: $model.substance).padding(12).hgCard()
                HStack(spacing: 12) {
                    TextField("Amount", text: $model.amountText)
                        .keyboardType(.decimalPad).padding(12).hgCard()
                    Menu {
                        ForEach(DoseCaptureModel.units, id: \.self) { u in
                            Button(u) { model.unit = u }
                        }
                    } label: {
                        HStack { Text(model.unit); Image(systemName: "chevron.down").font(.footnote) }
                            .padding(12).frame(minHeight: 44).hgCard()
                    }
                }
                if model.kind != .supplement {
                    TextField("Route (e.g. subQ, oral)", text: $model.route).padding(12).hgCard()
                }
                Button {
                    Task {
                        if let e = await model.saveForm(at: timestamp) {
                            onLogged(e); model.substance = ""; model.amountText = ""; model.route = ""
                        }
                    }
                } label: { Text("Log dose").frame(maxWidth: .infinity).padding(.vertical, 12) }
                    .buttonStyle(.borderedProminent).tint(HealthTheme.accent)
                    .foregroundStyle(HealthTheme.onAccent)
                    .disabled(model.substance.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(minHeight: 44)
            }
            .padding(16)
        }
        .task { await model.loadChips() }
    }
}
```

- [ ] **Step 4: Run the appended test + full suite; expect pass.**
- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS/Capture "Food IntolerancesTests/CaptureFlowTests.swift" && git commit -m "feat(app): dose capture — med/supplement/peptide with amount, unit, route"
```

---

### Task 12: App — note capture (multiline text)

**Files:**
- Modify: `Views/HealthOS/Capture/NoteCaptureView.swift` (replace skeleton)
- Test: `Food IntolerancesTests/CaptureFlowTests.swift` (append)

**Interfaces:** Consumes `CaptureService.logNote`, coordinator, tokens. Produces a `.note` event whose text is searchable (v3 FTS over subtype).

- [ ] **Step 1: Append the failing test**

```swift
    @Test func noteModelLogsSearchableNote() async throws {
        let database = try db()
        let store = GRDBEventStore(database: database)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let model = NoteCaptureModel(database: database)
        let e = await model.log(text: "Slept badly, groggy morning", at: base)
        #expect(e != nil)
        #expect(try await store.searchEvents(matching: "groggy", limit: 10).count == 1)
    }
```

- [ ] **Step 2: Run to verify failure** (`NoteCaptureModel` missing).

- [ ] **Step 3: Implement**

Replace `NoteCaptureView.swift`:

```swift
import SwiftUI
import HealthGraphCore

@MainActor
final class NoteCaptureModel: ObservableObject {
    @Published var text: String = ""
    private let capture: CaptureService
    init(database: AppDatabase) { capture = CaptureService(database: database) }
    @discardableResult
    func log(text: String, at timestamp: Date) async -> HealthEvent? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do { return try await capture.logNote(text: trimmed, at: timestamp) } catch { return nil }
    }
}

struct NoteCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    @StateObject private var model = NoteCaptureModel(database: HealthGraphProvider.shared)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Write a note", text: $model.text, axis: .vertical)
                .lineLimit(3...8).padding(12).hgCard()
            Button {
                Task { if let e = await model.log(text: model.text, at: timestamp) { onLogged(e); model.text = "" } }
            } label: { Text("Save note").frame(maxWidth: .infinity).padding(.vertical, 12) }
                .buttonStyle(.borderedProminent).tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .disabled(model.text.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(16)
    }
}
```

- [ ] **Step 4: Run the appended test + full suite; expect pass.**
- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS/Capture "Food IntolerancesTests/CaptureFlowTests.swift" && git commit -m "feat(app): note capture — searchable free-text note"
```

---

### Task 13: App — edit-in-detail (edit an event's fields)

**Files:**
- Create: `Views/HealthOS/Timeline/EventEditView.swift`
- Modify: `Views/HealthOS/Timeline/EventDetailView.swift` (replace the "Editing arrives…" footnote with an Edit button + sheet)
- Modify: `Views/HealthOS/Timeline/TimelineViewModel.swift` (add `update(_:)` — save the mutated event via `store.save`, bump `loadGeneration`, refresh the local slice)
- Test: `Food IntolerancesTests/TimelineViewModelTests.swift` (append)

**Interfaces:**
- Consumes: `EventStore.save` (upsert-by-id), `EventDisplay`, tokens.
- Produces: `TimelineViewModel.update(_ event: HealthEvent) async -> Bool` (persists the edit + refreshes the visible list); `EventEditView(event:viewModel:)`.

Design (locked): editing is re-saving the same `id` (upsert; the FTS `_au` trigger resyncs). `EventEditView` edits the fields that make sense for a manual event: **when** (`DatePicker`), **title/name** (`subtype` — the symptom display name, meal/dose/note text), **value** (severity slider for symptoms; amount field for doses; hidden otherwise), and (symptom) the note. It reconstructs the `HealthEvent` with the same `id`/`category`/`source`/`objectID` and changed fields, calls `viewModel.update`, and dismisses. `update` re-saves, and because the edit changes what's displayed, it reloads the visible slice (search-aware) like `refresh()`.

- [ ] **Step 1: Append the failing VM test**

In `TimelineViewModelTests.swift`:

```swift
    @Test func updatePersistsEditedEventAndRefreshes() async throws {
        let (_, store) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let e = HealthEvent(timestamp: base, category: .symptom, subtype: "headache",
                            value: 5, unit: "severity", source: .manual, createdAt: base)
        try await store.save(e)
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        await vm.loadInitial()
        var edited = e; edited.value = 9
        #expect(await vm.update(edited))
        // Persisted (upsert by id — still one row) and reflected.
        let page = try await store.eventsPage(before: nil, limit: 10, categories: nil, sources: nil)
        #expect(page.count == 1)
        #expect(page.first?.value == 9)
        #expect(vm.days.flatMap(\.events).first?.value == 9)
    }
```

(`makeStore()` is the existing private helper in the test file. `HealthEvent` is a `var`-mutable struct value, so `edited.value = 9` works.)

- [ ] **Step 2: Run to verify failure** (`update` missing).

- [ ] **Step 3: Implement `update` on the VM**

In `TimelineViewModel.swift`, add:

```swift
    /// Persist an edit (re-save by id = upsert; FTS resyncs) and refresh the visible list.
    @discardableResult
    func update(_ event: HealthEvent) async -> Bool {
        do { try await store.save(event) } catch { return false }
        loadGeneration &+= 1
        await refresh()   // search-aware; re-reads and regroups so the edit shows
        return true
    }
```

- [ ] **Step 4: Implement `EventEditView` + wire the detail button**

Create `Views/HealthOS/Timeline/EventEditView.swift`:

```swift
import SwiftUI
import HealthGraphCore

struct EventEditView: View {
    let original: HealthEvent
    @ObservedObject var viewModel: TimelineViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var timestamp: Date
    @State private var name: String
    @State private var severity: Double
    @State private var amountText: String

    init(event: HealthEvent, viewModel: TimelineViewModel) {
        self.original = event; self.viewModel = viewModel
        _timestamp = State(initialValue: event.timestamp)
        // Symptoms store a canonical camelCase key — show the human display name for editing.
        _name = State(initialValue: event.category == .symptom
                      ? SymptomCatalog.displayName(for: event.subtype ?? "")
                      : (event.subtype ?? ""))
        _severity = State(initialValue: event.value ?? 5)
        _amountText = State(initialValue: event.value.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "")
    }

    private var isSymptom: Bool { original.category == .symptom }
    private var isDose: Bool { [.medication, .supplement, .peptide].contains(original.category) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("When", selection: $timestamp, in: ...Date()).datePickerStyle(.compact)
                    TextField("Name", text: $name).padding(12).hgCard()
                    if isSymptom {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Severity: \(Int(severity))").font(.subheadline).foregroundStyle(HealthTheme.inkSecondary)
                            Slider(value: $severity, in: 1...10, step: 1).tint(CategoryFamily.symptoms.color)
                        }
                    } else if isDose {
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad).padding(12).hgCard()
                    }
                }
                .padding(16)
            }
            .background(HealthTheme.paper)
            .navigationTitle("Edit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        var edited = original
        edited.timestamp = timestamp
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Re-canonicalize a symptom name so the edited event stays in its severity series.
        edited.subtype = isSymptom ? SymptomCatalog.canonicalKey(for: trimmedName) : trimmedName
        if isSymptom { edited.value = severity; edited.unit = "severity" }
        else if isDose { edited.value = Double(amountText.replacingOccurrences(of: ",", with: ".")) }
        if await viewModel.update(edited) { dismiss() }
    }
}
```

In `EventDetailView.swift`, replace the "Editing arrives with capture, in the next update." footnote (the `Text(...)` block) with an Edit button that presents the editor, and add the sheet state:

```swift
    // add near the other @State:
    @State private var editing = false
    // replace the footnote Text(...) with:
    Button { editing = true } label: {
        Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity).padding(.vertical, 12)
    }
    .buttonStyle(.bordered)
    .sheet(isPresented: $editing) { EventEditView(event: event, viewModel: viewModel) }
```

- [ ] **Step 5: Run the VM test + full app suite**

Run the appended test and the full app suite (documented pattern). Expected: pass; the edit round-trips.

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add Views/HealthOS "Food IntolerancesTests/TimelineViewModelTests.swift" && git commit -m "feat(app): edit-in-detail — edit an event's when/name/value; upsert + search-aware refresh"
```

---

### Task 14: Hardening — carry-forward fixes (runSearch race, Insights stale, 0m segments)

**Files:**
- Modify: `Views/HealthOS/Timeline/TimelineViewModel.swift` (`runSearch` generation bump)
- Modify: `Views/HealthOS/Insights/InsightsPlaceholderView.swift` (reset counts on error)
- Modify: `HealthGraphCore/Sources/HealthGraphCore/Timeline/TimelineDayBuilder.swift` (drop 0-minute duration micro-segments)
- Test: `Food IntolerancesTests/TimelineViewModelTests.swift`, `HealthGraphCore/Tests/HealthGraphCoreTests/TimelineDayBuilderTests.swift` (append)

**Interfaces:**
- Consumes: nothing new.
- Produces: the three 1B carry-forwards closed.

Fixes:
1. **`runSearch()` generation race** (`TimelineViewModel.swift`): `runSearch` reads `loadGeneration` but never bumps it, so a stale in-flight search can repaint. Two edits: (a) add `loadGeneration &+= 1` at the TOP of `runSearch()` (before capturing `gen`) — a superseding search or `reloadFromScratch` then discards the stale one, and a search supersedes an in-flight browse `loadPage`; (b) also add `loadGeneration &+= 1` in the EMPTY branch of `searchTextChanged()` (the search-clear path, ~lines 101-103) so a still-suspended `runSearch` is discarded rather than resuming and repainting stale results over the just-restored browse slice. (Also move `isSearchActive = true` in `runSearch()` to AFTER its post-`await` `guard gen == loadGeneration` so a superseded search never flips the flag back on.)
2. **Insights stale-on-error** (`InsightsPlaceholderView.swift:57`): `guard let raw = try? await store.countsByCategory() else { return }` keeps stale counts. Change to reset on failure: `guard let raw = try? await store.countsByCategory() else { familyCounts = []; return }`.
3. **0-minute sleep micro-segments** (`TimelineDayBuilder.days`): HealthKit emits sub-30-second sleep stages that render "0m" rows. In `TimelineDayBuilder.days`, drop DURATION events shorter than 1 minute (`endTimestamp != nil` AND `endTimestamp - timestamp < 60`); keep ALL point events (`endTimestamp == nil`) regardless of value. This declutters the sleep sections without hiding any point-in-time data.

- [ ] **Step 1: Write the failing tests**

Append to `TimelineDayBuilderTests.swift`:

```swift
    @Test func dropsSubMinuteDurationMicroSegments() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let micro = HealthEvent(timestamp: base, endTimestamp: base.addingTimeInterval(20),
                                category: .sleep, subtype: "awake", value: 0, unit: "min",
                                source: .healthKit, createdAt: base)
        let real = HealthEvent(timestamp: base.addingTimeInterval(100), endTimestamp: base.addingTimeInterval(100 + 600),
                               category: .sleep, subtype: "asleepCore", value: 10, unit: "min",
                               source: .healthKit, createdAt: base)
        let days = TimelineDayBuilder.days(from: [real, micro], timeZone: TimeZone(identifier: "UTC")!)
        #expect(days.flatMap(\.events).map(\.subtype) == ["asleepCore"])   // micro dropped
    }
    @Test func keepsPointEventsEvenWithZeroValue() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let point = HealthEvent(timestamp: base, category: .symptom, subtype: "headache",
                                value: 0, unit: "severity", source: .manual, createdAt: base)
        let days = TimelineDayBuilder.days(from: [point], timeZone: TimeZone(identifier: "UTC")!)
        #expect(days.flatMap(\.events).count == 1)   // point event kept
    }
```

Append to `TimelineViewModelTests.swift`:

```swift
    @Test func runSearchBumpsGenerationSoStaleSearchDiscarded() async throws {
        // Behavioural pin: after a search then a clear, the browse slice is shown (no stale search repaint).
        let (_, store) = try makeStore()
        _ = try await seed(store, count: 3)
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        await vm.loadInitial()
        vm.searchText = "item0"; await vm.searchTextChanged()
        #expect(vm.isSearchActive)
        vm.searchText = ""; await vm.searchTextChanged()
        #expect(!vm.isSearchActive)
        #expect(vm.days.flatMap(\.events).count == 3)
    }
```

- [ ] **Step 2: Run to verify the new package test fails** (micro-segment not yet dropped); the VM test may pass already (it pins behavior) — that's fine, keep it as a regression guard.

- [ ] **Step 3: Implement the three fixes** (as described above).

For fix 3, in `TimelineDayBuilder.days`, filter the input before bucketing:

```swift
        let kept = events.filter { e in
            guard let end = e.endTimestamp else { return true }        // point events kept
            return end.timeIntervalSince(e.timestamp) >= 60            // duration >= 1 min
        }
```
and group `kept` instead of `events`.

- [ ] **Step 4: Run both suites**

```bash
cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO 2>&1 | tail -12
```
Expected: package `98/98` (96 + 2 new); app suite = documented pattern with the new VM test passing.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/FoodIntolerances && git add HealthGraphCore Views/HealthOS "Food IntolerancesTests/TimelineViewModelTests.swift" && git commit -m "fix(app+core): runSearch generation guard; Insights reset-on-error; drop sub-minute sleep micro-segments"
```

---

### Task 15: Whole-branch verification + human checkpoint

**Files:** none (verification only).

- [ ] **Step 1: Full suites, exact counts**

```bash
cd /Users/leo/Desktop/FoodIntolerances/HealthGraphCore && swift test 2>&1 | tail -3
cd /Users/leo/Desktop/FoodIntolerances && xcodebuild test -project "Food Intolerances.xcodeproj" -scheme "Food Intolerances" -destination 'platform=iOS Simulator,id=D9732FC9-1EDA-4BC8-B4FA-5C1DBA8D47EF' -parallel-testing-enabled NO 2>&1 | tail -12
```
Expected: package **98 tests / 15 suites**; app suite = prior tests + `CaptureFlowTests` (symptom/meal/dose/note) + the new TimelineViewModel tests, with exactly the ONE documented SwiftData crash. Report per-test numbers.

- [ ] **Step 2: Done-criteria walk (report each)**

1. Center [+] opens the real capture sheet; the type picker + when-control work; the sheet stays open for multiple logs and swipe-dismisses.
2. Symptom capture: ranked chips appear; tapping a chip shows the 1–10 severity step and tapping a number logs it; search finds catalog symptoms and accepts a new one (slider + note form); each log appears at the top of the Timeline immediately.
3. Meal capture: tapping a ranked food chip logs it instantly; free-text name + Log also works; writes a `.food` event + object.
4. Dose capture: kind toggle; tapping a substance chip logs at its last amount/unit; the form (amount + unit + route) logs a new dose; writes a `.medication/.supplement/.peptide` event linked to a find-or-create object.
5. Note capture: multiline text + Save writes a searchable note.
6. Every log shows the "Logged … · Undo" toast; Undo removes the event (soft delete) and the tabs reflect it.
7. Capturing while on Home/Insights refreshes those tabs (the coordinator write-through).
8. Search finds a just-logged meal/note by text AND a dose by its object name.
8. Edit a timeline event (when/name/severity/amount) → the change persists (one row, upsert) and shows.
9. No "0m" sleep micro-segment rows in the Timeline; real sleep stages unaffected.
10. Both appearance modes legible; XXL Dynamic Type survives the capture sheet + edit sheet; VoiceOver labels on chips/slider/buttons; capture buttons use `onAccent` (no raw white).
11. No causal language; no health values/subtypes/note text in logs.

- [ ] **Step 3: HUMAN CHECKPOINT — hand to Leo for on-device verification**

Build to Leo's iPhone. Ask him to log, on his real ~136k-event graph: a symptom (chip + severity), a meal, a peptide dose, and a note; confirm each appears on the Timeline instantly and survives an app relaunch (the graph is now the source of truth — no schema-reset wipe); search finds the note text and the dose substance; edit one event; capture while on Insights and confirm its counts update; dark mode + XXL. Findings feed fixes before merge (1A/1B precedent: checkpoint rounds).

- [ ] **Step 4: Dispatch the whole-branch review** (controller does this per subagent-driven-development; final review on the most capable model, with the accumulated Minor-findings list).

## Carried forward (NOT this plan)

- **Voice capture** (Foundation Models `@Generable`), **photo capture** (vision LLM), **App Intents** (Siri/Shortcuts/widgets), **onboarding**, the **body-map** symptom picker, and the **full cabinet** (vial inventory, reconstitution → doses-remaining, injection-site rotation, on/off cycles, reorder alerts) — all Plan 1D / later, per the approved split.
- **Object rename/edit**: `GRDBObjectStore` has no update method — editing a linked object's *name* (vs the event's subtype) is deferred; the edit path edits event fields only.
- **Explicit event `update` API**: 1C uses `save` (upsert) as the edit path; a dedicated partial-update method is deferred if ever needed.
- **Legacy debug-log noise**: `LogItemViewModel`'s symptom-catalog `Logger.debug` dump on startup — quiet it in a legacy-cleanup pass.
- **1B deferrals still open**: EventDisplay coverage gaps, the 120pt detail label column at XXL (make flexible), backfill-card gating test — fold into a future hardening task.
- **Dedup policy for manual vs import**: manual entries never dedup against imports today; revisit if double-counting (e.g. a manually-logged workout also imported from HealthKit) becomes a real complaint.
