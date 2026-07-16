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
}
