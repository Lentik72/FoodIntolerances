import Foundation

/// Short-sleep nights as exposures. Reuses SleepSessionBuilder to fold raw
/// stage segments into nightly sessions, then flags nights whose total asleep
/// falls below the threshold. Naps are never "short sleep". Timestamped at
/// wake time, so the lag window measures forward into the waking day.
public struct ShortSleepExposureSource: ExposureSource {
    let config: EvidenceConfig
    public init(config: EvidenceConfig) { self.config = config }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        let tzID = events.first(where: { $0.category == .sleep })?.timezoneID ?? "UTC"
        let tz = TimeZone(identifier: tzID) ?? .current
        let sessions = SleepSessionBuilder.sessions(from: events, timeZone: tz)
        // Deterministic synthetic id derived from the wake time (sessions aren't
        // graph events); reused for drill-down provenance.
        return sessions.compactMap { s in
            guard s.kind == .night, s.asleepMinutes < config.shortSleepThresholdMinutes else { return nil }
            let syntheticID = UUID(uuidString: Self.uuid(from: s.end)) ?? UUID()
            return ExposureOccurrence(key: .derived(.shortSleep), timestamp: s.end,
                                      timezoneID: tzID, sourceEventID: syntheticID)
        }
    }
    // Stable UUID string from an epoch second — no randomness (determinism rule).
    static func uuid(from date: Date) -> String {
        let n = UInt64(max(0, date.timeIntervalSince1970))
        let hex = String(format: "%016llx", n)
        return "00000000-0000-0000-\(hex.prefix(4))-\(hex.suffix(12))"
    }
}
