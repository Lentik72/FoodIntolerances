import Foundation

/// Discrete object exposures: food / medication / supplement / peptide events
/// that reference a health_object. One occurrence per event, keyed by objectID.
public struct ObjectExposureSource: ExposureSource {
    static let categories: Set<EventCategory> = [.food, .medication, .supplement, .peptide]
    public init() {}
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        events.compactMap { e in
            guard Self.categories.contains(e.category), let oid = e.objectID else { return nil }
            return ExposureOccurrence(key: .object(oid, e.category), timestamp: e.timestamp,
                                      timezoneID: e.timezoneID, sourceEventID: e.id)
        }
    }
}
