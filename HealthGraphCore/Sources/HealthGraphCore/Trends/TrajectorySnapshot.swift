import Foundation

/// The two chart windows the Trends UI offers: a recent quarter or a full
/// year. The raw value IS the week count `TrajectoryService` buckets over —
/// keep the two in lockstep; do not introduce a second mapping between this
/// case and its week count.
public enum TrendWindow: Int, CaseIterable, Sendable {
    case weeks13 = 13
    case weeks52 = 52
}

/// A charted series with its coverage. A VALUE, not a rendered string: the
/// doctor-report round renders these rather than recomputing them. Carries
/// NO direction, NO p-value, NO verdict of any kind — chartable was
/// deliberately decoupled from verdict-eligible for this round (see the
/// round's decision record:
/// docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md).
public struct TrajectorySnapshot: Sendable {
    public let series: TrajectorySeries
    public let window: TrendWindow
    /// Calendar-week medians; a week with no data is simply absent from this
    /// array, never a zero-valued point.
    public let weeks: [WeeklyPoint]
    public let coverage: SeriesCoverage
    /// Minimum weekly median across the window — NOT the minimum raw reading.
    public let rangeLow: Double
    /// Maximum weekly median across the window — NOT the maximum raw reading.
    public let rangeHigh: Double

    public init(
        series: TrajectorySeries,
        window: TrendWindow,
        weeks: [WeeklyPoint],
        coverage: SeriesCoverage,
        rangeLow: Double,
        rangeHigh: Double
    ) {
        self.series = series
        self.window = window
        self.weeks = weeks
        self.coverage = coverage
        self.rangeLow = rangeLow
        self.rangeHigh = rangeHigh
    }
}
