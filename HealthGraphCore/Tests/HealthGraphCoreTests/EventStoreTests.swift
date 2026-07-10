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
}
