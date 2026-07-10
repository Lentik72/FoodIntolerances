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

        // Second walk with limit: 1 forces every row onto its own page, so the
        // boundary between the two shared-timestamp rows must be crossed via a
        // fresh cursor. This is the only way to exercise the keyset WHERE
        // clause's `(timestamp = ? AND id < ?)` tiebreak branch: with limit 3
        // above, both shared-timestamp rows land inside a single page and the
        // branch is never evaluated across a page boundary.
        var seen2: [UUID] = []
        var cursor2: TimelineCursor? = nil
        while true {
            let page = try await store.eventsPage(before: cursor2, limit: 1, categories: nil, sources: nil)
            if page.isEmpty { break }
            #expect(page.count <= 1)
            seen2.append(contentsOf: page.map(\.id))
            cursor2 = TimelineCursor(timestamp: page.last!.timestamp, id: page.last!.id)
        }
        #expect(seen2.count == 7)                      // no skips
        #expect(Set(seen2).count == 7)                 // no dupes
        let stamps2 = seen2.map { byID[$0]! }
        #expect(stamps2 == stamps2.sorted(by: >))

        // The store orders ties by `id DESC`, where id is stored as a 16-byte
        // BLOB of the UUID's raw bytes (see UUID.databaseValue). Comparing
        // `uuidString` lexicographically matches that byte order exactly,
        // since the string is just those same bytes rendered as fixed-width
        // hex pairs with hyphens at identical positions in both operands.
        let sharedPair = all.filter { $0.timestamp == sharedTS }.map(\.id)
        #expect(sharedPair.count == 2)
        let orderedSharedIDs = sharedPair.sorted { $0.uuidString > $1.uuidString }
        let tiebreakFired = zip(seen2, seen2.dropFirst())
            .contains { $0 == orderedSharedIDs[0] && $1 == orderedSharedIDs[1] }
        #expect(tiebreakFired)                         // larger id, then smaller id, back-to-back
    }

    @Test func eventsPageAppliesCategoryAndSourceFilters() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let asleepCore = HealthEvent(timestamp: base, category: .sleep, subtype: "asleepCore", source: .healthKit, createdAt: base)
        let milk = HealthEvent(timestamp: base.addingTimeInterval(60), category: .food, subtype: "milk", source: .manual, createdAt: base)
        let running = HealthEvent(timestamp: base.addingTimeInterval(120), category: .exercise, subtype: "running", source: .healthKit, createdAt: base)
        // Extra rows for the combined cursor+categories+sources assertion
        // below, chosen so the three assertions above are unaffected: an
        // exercise+healthKit row (doesn't change the {sleep, exercise}
        // category set already produced by hkOnly) and a food+manual row
        // (excluded from hkOnly's source filter and from both's isEmpty
        // food+healthKit combo, same as milk already is).
        let cycling = HealthEvent(timestamp: base.addingTimeInterval(180), category: .exercise, subtype: "cycling", source: .healthKit, createdAt: base)
        let steak = HealthEvent(timestamp: base.addingTimeInterval(240), category: .food, subtype: "steak", source: .manual, createdAt: base)
        try await store.save([asleepCore, milk, running, cycling, steak])
        let sleepOnly = try await store.eventsPage(before: nil, limit: 10, categories: [.sleep], sources: nil)
        #expect(sleepOnly.map(\.subtype) == ["asleepCore"])
        let hkOnly = try await store.eventsPage(before: nil, limit: 10, categories: nil, sources: [.healthKit])
        #expect(Set(hkOnly.map(\.category)) == Set([.sleep, .exercise]))
        let both = try await store.eventsPage(before: nil, limit: 10, categories: [.food], sources: [.healthKit])
        #expect(both.isEmpty)

        // Combined cursor + categories + sources: the keyset predicate and
        // both IN filters must compose as an intersection, not independently.
        // The cursor points at cycling, so cycling itself is excluded by the
        // keyset even though it matches both IN filters; steak and milk are
        // excluded by category (and source); asleepCore and running are the
        // only rows that satisfy the keyset AND category-IN AND source-IN
        // simultaneously.
        let cursor = TimelineCursor(timestamp: cycling.timestamp, id: cycling.id)
        let combined = try await store.eventsPage(
            before: cursor, limit: 10, categories: [.sleep, .exercise], sources: [.healthKit]
        )
        #expect(combined.map(\.subtype) == ["running", "asleepCore"])
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
}
