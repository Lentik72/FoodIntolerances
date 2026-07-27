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

@Suite struct SymptomSeedsTests {
    @Test func dropsUnknownKeysAndPreservesOrder() {
        let real = SymptomCatalog.canonicalKey(for: "Headache")
        let other = SymptomCatalog.canonicalKey(for: "Bloating")
        #expect(SymptomSeeds.validate([other, "notARealKey", real], limit: 8) == [other, real])
    }

    @Test func excludesEveryRedFlagKey() {
        #expect(!RedFlagCatalog.allSymptomKeys.isEmpty)   // non-vacuous
        let cleaned = SymptomSeeds.validate(RedFlagCatalog.allSymptomKeys, limit: 8)
        #expect(cleaned.isEmpty)
    }

    @Test func dedupesPreservingFirstOccurrence() {
        let a = SymptomCatalog.canonicalKey(for: "Headache")
        let b = SymptomCatalog.canonicalKey(for: "Nausea")
        #expect(SymptomSeeds.validate([a, b, a], limit: 8) == [a, b])
    }

    @Test func appliesTheLimit() {
        let keys = SymptomCatalog.all.map(\.canonicalKey)
            .filter { !Set(RedFlagCatalog.allSymptomKeys).contains($0) }
        #expect(SymptomSeeds.validate(keys, limit: 8).count == 8)
    }

    @Test func nonPositiveLimitReturnsNothing() {
        // The cap inside validate is `out.count == limit`, which limit <= 0
        // can never hit (count starts at 0 and only grows) — without the
        // `limit > 0` guard, limit: 0 silently returned EVERY valid key.
        let real = SymptomCatalog.canonicalKey(for: "Headache")
        let cleaned = SymptomSeeds.validate([real], limit: 0)
        #expect(cleaned.isEmpty)
    }
}

@Suite struct ChipRankerSeedsTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let tz = TimeZone(identifier: "UTC")!

    private func ev(_ sub: String, _ t: Date) -> HealthEvent {
        HealthEvent(timestamp: t, timezoneID: "UTC", category: .symptom,
                    subtype: sub, source: .manual, createdAt: t)
    }

    @Test func historyRanksFirstAndSeedsFillOnlyLeftoverSlots() {
        let history = [ev("headache", now), ev("headache", now.addingTimeInterval(-3600)),
                       ev("nausea", now.addingTimeInterval(-7200))]
        let ranked = ChipRanker.rank(history: history, category: .symptom, now: now,
                                     timeZone: tz, limit: 4, seeds: ["bloating", "fatigue"])
        #expect(ranked.prefix(2) == ["headache", "nausea"])   // history wins the top slots
        #expect(ranked.count == 4)
        #expect(ranked.contains("bloating") && ranked.contains("fatigue"))
    }

    @Test func seedsAlreadyInHistoryAreNotDuplicated() {
        let history = [ev("headache", now)]
        let ranked = ChipRanker.rank(history: history, category: .symptom, now: now,
                                     timeZone: tz, limit: 4, seeds: ["headache", "nausea"])
        #expect(ranked == ["headache", "nausea"])
    }

    @Test func seedsNeverExceedTheLimit() {
        let ranked = ChipRanker.rank(history: [], category: .symptom, now: now,
                                     timeZone: tz, limit: 2, seeds: ["a", "b", "c", "d"])
        #expect(ranked == ["a", "b"])
    }

    @Test func anEmptyHistoryIsFullySeeded() {
        // The hole this closes: chips are filtered to sources [.manual], so a
        // HealthKit-only graph yields ZERO chips today.
        let ranked = ChipRanker.rank(history: [], category: .symptom, now: now,
                                     timeZone: tz, limit: 8, seeds: ["headache", "bloating"])
        #expect(ranked == ["headache", "bloating"])
    }

    @Test func omittingSeedsKeepsTheOldBehaviour() {
        let history = [ev("headache", now)]
        #expect(ChipRanker.rank(history: history, category: .symptom, now: now,
                                timeZone: tz, limit: 8) == ["headache"])
    }

    @Test func seedsNeverAddedWhenHistoryAlreadyFillsTheLimit() {
        // The ONLY fixture where ranked.count == limit — i.e. where the
        // guard's `ranked.count < limit` conjunct takes its false branch.
        // Without that conjunct the append loop is entered with out.count
        // already AT the limit, so the `out.count == limit` break can never
        // fire again (every append moves further past it) and EVERY
        // non-overlapping seed gets appended without bound.
        let history = [ev("headache", now), ev("nausea", now), ev("bloating", now), ev("fatigue", now)]
        let ranked = ChipRanker.rank(history: history, category: .symptom, now: now,
                                     timeZone: tz, limit: 4, seeds: ["cough"])
        #expect(ranked.count == 4)
        #expect(!ranked.contains("cough"))
    }

    @Test func internallyDuplicatedSeedsAppendOnlyOnce() {
        // `seeds` is a public parameter: deduping against the ranked list
        // alone would let ["bloating", "bloating"] produce a duplicate chip
        // whenever a caller skips SymptomSeeds.validate.
        let ranked = ChipRanker.rank(history: [], category: .symptom, now: now,
                                     timeZone: tz, limit: 4, seeds: ["bloating", "bloating", "fatigue"])
        #expect(ranked == ["bloating", "fatigue"])
    }
}
