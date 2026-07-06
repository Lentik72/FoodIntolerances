import Testing
import Foundation
import GRDB
import ZIPFoundation
@testable import HealthGraphCore

struct AppleHealthExportParserTests {
    static let fixtureXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <HealthData locale="en_US">
     <ExportDate value="2026-07-01 10:00:00 -0400"/>
     <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Health" unit="lb" \
    value="180" startDate="2026-06-01 08:00:00 -0400" endDate="2026-06-01 08:00:00 -0400"/>
     <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Watch" \
    value="HKCategoryValueSleepAnalysisAsleepDeep" \
    startDate="2026-06-01 01:00:00 -0400" endDate="2026-06-01 02:30:00 -0400"/>
     <Record type="HKCategoryTypeIdentifierHeadache" sourceName="Health" \
    value="HKCategoryValueSeverityModerate" \
    startDate="2026-06-01 11:00:00 -0400" endDate="2026-06-01 11:00:00 -0400"/>
     <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Phone" unit="count" \
    value="4000" startDate="2026-06-01 09:00:00 -0400" endDate="2026-06-01 09:10:00 -0400"/>
     <Record type="HKQuantityTypeIdentifierStepCount" sourceName="Phone" unit="count" \
    value="4200" startDate="2026-06-01 15:00:00 -0400" endDate="2026-06-01 15:10:00 -0400"/>
     <Record type="HKQuantityTypeIdentifierVO2Max" sourceName="Watch" unit="mL/min·kg" \
    value="41" startDate="2026-06-01 09:00:00 -0400" endDate="2026-06-01 09:00:00 -0400"/>
     <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="30" \
    durationUnit="min" totalDistance="5.2" totalDistanceUnit="km" totalEnergyBurned="412" \
    totalEnergyBurnedUnit="Cal" startDate="2026-06-01 07:00:00 -0400" \
    endDate="2026-06-01 07:30:00 -0400">
     </Workout>
    </HealthData>
    """

    func writeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).xml")
        try Self.fixtureXML.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func parsesFixtureIntoEvents() async throws {
        let db = try AppDatabase.inMemory()
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try AppleHealthExportParser(database: db).parse(xmlAt: url, progress: nil)

        // bodyMass + sleep + headache + workout + 1 daily steps event = 5
        #expect(result.summary.inserted == 5)
        #expect(result.recordsSkipped == 1) // VO2Max unmapped
        let store = GRDBEventStore(database: db)
        let byCategory = try await store.countsByCategory()
        #expect(byCategory["bodyMetric"] == 1)
        #expect(byCategory["sleep"] == 1)
        #expect(byCategory["symptom"] == 1)
        #expect(byCategory["exercise"] == 2) // workout + daily steps

        let all = try await store.recentEvents(limit: 10)
        let steps = all.first { $0.subtype == "steps" }
        #expect(steps?.value == 8200) // summed across the day
        #expect(steps?.endTimestamp != nil)
        let weight = all.first { $0.subtype == "weight" }
        #expect(abs((weight?.value ?? 0) - 81.6466) < 0.001)
        #expect(all.allSatisfy { $0.source == .healthExportFile })
        #expect(all.allSatisfy { $0.dedupKey != nil })
    }

    @Test func reparsingIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let parser = AppleHealthExportParser(database: db)
        _ = try parser.parse(xmlAt: url, progress: nil)
        let second = try parser.parse(xmlAt: url, progress: nil)
        #expect(second.summary.inserted == 0)
        #expect(try await GRDBEventStore(database: db).count() == 5)
    }

    @Test func malformedXMLThrows() throws {
        let db = try AppDatabase.inMemory()
        let malformed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="en_US">
         <Record type="HKQuantityTypeIdentifierBodyMass" <<<garbage
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).xml")
        try malformed.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self) {
            _ = try AppleHealthExportParser(database: db).parse(xmlAt: url, progress: nil)
        }
    }

    @Test func flushFailureSurfacesFromParse() throws {
        let db = try AppDatabase.inMemory()
        // Test-only sabotage: break the schema so the flush write fails.
        try db.dbWriter.write { try $0.execute(sql: "DROP TABLE health_events") }
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self) {
            _ = try AppleHealthExportParser(database: db).parse(xmlAt: url, progress: nil)
        }
    }

    @Test func extractsExportXMLFromZip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("apple_health_export"), withIntermediateDirectories: true)
        let xmlURL = dir.appendingPathComponent("apple_health_export/export.xml")
        try Self.fixtureXML.write(to: xmlURL, atomically: true, encoding: .utf8)
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        try FileManager.default.zipItem(
            at: dir.appendingPathComponent("apple_health_export"), to: zipURL)
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: zipURL)
        }
        let extracted = try ExportArchive.extractExportXML(from: zipURL)
        let content = try String(contentsOf: extracted, encoding: .utf8)
        #expect(content.contains("HKQuantityTypeIdentifierBodyMass"))
    }

    @Test func zipWithoutExportXMLThrows() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        try FileManager.default.zipItem(at: file, to: zipURL)
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: zipURL)
        }
        #expect(throws: ExportArchiveError.self) {
            _ = try ExportArchive.extractExportXML(from: zipURL)
        }
    }
}
