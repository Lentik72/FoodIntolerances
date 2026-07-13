import Foundation
import Testing
@testable import HealthGraphCore

struct ChipRankerTests {
    let tz = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_750_000_000)   // fixed
    private func ev(_ sub: String, _ t: Date) -> HealthEvent {
        HealthEvent(timestamp: t, category: .symptom, subtype: sub, source: .manual, createdAt: t)
    }
    @Test func frequentAndRecentRanksAboveRareOld() {
        let hist = [
            ev("headache", now.addingTimeInterval(-3600)),
            ev("headache", now.addingTimeInterval(-2 * 86_400)),
            ev("headache", now.addingTimeInterval(-3 * 86_400)),
            ev("nausea", now.addingTimeInterval(-40 * 86_400)),   // old, rare
        ]
        let ranked = ChipRanker.rank(history: hist, category: .symptom, now: now, timeZone: tz, limit: 5)
        #expect(ranked.first == "headache")
        #expect(ranked.contains("nausea"))
    }
    @Test func filtersCategoryAndRespectsLimit() {
        let hist = [
            ev("headache", now), ev("nausea", now),
            HealthEvent(timestamp: now, category: .food, subtype: "eggs", source: .manual, createdAt: now),
        ]
        let ranked = ChipRanker.rank(history: hist, category: .symptom, now: now, timeZone: tz, limit: 1)
        #expect(ranked.count == 1)
        #expect(!ranked.contains("eggs"))
    }
    @Test func emptyHistoryReturnsEmpty() {
        #expect(ChipRanker.rank(history: [], category: .food, now: now, timeZone: tz, limit: 5).isEmpty)
    }
}
