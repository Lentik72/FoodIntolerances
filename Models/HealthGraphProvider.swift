import Foundation
import HealthGraphCore

/// App-wide access to the Health Graph database.
enum HealthGraphProvider {
    static let shared: AppDatabase = {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let url = support.appendingPathComponent("HealthGraph/healthgraph.sqlite")
            let db = try AppDatabase.open(at: url)
            #if !DEBUG
            // Guarantee fabricated demo rows never reach a shipped build. Runs
            // synchronously here, after migration and before this handle is
            // returned, so no reader observes the pre-purge state. The guard makes
            // it a true no-op on the common case (a DB that never held demo data).
            // No recompute is scheduled: the freshly constructed
            // InsightsRefreshCoordinator recomputes on its lastRecomputeAt==nil
            // never-run branch when Insights loads; a second here could race its
            // single-flight guard.
            //
            // FAIL CLOSED: `try`, not `try?`. If the purge throws, the outer
            // `catch` below fails database bootstrap (fatalError) rather than
            // exposing fabricated demo rows in a shipped build. A silent
            // `try?` would defeat the entire purpose of the Release purge.
            _ = try db.purgeSyntheticDataSync(scope: .all)
            #endif
            return db
        } catch {
            fatalError("Health Graph database could not be opened: \(error)")
        }
    }()

    /// Root folder for event attachments (photos). Paths stored on events
    /// are relative to Application Support.
    static func attachmentsDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = support.appendingPathComponent("HealthGraph/attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
