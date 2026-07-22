import Foundation

/// Centralized API configuration
/// API keys should be loaded from environment or secure storage, NOT hardcoded
enum APIConfig {

    // MARK: - OpenWeather Configuration

    /// OpenWeatherMap API key (nil if not configured)
    /// To configure: Set OPENWEATHER_API_KEY in your xcconfig or environment
    static var openWeatherAPIKey: String? {
        // Try to get from Info.plist (injected via xcconfig)
        if let key = Bundle.main.infoDictionary?["OPENWEATHER_API_KEY"] as? String,
           !key.isEmpty,
           !key.hasPrefix("$(") { // Not an unresolved variable
            return key
        }

        // Try environment variable (for CI/testing)
        if let key = ProcessInfo.processInfo.environment["OPENWEATHER_API_KEY"],
           !key.isEmpty {
            return key
        }

        #if DEBUG
        Logger.warning("OPENWEATHER_API_KEY not configured. Weather features disabled.", category: .network)
        #endif

        return nil
    }

    /// Whether weather features are available
    static var isWeatherAvailable: Bool {
        openWeatherAPIKey != nil
    }

    /// Base URL for OpenWeatherMap API
    static let openWeatherBaseURL = "https://api.openweathermap.org/data/2.5"

    /// Build weather API URL for given coordinates (nil if API key not configured)
    static func weatherURL(latitude: Double, longitude: Double) -> URL? {
        guard let apiKey = openWeatherAPIKey else {
            return nil
        }
        let urlString = "\(openWeatherBaseURL)/weather?lat=\(latitude)&lon=\(longitude)&appid=\(apiKey)&units=metric"
        return URL(string: urlString)
    }

    /// Build forecast API URL for given coordinates (nil if API key not configured)
    static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        guard let apiKey = openWeatherAPIKey else {
            return nil
        }
        let urlString = "\(openWeatherBaseURL)/forecast?lat=\(latitude)&lon=\(longitude)&appid=\(apiKey)&units=metric"
        return URL(string: urlString)
    }

    /// Build air pollution forecast API URL for given coordinates (nil if API key not configured)
    static func airPollutionURL(latitude: Double, longitude: Double) -> URL? {
        guard let apiKey = openWeatherAPIKey else {
            return nil
        }
        let urlString = "\(openWeatherBaseURL)/air_pollution/forecast?lat=\(latitude)&lon=\(longitude)&appid=\(apiKey)"
        return URL(string: urlString)
    }

    /// Build air pollution HISTORY API URL for given coordinates and a Unix-epoch
    /// `[start, end]` span (nil if API key not configured). `start`/`end` are
    /// `TimeInterval` — callers pass `window.start.timeIntervalSince1970` from a
    /// `completedDayWindow(...)` result, not `Int(aDate)` (a `Date` doesn't
    /// convert to `Int`).
    static func airPollutionHistoryURL(latitude: Double, longitude: Double, start: TimeInterval, end: TimeInterval) -> URL? {
        guard let apiKey = openWeatherAPIKey else {
            return nil
        }
        let urlString = "\(openWeatherBaseURL)/air_pollution/history?lat=\(latitude)&lon=\(longitude)&start=\(Int(start))&end=\(Int(end))&appid=\(apiKey)"
        return URL(string: urlString)
    }

    /// Base URL for OpenWeather One Call 3.0 (separate subscription; a 401 error
    /// body — not a transport failure — is what "not subscribed" looks like).
    static let openWeatherOneCallBaseURL = "https://api.openweathermap.org/data/3.0"

    /// Build a One Call day_summary URL for observed completed-day weather.
    /// `date` is a local "yyyy-MM-dd" string; `tz` is the "±HH:MM" offset that
    /// controls the provider's aggregation day (WITHOUT it, OpenWeather derives
    /// the timezone from the location — for a remote manual location that would
    /// disagree with the app's stored local day, so the caller always supplies
    /// the app calendar's date-specific offset). "+" is percent-encoded (%2B) so
    /// no query parser can read it as a space. Nil if the API key is missing.
    static func oneCallDaySummaryURL(latitude: Double, longitude: Double, date: String, tz: String) -> URL? {
        guard let apiKey = openWeatherAPIKey else {
            return nil
        }
        let encodedTZ = tz.replacingOccurrences(of: "+", with: "%2B")
        let urlString = "\(openWeatherOneCallBaseURL)/onecall/day_summary?lat=\(latitude)&lon=\(longitude)&date=\(date)&tz=\(encodedTZ)&units=metric&appid=\(apiKey)"
        return URL(string: urlString)
    }
}
