import Foundation

/// Poor-air-day exposures. The factory emits a daily `airQuality` event whose value
/// is the US EPA AQI; a day at or above the "Unhealthy for Sensitive Groups"
/// threshold (AQI ≥ 101) is a `poorAirDay`. Absolute health threshold — no
/// percentile, no min-readings guard.
public struct AirQualityExposureSource: ExposureSource {
    public init() {}
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard e.category == .environment, e.subtype == "airQuality", e.temporalProvenance == .observedCompletedDay,
                  let aqi = e.value, Int(aqi) >= AirQualityIndex.poorAirThreshold else { return nil }
            return ExposureOccurrence(key: .derived(.poorAirDay), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
