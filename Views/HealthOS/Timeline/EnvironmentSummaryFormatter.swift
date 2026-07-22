import Foundation
import HealthGraphCore

/// One expanded environment reading. `id` is the source event's id — stable SwiftUI
/// identity even when a day has duplicate subtypes/provenance (avoids duplicate
/// `ForEach` ids). `subtype` lets the row identify the AQI line structurally; `aqi` is
/// set ONLY for the airQuality line — the badge's color input. `value == nil` → a
/// presence line (mercury).
struct EnvironmentDetailLine: Identifiable {
    let id: UUID
    let subtype: String?
    let label: String
    let value: String?
    let aqi: Int?
}

/// The collapsed headline plus the AQI it displays, if any. `aqi` is non-nil whenever
/// the SELECTED headline actually shows an AQI value — a poor-air lead OR a good-air
/// degenerate "Air quality: …" fallback — so the row badges every headline that shows
/// an AQI, not only poor-air ones.
struct EnvironmentHeadline {
    let text: String
    let aqi: Int?
}

/// Builds the collapsed headline and expanded detail lines for an Environment
/// summary row, honoring the user's °C/°F setting for temperature. Pure.
enum EnvironmentSummaryFormatter {
    /// Collapsed one-liner + the AQI it displays (if any). Temperature range (· humidity)
    /// when present; else moon phase (· season); else the single remaining reading. A
    /// poor-air day leads with the AQI; a day whose only/first reading is airQuality shows
    /// it via the degenerate fallback — both set `aqi` so the row badges them.
    static func headlineResult(_ summary: EnvironmentDaySummary, unit: TemperatureUnit) -> EnvironmentHeadline {
        // Poor-air days lead with the AQI — the most health-salient signal that day.
        if let aqi = poorAirAQI(summary) {
            return EnvironmentHeadline(text: "AQI \(aqi) · \(AirQualityIndex.category(aqi: aqi).name)", aqi: aqi)
        }
        if let temp = value("temperature", summary, unit) {
            if let hum = value("humidity", summary, unit) { return EnvironmentHeadline(text: "\(temp) · \(hum)", aqi: nil) }
            return EnvironmentHeadline(text: temp, aqi: nil)
        }
        if let moon = value("moonPhase", summary, unit) {
            if let season = value("season", summary, unit) { return EnvironmentHeadline(text: "\(moon) · \(season)", aqi: nil) }
            return EnvironmentHeadline(text: moon, aqi: nil)
        }
        if let first = detailLines(summary, unit: unit).first {
            // The degenerate lead carries an AQI only when that first line IS the airQuality line.
            let text = first.value.map { "\(first.label): \($0)" } ?? first.label
            return EnvironmentHeadline(text: text, aqi: first.aqi)
        }
        return EnvironmentHeadline(text: "Environment", aqi: nil)
    }

    /// The collapsed headline text (delegates to `headlineResult`; kept for the row's
    /// a11y label and the existing headline tests).
    static func headline(_ summary: EnvironmentDaySummary, unit: TemperatureUnit) -> String {
        headlineResult(summary, unit: unit).text
    }

    /// The AQI value when the collapsed headline leads with AQI (a poor-air day, AQI
    /// >= poorAirThreshold), else nil. Shares the poor-air check with `headline` so the
    /// dot appears exactly when the headline shows the AQI.
    static func poorAirAQI(_ summary: EnvironmentDaySummary) -> Int? {
        guard let aq = summary.events.first(where: { $0.subtype == "airQuality" }),
              let v = aq.value, Int(v) >= AirQualityIndex.poorAirThreshold else { return nil }
        return Int(v)
    }

    /// Ordered detail rows. `value == nil` → a presence line (mercury).
    /// pressureDrop is folded into the Air pressure line, not its own row.
    static func detailLines(_ summary: EnvironmentDaySummary, unit: TemperatureUnit) -> [EnvironmentDetailLine] {
        var rows: [EnvironmentDetailLine] = []
        for e in summary.events {
            guard let subtype = e.subtype, subtype != "pressureDrop" else { continue }   // nil subtype skipped; pressureDrop folds into pressure
            // Format the text from THIS event so the value always matches the line's own
            // aqi/provenance — never a different same-subtype event chosen by a lookup.
            let text = WeatherValueFormatter.line(for: e, unit: unit) ?? EventDisplay.valueLine(for: e)
            switch subtype {
            case "pressure":
                var v = text
                if let drop = summary.events.first(where: { $0.subtype == "pressureDrop" }), let d = drop.value {
                    v = [v, "↓\(Int(d.rounded())) hPa"].compactMap { $0 }.joined(separator: " · ")
                }
                rows.append(EnvironmentDetailLine(id: e.id, subtype: subtype, label: EventDisplay.title(for: e), value: v, aqi: nil))
            case "airQuality":
                rows.append(EnvironmentDetailLine(id: e.id, subtype: subtype, label: EventDisplay.title(for: e), value: text, aqi: e.value.map { Int($0) }))
            default:
                rows.append(EnvironmentDetailLine(id: e.id, subtype: subtype, label: EventDisplay.title(for: e), value: text, aqi: nil))
            }
        }
        // Defensive: a lone pressureDrop with no pressure event still shows.
        if !summary.events.contains(where: { $0.subtype == "pressure" }),
           let drop = summary.events.first(where: { $0.subtype == "pressureDrop" }) {
            rows.append(EnvironmentDetailLine(id: drop.id, subtype: drop.subtype, label: EventDisplay.title(for: drop),
                                              value: EventDisplay.valueLine(for: drop), aqi: nil))
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
