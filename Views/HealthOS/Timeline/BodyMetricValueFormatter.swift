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
}

/// The Timeline value line for a body-weight event, in the user's unit, to one
/// decimal place. Returns nil for any non-weight event (caller falls back to the
/// weather formatter, then `EventDisplay.valueLine`). Stored weight is canonical kg.
enum BodyMetricValueFormatter {
    private static let poundsPerKilogram = 2.20462

    /// A raw kilogram value in the user's preferred unit, unformatted — what a
    /// chart plots, since a chart cannot plot a string. THE conversion: `line`
    /// formats exactly this, so copy and chart can never disagree, and no
    /// second `poundsPerKilogram` may exist anywhere in the app.
    static func value(kg: Double, unit: WeightUnit) -> Double {
        unit == .pounds ? kg * poundsPerKilogram : kg
    }

    /// Formats a raw kilogram value in the user's preferred unit, to one decimal place.
    static func line(kg: Double, unit: WeightUnit) -> String {
        String(format: "%.1f %@", value(kg: kg, unit: unit), unit.abbreviation)
    }

    static func line(for event: HealthEvent, unit: WeightUnit) -> String? {
        guard event.category == .bodyMetric,
              event.subtype == "weight",
              event.unit == "kg",
              let kg = event.value else { return nil }
        return line(kg: kg, unit: unit)
    }
}
