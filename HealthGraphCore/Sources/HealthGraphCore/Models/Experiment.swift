import Foundation
import GRDB

/// Fixed-run versus ongoing intake. DECLARED at creation and never inferred: a
/// fortnight of consecutive doses could be an antibiotic course or the start of
/// a daily habit, and the events cannot tell them apart. Guessing wrong is how a
/// single course ends up with a fabricated verdict.
public enum ExperimentShape: String, Codable, Sendable, CaseIterable {
    case repeated, course
}

public enum ExperimentStatus: String, Codable, Sendable, CaseIterable {
    case running, completed, abandoned
}

/// A declared question with a window. Stores no logging of its own — adherence is
/// derived from the dose events the capture sheet already writes, so the
/// experiment can never disagree with the Timeline.
public struct Experiment: Codable, Identifiable, Equatable,
                          FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "experiments"

    public var id: UUID
    public var interventionObjectID: UUID
    /// A symptom subtype. Mood targets are Phase B: they need the engine's
    /// lowMood/goodMood outcome keys rather than a subtype string.
    public var outcomeSubtype: String
    public var shape: ExperimentShape
    public var startedAt: Date
    public var intendedEndAt: Date
    public var endedAt: Date?
    public var status: ExperimentStatus
    /// Unused in Phase A, stored from the start so Phase B does not need a
    /// migration to record it. A reminded regimen and an unreminded one are
    /// different evidence, and the record should say which it was.
    public var remindersEnabled: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), interventionObjectID: UUID, outcomeSubtype: String,
                shape: ExperimentShape, startedAt: Date, intendedEndAt: Date,
                endedAt: Date? = nil, status: ExperimentStatus = .running,
                remindersEnabled: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.interventionObjectID = interventionObjectID
        self.outcomeSubtype = outcomeSubtype
        self.shape = shape
        self.startedAt = startedAt
        self.intendedEndAt = intendedEndAt
        self.endedAt = endedAt
        self.status = status
        self.remindersEnabled = remindersEnabled
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, interventionObjectID, outcomeSubtype, shape, startedAt, intendedEndAt
        case endedAt, status, remindersEnabled, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode id: try both UUID directly and String
        if let idString = try container.decodeIfPresent(String.self, forKey: .id),
           let uuid = UUID(uuidString: idString) {
            id = uuid
        } else if let uuid = try container.decodeIfPresent(UUID.self, forKey: .id) {
            id = uuid
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Cannot decode id as UUID")
        }

        // Decode interventionObjectID: try both UUID directly and String
        if let idString = try container.decodeIfPresent(String.self, forKey: .interventionObjectID),
           let uuid = UUID(uuidString: idString) {
            interventionObjectID = uuid
        } else if let uuid = try container.decodeIfPresent(UUID.self, forKey: .interventionObjectID) {
            interventionObjectID = uuid
        } else {
            throw DecodingError.dataCorruptedError(forKey: .interventionObjectID, in: container, debugDescription: "Cannot decode interventionObjectID as UUID")
        }

        outcomeSubtype = try container.decode(String.self, forKey: .outcomeSubtype)
        shape = try container.decode(ExperimentShape.self, forKey: .shape)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        intendedEndAt = try container.decode(Date.self, forKey: .intendedEndAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        status = try container.decode(ExperimentStatus.self, forKey: .status)
        remindersEnabled = try container.decode(Bool.self, forKey: .remindersEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(interventionObjectID.uuidString, forKey: .interventionObjectID)
        try container.encode(outcomeSubtype, forKey: .outcomeSubtype)
        try container.encode(shape, forKey: .shape)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(intendedEndAt, forKey: .intendedEndAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(status, forKey: .status)
        try container.encode(remindersEnabled, forKey: .remindersEnabled)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
