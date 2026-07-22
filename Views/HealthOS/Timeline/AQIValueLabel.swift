import SwiftUI
import HealthGraphCore

/// The accessibility-adjusted AirNow color for an AQI category. Keys on the core
/// category (single source of the band thresholds); the six colors live in HealthTheme.
private func aqiColor(for category: AirQualityIndex.AQICategory) -> Color {
    switch category {
    case .good:               HealthTheme.aqiGood
    case .moderate:           HealthTheme.aqiModerate
    case .unhealthySensitive: HealthTheme.aqiUnhealthySensitive
    case .unhealthy:          HealthTheme.aqiUnhealthy
    case .veryUnhealthy:      HealthTheme.aqiVeryUnhealthy
    case .hazardous:          HealthTheme.aqiHazardous
    }
}

/// A small, decorative AQI severity dot (AirNow color for the value's band) with a
/// hairline border so light fills still read on cream. Never the sole signal — the
/// AQI number + category text always accompany it (see `AQIValueLabel`).
struct AQIBadge: View {
    let aqi: Int
    var body: some View {
        Circle()
            .fill(aqiColor(for: AirQualityIndex.category(aqi: aqi)))
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(HealthTheme.inkSecondary.opacity(0.35), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The single AQI-value presentation used at every site: the severity dot followed
/// by the caller-provided value text (e.g. "132 · Unhealthy for sensitive groups").
/// The caller applies its own `.font`/`.foregroundStyle` (the dot's fill is explicit,
/// so it is unaffected). Combined for VoiceOver so it reads the text once, dot silent.
struct AQIValueLabel: View {
    let value: String
    let aqi: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            AQIBadge(aqi: aqi)
            Text(value)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("AQI badges — all bands") {
    VStack(alignment: .leading, spacing: 10) {
        AQIValueLabel(value: "25 · Good", aqi: 25)
        AQIValueLabel(value: "75 · Moderate", aqi: 75)
        AQIValueLabel(value: "132 · Unhealthy for sensitive groups", aqi: 132)
        AQIValueLabel(value: "175 · Unhealthy", aqi: 175)
        AQIValueLabel(value: "250 · Very unhealthy", aqi: 250)
        AQIValueLabel(value: "350 · Hazardous", aqi: 350)
    }
    .font(.footnote)
    .padding()
    .background(HealthTheme.paper)
}
