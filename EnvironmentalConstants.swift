import Foundation

// MARK: - Moon Phase

/// Type-safe moon phase representation
enum MoonPhase: String, CaseIterable, Codable {
    case newMoon = "New Moon 🌑"
    case waxingCrescent = "Waxing Crescent 🌒"
    case firstQuarter = "First Quarter 🌓"
    case waxingGibbous = "Waxing Gibbous 🌔"
    case fullMoon = "Full Moon 🌕"
    case waningGibbous = "Waning Gibbous 🌖"
    case lastQuarter = "Last Quarter 🌗"
    case waningCrescent = "Waning Crescent 🌘"

    /// Display name without emoji
    var name: String {
        switch self {
        case .newMoon: return "New Moon"
        case .waxingCrescent: return "Waxing Crescent"
        case .firstQuarter: return "First Quarter"
        case .waxingGibbous: return "Waxing Gibbous"
        case .fullMoon: return "Full Moon"
        case .waningGibbous: return "Waning Gibbous"
        case .lastQuarter: return "Last Quarter"
        case .waningCrescent: return "Waning Crescent"
        }
    }

    /// Emoji representation
    var emoji: String {
        switch self {
        case .newMoon: return "🌑"
        case .waxingCrescent: return "🌒"
        case .firstQuarter: return "🌓"
        case .waxingGibbous: return "🌔"
        case .fullMoon: return "🌕"
        case .waningGibbous: return "🌖"
        case .lastQuarter: return "🌗"
        case .waningCrescent: return "🌘"
        }
    }

    /// Check if this phase matches a string (for legacy compatibility)
    func matches(_ string: String) -> Bool {
        let lowered = string.lowercased()
        return lowered.contains(name.lowercased()) || rawValue.lowercased() == lowered
    }

    /// Create from legacy string
    static func from(string: String) -> MoonPhase? {
        let lowered = string.lowercased()
        return MoonPhase.allCases.first { phase in
            lowered.contains(phase.name.lowercased())
        }
    }
}

// MARK: - Mercury Retrograde

/// Centralized Mercury retrograde periods
/// Update this annually with new periods
enum MercuryRetrograde {
    /// All known retrograde periods
    static let periods: [(start: Date, end: Date)] = {
        let calendar = Calendar.current
        var periods: [(Date, Date)] = []

        // 2025 periods
        if let start1 = calendar.date(from: DateComponents(year: 2025, month: 3, day: 14)),
           let end1 = calendar.date(from: DateComponents(year: 2025, month: 4, day: 7)) {
            periods.append((start1, end1))
        }
        if let start2 = calendar.date(from: DateComponents(year: 2025, month: 7, day: 17)),
           let end2 = calendar.date(from: DateComponents(year: 2025, month: 8, day: 11)) {
            periods.append((start2, end2))
        }
        if let start3 = calendar.date(from: DateComponents(year: 2025, month: 11, day: 9)),
           let end3 = calendar.date(from: DateComponents(year: 2025, month: 11, day: 29)) {
            periods.append((start3, end3))
        }

        // 2026 periods
        if let start1 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 25)),
           let end1 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20)) {
            periods.append((start1, end1))
        }
        if let start2 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 29)),
           let end2 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 23)) {
            periods.append((start2, end2))
        }
        if let start3 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24)),
           let end3 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13)) {
            periods.append((start3, end3))
        }

        return periods
    }()

    /// Check if a given date falls within a Mercury retrograde period
    static func isRetrograde(on date: Date = Date()) -> Bool {
        for (start, end) in periods {
            if date >= start && date <= end {
                return true
            }
        }
        return false
    }

    /// Get the current or next retrograde period
    static func currentOrNextPeriod(from date: Date = Date()) -> (start: Date, end: Date)? {
        // Check if currently in retrograde
        for period in periods {
            if date >= period.start && date <= period.end {
                return period
            }
        }
        // Find next upcoming period
        return periods.first { $0.start > date }
    }
}

// MARK: - Pressure Category

/// Atmospheric pressure categories
enum PressureCategory: String, CaseIterable, Codable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"

    /// Categorize a pressure value in hPa
    static func from(pressure: Double) -> PressureCategory {
        switch pressure {
        case ..<1000:
            return .low
        case 1000...1020:
            return .normal
        default:
            return .high
        }
    }
}

// MARK: - Environmental Thresholds

/// Centralized environmental thresholds and constants
enum EnvironmentalThresholds {
    /// Pressure change threshold for "sudden change" detection (in hPa)
    static let suddenPressureChange: Double = 6.0

    /// Default/fallback atmospheric pressure (in hPa)
    static let defaultPressure: Double = 1013.0

    /// Minimum interval between pressure readings (in seconds)
    static let pressureReadingInterval: TimeInterval = 3600 // 1 hour

    /// Location update distance filter (in meters)
    static let locationDistanceFilter: Double = 100.0

    /// Location request timeout (in seconds)
    static let locationTimeout: TimeInterval = 5.0
}
