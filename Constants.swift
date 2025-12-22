import SwiftUI

// MARK: - App Constants
enum AppConstants {

    // MARK: - Severity Scale
    enum Severity {
        static let range = 1...5
        static let min = 1
        static let max = 5

        static let descriptions = [
            1: "Mild",
            2: "Light",
            3: "Moderate",
            4: "Severe",
            5: "Extreme"
        ]

        static func description(for level: Int) -> String {
            descriptions[level] ?? "Unknown"
        }
    }

    // MARK: - Atmospheric Pressure
    enum AtmosphericPressure {
        static let categories = ["Low", "Normal", "High"]
        static let low = "Low"
        static let normal = "Normal"
        static let high = "High"
    }

    // MARK: - Status
    enum Status {
        static let active = "Active"
        static let inactive = "Inactive"
        static let loading = "Loading..."
        static let error = "Error"
    }

    // MARK: - Tags
    enum Tags {
        static let webSourceUnverified = "Web Source - Unverified"
    }

    // MARK: - Limits
    enum Limits {
        static let maxTopResults = 5
        static let maxRecentItems = 10
        static let maxUpcomingReminders = 3
        static let minCorrelationOccurrences = 3
    }

    // MARK: - Time Intervals (in seconds)
    enum TimeInterval {
        static let minimumRefresh: Double = 300 // 5 minutes
        static let pressureReadingInterval: Double = 3600 // 1 hour
        static let confirmationDisplay: Double = 1.5
        static let refreshDebounce: Double = 2.0
        static let defaultGoalDuration: Double = 60 * 60 * 24 * 30 // 30 days

        // Reminder offsets
        static let reminder1Hour: Double = 3600
        static let reminder2Hours: Double = 7200
        static let reminder3Hours: Double = 10800
    }

    // MARK: - Timeouts (in nanoseconds)
    enum Timeout {
        static let atmosphericFetch: UInt64 = 8_000_000_000 // 8s
        static let locationRequest: UInt64 = 5_000_000_000 // 5s
        static let debounceDelay: UInt64 = 100_000_000 // 100ms
        static let locationRetry: UInt64 = 1_000_000_000 // 1s
    }
}

// MARK: - UI Constants
enum UIConstants {

    // MARK: - Spacing
    enum Spacing {
        static let none: CGFloat = 0
        static let minimal: CGFloat = 2
        static let extraSmall: CGFloat = 4
        static let small: CGFloat = 5
        static let base: CGFloat = 8
        static let medium: CGFloat = 10
        static let mediumPlus: CGFloat = 12
        static let large: CGFloat = 15
        static let extraLarge: CGFloat = 20
    }

    // MARK: - Corner Radius
    enum CornerRadius {
        static let minimal: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 10
        static let mediumPlus: CGFloat = 12
        static let large: CGFloat = 15
        static let extraLarge: CGFloat = 20
    }

    // MARK: - Shadow
    enum Shadow {
        static let minimal: CGFloat = 1
        static let small: CGFloat = 2
        static let medium: CGFloat = 3
        static let large: CGFloat = 4
        static let extraLarge: CGFloat = 5
    }

    // MARK: - Opacity
    enum Opacity {
        static let veryLight: Double = 0.1
        static let light: Double = 0.15
        static let minimal: Double = 0.2
        static let subtle: Double = 0.3
        static let medium: Double = 0.5
        static let mediumStrong: Double = 0.6
        static let strong: Double = 0.8
    }

    // MARK: - Frame Heights
    enum Height {
        static let imagePreview: CGFloat = 100
        static let chartSmall: CGFloat = 200
        static let chartMedium: CGFloat = 250
        static let chartLarge: CGFloat = 300
        static let bodyMapModal: CGFloat = 400
        static let standardButton: CGFloat = 44
    }

    // MARK: - Icon Sizes
    enum IconSize {
        static let small: CGFloat = 40
        static let medium: CGFloat = 50
        static let large: CGFloat = 60
    }

    // MARK: - Animation
    enum Animation {
        static let quick: Double = 0.2
        static let mediumFast: Double = 0.3
        static let medium: Double = 0.5
    }

    // MARK: - Scale Effects
    enum Scale {
        static let buttonPress: CGFloat = 0.95
        static let hover: CGFloat = 1.05
        static let slightExpansion: CGFloat = 1.1
        static let emphasis: CGFloat = 1.5
    }
}
