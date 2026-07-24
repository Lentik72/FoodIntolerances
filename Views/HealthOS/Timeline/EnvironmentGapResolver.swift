import Foundation
import HealthGraphCore

/// The one thing a day's Environment row can be missing because a fetch failed.
enum EnvironmentGap {
    case weather
    case airQuality

    var label: String {
        switch self {
        case .weather:    return "Weather unavailable"
        case .airQuality: return "Air quality unavailable"
        }
    }
}

/// Pure: does this day lack a reading that a *live* failure says was attempted?
/// Today consults the forward forecast; completed days consult observed history.
/// Scope containment uses each failure's own timezone, so a marker stays anchored
/// to the days it was about even if the device timezone later changes.
enum EnvironmentGapResolver {
    static func gap(for summary: EnvironmentDaySummary,
                    status: [EnvironmentCapability: EnvironmentCapabilityStatus],
                    now: Date, calendar: Calendar) -> EnvironmentGap? {
        let isToday = calendar.startOfDay(for: summary.dayStart) == calendar.startOfDay(for: now)
        let hasTemperature = summary.events.contains { $0.subtype == "temperature" }
        let hasAirQuality  = summary.events.contains { $0.subtype == "airQuality" }

        // Weather leads. Today → forecastWeather; a completed day → observedWeather.
        if !hasTemperature {
            let capability: EnvironmentCapability = isToday ? .forecastWeather : .observedWeather
            if liveScopeContains(summary.dayStart, status[capability]?.liveFailure) { return .weather }
        }
        // Air quality: completed days only (today has no observed AQI by design), and
        // only when weather didn't already fire.
        if !hasAirQuality, !isToday,
           liveScopeContains(summary.dayStart, status[.observedAirQuality]?.liveFailure) {
            return .airQuality
        }
        return nil
    }

    /// `dayStart` (an instant) falls inside `[scopeStart, scopeEnd]` when its
    /// start-of-day in the failure's own timezone lies within the stored bounds.
    private static func liveScopeContains(_ dayStart: Date, _ failure: EnvironmentFailure?) -> Bool {
        guard let failure else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: failure.timezoneID) ?? .current
        let day = cal.startOfDay(for: dayStart)
        return day >= failure.scopeStart && day <= failure.scopeEnd
    }
}
