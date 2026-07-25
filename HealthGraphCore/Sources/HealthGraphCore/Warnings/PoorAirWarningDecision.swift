/// The warning to render, or `.none`.
public enum PoorAirWarning: Equatable {
    case none
    case show(aqi: Int, band: AirQualityIndex.AQICategory, personalizedSymptom: String?)
}

/// Pure decision — no I/O, dates, or SwiftUI. All day-scoping is resolved by the
/// caller (which passes today's `highestDismissedBandToday`).
public enum PoorAirWarningDecision {
    public static func decide(
        forecastAQI: Int?,
        highestDismissedBandToday: AirQualityIndex.AQICategory?,
        personalizedSymptom: String?
    ) -> PoorAirWarning {
        guard let aqi = forecastAQI, aqi >= AirQualityIndex.poorAirThreshold else { return .none }
        let band = AirQualityIndex.category(aqi: aqi)
        // Show unless the user has already dismissed this band or a higher one today.
        if let dismissed = highestDismissedBandToday, band <= dismissed { return .none }
        return .show(aqi: aqi, band: band, personalizedSymptom: personalizedSymptom)
    }
}
