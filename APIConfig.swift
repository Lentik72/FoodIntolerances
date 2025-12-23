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
        let urlString = "\(openWeatherBaseURL)/forecast?lat=\(latitude)&lon=\(longitude)&appid=\(apiKey)"
        return URL(string: urlString)
    }
}
