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

    /// Integration: the core retired-subtype filter (TimelineDayBuilder) reaches the
    /// search surface — no season-specific code exists in TimelineViewModel.
    @Test func searchNeverShowsRetiredEnvironmentSubtypes() async throws {
        let (_, store) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save([
            HealthEvent(timestamp: base, category: .environment, subtype: "season",
                        source: .weatherAPI, createdAt: base),
            HealthEvent(timestamp: base.addingTimeInterval(60), category: .environment, subtype: "airQuality",
                        value: 42, source: .weatherAPI, createdAt: base),
        ])
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        vm.searchText = "season"
        await vm.searchTextChanged()
        #expect(vm.isSearchActive)
        #expect(vm.days.flatMap(\.events).isEmpty)   // the stored season row must never display
        vm.searchText = "airquality"
        await vm.searchTextChanged()
        #expect(vm.days.flatMap(\.events).map(\.subtype) == ["airQuality"])   // other env subtypes still pass
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

    @Test func undoWhileSearchingRestoresRowIntoVisibleResults() async throws {
        let (_, store) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let matching = HealthEvent(timestamp: base, category: .symptom, subtype: "headache",
                                    value: 5, unit: "severity", source: .manual, createdAt: base)
        let other = HealthEvent(timestamp: base.addingTimeInterval(60), category: .food, subtype: "toast",
                                 source: .manual, createdAt: base)
        try await store.save([matching, other])
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        await vm.loadInitial()
        vm.searchText = "head"
        await vm.searchTextChanged()
        #expect(vm.isSearchActive)
        #expect(vm.days.flatMap(\.events).map(\.id) == [matching.id])
        await vm.delete(matching)
        #expect(vm.pendingUndo?.id == matching.id)
        #expect(vm.days.flatMap(\.events).isEmpty)
        await vm.undoDelete()
        #expect(vm.pendingUndo == nil)
        #expect(vm.isSearchActive)
        // No searchTextChanged() call in between — undoDelete() itself must have
        // re-run the search so the restored row reappears in the visible results.
        #expect(vm.days.flatMap(\.events).map(\.id) == [matching.id])
    }

    @Test func undoOfSearchOnlyEventDoesNotDuplicateAfterLoadMore() async throws {
        let (_, store) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        // Oldest event is uniquely matchable via search but, with a page size of 2,
        // falls outside the first browse page (browse pages newest-first).
        let searchOnly = HealthEvent(timestamp: base, category: .symptom, subtype: "rareheadache",
                                      value: 5, unit: "severity", source: .manual, createdAt: base)
        let filler = try await seed(store, count: 4, startingAt: base.addingTimeInterval(1800))
        try await store.save([searchOnly])
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 2)
        await vm.loadInitial()
        let browseIds = vm.days.flatMap(\.events).map(\.id)
        #expect(!browseIds.contains(searchOnly.id))
        vm.searchText = "rarehead"
        await vm.searchTextChanged()
        #expect(vm.isSearchActive)
        #expect(vm.days.flatMap(\.events).map(\.id) == [searchOnly.id])
        await vm.delete(searchOnly)
        #expect(vm.pendingUndo?.id == searchOnly.id)
        await vm.undoDelete()
        #expect(vm.pendingUndo == nil)
        vm.searchText = ""
        await vm.searchTextChanged()
        #expect(!vm.isSearchActive)
        while vm.hasMore {
            await vm.loadMore()
        }
        let allIds = vm.days.flatMap(\.events).map(\.id)
        #expect(Set(allIds).count == allIds.count)
        #expect(allIds.filter { $0 == searchOnly.id }.count == 1)
        #expect(allIds.count == filler.count + 1)
    }

    @Test func refreshDuringActiveSearchStaysInSearchMode() async throws {
        let (_, store) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let matching = HealthEvent(timestamp: base, category: .symptom, subtype: "headache",
                                    value: 5, unit: "severity", source: .manual, createdAt: base)
        let other = HealthEvent(timestamp: base.addingTimeInterval(60), category: .food, subtype: "toast",
                                 source: .manual, createdAt: base)
        try await store.save([matching, other])
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        await vm.loadInitial()
        vm.searchText = "head"
        await vm.searchTextChanged()
        #expect(vm.isSearchActive)
        #expect(vm.days.flatMap(\.events).map(\.subtype) == ["headache"])
        await vm.refresh()
        #expect(vm.isSearchActive)
        // refresh() must have re-run the search, not reverted to the full browse slice.
        #expect(vm.days.flatMap(\.events).map(\.subtype) == ["headache"])
    }

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

    private func seedNight(_ store: GRDBEventStore, endingAt wake: Date) async throws {
        // Two contiguous stage segments ending at `wake`: core 4h then rem 4h.
        let core = HealthEvent(timestamp: wake.addingTimeInterval(-8 * 3600),
                               endTimestamp: wake.addingTimeInterval(-4 * 3600),
                               category: .sleep, subtype: "asleepCore", value: 240, unit: "min",
                               source: .healthKit, createdAt: wake)
        let rem = HealthEvent(timestamp: wake.addingTimeInterval(-4 * 3600), endTimestamp: wake,
                              category: .sleep, subtype: "asleepREM", value: 240, unit: "min",
                              source: .healthKit, createdAt: wake)
        try await store.save([core, rem])
    }

    @Test func browseCollapsesSleepIntoOneSessionItem() async throws {
        let (_, store) = try makeStore()
        let wake = Date(timeIntervalSince1970: 1_750_000_000)
        try await seedNight(store, endingAt: wake)
        try await store.save(HealthEvent(timestamp: wake.addingTimeInterval(600),
                                         category: .food, subtype: "coffee",
                                         source: .manual, createdAt: wake))
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        await vm.loadInitial()
        let sessions = vm.days.flatMap(\.items).compactMap { item -> SleepSession? in
            if case .sleepSession(let s) = item { s } else { nil }
        }
        #expect(sessions.count == 1)
        #expect(sessions[0].asleepMinutes == 480)
        #expect(vm.days.flatMap(\.events).allSatisfy { $0.category != .sleep })
    }

    private func weatherEvent(_ provenance: TemporalProvenance, hour: Int, day base: Date) -> HealthEvent {
        HealthEvent(timestamp: base.addingTimeInterval(Double(hour) * 3600), timezoneID: "UTC",
                    category: .environment, subtype: "temperature", value: 20, source: .weatherAPI,
                    metadata: try! JSONEncoder().encode(["provenance": provenance.rawValue]), createdAt: base)
    }

    /// A pageSize-1 browse slice contains ONLY the (later-stamped) forecast event;
    /// hydration must pull the observed sibling from the store so precedence
    /// suppresses the forecast — the boundary day shows actuals, not the forecast.
    @Test func tinyPageSplitOfWeatherSiblingsStillShowsObserved() async throws {
        let (_, store) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_750_032_000)   // 00:00 UTC of some day
        let forecast = weatherEvent(.forecast, hour: 18, day: base)          // 18:00 — newest
        let observed = weatherEvent(.observedCompletedDay, hour: 12, day: base)   // noon
        try await store.save([forecast, observed])
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 1)
        await vm.loadInitial()
        let envEvents = vm.days.flatMap(\.items).compactMap { item -> [HealthEvent]? in
            if case .environmentSummary(let s) = item { return s.events } else { return nil }
        }.flatMap { $0 }
        let temps = envEvents.filter { $0.subtype == "temperature" }
        #expect(temps.map(\.id) == [observed.id])   // observed displayed; split forecast suppressed
    }

    /// A searchLimit-1 result slice contains ONLY the forecast event; hydration
    /// completes the pair so raw search shows the observed value, not the forecast.
    @Test func searchLimitSplitOfWeatherSiblingsStillShowsObserved() async throws {
        let (_, store) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_750_032_000)
        let forecast = weatherEvent(.forecast, hour: 18, day: base)
        let observed = weatherEvent(.observedCompletedDay, hour: 12, day: base)
        try await store.save([forecast, observed])
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50, searchLimit: 1)
        vm.searchText = "temperature"
        await vm.searchTextChanged()
        let temps = vm.days.flatMap(\.events).filter { $0.subtype == "temperature" }
        #expect(temps.map(\.id) == [observed.id])
    }

    @Test func deletingEventOnSessionDayKeepsTheSession() async throws {
        let (_, store) = try makeStore()
        let wake = Date(timeIntervalSince1970: 1_750_000_000)
        try await seedNight(store, endingAt: wake)
        let coffee = HealthEvent(timestamp: wake.addingTimeInterval(600),
                                 category: .food, subtype: "coffee",
                                 source: .manual, createdAt: wake)
        try await store.save(coffee)
        let vm = TimelineViewModel(store: store, timeZone: TimeZone(identifier: "UTC")!, pageSize: 50)
        await vm.loadInitial()
        await vm.delete(coffee)
        // The raw event is gone; the session row survives the rebuild.
        #expect(vm.days.flatMap(\.events).isEmpty)
        let sessions = vm.days.flatMap(\.items).compactMap { item -> SleepSession? in
            if case .sleepSession(let s) = item { s } else { nil }
        }
        #expect(sessions.count == 1)
        await vm.undoDelete()
        #expect(vm.days.flatMap(\.events).map(\.subtype) == ["coffee"])
        #expect(vm.days.flatMap(\.items).count == 2)   // session + coffee
    }
}
