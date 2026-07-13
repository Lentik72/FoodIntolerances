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

    @discardableResult
    func delete(_ event: HealthEvent) async -> Bool {
        do {
            try await store.softDelete(id: event.id)
        } catch {
            return false // row untouched; keep UI consistent with the store
        }
        let wasInBrowseSlice = browseEvents.contains { $0.id == event.id }
        browseEvents.removeAll { $0.id == event.id }
        days = days.compactMap { day in
            guard day.events.contains(where: { $0.id == event.id }) else { return day }
            let remaining = day.events.filter { $0.id != event.id }
            guard !remaining.isEmpty else { return nil }
            return TimelineDayBuilder.days(from: remaining, timeZone: timeZone).first
        }
        pendingUndoWasInBrowse = wasInBrowseSlice
        armUndo(event)
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

    // MARK: private

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
            days = TimelineDayBuilder.days(from: browseEvents, timeZone: timeZone)
        } catch {
            guard gen == loadGeneration else { return }
            hasMore = false
        }
    }

    private func runSearch() async {
        let gen = loadGeneration
        isLoading = true
        defer { isLoading = false }
        isSearchActive = true
        do {
            var results = try await store.searchEvents(matching: searchText, limit: 400)
            guard gen == loadGeneration else { return }
            if let categoryFilter { results = results.filter { categoryFilter.contains($0.category) } }
            if let sourceFilter { results = results.filter { sourceFilter.contains($0.source) } }
            days = TimelineDayBuilder.days(from: results, timeZone: timeZone)
        } catch {
            guard gen == loadGeneration else { return }
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
