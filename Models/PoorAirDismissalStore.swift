import Foundation
import HealthGraphCore

/// Persists, per LOCAL calendar day, the highest AQI band the user has dismissed —
/// so a warning re-shows only on a new day or when the forecast escalates to a
/// higher band. Stored as the band's STABLE token (never `name`/`severityRank`).
struct PoorAirDismissalStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(now: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: now)
        // Stable, locale-independent day key.
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        return "hg.poorAir.dismissed.\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    /// Test-only key exposure (used to seed a corrupt token).
    func debugKey(now: Date, calendar: Calendar) -> String { key(now: now, calendar: calendar) }

    func highestDismissedBandToday(now: Date, calendar: Calendar) -> AirQualityIndex.AQICategory? {
        guard let token = defaults.string(forKey: key(now: now, calendar: calendar)) else { return nil }
        return AirQualityIndex.AQICategory(persistedToken: token)   // unknown token → nil
    }

    func recordDismissed(_ band: AirQualityIndex.AQICategory, now: Date, calendar: Calendar) {
        let existing = highestDismissedBandToday(now: now, calendar: calendar)
        let maxBand = max(existing ?? band, band)                  // Comparable from Task 1
        defaults.set(maxBand.persistedToken, forKey: key(now: now, calendar: calendar))
    }
}
