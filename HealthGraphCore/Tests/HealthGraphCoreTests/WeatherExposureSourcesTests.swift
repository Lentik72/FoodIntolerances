import Testing
import Foundation
@testable import HealthGraphCore

struct WeatherExposureSourcesTests {
    private func tempDay(high: Double, low: Double, _ i: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                    category: .environment, subtype: "temperature", value: high, unit: "°C",
                    source: .weatherAPI, metadata: try? JSONEncoder().encode(["low": String(low), "provenance": "observedCompletedDay"]))
    }
    private func humid(_ v: Double, _ i: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                    category: .environment, subtype: "humidity", value: v, unit: "%", source: .weatherAPI,
                    metadata: try? JSONEncoder().encode(["provenance": "observedCompletedDay"]))
    }
    // Values 1…20 in SHUFFLED input order — the source must sort internally (a dropped
    // `.sorted()` would pass a pre-sorted fixture but fail this one).
    private let shuffled20: [Double] = [11, 3, 17, 8, 20, 1, 14, 6, 19, 9, 2, 15, 7, 12, 4, 18, 10, 5, 16, 13]
    // A fixed NON-sorted permutation of 1…21 (odds then evens) — catches a dropped `.sorted()`,
    // and n=21 gives a FRACTIONAL rank so it discriminates nearest-rank (ceil) from floor.
    private let shuffled21: [Double] =
        Array(stride(from: 1.0, through: 21.0, by: 2)) + Array(stride(from: 2.0, through: 20.0, by: 2))

    @Test func hotOnHighQuartileColdOnLowQuartile() {
        // highs = shuffled 1…20, lows = high − 10 (constant 10° range → no swing spread)
        let events = shuffled20.enumerated().map { tempDay(high: $0.element, low: $0.element - 10, $0.offset) }
        let occ = TemperatureExposureSource(config: .default).occurrences(from: events)
        #expect(occ.filter { $0.key == .derived(.hotDay) }.count == 6)    // high ≥ p75(1…20)=15 → 15…20
        #expect(occ.filter { $0.key == .derived(.coldDay) }.count == 5)   // low ≤ p25(lows −9…10)=−5 → highs 1…5
        #expect(occ.filter { $0.key == .derived(.swingDay) }.isEmpty)     // ranges all 10 → range spread guard bails
    }
    @Test func percentileIsNearestRankNotFloorOnCombinedEvents() {
        // n=21: p75·21=15.75 → ceil→rank16 → cutoff 16 → hot={16…21}=6. Floor(15) would give 7; a
        // dropped .sorted() on the odds-then-evens input would also miss. Pins the rank arithmetic.
        let events = shuffled21.enumerated().map { tempDay(high: $0.element, low: $0.element - 10, $0.offset) }
        #expect(TemperatureExposureSource(config: .default).occurrences(from: events)
            .filter { $0.key == .derived(.hotDay) }.count == 6)
    }
    @Test func swingOnRangeQuartile() {
        // high = 20 (flat → no hot), low = 20 − range, ranges = shuffled 1…20; lows land at 0…19
        let events = shuffled20.enumerated().map { tempDay(high: 20, low: 20 - $0.element, $0.offset) }
        let occ = TemperatureExposureSource(config: .default).occurrences(from: events)
        #expect(occ.filter { $0.key == .derived(.swingDay) }.count == 6)  // range ≥ p75(1…20)=15
        #expect(occ.filter { $0.key == .derived(.hotDay) }.isEmpty)       // highs all 20 → high spread guard bails
        #expect(occ.filter { $0.key == .derived(.coldDay) }.count == 5)   // low ≤ p25(lows 0…19)=4 → pins cold reads LOW
    }
    @Test func aDayCanBeBothHotAndSwing() {
        // low = 0 for all → range = high; both the highs series AND the ranges series are 1…20
        // (both have spread), so the top day (high 20, range 20) is both hot AND swingy.
        let events = shuffled20.enumerated().map { tempDay(high: $0.element, low: 0, $0.offset) }
        let occ = TemperatureExposureSource(config: .default).occurrences(from: events)
        let top = events.first { $0.value == 20 }!
        let keys = occ.filter { $0.sourceEventID == top.id }.map(\.key)
        #expect(keys.contains(.derived(.hotDay)) && keys.contains(.derived(.swingDay)))
        #expect(occ.filter { $0.key == .derived(.coldDay) }.isEmpty)      // lows all 0 → low spread guard bails
    }
    @Test func oldSnapshotEventsWithoutLowAreSkippedNotMined() {
        // 20 valid combined events + 5 legacy single-value snapshots (no metadata.low, extreme value).
        // If the skip were broken the 999° snapshots would blow up the hot count / percentiles.
        let valid = shuffled20.enumerated().map { tempDay(high: $0.element, low: $0.element - 10, $0.offset) }
        let snapshots = (0..<5).map { i in HealthEvent(timestamp: Date(timeIntervalSince1970: Double(100 + i) * 86_400),
            timezoneID: "UTC", category: .environment, subtype: "temperature", value: 999, unit: "°C", source: .weatherAPI) }
        let validIDs = Set(valid.map(\.id))
        let occ = TemperatureExposureSource(config: .default).occurrences(from: valid + snapshots)
        #expect(!occ.isEmpty)                                             // not vacuously empty
        #expect(occ.allSatisfy { validIDs.contains($0.sourceEventID) })   // no snapshot produced an occurrence
        #expect(occ.filter { $0.key == .derived(.hotDay) }.count == 6)    // hot count unchanged by the 999° snapshots
    }
    @Test func degenerateFlatSeriesEmitsNothing() {   // all identical → every series has no spread → all cutoffs nil
        #expect(TemperatureExposureSource(config: .default)
            .occurrences(from: (1...25).map { tempDay(high: 20, low: 10, $0) }).isEmpty)
        #expect(HumidityExposureSource(config: .default).occurrences(from: (1...25).map { humid(55, $0) }).isEmpty)
    }
    @Test func belowMinAtBoundaryEmitsNothing() {     // 19 = minWeatherReadings − 1 → catches a too-lenient guard
        #expect(TemperatureExposureSource(config: .default)
            .occurrences(from: (1...19).map { tempDay(high: Double($0), low: Double($0) - 10, $0) }).isEmpty)
    }
    @Test func belowMinReadingsEmitsNothing() {
        #expect(TemperatureExposureSource(config: .default)
            .occurrences(from: (1...10).map { tempDay(high: Double($0), low: Double($0) - 10, $0) }).isEmpty)
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
        var events = shuffled20.enumerated().map { tempDay(high: $0.element, low: $0.element - 10, $0.offset) }
        events += shuffled20.enumerated().map { humid($0.element, $0.offset + 100) }
        events.append(HealthEvent(timestamp: Date(timeIntervalSince1970: 900 * 86_400), timezoneID: "UTC",
            category: .environment, subtype: "pressure", value: 1013, unit: "hPa", source: .weatherAPI))
        #expect(TemperatureExposureSource(config: .default).occurrences(from: events)
            .allSatisfy { $0.key == .derived(.hotDay) || $0.key == .derived(.coldDay) || $0.key == .derived(.swingDay) })
        #expect(HumidityExposureSource(config: .default).occurrences(from: events)
            .allSatisfy { $0.key == .derived(.humidDay) })
    }
    // Self-contained: observed → occurrences; forecast → none; NO-flag (legacy) → none.
    @Test func temperatureMinedOnlyWhenObserved() {
        func tempDay(_ high: Double, _ low: Double, _ i: Int, _ provenance: String?) -> HealthEvent {
            var meta = ["low": String(low)]; if let p = provenance { meta["provenance"] = p }
            return HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                               category: .environment, subtype: "temperature", value: high, unit: "°C",
                               source: .weatherAPI, metadata: try? JSONEncoder().encode(meta))
        }
        func run(_ p: String?) -> [ExposureOccurrence] {
            TemperatureExposureSource(config: .default)
                .occurrences(from: shuffled20.enumerated().map { tempDay($0.element, $0.element - 10, $0.offset, p) })
        }
        #expect(run("observedCompletedDay").contains { $0.key == .derived(.hotDay) })   // gate isn't just `return []`
        #expect(run("forecast").isEmpty)                                                 // forecast never mined
        #expect(run(nil).isEmpty)                                                        // fail-closed: no flag → not mined
    }
    // Self-contained: observed → occurrences; forecast → none; NO-flag (legacy) → none.
    @Test func humidityMinedOnlyWhenObserved() {
        func humidDay(_ v: Double, _ i: Int, _ provenance: String?) -> HealthEvent {
            var meta: [String: String] = [:]; if let p = provenance { meta["provenance"] = p }
            return HealthEvent(timestamp: Date(timeIntervalSince1970: Double(i) * 86_400), timezoneID: "UTC",
                               category: .environment, subtype: "humidity", value: v, unit: "%",
                               source: .weatherAPI, metadata: try? JSONEncoder().encode(meta))
        }
        func run(_ p: String?) -> [ExposureOccurrence] {
            HumidityExposureSource(config: .default)
                .occurrences(from: shuffled20.enumerated().map { humidDay($0.element, $0.offset, p) })
        }
        #expect(run("observedCompletedDay").contains { $0.key == .derived(.humidDay) })   // gate isn't just `return []`
        #expect(run("forecast").isEmpty)                                                   // forecast never mined
        #expect(run(nil).isEmpty)                                                          // fail-closed: no flag → not mined
    }
}
