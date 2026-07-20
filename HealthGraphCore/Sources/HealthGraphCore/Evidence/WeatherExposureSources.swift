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

    private struct DayTemp { let event: HealthEvent; let high: Double; let low: Double }

    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        // Combined daily events only: value = high, metadata["low"] = low. Old single-value
        // snapshots (no "low") are skipped — clean migration, no data change.
        let days: [DayTemp] = events.compactMap { e in
            guard e.category == .environment, e.subtype == "temperature", let high = e.value,
                  let data = e.metadata,
                  let meta = try? JSONDecoder().decode([String: String].self, from: data),
                  let low = meta["low"].flatMap({ Double($0) }) else { return nil }
            return DayTemp(event: e, high: high, low: low)
        }
        guard days.count >= config.minWeatherReadings else { return [] }

        // (lo, hi) quartile cutoffs for a series, or nil if it has no spread (flat/degenerate).
        func cutoffs(_ values: [Double]) -> (lo: Double, hi: Double)? {
            let sorted = values.sorted()
            let hi = Percentile.value(sorted, config.weatherHighPercentile)
            let lo = Percentile.value(sorted, config.weatherLowPercentile)
            return hi > lo ? (lo, hi) : nil
        }
        let highCut = cutoffs(days.map(\.high))
        let lowCut = cutoffs(days.map(\.low))
        let rangeCut = cutoffs(days.map { $0.high - $0.low })

        func occ(_ k: DerivedExposureKind, _ e: HealthEvent) -> ExposureOccurrence {
            ExposureOccurrence(key: .derived(k), timestamp: e.timestamp, timezoneID: e.timezoneID, sourceEventID: e.id)
        }
        var out: [ExposureOccurrence] = []
        for d in days {
            if let c = highCut, d.high >= c.hi { out.append(occ(.hotDay, d.event)) }
            if let c = lowCut, d.low <= c.lo { out.append(occ(.coldDay, d.event)) }
            if let c = rangeCut, (d.high - d.low) >= c.hi { out.append(occ(.swingDay, d.event)) }
        }
        return out
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
