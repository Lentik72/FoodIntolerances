import Foundation

/// One day's environmental readings, gathered by the app layer.
public struct EnvironmentalReading: Sendable {
    public let date: Date
    public let pressureHPa: Double?
    public let previousPressureHPa: Double?
    public let moonPhaseName: String?
    public let season: String?
    public let isMercuryRetrograde: Bool
    public let timezoneID: String
    public let temperatureC: Double?
    public let humidityPct: Double?

    public init(date: Date, pressureHPa: Double?, previousPressureHPa: Double?,
                moonPhaseName: String?, season: String?,
                isMercuryRetrograde: Bool, timezoneID: String,
                temperatureC: Double? = nil, humidityPct: Double? = nil) {
        self.date = date
        self.pressureHPa = pressureHPa
        self.previousPressureHPa = previousPressureHPa
        self.moonPhaseName = moonPhaseName
        self.season = season
        self.isMercuryRetrograde = isMercuryRetrograde
        self.timezoneID = timezoneID
        self.temperatureC = temperatureC
        self.humidityPct = humidityPct
    }
}

/// Synthesizes environment exposure events (spec §6.6). Ordinary exposures to
/// the engine — if the data shows no association, the app will say so.
public enum EnvironmentalEventFactory {
    public static let pressureDropThresholdHPa = 6.0

    public static func events(for r: EnvironmentalReading) -> [HealthEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: r.timezoneID) ?? .current
        let dayStart = cal.startOfDay(for: r.date)
        var events: [HealthEvent] = []

        func event(_ subtype: String, value: Double? = nil, unit: String? = nil,
                   metadata: [String: String]? = nil) -> HealthEvent {
            HealthEvent(
                timestamp: r.date, timezoneID: r.timezoneID,
                category: .environment, subtype: subtype,
                value: value, unit: unit, source: .weatherAPI,
                metadata: metadata.flatMap { try? JSONEncoder().encode($0) },
                dedupKey: DedupKey.daily(.environment, subtype, dayStart: dayStart)
            )
        }

        if let pressure = r.pressureHPa {
            events.append(event("pressure", value: pressure, unit: "hPa"))
            if let previous = r.previousPressureHPa,
               previous - pressure >= pressureDropThresholdHPa {
                events.append(event("pressureDrop", value: previous - pressure, unit: "hPa"))
            }
        }
        if let moon = r.moonPhaseName {
            let cleaned = moon.filter { $0.isLetter || $0.isWhitespace }
                .trimmingCharacters(in: .whitespaces)
            events.append(event("moonPhase", metadata: ["phase": cleaned]))
        }
        if r.isMercuryRetrograde {
            events.append(event("mercuryRetrograde"))
        }
        if let season = r.season {
            // Daily exposure — the engine correlates against season presence,
            // not just the four transition days a year.
            events.append(event("season", metadata: ["season": season]))
        }
        if let temp = r.temperatureC {
            events.append(event("temperature", value: temp, unit: "°C"))
        }
        if let humidity = r.humidityPct {
            events.append(event("humidity", value: humidity, unit: "%"))
        }
        return events
    }
}
