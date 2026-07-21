import Testing
@testable import HealthGraphCore

struct AirQualityIndexTests {
    @Test func epaAQIAtCategoryBoundaries() {
        #expect(AirQualityIndex.epaAQI(pm25: 0) == 0)
        #expect(AirQualityIndex.epaAQI(pm25: 12.0) == 50)
        #expect(AirQualityIndex.epaAQI(pm25: 12.1) == 51)
        #expect(AirQualityIndex.epaAQI(pm25: 35.4) == 100)
        #expect(AirQualityIndex.epaAQI(pm25: 35.5) == 101)   // the poorAirDay boundary
        #expect(AirQualityIndex.epaAQI(pm25: 55.4) == 150)
        #expect(AirQualityIndex.epaAQI(pm25: 55.5) == 151)
        #expect(AirQualityIndex.epaAQI(pm25: 9999) == 500)   // clamps above the top breakpoint
    }
    @Test func epaAQIInterpolatesWithinABin() {
        #expect(AirQualityIndex.epaAQI(pm25: 6.0) == 25)     // midpoint of Good bin (0–12→0–50)
        #expect(AirQualityIndex.epaAQI(pm25: 45.0) == 124)   // interior of 35.5–55.4 bin: (49/19.9)*9.5+101 → 124
    }
    @Test func epaAQITruncatesConcentrationToTenth() {
        // Pins the EPA 0.1-truncation: 35.49 → 35.4 → AQI 100 (NOT poor). Without the
        // truncation the value would round to 101 and flip poorAirDay. (Real meanPM25
        // output has many decimals, so this step is health-critical near the threshold.)
        #expect(AirQualityIndex.epaAQI(pm25: 35.49) == 100)
    }
    @Test func categoryNamesAndThreshold() {
        #expect(AirQualityIndex.category(aqi: 50).name == "Good")
        #expect(AirQualityIndex.category(aqi: 100).name == "Moderate")
        #expect(AirQualityIndex.category(aqi: 101).name == "Unhealthy for sensitive groups")
        #expect(AirQualityIndex.category(aqi: 175).name == "Unhealthy")
        #expect(AirQualityIndex.category(aqi: 250).name == "Very unhealthy")
        #expect(AirQualityIndex.category(aqi: 400).name == "Hazardous")
        #expect(AirQualityIndex.poorAirThreshold == 101)
    }
}
