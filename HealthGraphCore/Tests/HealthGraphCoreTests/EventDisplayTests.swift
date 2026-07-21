import Foundation
import Testing
@testable import HealthGraphCore

struct EventDisplayMoodTests {
    private func mood(_ v: Double) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .mood,
                    subtype: "mood", value: v, source: .manual)
    }
    @Test func moodTitleShowsTheLevel() {
        #expect(EventDisplay.title(for: mood(1)) == "Mood: Rough")
        #expect(EventDisplay.title(for: mood(2)) == "Mood: Okay")
        #expect(EventDisplay.title(for: mood(3)) == "Mood: Good")
    }
    @Test func moodTitleClampsOutOfRangeValues() {
        #expect(EventDisplay.title(for: mood(0)) == "Mood: Rough")   // guards orphaned/garbage
        #expect(EventDisplay.title(for: mood(4)) == "Mood: Good")    // old "Good"
        #expect(EventDisplay.title(for: mood(5)) == "Mood: Good")    // old "Great"
    }
    @Test func moodValueLineIsNilBecauseTitleCarriesIt() {
        #expect(EventDisplay.valueLine(for: mood(2)) == nil)
    }
}

struct EventDisplayAirQualityTests {
    private func airQuality(_ v: Double) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .environment,
                    subtype: "airQuality", value: v, source: .weatherAPI)
    }
    @Test func titleIsAirQuality() {
        #expect(EventDisplay.title(for: airQuality(132)) == "Air quality")
    }
    @Test func valueLineShowsAQIAndCategoryName() {
        #expect(EventDisplay.valueLine(for: airQuality(132)) == "132 · Unhealthy for sensitive groups")
    }
}
