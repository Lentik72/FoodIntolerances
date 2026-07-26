import SwiftUI
import HealthGraphCore

/// Dismissible, tier-scaled poor-air warning. NOT a takeover — stays outside the
/// red-flag/crisis interstitial system. Reuses the tuned AirNow palette via
/// `AQIValueLabel` (the value line) and `aqiColor(for:)` (the accent).
struct PoorAirWarningBanner: View {
    let aqi: Int
    let band: AirQualityIndex.AQICategory
    let personalizedSymptom: String?
    let isDismissible: Bool
    let onDismiss: () -> Void

    /// Testable — pins the forecast-oriented copy (spec Decision 2) + the hazardous variant.
    static func title(for band: AirQualityIndex.AQICategory) -> String {
        band == .hazardous ? "Air quality is forecast to be hazardous"
                           : "Air quality is forecast to be unhealthy"
    }
    private var accent: Color { aqiColor(for: band) }   // SAME palette as AQIBadge — all 6 bands distinct

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.title(for: band)).font(.subheadline.weight(.semibold))
                Spacer()
                if isDismissible {   // never during a pending fetch (VM sets isDismissible=false)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.footnote.weight(.bold))
                            .frame(width: 44, height: 44)          // ≥44×44 hit target
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Dismiss air quality warning")
                }
            }
            AQIValueLabel(value: "AQI \(aqi) · \(band.name)", aqi: aqi)   // tuned dot + VoiceOver-combined
                .font(.caption)
            Text(PoorAirWarningViewModel.guidance(for: band)).font(.caption)
            if let personalizedSymptom {
                Text("Poor-air days have been linked to your \(personalizedSymptom).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(band >= .veryUnhealthy ? 0.18 : 0.12),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.4), lineWidth: 1))
    }
}
