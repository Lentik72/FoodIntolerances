import Foundation
import GRDB

/// Everything that happens is an event. Spec §4.
public struct HealthEvent: Codable, Identifiable, Equatable,
                           FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "health_events"

    public var id: UUID
    public var timestamp: Date
    public var timezoneID: String
    public var endTimestamp: Date?
    public var category: EventCategory
    public var subtype: String?
    public var objectID: UUID?
    public var value: Double?
    public var unit: String?
    public var source: EventSource
    public var confidence: Double
    public var metadata: Data?
    public var attachmentPath: String?
    public var createdAt: Date
    public var dedupKey: String?
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        timezoneID: String = TimeZone.current.identifier,
        endTimestamp: Date? = nil,
        category: EventCategory,
        subtype: String? = nil,
        objectID: UUID? = nil,
        value: Double? = nil,
        unit: String? = nil,
        source: EventSource,
        confidence: Double = 1.0,
        metadata: Data? = nil,
        attachmentPath: String? = nil,
        createdAt: Date = Date(),
        dedupKey: String? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.timezoneID = timezoneID
        self.endTimestamp = endTimestamp
        self.category = category
        self.subtype = subtype
        self.objectID = objectID
        self.value = value
        self.unit = unit
        self.source = source
        self.confidence = confidence
        self.metadata = metadata
        self.attachmentPath = attachmentPath
        self.createdAt = createdAt
        self.dedupKey = dedupKey
        self.deletedAt = deletedAt
    }
}
