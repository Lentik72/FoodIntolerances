import Foundation

/// US EPA Air Quality Index from PM2.5 (fine particulates). Pure; no I/O. Used at
/// ingest (app computes AQI from the day's mean PM2.5) and display (category name).
public enum AirQualityIndex {
    public static let poorAirThreshold = 101   // AQI ≥ 101 = "Unhealthy for Sensitive Groups"+

    /// EPA 24-hr PM2.5 breakpoints (µg/m³ → AQI), piecewise-linear.
    private static let breakpoints: [(cLo: Double, cHi: Double, iLo: Int, iHi: Int)] = [
        (0.0, 9.0, 0, 50), (9.1, 35.4, 51, 100), (35.5, 55.4, 101, 150),
        (55.5, 125.4, 151, 200), (125.5, 225.4, 201, 300), (225.5, 325.4, 301, 500),
    ]

    /// EPA AQI for a PM2.5 concentration (µg/m³). Concentration truncated to 0.1 per
    /// EPA convention; above the top breakpoint clamps to 500.
    public static func epaAQI(pm25: Double) -> Int {
        let c = (max(0, pm25) * 10).rounded(.down) / 10          // truncate to 0.1
        guard let bp = breakpoints.first(where: { c <= $0.cHi }) else { return 500 }
        let aqi = (Double(bp.iHi - bp.iLo) / (bp.cHi - bp.cLo)) * (c - bp.cLo) + Double(bp.iLo)
        return Int(aqi.rounded())
    }

    public enum AQICategory: Sendable, Equatable, Comparable, Hashable {
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

        /// Ordinal for comparing bands (escalation). NOT persisted — see `persistedToken`.
        public var severityRank: Int {
            switch self {
            case .good: 0
            case .moderate: 1
            case .unhealthySensitive: 2
            case .unhealthy: 3
            case .veryUnhealthy: 4
            case .hazardous: 5
            }
        }

        /// STABLE identifier for UserDefaults persistence — frozen, independent of
        /// `name` (localized) and `severityRank` (an ordering that could be renumbered).
        public var persistedToken: String {
            switch self {
            case .good: "good"
            case .moderate: "moderate"
            case .unhealthySensitive: "unhealthySensitive"
            case .unhealthy: "unhealthy"
            case .veryUnhealthy: "veryUnhealthy"
            case .hazardous: "hazardous"
            }
        }

        public init?(persistedToken token: String) {
            switch token {
            case "good": self = .good
            case "moderate": self = .moderate
            case "unhealthySensitive": self = .unhealthySensitive
            case "unhealthy": self = .unhealthy
            case "veryUnhealthy": self = .veryUnhealthy
            case "hazardous": self = .hazardous
            default: return nil
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.severityRank < rhs.severityRank }
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
