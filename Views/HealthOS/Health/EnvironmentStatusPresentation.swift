import Foundation

/// Pure formatting for the Health "Environment data" screen. Returns dates (not
/// formatted strings) so the view owns time formatting and this stays testable.
enum EnvironmentStatusPresentation {

    // Order used to pick the earliest failing capability for the summary + explanation.
    static let order: [EnvironmentCapability] = [
        .currentPressure, .forecastWeather, .observedWeather, .forecastAirQuality, .observedAirQuality
    ]

    enum Section { case weather, airQuality }

    // MARK: Summary row

    enum Summary: Equatable {
        case unavailable(String)   // an affected-group phrase
        case notChecked
        case updated(Date)         // the LEAST-recent success across all five
    }

    static func summary(_ statuses: [EnvironmentCapability: EnvironmentCapabilityStatus]) -> Summary {
        if let cap = order.first(where: { statuses[$0]?.liveFailure != nil }) {
            return .unavailable(groupPhrase(for: cap))
        }
        let successes = EnvironmentCapability.allCases.map { statuses[$0]?.lastSuccess }
        if successes.contains(where: { $0 == nil }) { return .notChecked }
        let leastRecent = successes.compactMap { $0 }.min()!
        return .updated(leastRecent)
    }

    /// A live-failure group phrase for the summary.
    private static func groupPhrase(for capability: EnvironmentCapability) -> String {
        switch capability {
        case .currentPressure, .forecastWeather: return "Weather unavailable"
        case .observedWeather:                    return "Weather history unavailable"
        case .forecastAirQuality:                 return "Air quality unavailable"
        case .observedAirQuality:                 return "Air quality history unavailable"
        }
    }

    // MARK: Per-capability rows

    enum RowStatus: Equatable { case unavailable, notChecked, updated(Date) }
    struct Row: Equatable {
        let capability: EnvironmentCapability
        let section: Section
        let title: String
        let status: RowStatus
    }

    static func rows(_ statuses: [EnvironmentCapability: EnvironmentCapabilityStatus]) -> [Row] {
        order.map { cap in
            Row(capability: cap, section: section(for: cap), title: title(for: cap), status: rowStatus(statuses[cap])) }
    }

    private static func rowStatus(_ s: EnvironmentCapabilityStatus?) -> RowStatus {
        if s?.liveFailure != nil { return .unavailable }
        if let success = s?.lastSuccess { return .updated(success) }
        return .notChecked
    }

    private static func section(for capability: EnvironmentCapability) -> Section {
        switch capability {
        case .currentPressure, .forecastWeather, .observedWeather: return .weather
        case .forecastAirQuality, .observedAirQuality: return .airQuality
        }
    }

    private static func title(for capability: EnvironmentCapability) -> String {
        switch capability {
        case .currentPressure:    return "Air pressure"
        case .forecastWeather:    return "Today's forecast"
        case .observedWeather:    return "Observed history"
        case .forecastAirQuality: return "Today's forecast"
        case .observedAirQuality: return "Observed history"
        }
    }

    // MARK: Bottom explanation (live > resolved > none)

    struct Explanation: Equatable {
        let heading: String       // "Why it stopped" | "Last issue — resolved"
        let body: String
        let showOpenSettings: Bool
        let isResolved: Bool
        let at: Date              // when the selected failure occurred
    }

    static func explanation(_ statuses: [EnvironmentCapability: EnvironmentCapabilityStatus]) -> Explanation? {
        if let cap = order.first(where: { statuses[$0]?.liveFailure != nil }),
           let live = statuses[cap]?.liveFailure {
            return Explanation(heading: "Why it stopped",
                               body: liveCopy(live.reason, capability: cap),
                               showOpenSettings: live.reason == .locationDenied,
                               isResolved: false,
                               at: live.at)
        }
        // All healed: the most recent retained failure, past tense, no action.
        let retained = EnvironmentCapability.allCases.compactMap { statuses[$0]?.lastFailure }
        if let mostRecent = retained.max(by: { $0.at < $1.at }) {
            return Explanation(heading: "Last issue — resolved",
                               body: resolvedCopy(mostRecent.reason),
                               showOpenSettings: false,
                               isResolved: true,
                               at: mostRecent.at)
        }
        return nil
    }

    // MARK: Adaptive timestamp decision (pure; views own the actual formatting)

    enum TimestampStyle: Equatable { case timeToday, dateOlder }

    static func timestampStyle(for date: Date, now: Date, calendar: Calendar) -> TimestampStyle {
        calendar.isDate(date, inSameDayAs: now) ? .timeToday : .dateOlder
    }

    private static func liveCopy(_ reason: EnvironmentFailureReason, capability: EnvironmentCapability) -> String {
        switch reason {
        case .notConfigured:      return "Weather data isn't configured in this build."
        case .rejected:
            return capability == .observedWeather
                ? "Historical weather may need a valid API key or an active One Call subscription."
                : "The weather service rejected the request."
        case .locationDenied:     return "Location access is off, so conditions can't be looked up for where you are."
        case .locationUnavailable:return "Your location hasn't been determined yet."
        case .offline:            return "No internet connection the last time we checked."
        case .insufficientData:   return "The forecast didn't include enough data for today yet."
        case .badResponse:        return "The weather service returned something unexpected."
        }
    }

    private static func resolvedCopy(_ reason: EnvironmentFailureReason) -> String {
        switch reason {
        case .notConfigured:      return "Weather data wasn't configured."
        case .rejected:           return "The weather service was rejecting requests."
        case .locationDenied:     return "Location access was off."
        case .locationUnavailable:return "Your location couldn't be determined."
        case .offline:            return "There was no internet connection."
        case .insufficientData:   return "The forecast was briefly incomplete."
        case .badResponse:        return "The weather service returned something unexpected."
        }
    }
}
