import Foundation

/// Whether an environmental event reflects reality the user has already experienced
/// (mineable) or a forecast (display/warnings only). Stored in event metadata under
/// "provenance"; the mining sources are fail-closed on `.observedCompletedDay`.
public enum TemporalProvenance: String, Sendable, Equatable {
    case observedCompletedDay   // a completed local day's observation (or a deterministic date-fact)
    case forecast               // future conditions — never mined
    case currentSnapshot        // a current-conditions reading (e.g. pressure)
}

extension HealthEvent {
    /// Fail-closed: nil when metadata is absent, has no "provenance", or holds an
    /// unknown value — mining treats nil as NOT observed.
    public var temporalProvenance: TemporalProvenance? {
        guard let data = metadata,
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let raw = dict["provenance"] else { return nil }
        return TemporalProvenance(rawValue: raw)
    }
}
