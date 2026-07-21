import Foundation
import HealthGraphCore

/// The user's weight unit for Timeline display. Body mass is stored canonically
/// in kilograms (HealthKit + DB); this only affects how it's shown.
enum WeightUnit {
    case kilograms, pounds

    /// Unit abbreviation as shown in the Timeline.
    var abbreviation: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }

    /// Resolve the display unit from the profile's stored `unitPreference`
    /// ("imperial" → pounds, "metric" → kilograms). A nil preference (no profile)
    /// — or any unrecognized value — falls back to the device locale: US → pounds,
    /// everywhere else → kilograms. Locale is injectable for testability (mirrors
    /// `TemperatureUnit.localeDefault`).
    static func resolved(preference: String?, locale: Locale = .current) -> WeightUnit {
        switch preference {
        case "imperial": return .pounds
        case "metric": return .kilograms
        default: return locale.measurementSystem == .us ? .pounds : .kilograms
        }
    }
}

/// The Timeline value line for a body-weight event, in the user's unit, to one
/// decimal place. Returns nil for any non-weight event (caller falls back to the
/// weather formatter, then `EventDisplay.valueLine`). Stored weight is canonical kg.
enum BodyMetricValueFormatter {
    private static let poundsPerKilogram = 2.20462

    static func line(for event: HealthEvent, unit: WeightUnit) -> String? {
        guard event.category == .bodyMetric,
              event.subtype == "weight",
              event.unit == "kg",
              let kg = event.value else { return nil }
        let shown = unit == .pounds ? kg * poundsPerKilogram : kg
        return String(format: "%.1f %@", shown, unit.abbreviation)
    }
}
