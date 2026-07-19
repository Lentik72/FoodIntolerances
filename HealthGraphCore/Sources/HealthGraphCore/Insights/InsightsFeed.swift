import Foundation

public enum InsightsFeed {
    public static func build(_ resolved: [ResolvedRelationship], now: Date,
                             config: InsightsConfig = .default) -> InsightsFeedModel {
        // Mood-outcome edges (toCategory == "mood") are mined + stored but not surfaced this
        // cycle — their reading experience ("what lifts your mood") is the next round.
        let resolved = resolved.filter { $0.relationship.toCategory != "mood" }
        let active = resolved.filter { $0.relationship.status == .active }
        let noEffect = resolved.filter { $0.relationship.status == .confirmedNoEffect }
        let archive = resolved.filter { $0.relationship.status == .decayed || $0.relationship.status == .userDismissed }

        // "New" selection: recent active edges, top N by confidence × novelty.
        func novelty(_ r: Relationship) -> Double {
            let ageDays = now.timeIntervalSince(r.firstSeen) / 86_400
            return max(0, 1 - ageDays / config.newWindowDays)
        }
        let recent = active.filter { now.timeIntervalSince($0.relationship.firstSeen) / 86_400 <= config.newWindowDays }
        func score(_ r: Relationship) -> Double { r.confidence * novelty(r) }
        let newIDs = Set(recent
            .sorted { score($0.relationship) != score($1.relationship)
                    ? score($0.relationship) > score($1.relationship)
                    : $0.relationship.id.uuidString < $1.relationship.id.uuidString }   // stable tiebreak
            .prefix(config.newPerWeek)
            .map { $0.relationship.id })

        func card(_ rr: ResolvedRelationship) -> InsightCardModel {
            let r = rr.relationship
            return InsightCardModel(
                id: r.id, claim: InsightPhrasing.claim(rr), exposureCategory: rr.exposureCategory,
                badge: InsightPhrasing.badge(confidence: r.confidence, config: config),
                countLine: InsightPhrasing.countLine(rr), recentDots: rr.recentOutcomes,
                subline: InsightPhrasing.subline(rr), isNew: newIDs.contains(r.id), kind: r.type)
        }
        func idTiebreak(_ a: ResolvedRelationship, _ b: ResolvedRelationship) -> Bool {
            a.relationship.id.uuidString < b.relationship.id.uuidString
        }

        let activeCards = active
            .sorted { lhs, rhs in
                let ln = newIDs.contains(lhs.relationship.id), rn = newIDs.contains(rhs.relationship.id)
                if ln != rn { return ln }                                   // New first
                if lhs.relationship.confidence != rhs.relationship.confidence {
                    return lhs.relationship.confidence > rhs.relationship.confidence
                }
                if lhs.relationship.lastSeen != rhs.relationship.lastSeen {
                    return lhs.relationship.lastSeen > rhs.relationship.lastSeen
                }
                return idTiebreak(lhs, rhs)
            }.map(card)
        let noEffectCards = noEffect.sorted {
            $0.relationship.lastSeen != $1.relationship.lastSeen
                ? $0.relationship.lastSeen > $1.relationship.lastSeen : idTiebreak($0, $1) }.map(card)
        let archiveCards = archive.sorted {
            $0.relationship.lastRecomputed != $1.relationship.lastRecomputed
                ? $0.relationship.lastRecomputed > $1.relationship.lastRecomputed : idTiebreak($0, $1) }.map(card)

        var sections: [InsightSection] = []
        if !activeCards.isEmpty { sections.append(InsightSection(kind: .active, cards: activeCards)) }
        if !noEffectCards.isEmpty { sections.append(InsightSection(kind: .noEffect, cards: noEffectCards)) }
        if !archiveCards.isEmpty { sections.append(InsightSection(kind: .archive, cards: archiveCards)) }
        return InsightsFeedModel(sections: sections)
    }
}
