import Foundation
import Testing
@testable import HealthGraphCore

struct MoodScaleTests {
    @Test func levelsAreOrderedOneToFive() {
        #expect(MoodLevel.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
    }
    @Test func labelsAndEmoji() {
        #expect(MoodLevel.awful.label == "Awful")
        #expect(MoodLevel.great.label == "Great")
        #expect(MoodLevel.okay.emoji == "😐")
        #expect(MoodLevel(rawValue: 4)?.label == "Good")
    }
    @Test func logMoodWritesAMoodEvent() async throws {
        let db = try AppDatabase.inMemory()
        let event = try await CaptureService(database: db).logMood(
            level: .good, at: Date(timeIntervalSince1970: 1_700_000_000), note: "sunny walk")
        #expect(event.category == .mood)
        #expect(event.subtype == "mood")
        #expect(event.value == 4)
        #expect(event.source == .manual)
        let dict = try JSONDecoder().decode([String: String].self, from: #require(event.metadata))
        #expect(dict["note"] == "sunny walk")   // note round-trips into metadata
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.contains { $0.id == event.id })
    }
}
