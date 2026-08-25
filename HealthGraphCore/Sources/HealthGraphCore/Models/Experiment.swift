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

    public static func databaseUUIDEncodingStrategy(for: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }
}
