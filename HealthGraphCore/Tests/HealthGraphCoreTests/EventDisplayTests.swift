import Foundation
import Testing
@testable import HealthGraphCore

struct EventDisplayMoodTests {
    private func mood(_ v: Double) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .mood,
                    subtype: "mood", value: v, source: .manual)
    }
    @Test func moodTitleShowsTheLevel() {
        #expect(EventDisplay.title(for: mood(4)) == "Mood: Good")
        #expect(EventDisplay.title(for: mood(1)) == "Mood: Awful")
    }
    @Test func moodValueLineIsNilBecauseTitleCarriesIt() {
        #expect(EventDisplay.valueLine(for: mood(4)) == nil)
    }
}
