import Foundation

/// Kinds of substance a dose can be logged against.
public enum DoseKind: String, CaseIterable, Sendable {
    case medication, supplement, peptide

    public var objectKind: ObjectKind {
        switch self {
        case .medication: .medication
        case .supplement: .supplement
        case .peptide: .peptide
        }
    }
    public var eventCategory: EventCategory {
        switch self {
        case .medication: .medication
        case .supplement: .supplement
        case .peptide: .peptide
        }
    }
}

/// Composes ObjectStore.findOrCreate + EventStore.save for manual capture.
/// All manual capture is source == .manual, dedupKey == nil (import-dedup exempt).
public struct CaptureService: Sendable {
    // Store AppDatabase (which IS Sendable) rather than the GRDB*Store structs
    // (public, not-declared-Sendable) so `CaptureService: Sendable` is warning-free.
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }
    private var eventStore: GRDBEventStore { GRDBEventStore(database: database) }
    private var objectStore: GRDBObjectStore { GRDBObjectStore(database: database) }

    private static func metadata(_ pairs: [String: String]) -> Data? {
        pairs.isEmpty ? nil : try? JSONEncoder().encode(pairs)
    }

    @discardableResult
    public func logSymptom(canonicalKey: String, severity: Int?, at timestamp: Date,
                           note: String?) async throws -> HealthEvent {
        var meta: [String: String] = [:]
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meta["note"] = note
        }
        let event = HealthEvent(
            timestamp: timestamp, category: .symptom,
            subtype: canonicalKey,
            value: severity.map(Double.init),
            unit: severity == nil ? nil : "severity",
            source: .manual, metadata: Self.metadata(meta), dedupKey: nil)
        try await eventStore.save(event)
        return event
    }

    @discardableResult
    public func logMood(level: MoodLevel, at timestamp: Date, note: String?) async throws -> HealthEvent {
        var meta: [String: String] = [:]
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meta["note"] = note
        }
        let event = HealthEvent(
            timestamp: timestamp, category: .mood,
            subtype: "mood",
            value: Double(level.rawValue),
            source: .manual, metadata: Self.metadata(meta), dedupKey: nil)
        try await eventStore.save(event)
        return event
    }

    @discardableResult
    public func logMeal(name: String, at timestamp: Date) async throws -> HealthEvent {
        let object = try await objectStore.findOrCreate(name: name, kind: .food, metadata: nil)
        let event = HealthEvent(
            timestamp: timestamp, category: .food, subtype: name,
            objectID: object.id, source: .manual, dedupKey: nil)
        try await eventStore.save(event)
        return event
    }

    @discardableResult
    public func logDose(substance: String, kind: DoseKind, amount: Double?, unit: String?,
                        route: String?, at timestamp: Date) async throws -> HealthEvent {
        let object = try await objectStore.findOrCreate(name: substance, kind: kind.objectKind, metadata: nil)
        var meta: [String: String] = [:]
        if let route, !route.isEmpty { meta["route"] = route }
        let event = HealthEvent(
            timestamp: timestamp, category: kind.eventCategory, subtype: substance,
            objectID: object.id, value: amount, unit: unit,
            source: .manual, metadata: Self.metadata(meta), dedupKey: nil)
        try await eventStore.save(event)
        return event
    }

    @discardableResult
    public func logNote(text: String, at timestamp: Date) async throws -> HealthEvent {
        let event = HealthEvent(
            timestamp: timestamp, category: .note, subtype: text,
            source: .manual, dedupKey: nil)
        try await eventStore.save(event)
        return event
    }
}
