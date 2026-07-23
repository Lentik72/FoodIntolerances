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
    private let searchLimit: Int
    private var browseEvents: [HealthEvent] = []
    private var cursor: TimelineCursor?
    private var undoTimer: Task<Void, Never>?
    /// Whether the event currently pending undo was actually present in `browseEvents`
    /// (as opposed to a search-only row never paged into the browse slice). Guards
    /// `undoDelete()`'s re-insert so we don't duplicate a row that `loadMore()` will
    /// later re-fetch from the DB anyway.
    private var pendingUndoWasInBrowse = false
    /// Bumped by `reloadFromScratch()` on every fresh load. `loadPage()`/`runSearch()`
    /// capture it before their await and re-check it after, so a superseded in-flight
    /// load (e.g. a stale page fetch racing a filter change that already reset the
    /// slice) discards its results instead of corrupting the current one.
    private var loadGeneration = 0

    init(store: any EventStore, timeZone: TimeZone = .current, pageSize: Int = 200, searchLimit: Int = 400) {
        self.store = store
        self.timeZone = timeZone
        self.pageSize = pageSize
        self.searchLimit = searchLimit
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
        if isSearchActive {
            await runSearch()
        } else {
            await reloadFromScratch()
        }
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
            // Discard any still-suspended runSearch() so it can't resume later and
            // repaint stale search results over the just-restored browse slice.
            loadGeneration &+= 1
            isSearchActive = false
            days = TimelineDayBuilder.days(from: browseEvents, timeZone: timeZone)
        } else {
            await runSearch()
        }
    }

    @discardableResult
    func delete(_ event: HealthEvent) async -> Bool {
        do {
            try await store.softDelete(id: event.id)
        } catch {
            return false // row untouched; keep UI consistent with the store
        }
        let wasInBrowseSlice = browseEvents.contains { $0.id == event.id }
        browseEvents.removeAll { $0.id == event.id }
        if isSearchActive {
            // Search days hold raw rows only (sessionizeSleep: false), so a
            // surgical per-day rebuild is still valid here.
            days = days.compactMap { day in
                guard day.events.contains(where: { $0.id == event.id }) else { return day }
                let remaining = day.events.filter { $0.id != event.id }
                guard !remaining.isEmpty else { return nil }
                return TimelineDayBuilder.days(from: remaining, timeZone: timeZone,
                                               sessionizeSleep: false, groupEnvironment: false).first
            }
        } else {
            // Browse days contain sleep sessions whose segments can span day
            // buckets — rebuild from the full remaining slice instead.
            days = TimelineDayBuilder.days(from: browseEvents, timeZone: timeZone)
        }
        pendingUndoWasInBrowse = wasInBrowseSlice
        armUndo(event)
        // Discard any in-flight loadPage() that snapshotted the DB before this
        // softDelete committed — otherwise it could re-append the deleted row.
        loadGeneration &+= 1
        return true
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
        if pendingUndoWasInBrowse {
            let insertAt = browseEvents.firstIndex {
                ($0.timestamp, $0.id.uuidString) < (event.timestamp, event.id.uuidString)
            } ?? browseEvents.endIndex
            browseEvents.insert(event, at: insertAt)
        }
        // A search-only row (never paged into browseEvents) doesn't need a manual
        // splice: re-running the active search re-surfaces it straight from the DB.
        if isSearchActive {
            await runSearch()
        } else {
            days = TimelineDayBuilder.days(from: browseEvents, timeZone: timeZone)
        }
    }

    func dismissUndo() {
        undoTimer?.cancel()
        pendingUndo = nil
        pendingUndoWasInBrowse = false
    }

    /// Persist an edit (re-save by id = upsert; FTS resyncs) and refresh the visible list.
    @discardableResult
    func update(_ event: HealthEvent) async -> Bool {
        do { try await store.save(event) } catch { return false }
        loadGeneration &+= 1
        await refresh()   // search-aware; re-reads and regroups so the edit shows
        return true
    }

    // MARK: private

    /// Observed-wins precedence needs COMPLETE same-day sibling context, but page
    /// and search slices can cut between a forecast weather event and its observed
    /// sibling (their timestamps differ within the day). Union the slice with ALL
    /// stored weather events across the slice's weather-day span so the core
    /// filter always sees both siblings. A store failure degrades to the
    /// unhydrated slice (display falls back to slice-relative behavior).
    private func hydratingWeatherSiblings(_ events: [HealthEvent]) async -> [HealthEvent] {
        let weatherSubtypes = EnvironmentDaySummaryBuilder.observedPrecedenceSubtypes
        let weatherStamps = events.compactMap { e -> Date? in
            guard e.category == .environment, weatherSubtypes.contains(e.subtype ?? "") else { return nil }
            return e.timestamp
        }
        guard let minTS = weatherStamps.min(), let maxTS = weatherStamps.max() else { return events }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let from = calendar.startOfDay(for: minTS)
        let through = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: maxTS)) ?? maxTS
        guard let siblings = try? await store.environmentEvents(subtypes: weatherSubtypes, from: from, through: through)
        else { return events }
        let known = Set(events.map(\.id))
        return events + siblings.filter { !known.contains($0.id) }
    }

    private func reloadFromScratch() async {
        loadGeneration &+= 1
        cursor = nil
        browseEvents = []
        hasMore = true
        await loadPage()
    }

    private func loadPage() async {
        let gen = loadGeneration
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await store.eventsPage(before: cursor, limit: pageSize,
                                                  categories: categoryFilter, sources: sourceFilter)
            // A newer reloadFromScratch() already reset cursor/browseEvents while this
            // fetch was in flight — discard the stale-filter results instead of
            // appending onto (and thereby corrupting) the current slice.
            guard gen == loadGeneration else { return }
            if let last = page.last {
                cursor = TimelineCursor(timestamp: last.timestamp, id: last.id)
            }
            hasMore = page.count == pageSize
            browseEvents.append(contentsOf: page)
            let hydrated = await hydratingWeatherSiblings(browseEvents)
            guard gen == loadGeneration else { return }   // hydration awaited — re-check staleness
            days = TimelineDayBuilder.days(from: hydrated, timeZone: timeZone)
        } catch {
            guard gen == loadGeneration else { return }
            hasMore = false
        }
    }

    private func runSearch() async {
        // A search supersedes any in-flight browse loadPage() and discards any
        // earlier in-flight search — bump before capturing gen so both are stale.
        loadGeneration &+= 1
        let gen = loadGeneration
        isLoading = true
        defer { isLoading = false }
        do {
            var results = try await store.searchEvents(matching: searchText, limit: searchLimit)
            guard gen == loadGeneration else { return }
            isSearchActive = true
            if let categoryFilter { results = results.filter { categoryFilter.contains($0.category) } }
            if let sourceFilter { results = results.filter { sourceFilter.contains($0.source) } }
            let hydrated = await hydratingWeatherSiblings(results)
            guard gen == loadGeneration else { return }
            days = TimelineDayBuilder.days(from: hydrated, timeZone: timeZone, sessionizeSleep: false, groupEnvironment: false)
        } catch {
            guard gen == loadGeneration else { return }
            isSearchActive = true
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
            self?.pendingUndoWasInBrowse = false
        }
    }
}
