import Foundation

public extension HealthEvent {
    /// HealthKit's period-start marker, tri-state.
    ///
    /// `true` = authoritative start. `false` = authoritatively NOT a start.
    /// `nil` = unknown, which is what export-file and legacy rows carry and is
    /// the ONLY case eligible for run inference (see CyclePhaseExposureSource).
    /// Never collapse nil to false — `dict["…"] == "true"` would do exactly that.
    var menstrualCycleStart: Bool? {
        guard let metadata,
              let dict = try? JSONDecoder().decode([String: String].self, from: metadata),
              let raw = dict["menstrualCycleStart"] else { return nil }
        return raw == "true"
    }
}
