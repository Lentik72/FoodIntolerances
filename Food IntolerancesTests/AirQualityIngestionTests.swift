import Testing
import Foundation
@testable import Food_Intolerances

struct AirQualityIngestionTests {
    @Test func meanPM25AveragesInWindowAndExcludesOutside() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let t = now.timeIntervalSince1970
        // 3 in-window slots average 10; the out-of-window 100s must NOT move the mean.
        let slots: [(dt: TimeInterval, pm25: Double)] = [
            (t, 10), (t + 3600, 10), (t + 86_400, 10),   // dt == now and dt == now+24h are INCLUSIVE
            (t - 1, 100), (t + 86_401, 100),             // just outside both boundaries → excluded
        ]
        #expect(EnvironmentalDataService.meanPM25(slots: slots, now: now) == 10)
    }
    @Test func meanPM25NilBelowThreeInWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let t = now.timeIntervalSince1970
        #expect(EnvironmentalDataService.meanPM25(slots: [(t, 10), (t + 3600, 20)], now: now) == nil)   // only 2 → nil
    }
}
