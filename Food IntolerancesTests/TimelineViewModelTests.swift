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
