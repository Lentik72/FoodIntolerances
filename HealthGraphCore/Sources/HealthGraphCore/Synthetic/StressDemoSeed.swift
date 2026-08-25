import Foundation

/// A deterministic corpus for the high-stress exposure, and the only thing in
/// the app that produces its accepted shape at any volume.
///
/// It exists because a real device cannot demonstrate this feature: mining
/// needs exposure→outcome pairs, outcomes come almost entirely from manual
/// capture, and a real graph is overwhelmingly imported HealthKit data with a
/// handful of manual events. The relationship report on such a graph is empty,
/// so every assertion about it passes for the wrong reason.
///
/// Deliberately index arithmetic rather than a seeded RNG: the acceptance test
/// asserts exact follower counts, and a generator that could drift by one would
/// make that test flaky rather than precise.
public enum StressDemoSeed {
    public static let days = 120
    public static let outcomeSubtype = "headache"

    /// `endingAt` is the most recent day of the corpus; everything runs backwards
    /// from it, so the data is always recent relative to the recompute that
    /// follows and cannot age out of a staleness window.
    public static func events(endingAt end: Date, timeZone: TimeZone = .current) -> [HealthEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let tz = timeZone.identifier
        let lastDay = cal.startOfDay(for: end)
        var events: [HealthEvent] = []

        for d in 0..<days {
            guard let dayStart = cal.date(byAdding: .day, value: -(days - 1 - d), to: lastDay) else { continue }

            // Stress on every even day index — 60 of 120, comfortably above
            // minExposures (5) and above noEffectMinExposures (20), so the edge is
            // evaluated as a trigger rather than parked as a null result.
            guard d % 2 == 0 else {
                // A headache on one in seven stress-free days (~15%). Without this
                // the unexposed rate is zero, the ratio is degenerate, and the
                // demo proves less than it appears to.
                //
                // 18:00 specifically, NOT the morning: stress lands at 14:00 and
                // stressLagHours is 0...24, so a stress-free day's morning is still
                // inside the PREVIOUS stress day's window. A baseline headache
                // placed there would be counted as a follow, inflating the exposed
                // rate and shrinking the very contrast this noise exists to create.
                // 18:00 on an odd day is 28h after the last stress event.
                if (d / 2) % 7 == 0 {
                    events.append(headache(at: dayStart.addingTimeInterval(18 * 3600), tz: tz,
                                           day: d, severity: 4, kind: "base"))
                }
                continue
            }

            let stressAt = dayStart.addingTimeInterval(14 * 3600)
            events.append(HealthEvent(
                timestamp: stressAt, timezoneID: tz, category: .symptom,
                subtype: HighStressExposureSource.symptomSubtype,
                value: Double(7 + (d / 2) % 3),                    // 7, 8, 9 — all at or above threshold
                unit: HighStressExposureSource.symptomUnit,
                source: .manual,
                dedupKey: "stressDemo|stress|\(d)"))

            // Three of every four stress days are followed (75%), three hours
            // later — well inside stressLagHours (0...24).
            if (d / 2) % 4 != 3 {
                events.append(headache(at: stressAt.addingTimeInterval(3 * 3600), tz: tz,
                                       day: d, severity: 6, kind: "follow"))
            }
        }
        return events
    }

    private static func headache(at timestamp: Date, tz: String, day: Int,
                                 severity: Double, kind: String) -> HealthEvent {
        HealthEvent(timestamp: timestamp, timezoneID: tz, category: .symptom,
                    subtype: outcomeSubtype, value: severity, unit: "severity",
                    source: .manual, dedupKey: "stressDemo|\(kind)|\(day)")
    }
}
