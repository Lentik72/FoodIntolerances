import Foundation
import GRDB

/// A mined edge between an exposure and an outcome — the moat. Spec §4.
/// `confidence` is computed by the EvidenceEngine (Phase 2), never by an LLM.
public struct Relationship: Codable, Identifiable, Equatable,
                            FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "relationships"

    public var id: UUID
    public var fromObjectID: UUID?
    public var fromCategory: String?
    public var toObjectID: UUID?
    public var toCategory: String?
    public var type: RelationshipType
    public var evidenceCount: Int
    public var contradictionCount: Int
    public var confidence: Double
    public var strength: Double?
    public var lagHours: Double?
    public var firstSeen: Date
    public var lastSeen: Date
    public var lastRecomputed: Date
    public var status: RelStatus
    public var aiExplanation: String?

    public init(
        id: UUID = UUID(),
        fromObjectID: UUID? = nil,
        fromCategory: String? = nil,
        toObjectID: UUID? = nil,
        toCategory: String? = nil,
        type: RelationshipType,
        evidenceCount: Int = 0,
        contradictionCount: Int = 0,
        confidence: Double = 0,
        strength: Double? = nil,
        lagHours: Double? = nil,
        firstSeen: Date,
        lastSeen: Date,
        lastRecomputed: Date,
        status: RelStatus = .candidate,
        aiExplanation: String? = nil
    ) {
        self.id = id
        self.fromObjectID = fromObjectID
        self.fromCategory = fromCategory
        self.toObjectID = toObjectID
        self.toCategory = toCategory
        self.type = type
        self.evidenceCount = evidenceCount
        self.contradictionCount = contradictionCount
        self.confidence = confidence
        self.strength = strength
        self.lagHours = lagHours
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.lastRecomputed = lastRecomputed
        self.status = status
        self.aiExplanation = aiExplanation
    }
}
