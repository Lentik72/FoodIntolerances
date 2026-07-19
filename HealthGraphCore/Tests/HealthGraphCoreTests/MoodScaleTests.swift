import Foundation
import Testing
@testable import HealthGraphCore

struct MoodScaleTests {
    @Test func levelsAreOrderedOneToThree() {
        #expect(MoodLevel.allCases.map(\.rawValue) == [1, 2, 3])
    }
    @Test func labels() {
        #expect(MoodLevel.rough.label == "Rough")
        #expect(MoodLevel.okay.label == "Okay")
        #expect(MoodLevel.good.label == "Good")
    }
    @Test func clampingMapsAnyIntToNearestLevel() {
        #expect(MoodLevel(clamping: -5) == .rough)
        #expect(MoodLevel(clamping: 0) == .rough)
        #expect(MoodLevel(clamping: 1) == .rough)
        #expect(MoodLevel(clamping: 2) == .okay)
        #expect(MoodLevel(clamping: 3) == .good)
        #expect(MoodLevel(clamping: 4) == .good)
        #expect(MoodLevel(clamping: 99) == .good)
    }
    @Test func logMoodWritesAMoodEvent() async throws {
        let db = try AppDatabase.inMemory()
        let event = try await CaptureService(database: db).logMood(
            level: .good, at: Date(timeIntervalSince1970: 1_700_000_000), note: "sunny walk")
        #expect(event.category == .mood)
        #expect(event.subtype == "mood")
        #expect(event.value == 3)     // Good is 3 on the 1–3 scale
        #expect(event.source == .manual)
        let dict = try JSONDecoder().decode([String: String].self, from: #require(event.metadata))
        #expect(dict["note"] == "sunny walk")   // note round-trips into metadata
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.contains { $0.id == event.id })
    }
}
