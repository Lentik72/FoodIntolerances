import Testing
import Foundation
@testable import HealthGraphCore

struct WeatherExposureSourcesTests {
    private func temp(_ v: Double, _ i: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                    category: .environment, subtype: "temperature", value: v, unit: "°C", source: .weatherAPI)
    }
    private func humid(_ v: Double, _ i: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                    category: .environment, subtype: "humidity", value: v, unit: "%", source: .weatherAPI)
    }
    // Values 1…20 in SHUFFLED input order — the source must sort internally (a dropped
    // `.sorted()` would pass a pre-sorted fixture but fail this one).
    private let shuffled20: [Double] = [11, 3, 17, 8, 20, 1, 14, 6, 19, 9, 2, 15, 7, 12, 4, 18, 10, 5, 16, 13]

    @Test func hotAndColdByQuartile() {
        let events = shuffled20.enumerated().map { temp($0.element, $0.offset) }   // n=20, values 1…20
        let occ = TemperatureExposureSource(config: .default).occurrences(from: events)
        let hot = occ.filter { $0.key == .derived(.hotDay) }.count
        let cold = occ.filter { $0.key == .derived(.coldDay) }.count
        #expect(hot == 6)     // >= p75(15): 15…20
        #expect(cold == 5)    // <= p25(5): 1…5
        #expect(occ.count == hot + cold)   // middle → neither
    }
    @Test func percentileIsNearestRankNotFloorOrLinear() {   // n=21 → fractional rank exercises .rounded(.up)
        let occ = TemperatureExposureSource(config: .default).occurrences(from: (1...21).map { temp(Double($0), $0) })
        #expect(occ.filter { $0.key == .derived(.hotDay) }.count == 6)    // p75 rank=ceil(15.75)=16 → cutoff 16 → 16…21
        #expect(occ.filter { $0.key == .derived(.coldDay) }.count == 6)   // p25 rank=ceil(5.25)=6 → cutoff 6 → 1…6
    }
    @Test func belowMinReadingsEmitsNothing() {
        #expect(TemperatureExposureSource(config: .default).occurrences(from: (1...10).map { temp(Double($0), $0) }).isEmpty)
    }
    @Test func atMinMinusOneEmitsNothing() {   // n=19 = minWeatherReadings−1 → catches a too-lenient guard
        #expect(TemperatureExposureSource(config: .default).occurrences(from: (1...19).map { temp(Double($0), $0) }).isEmpty)
    }
    @Test func degenerateAllEqualSeriesEmitsNothing() {   // no spread → NO false signal (the percentile-design guarantee)
        #expect(TemperatureExposureSource(config: .default).occurrences(from: (1...25).map { temp(20, $0) }).isEmpty)
        #expect(HumidityExposureSource(config: .default).occurrences(from: (1...25).map { humid(55, $0) }).isEmpty)
    }
    @Test func humidityTopQuartileOnly() {
        let occ = HumidityExposureSource(config: .default).occurrences(from: shuffled20.enumerated().map { humid($0.element, $0.offset) })
        #expect(occ.allSatisfy { $0.key == .derived(.humidDay) })
        #expect(occ.count == 6)   // >= p75(15)
    }
    @Test func humidityBelowMinReadingsEmitsNothing() {
        #expect(HumidityExposureSource(config: .default).occurrences(from: (1...10).map { humid(Double($0), $0) }).isEmpty)
    }
    @Test func eachSourceIgnoresOtherSubtypes() {   // mixed batch → each source reacts only to its own subtype
        var events = shuffled20.enumerated().map { temp($0.element, $0.offset) }
        events += shuffled20.enumerated().map { humid($0.element, $0.offset + 100) }
        events.append(HealthEvent(timestamp: Date(timeIntervalSince1970: 900 * 86_400), timezoneID: "UTC",
            category: .environment, subtype: "pressure", value: 1013, unit: "hPa", source: .weatherAPI))
        #expect(TemperatureExposureSource(config: .default).occurrences(from: events)
            .allSatisfy { $0.key == .derived(.hotDay) || $0.key == .derived(.coldDay) })
        #expect(HumidityExposureSource(config: .default).occurrences(from: events)
            .allSatisfy { $0.key == .derived(.humidDay) })
    }
}
