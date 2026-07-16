import Testing
import Foundation
@testable import HealthGraphCore

struct RecomputePolicyTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let interval: TimeInterval = 900   // 15 min

    @Test func recomputesWhenNeverRun() {
        #expect(RecomputePolicy.shouldRecompute(lastRunAt: nil, lastWatermark: 0, now: now,
                                                currentWatermark: 0, minInterval: interval))
    }
    @Test func recomputesWhenWatermarkChanged() {
        #expect(RecomputePolicy.shouldRecompute(lastRunAt: now, lastWatermark: 10, now: now.addingTimeInterval(60),
                                                currentWatermark: 11, minInterval: interval))
    }
    @Test func skipsWhenRecentAndUnchanged() {
        #expect(!RecomputePolicy.shouldRecompute(lastRunAt: now, lastWatermark: 10,
                                                 now: now.addingTimeInterval(60), currentWatermark: 10, minInterval: interval))
    }
    @Test func recomputesAfterIntervalEvenIfUnchanged() {
        #expect(RecomputePolicy.shouldRecompute(lastRunAt: now, lastWatermark: 10,
                                                now: now.addingTimeInterval(1000), currentWatermark: 10, minInterval: interval))
    }
}
