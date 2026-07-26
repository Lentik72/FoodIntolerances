import Testing
@testable import HealthGraphCore

@Suite struct PoorAirWarningDecisionTests {
    typealias Cat = AirQualityIndex.AQICategory
    func decide(_ aqi: Int?, dismissed: Cat? = nil, symptom: String? = nil) -> PoorAirWarning {
        PoorAirWarningDecision.decide(forecastAQI: aqi, highestDismissedBandToday: dismissed, personalizedSymptom: symptom)
    }

    @Test func nilOrBelowThresholdIsNone() {
        #expect(decide(nil) == .none)
        #expect(decide(100) == .none)                         // below 101
    }
    @Test func atThresholdShowsUnhealthySensitive() {
        #expect(decide(101) == .show(aqi: 101, band: .unhealthySensitive, personalizedSymptom: nil))
    }
    @Test func bandMatchesCategoryMapping() {
        #expect(decide(175) == .show(aqi: 175, band: .unhealthy, personalizedSymptom: nil))
        #expect(decide(350) == .show(aqi: 350, band: .hazardous, personalizedSymptom: nil))
    }
    @Test func suppressedWhenDismissedSameBand() {
        #expect(decide(120, dismissed: .unhealthySensitive) == .none)
        #expect(decide(120, dismissed: .unhealthy) == .none)  // dismissed a HIGHER band today → still suppressed
    }
    @Test func reshownWhenBandEscalatesAboveDismissed() {
        #expect(decide(175, dismissed: .unhealthySensitive) == .show(aqi: 175, band: .unhealthy, personalizedSymptom: nil))
    }
    @Test func personalizedSymptomPassesThrough() {
        #expect(decide(160, symptom: "cough") == .show(aqi: 160, band: .unhealthy, personalizedSymptom: "cough"))
    }
}
