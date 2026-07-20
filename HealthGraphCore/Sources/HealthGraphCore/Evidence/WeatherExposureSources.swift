import Foundation

/// Deterministic nearest-rank percentile over an ascending-sorted, non-empty array.
/// `p` in 0...1. Ties at the cutoff are the caller's to include (`>=`/`<=`).
enum Percentile {
    static func value(_ sortedAscending: [Double], _ p: Double) -> Double {
        guard let first = sortedAscending.first else { return 0 }
        guard sortedAscending.count > 1 else { return first }
        let rank = Int((p * Double(sortedAscending.count)).rounded(.up))   // 1-based
        return sortedAscending[max(1, min(sortedAscending.count, rank)) - 1]
    }
}

/// Temperature exposures — personal-percentile: a day's temp in the user's top
/// quartile → hotDay, bottom quartile → coldDay. Needs ≥ minWeatherReadings for a
/// stable distribution (below that, no exposures — the engine's own cold-start).
public struct TemperatureExposureSource: ExposureSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        let temps = events.filter { $0.category == .environment && $0.subtype == "temperature" && $0.value != nil }
        guard temps.count >= config.minWeatherReadings else { return [] }
        let sorted = temps.compactMap(\.value).sorted()
        let hi = Percentile.value(sorted, config.weatherHighPercentile)
        let lo = Percentile.value(sorted, config.weatherLowPercentile)
        guard hi > lo else { return [] }   // no spread (flat/degenerate series) → no buckets, no false signal
        return temps.compactMap { e in
            guard let v = e.value else { return nil }
            if v >= hi { return ExposureOccurrence(key: .derived(.hotDay), timestamp: e.timestamp,
                                                   timezoneID: e.timezoneID, sourceEventID: e.id) }
            if v <= lo { return ExposureOccurrence(key: .derived(.coldDay), timestamp: e.timestamp,
                                                   timezoneID: e.timezoneID, sourceEventID: e.id) }
            return nil
        }
    }
}

/// Humidity exposures — top-quartile day → humidDay (high humidity is the cited pole).
public struct HumidityExposureSource: ExposureSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        let hums = events.filter { $0.category == .environment && $0.subtype == "humidity" && $0.value != nil }
        guard hums.count >= config.minWeatherReadings else { return [] }
        let sorted = hums.compactMap(\.value).sorted()
        let hi = Percentile.value(sorted, config.weatherHighPercentile)
        let lo = Percentile.value(sorted, config.weatherLowPercentile)
        guard hi > lo else { return [] }   // no spread → no buckets
        return hums.compactMap { e in
            guard let v = e.value, v >= hi else { return nil }
            return ExposureOccurrence(key: .derived(.humidDay), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
