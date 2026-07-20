import Testing
import Foundation
@testable import Food_Intolerances

/// Exercises the pure `EnvironmentalDataService.aggregate24h(slots:now:)` — the
/// next-24h high/low/mean-humidity reduction over 3-hourly /forecast slots. No
/// network: the aggregation is a static function so it can be tested directly.
struct ForecastAggregationTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func aggregatesHighLowMeanOverInWindowSlots() {
        let base = now.timeIntervalSince1970
        let slots: [(dt: TimeInterval, temp: Double, humidity: Double)] = [
            (base + 3_600, 10, 40),
            (base + 7_200, 24, 60),    // high
            (base + 10_800, 6, 80),    // low
        ]
        let result = EnvironmentalDataService.aggregate24h(slots: slots, now: now)
        #expect(result?.high == 24)
        #expect(result?.low == 6)
        #expect(result?.humidity == 60)   // (40 + 60 + 80) / 3
    }

    @Test func excludesSlotsOutsideTheNext24hWindow() {
        let base = now.timeIntervalSince1970
        let slots: [(dt: TimeInterval, temp: Double, humidity: Double)] = [
            (base - 3_600, 100, 10),    // before now → excluded
            (base + 3_600, 10, 40),
            (base + 7_200, 24, 60),
            (base + 10_800, 6, 80),
            (base + 90_000, -50, 90),   // > now + 86_400 → excluded
        ]
        let result = EnvironmentalDataService.aggregate24h(slots: slots, now: now)
        #expect(result?.high == 24)       // 100 and -50 excluded
        #expect(result?.low == 6)
        #expect(result?.humidity == 60)   // mean over the 3 in-window slots only
    }

    @Test func fewerThanThreeInWindowSlotsReturnsNil() {
        let base = now.timeIntervalSince1970
        let slots: [(dt: TimeInterval, temp: Double, humidity: Double)] = [
            (base + 3_600, 10, 40),
            (base + 7_200, 24, 60),
        ]
        #expect(EnvironmentalDataService.aggregate24h(slots: slots, now: now) == nil)
    }
}
