import Foundation

public enum BadgeTier: String, Sendable, Equatable { case earlySignal, moderate, strong }

/// A mined relationship plus its resolved human labels, a representative category for the
/// exposure's icon, and (for ACTIVE edges) the last-N chronological "followed" flags.
public struct ResolvedRelationship: Sendable, Equatable {
    public let relationship: Relationship
    public let exposureLabel: String
    public let outcomeLabel: String
    public let exposureCategory: EventCategory
    public let recentOutcomes: [Bool]     // last-~N exposures, chronological; empty for non-active
    public init(relationship: Relationship, exposureLabel: String, outcomeLabel: String,
                exposureCategory: EventCategory, recentOutcomes: [Bool] = []) {
        self.relationship = relationship; self.exposureLabel = exposureLabel
        self.outcomeLabel = outcomeLabel; self.exposureCategory = exposureCategory
        self.recentOutcomes = recentOutcomes
    }
}

/// One card's display data. `recentDots` is the last-~8 chronological hit/miss sequence
/// (empty for noEffect/archive); NOT the lifetime total.
public struct InsightCardModel: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let claim: String
    public let exposureCategory: EventCategory
    public let badge: BadgeTier
    public let countLine: String?     // "In 6 of your last 8 Dairy logs, bloating followed" (active)
    public let recentDots: [Bool]     // last-~8 followed flags, chronological
    public let subline: String?       // lag+severity (trigger only)
    public let isNew: Bool
    public let kind: RelationshipType
    public let tier: PlausibilityTier
    public init(id: UUID, claim: String, exposureCategory: EventCategory, badge: BadgeTier,
                countLine: String?, recentDots: [Bool], subline: String?, isNew: Bool, kind: RelationshipType,
                tier: PlausibilityTier = .established) {
        self.id = id; self.claim = claim; self.exposureCategory = exposureCategory; self.badge = badge
        self.countLine = countLine; self.recentDots = recentDots; self.subline = subline
        self.isNew = isNew; self.kind = kind; self.tier = tier
    }
}

public enum InsightSectionKind: Sendable, Equatable { case active, noEffect, archive, justForFun }
public struct InsightSection: Sendable, Equatable, Identifiable {
    public var id: InsightSectionKind { kind }
    public let kind: InsightSectionKind
    public let cards: [InsightCardModel]
    public init(kind: InsightSectionKind, cards: [InsightCardModel]) { self.kind = kind; self.cards = cards }
}
public struct InsightsFeedModel: Sendable, Equatable {
    public let sections: [InsightSection]   // active, noEffect, archive (empties omitted)
    public init(sections: [InsightSection]) { self.sections = sections }
}

public struct InsightsConfig: Sendable {
    public var newPerWeek = 3
    public var newWindowDays = 7.0
    public var recentDotCount = 8
    public var earlyMax = 0.5
    public var strongMin = 0.75
    public init() {}
    public static let `default` = InsightsConfig()
}
