import Foundation
import HealthGraphCore

/// TrajectoriesView's screen state: the published snapshots the body
/// renders, the window selection, and the synchronous load guard. Follows
/// the established pattern (`ConnectViewState`, `ExperimentViewState`,
/// `DataSourcesViewState`): `@MainActor`, a synchronous double-invocation
/// guard set BEFORE any dispatch, and the in-flight `Task` exposed
/// read-only so tests await it deterministically instead of spinning a run
/// loop. This repo has had three off-main-actor `@Published` cold-launch
/// crashes — the pattern is not optional.
///
/// Owns no verdict logic — `TrajectoryService` reads the corpus and buckets
/// it; this only decides WHEN to ask and publishes WHAT came back.
@MainActor
final class TrajectoriesViewState: ObservableObject {
    @Published private(set) var snapshots: [TrajectorySnapshot] = []
    @Published private(set) var window: TrendWindow = .weeks13
    @Published private(set) var isLoading = false

    private let service: TrajectoryService
    private let now: () -> Date

    /// Read-only outside; tests await it so assertions run deterministically
    /// after completion instead of spinning a run loop. Production code
    /// never reads it.
    private(set) var loadTask: Task<Void, Never>?

    /// `calendar` and `now` are injected at the app boundary (production
    /// passes `Calendar.current` and `Date.init`) so tests can pin both a
    /// fixed week grid and a fixed "as of" instant.
    init(eventStore: any EventStore, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.service = TrajectoryService(eventStore: eventStore, calendar: calendar)
        self.now = now
    }

    /// The guard runs SYNCHRONOUSLY, before any dispatch: two `.task`/
    /// `.onAppear` firings landing in the same main-actor turn must not
    /// enqueue two overlapping reads of the corpus.
    func appeared() {
        guard !isLoading else { return }
        isLoading = true
        loadTask = Task { await self.load(window: self.window) }
    }

    /// Same synchronous guard as `appeared()`. Re-selecting the already-
    /// current window is a no-op — it neither restarts an in-flight load
    /// nor issues a redundant one.
    func selectWindow(_ newWindow: TrendWindow) {
        guard !isLoading, newWindow != window else { return }
        window = newWindow
        isLoading = true
        loadTask = Task { await self.load(window: newWindow) }
    }

    private func load(window: TrendWindow) async {
        defer { isLoading = false }
        let asOf = now()
        do {
            snapshots = try await service.snapshots(window: window, asOf: asOf)
        } catch {
            Logger.error(error, message: "Failed to load trajectory snapshots", category: .data)
            snapshots = []
        }
    }
}
