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
            return try AppDatabase.open(at: url)
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
