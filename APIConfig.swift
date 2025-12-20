import Foundation

/// Centralized API configuration
/// API keys should be stored in Info.plist, NOT hardcoded in source code
enum APIConfig {

    /// OpenWeatherMap API key
    /// To configure: Add "OPENWEATHER_API_KEY" to your Info.plist
    /// For production: Use environment variables or a secure secrets manager
    static var openWeatherAPIKey: String {
        // First try to get from Info.plist
        if let key = Bundle.main.infoDictionary?["OPENWEATHER_API_KEY"] as? String,
           !key.isEmpty,
           !key.hasPrefix("$(") { // Not an unresolved variable
            return key
        }

        // Fallback for development - should be removed before App Store submission
        #if DEBUG
        print("⚠️ Warning: Using fallback API key. Add OPENWEATHER_API_KEY to Info.plist for production.")
        return "816e786b3842e5b9ee47464ead16193c"
        #else
        // In release builds, require proper configuration
        fatalError("OPENWEATHER_API_KEY not configured in Info.plist. Please add your API key.")
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
