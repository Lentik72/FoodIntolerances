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
        // A synthetic object's identity is namespaced so it can never collide with a
        // real object of the same name+kind. Deriving it HERE (not via a post-init
        // override in the store) means any direct `HealthObject(…, syntheticBatch:)`
        // is correct by construction. `DemoBatch` is same-module.
        self.normalizedName = syntheticBatch
            .map { DemoBatch.normalizedName(name, batch: $0) }
            ?? NameNormalizer.normalize(name)
        self.metadata = metadata
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.syntheticBatch = syntheticBatch
    }
}
