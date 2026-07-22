import Foundation

/// One day's environmental readings, gathered by the app layer.
public struct EnvironmentalReading: Sendable {
    public let date: Date
    public let pressureHPa: Double?
    public let previousPressureHPa: Double?
    public let moonPhaseName: String?
    public let isMercuryRetrograde: Bool
    public let timezoneID: String
    public let temperatureHighC: Double?
    public let temperatureLowC: Double?
    public let humidityPct: Double?
    public let airQualityAQI: Int?

    public init(date: Date, pressureHPa: Double?, previousPressureHPa: Double?,
                moonPhaseName: String?,
                isMercuryRetrograde: Bool, timezoneID: String,
                temperatureHighC: Double? = nil, temperatureLowC: Double? = nil, humidityPct: Double? = nil,
                airQualityAQI: Int? = nil) {
        self.date = date
        self.pressureHPa = pressureHPa
        self.previousPressureHPa = previousPressureHPa
        self.moonPhaseName = moonPhaseName
        self.isMercuryRetrograde = isMercuryRetrograde
        self.timezoneID = timezoneID
        self.temperatureHighC = temperatureHighC
        self.temperatureLowC = temperatureLowC
        self.humidityPct = humidityPct
        self.airQualityAQI = airQualityAQI
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

        // Provenance is intrinsic to each signal's real source: it rides in
        // metadata (so mining stays fail-closed on `.observedCompletedDay`) AND
        // scopes the dedup key, so a forecast reading and an observed reading for
        // the same day+subtype never overwrite one another.
        func event(_ subtype: String, value: Double? = nil, unit: String? = nil,
                   metadata: [String: String]? = nil, provenance: TemporalProvenance) -> HealthEvent {
            var meta = metadata ?? [:]
            meta["provenance"] = provenance.rawValue
            return HealthEvent(
                timestamp: r.date, timezoneID: r.timezoneID,
                category: .environment, subtype: subtype,
                value: value, unit: unit, source: .weatherAPI,
                metadata: try? JSONEncoder().encode(meta),
                dedupKey: DedupKey.daily(.environment, subtype, dayStart: dayStart, provenance: provenance)
            )
        }

        if let pressure = r.pressureHPa {
            // Barometric pressure is a current-conditions reading.
            events.append(event("pressure", value: pressure, unit: "hPa", provenance: .currentSnapshot))
            if let previous = r.previousPressureHPa,
               previous - pressure >= pressureDropThresholdHPa {
                events.append(event("pressureDrop", value: previous - pressure, unit: "hPa",
                                    provenance: .currentSnapshot))
            }
        }
        if let moon = r.moonPhaseName {
            let cleaned = moon.filter { $0.isLetter || $0.isWhitespace }
                .trimmingCharacters(in: .whitespaces)
            // Deterministic date-fact for a completed local day → mineable.
            events.append(event("moonPhase", metadata: ["phase": cleaned],
                                provenance: .observedCompletedDay))
        }
        if r.isMercuryRetrograde {
            events.append(event("mercuryRetrograde", provenance: .observedCompletedDay))
        }
        if let high = r.temperatureHighC, let low = r.temperatureLowC {
            // Weather is forecast-derived → display/warnings only, never mined.
            events.append(event("temperature", value: high, unit: "°C", metadata: ["low": String(low)],
                                provenance: .forecast))
        }
        if let humidity = r.humidityPct {
            events.append(event("humidity", value: humidity, unit: "%", provenance: .forecast))
        }
        if let aqi = r.airQualityAQI {
            // The AQI emitter reads a completed-day observed index → mineable.
            events.append(event("airQuality", value: Double(aqi), provenance: .observedCompletedDay))
        }
        return events
    }
}
