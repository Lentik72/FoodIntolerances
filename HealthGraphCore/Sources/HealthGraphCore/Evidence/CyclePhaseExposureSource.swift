import Foundation

/// Cycle-phase exposures. v1 scopes to the two symptomatic windows: menstrual
/// (the logged period-start day) and luteal (the configured number of days
/// before the *next* logged period start). Each phase-day is emitted as one
/// occurrence at that day's start, so the analyzer treats it with a standard
/// 24h window. Needs ≥2 logged period starts to bound a luteal window.
public struct CyclePhaseExposureSource: ExposureSource {
    let config: EvidenceConfig
    let timeZone: TimeZone
    public init(config: EvidenceConfig, timeZone: TimeZone) {
        self.config = config; self.timeZone = timeZone
    }
    public func occurrences(from events: [HealthEvent]) -> [ExposureOccurrence] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let starts = events
            .filter { $0.category == .cycle && $0.subtype == "periodStart" }
            .map(\.timestamp)
            .sorted()
        guard starts.count >= 2 else { return [] }
        var out: [ExposureOccurrence] = []
        func occ(_ phase: CyclePhase, day: Date) -> ExposureOccurrence {
            let d = cal.startOfDay(for: day)
            // Deterministic synthetic id from the day (phase-days aren't graph events).
            let sid = UUID(uuidString: ShortSleepExposureSource.uuid(from: d)) ?? UUID()
            return ExposureOccurrence(key: .derived(.cyclePhase(phase)), timestamp: d,
                                      timezoneID: timeZone.identifier, sourceEventID: sid)
        }
        for start in starts { out.append(occ(.menstrual, day: start)) }
        for i in 1..<starts.count {
            let nextStart = cal.startOfDay(for: starts[i])
            for back in 1...config.lutealWindowDays {
                if let day = cal.date(byAdding: .day, value: -back, to: nextStart) {
                    out.append(occ(.luteal, day: day))
                }
            }
        }
        return out
    }
}
