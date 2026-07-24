import Foundation
import GRDB

/// A persistent thing events reference (a supplement, a food, a doctor…). Spec §4.
public struct HealthObject: Codable, Identifiable, Equatable,
                            FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "health_objects"

    public var id: UUID
    public var kind: ObjectKind
    public var name: String
    public var normalizedName: String
    public var metadata: Data?
    public var isArchived: Bool
    public var createdAt: Date
    /// Non-nil marks a demo/seed object and names its batch. NULL = real.
    public var syntheticBatch: String?

    public init(
        id: UUID = UUID(),
        kind: ObjectKind,
        name: String,
        metadata: Data? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        syntheticBatch: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.normalizedName = NameNormalizer.normalize(name)
        self.metadata = metadata
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.syntheticBatch = syntheticBatch
    }
}
