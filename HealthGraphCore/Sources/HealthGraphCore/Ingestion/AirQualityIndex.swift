import Foundation

/// US EPA Air Quality Index from PM2.5 (fine particulates). Pure; no I/O. Used at
/// ingest (app computes AQI from the day's mean PM2.5) and display (category name).
public enum AirQualityIndex {
    public static let poorAirThreshold = 101   // AQI ≥ 101 = "Unhealthy for Sensitive Groups"+

    /// EPA 24-hr PM2.5 breakpoints (µg/m³ → AQI), piecewise-linear.
    private static let breakpoints: [(cLo: Double, cHi: Double, iLo: Int, iHi: Int)] = [
        (0.0, 12.0, 0, 50), (12.1, 35.4, 51, 100), (35.5, 55.4, 101, 150),
        (55.5, 150.4, 151, 200), (150.5, 250.4, 201, 300),
        (250.5, 350.4, 301, 400), (350.5, 500.4, 401, 500),
    ]

    /// EPA AQI for a PM2.5 concentration (µg/m³). Concentration truncated to 0.1 per
    /// EPA convention; above the top breakpoint clamps to 500.
    public static func epaAQI(pm25: Double) -> Int {
        let c = (max(0, pm25) * 10).rounded(.down) / 10          // truncate to 0.1
        guard let bp = breakpoints.first(where: { c <= $0.cHi }) else { return 500 }
        let aqi = (Double(bp.iHi - bp.iLo) / (bp.cHi - bp.cLo)) * (c - bp.cLo) + Double(bp.iLo)
        return Int(aqi.rounded())
    }

    public enum AQICategory: Sendable, Equatable {
        case good, moderate, unhealthySensitive, unhealthy, veryUnhealthy, hazardous
        public var name: String {
            switch self {
            case .good: "Good"
            case .moderate: "Moderate"
            case .unhealthySensitive: "Unhealthy for sensitive groups"
            case .unhealthy: "Unhealthy"
            case .veryUnhealthy: "Very unhealthy"
            case .hazardous: "Hazardous"
            }
        }
    }

    public static func category(aqi: Int) -> AQICategory {
        switch aqi {
        case ..<51: .good
        case ..<101: .moderate
        case ..<151: .unhealthySensitive
        case ..<201: .unhealthy
        case ..<301: .veryUnhealthy
        default: .hazardous
        }
    }
}
