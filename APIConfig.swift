import Foundation

/// Centralized API configuration
/// API keys are loaded from Secrets.xcconfig (gitignored) via Info.plist
enum APIConfig {

    /// OpenWeatherMap API key
    /// To configure: Copy Secrets.xcconfig.template to Secrets.xcconfig and add your key
    static var openWeatherAPIKey: String {
        // First try to get from Info.plist
        if let key = Bundle.main.infoDictionary?["OPENWEATHER_API_KEY"] as? String,
           !key.isEmpty,
           !key.hasPrefix("$(") { // Not an unresolved variable
            return key
        }

        // No fallback - require proper configuration
        #if DEBUG
        fatalError("""
            OPENWEATHER_API_KEY not configured.

            To fix:
            1. Copy Secrets.xcconfig.template to Secrets.xcconfig
            2. Add your OpenWeather API key to Secrets.xcconfig
            3. In Xcode, add Secrets.xcconfig to your project's build configuration

            Get a free API key at: https://openweathermap.org/api
            """)
        #else
        fatalError("OPENWEATHER_API_KEY not configured. Please check your build configuration.")
        #endif
    }

    /// Base URL for OpenWeatherMap API
    static let openWeatherBaseURL = "https://api.openweathermap.org/data/2.5"

    /// Build weather API URL for given coordinates
    static func weatherURL(latitude: Double, longitude: Double) -> URL? {
        let urlString = "\(openWeatherBaseURL)/weather?lat=\(latitude)&lon=\(longitude)&appid=\(openWeatherAPIKey)&units=metric"
        return URL(string: urlString)
    }

    /// Build forecast API URL for given coordinates
    static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        let urlString = "\(openWeatherBaseURL)/forecast?lat=\(latitude)&lon=\(longitude)&appid=\(openWeatherAPIKey)"
        return URL(string: urlString)
    }
}
