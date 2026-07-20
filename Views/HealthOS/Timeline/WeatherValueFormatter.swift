import Foundation
import HealthGraphCore

enum TemperatureUnit: String, CaseIterable {
    case celsius = "C", fahrenheit = "F"

    /// Device-locale default: US (imperial) → °F, everywhere else → °C. Locale is
    /// injectable for testability.
    static func localeDefault(for locale: Locale = .current) -> TemperatureUnit {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }
    /// An explicit stored choice ("C"/"F") wins; empty/unknown → locale default.
    static func resolved(from raw: String, locale: Locale = .current) -> TemperatureUnit {
        TemperatureUnit(rawValue: raw) ?? localeDefault(for: locale)
    }
}

/// The Timeline value line for a weather event, in the user's unit, rounded to a
/// whole number. Returns nil for non-weather events (caller falls back to
/// EventDisplay.valueLine). Stored temperature is canonical °C.
enum WeatherValueFormatter {
    static func line(for event: HealthEvent, unit: TemperatureUnit) -> String? {
        guard event.category == .environment, let v = event.value else { return nil }
        switch event.subtype {
        case "temperature":
            let shown = unit == .fahrenheit ? v * 9 / 5 + 32 : v
            return "\(Int(shown.rounded()))°\(unit.rawValue)"     // rawValue is "C"/"F"
        case "humidity":
            return "\(Int(v.rounded()))%"
        default:
            return nil
        }
    }
}
