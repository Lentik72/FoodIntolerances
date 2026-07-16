import Foundation
import HealthGraphCore

@MainActor
final class InsightsRefreshCoordinator: ObservableObject {
    @Published private(set) var lastRecomputeAt: Date?

    private let database: AppDatabase
    private let minInterval: TimeInterval
    private let now: () -> Date
    private var lastWatermark = 0
    private var isRunning = false

    init(database: AppDatabase = HealthGraphProvider.shared,
         minInterval: TimeInterval = 900, now: @escaping () -> Date = { Date() }) {
        self.database = database; self.minInterval = minInterval; self.now = now
    }

    func refreshIfNeeded() async {
        // Set the flag SYNCHRONOUSLY after the guard (no await between), so concurrent
        // @MainActor triggers (appear + foreground + post-capture) can't overlap recomputes.
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let watermark = (try? await GRDBEventStore(database: database).count()) ?? lastWatermark
        guard RecomputePolicy.shouldRecompute(lastRunAt: lastRecomputeAt, lastWatermark: lastWatermark,
                                              now: now(), currentWatermark: watermark, minInterval: minInterval)
        else { return }   // defer resets isRunning
        _ = try? await EvidenceEngine(database: database).recompute(asOf: now())
        lastWatermark = watermark
        lastRecomputeAt = now()
    }

    /// Extension point (spec §6): register a nightly BGTask that calls the same recompute.
    /// Intentionally unimplemented for 2B.
    func scheduleBackgroundRecompute() { /* Phase 2B+: BGTaskScheduler wiring */ }
}
