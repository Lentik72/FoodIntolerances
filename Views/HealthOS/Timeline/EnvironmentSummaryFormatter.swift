import Foundation
import HealthGraphCore

/// Builds the collapsed headline and expanded detail lines for an Environment
/// summary row, honoring the user's °C/°F setting for temperature. Pure.
enum EnvironmentSummaryFormatter {
    /// Collapsed one-liner: temperature range (· humidity) when present; else moon
    /// phase (· season); else the single remaining reading.
    static func headline(_ summary: EnvironmentDaySummary, unit: TemperatureUnit) -> String {
        if let temp = value("temperature", summary, unit) {
            if let hum = value("humidity", summary, unit) { return "\(temp) · \(hum)" }
            return temp
        }
        if let moon = value("moonPhase", summary, unit) {
            if let season = value("season", summary, unit) { return "\(moon) · \(season)" }
            return moon
        }
        if let first = detailLines(summary, unit: unit).first {
            return first.value.map { "\(first.label): \($0)" } ?? first.label
        }
        return "Environment"
    }

    /// Ordered (label, value?) rows. `value == nil` → a presence line (mercury).
    /// pressureDrop is folded into the Air pressure line, not its own row.
    static func detailLines(_ summary: EnvironmentDaySummary, unit: TemperatureUnit) -> [(label: String, value: String?)] {
        var rows: [(label: String, value: String?)] = []
        for e in summary.events {
            guard let subtype = e.subtype else { continue }
            switch subtype {
            case "pressureDrop":
                continue   // folded into the pressure line
            case "pressure":
                var v = EventDisplay.valueLine(for: e)
                if let drop = summary.events.first(where: { $0.subtype == "pressureDrop" }), let d = drop.value {
                    v = [v, "↓\(Int(d.rounded())) hPa"].compactMap { $0 }.joined(separator: " · ")
                }
                rows.append((EventDisplay.title(for: e), v))
            default:
                rows.append((EventDisplay.title(for: e), value(subtype, summary, unit)))
            }
        }
        // Defensive: a lone pressureDrop with no pressure event still shows.
        if !summary.events.contains(where: { $0.subtype == "pressure" }),
           let drop = summary.events.first(where: { $0.subtype == "pressureDrop" }) {
            rows.append((EventDisplay.title(for: drop), EventDisplay.valueLine(for: drop)))
        }
        return rows
    }

    /// Display value for a subtype: temperature/humidity via the unit-aware
    /// WeatherValueFormatter, everything else via EventDisplay.
    private static func value(_ subtype: String, _ summary: EnvironmentDaySummary, _ unit: TemperatureUnit) -> String? {
        guard let e = summary.events.first(where: { $0.subtype == subtype }) else { return nil }
        return WeatherValueFormatter.line(for: e, unit: unit) ?? EventDisplay.valueLine(for: e)
    }
}
