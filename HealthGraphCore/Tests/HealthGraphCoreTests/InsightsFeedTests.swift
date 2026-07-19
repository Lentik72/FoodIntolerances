import Testing
import Foundation
@testable import HealthGraphCore

struct InsightsFeedTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    func rr(_ status: RelStatus, conf: Double, firstSeenDaysAgo: Double, type: RelationshipType = .possibleTrigger,
            outcome: String) -> ResolvedRelationship {
        let fs = now.addingTimeInterval(-firstSeenDaysAgo * 86_400)
        let r = Relationship(fromCategory: "food", toCategory: "symptom", type: type,
                             evidenceCount: 6, contradictionCount: 2, confidence: conf,
                             strength: 5, lagHours: 12, firstSeen: fs, lastSeen: now,
                             lastRecomputed: now, status: status, edgeKey: "k-\(outcome)-\(conf)", toSubtype: outcome)
        return ResolvedRelationship(relationship: r, exposureLabel: "Food", outcomeLabel: outcome, exposureCategory: .food)
    }

    @Test func sectionsByStatus() {
        let feed = InsightsFeed.build([
            rr(.active, conf: 0.6, firstSeenDaysAgo: 30, outcome: "bloating"),
            rr(.confirmedNoEffect, conf: 0.5, firstSeenDaysAgo: 100, type: .noEffect, outcome: "fatigue"),
            rr(.decayed, conf: 0.2, firstSeenDaysAgo: 200, outcome: "headache"),
            rr(.userDismissed, conf: 0.6, firstSeenDaysAgo: 40, outcome: "nausea"),
        ], now: now)
        let byKind = Dictionary(uniqueKeysWithValues: feed.sections.map { ($0.kind, $0.cards) })
        #expect(byKind[.active]?.count == 1)
        #expect(byKind[.noEffect]?.count == 1)
        #expect(byKind[.archive]?.count == 2)   // decayed + dismissed
    }

    @Test func newFlagCapsAtThreeMostConfidentRecent() {
        // 4 recent (≤7d) active + 1 old active. Only top-3 recent by conf×novelty are New.
        var input = [
            rr(.active, conf: 0.70, firstSeenDaysAgo: 1, outcome: "a"),
            rr(.active, conf: 0.65, firstSeenDaysAgo: 2, outcome: "b"),
            rr(.active, conf: 0.60, firstSeenDaysAgo: 3, outcome: "c"),
            rr(.active, conf: 0.55, firstSeenDaysAgo: 4, outcome: "d"),
            rr(.active, conf: 0.72, firstSeenDaysAgo: 90, outcome: "old"),  // not recent → never New
        ]
        var rng = SeededGenerator(seed: 1); input.shuffle(using: &rng)   // order-independence
        let active = InsightsFeed.build(input, now: now).sections.first { $0.kind == .active }!.cards
        let newOutcomes = Set(active.filter(\.isNew).map { $0.claim })
        #expect(active.filter(\.isNew).count == 3)
        #expect(!newOutcomes.contains { $0.contains("old") })   // old edge is not New despite high conf
        // New cards sort ahead of non-New.
        #expect(active.prefix(3).allSatisfy { $0.isNew })
    }

    @Test func badgeTieringHonorsCustomConfig() {
        // Default earlyMax = 0.5 would put 0.55 confidence at .moderate; a custom
        // earlyMax = 0.6 must push it down to .earlySignal — proving `build` threads
        // `config` into InsightPhrasing.badge instead of always using `.default`.
        var c = InsightsConfig(); c.earlyMax = 0.6
        let feed = InsightsFeed.build([
            rr(.active, conf: 0.55, firstSeenDaysAgo: 30, outcome: "bloating"),
        ], now: now, config: c)
        let card = feed.sections.first { $0.kind == .active }!.cards.first!
        #expect(card.badge == .earlySignal)
    }

    @Test func moodOutcomeEdgesAreSuppressed() {
        let refNow = Date(timeIntervalSince1970: 1_700_000_000)
        func rel(toCategory: String, toSubtype: String, key: String) -> Relationship {
            Relationship(fromCategory: "food", toCategory: toCategory, type: .possibleTrigger,
                         evidenceCount: 6, contradictionCount: 2, confidence: 0.6, strength: 5, lagHours: 12,
                         firstSeen: refNow.addingTimeInterval(-5 * 86_400), lastSeen: refNow,
                         lastRecomputed: refNow, status: .active, edgeKey: key, toSubtype: toSubtype)
        }
        let dairy = ResolvedRelationship(
            relationship: rel(toCategory: "symptom", toSubtype: "bloating", key: "k-dairy"),
            exposureLabel: "Dairy", outcomeLabel: "bloating", exposureCategory: .food, recentOutcomes: [])
        let coffeeMood = ResolvedRelationship(
            relationship: rel(toCategory: "mood", toSubtype: "low", key: "k-coffee-mood"),
            exposureLabel: "Coffee", outcomeLabel: "low", exposureCategory: .food, recentOutcomes: [])
        let claims = InsightsFeed.build([dairy, coffeeMood], now: refNow)
            .sections.flatMap(\.cards).map { $0.claim.lowercased() }
        #expect(claims.contains { $0.contains("dairy") })    // the symptom edge survives
        #expect(!claims.contains { $0.contains("coffee") })  // the mood edge is suppressed
        #expect(claims.count == 1)                           // exactly one card (guards vacuity)
    }
}
