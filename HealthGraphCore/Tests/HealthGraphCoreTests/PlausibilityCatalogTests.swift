import Testing
@testable import HealthGraphCore

struct PlausibilityCatalogTests {
    @Test func tiers() {
        #expect(PlausibilityCatalog.tier(forExposureCategory: "fullMoon") == .contested)
        #expect(PlausibilityCatalog.tier(forExposureCategory: "mercuryRetrograde") == .novelty)
        #expect(PlausibilityCatalog.tier(forExposureCategory: "food") == .established)
        #expect(PlausibilityCatalog.tier(forExposureCategory: "shortSleep") == .established)
        #expect(PlausibilityCatalog.tier(forExposureCategory: nil) == .established)
        #expect(PlausibilityCatalog.tier(forExposureCategory: "hotDay") == .contested)
        #expect(PlausibilityCatalog.tier(forExposureCategory: "coldDay") == .contested)
        #expect(PlausibilityCatalog.tier(forExposureCategory: "humidDay") == .contested)
    }
}
