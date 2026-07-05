import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

struct AppDatabaseTests {
    @Test func migrationCreatesCoreTables() throws {
        let db = try AppDatabase.inMemory()
        try db.dbWriter.read { d in
            #expect(try d.tableExists("health_objects"))
            #expect(try d.tableExists("health_events"))
            #expect(try d.tableExists("relationships"))
            let eventCols = try d.columns(in: "health_events").map(\.name)
            #expect(eventCols.contains("timezoneID"))
            #expect(eventCols.contains("deletedAt"))
            #expect(eventCols.contains("attachmentPath"))
            let objCols = try d.columns(in: "health_objects").map(\.name)
            #expect(objCols.contains("normalizedName"))
            let relCols = try d.columns(in: "relationships").map(\.name)
            #expect(relCols.contains("contradictionCount"))
            #expect(relCols.contains("lagHours"))
            let eventIndexes = try d.indexes(on: "health_events").map(\.name)
            #expect(eventIndexes.contains("idx_events_category_timestamp"))
            #expect(eventIndexes.contains("idx_events_object_timestamp"))
        }
    }

    @Test func migrationIsIdempotentOnReopen() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("test.sqlite")
        _ = try AppDatabase.open(at: url)
        _ = try AppDatabase.open(at: url) // must not throw on second open
        try? FileManager.default.removeItem(at: dir)
    }
}
