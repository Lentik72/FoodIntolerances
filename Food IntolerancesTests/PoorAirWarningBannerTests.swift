import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct PoorAirWarningBannerTests {
    @Test func titleIsForecastOrientedAndHazardousVariant() {
        #expect(PoorAirWarningBanner.title(for: .unhealthySensitive) == "Air quality is forecast to be unhealthy")
        #expect(PoorAirWarningBanner.title(for: .unhealthy) == "Air quality is forecast to be unhealthy")
        #expect(PoorAirWarningBanner.title(for: .veryUnhealthy) == "Air quality is forecast to be unhealthy")
        #expect(PoorAirWarningBanner.title(for: .hazardous) == "Air quality is forecast to be hazardous")
    }
}
