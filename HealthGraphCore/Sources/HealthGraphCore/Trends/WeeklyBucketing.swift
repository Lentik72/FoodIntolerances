import Foundation

/// One reading collapsed onto a calendar day — the unit `WeeklyBucketing`
/// consumes. Multiple readings on the same day are the caller's business:
/// bucketing collapses them to that day's median before a week ever sees
/// them (see `WeeklyBucketing.bucket`).
public struct DailyPoint: Equatable, Sendable {
    public let day: Date
    public let value: Double

    public init(day: Date, value: Double) {
        self.day = day
        self.value = value
    }
}

/// One calendar week's summary. `value` is the median of that week's day
/// medians, not the median (or mean) of its raw readings. `dayCount` counts
/// DAYS with data, not readings — three weigh-ins on one Monday count once.
public struct WeeklyPoint: Equatable, Sendable {
    public let weekStart: Date
    public let value: Double
    public let dayCount: Int

    public init(weekStart: Date, value: Double, dayCount: Int) {
        self.weekStart = weekStart
        self.value = value
        self.dayCount = dayCount
    }
}

/// How much of the requested window actually has data, at both grains.
/// `daysInWindow` ends at `asOf`, not at the end of the (possibly partial)
/// current week — otherwise a perfect logger could never show 100% coverage
/// mid-week. `weeksInWindow` is always the requested `weeksBack`.
public struct SeriesCoverage: Equatable, Sendable {
    public let daysWithData: Int
    public let daysInWindow: Int
    public let weeksWithData: Int
    public let weeksInWindow: Int

    public init(daysWithData: Int, daysInWindow: Int, weeksWithData: Int, weeksInWindow: Int) {
        self.daysWithData = daysWithData
        self.daysInWindow = daysInWindow
        self.weeksWithData = weeksWithData
        self.weeksInWindow = weeksInWindow
    }
}

/// Pure calendar-week bucketing for chart-only trend series — no verdict,
/// no direction, just medians and coverage (see the round's decision record:
/// docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md).
///
/// Buckets are actual calendar weeks (`dateInterval(of: .weekOfYear)`),
/// respecting the calendar's `firstWeekday`. That is what makes bucket
/// membership stable: the same reading lands in the same week no matter
/// which day the analysis runs. A window anchored to "now" instead would
/// have the opposite property — every boundary sliding daily.
///
/// All date arithmetic here goes through `Calendar`, never fixed-second
/// offsets: a week is not always 604,800 seconds, and a day is not always
/// 86,400 — DST transitions make both untrue twice a year.
public enum WeeklyBucketing {
    /// Buckets `points` into the last `weeksBack` calendar weeks ending with
    /// the week containing `asOf`. That last week may be partial and is
    /// still included as such — every *other* bucket holds exactly seven
    /// days. Readings before the window start or after `asOf` are dropped;
    /// the window filter is the only boundary applied. Empty weeks are
    /// omitted, never emitted as a zero-valued point. Weeks are sorted
    /// ascending by `weekStart`.
    public static func bucket(
        _ points: [DailyPoint],
        weeksBack: Int,
        asOf: Date,
        calendar: Calendar
    ) -> (weeks: [WeeklyPoint], coverage: SeriesCoverage) {
        let windowStart = windowStart(weeksBack: weeksBack, asOf: asOf, calendar: calendar)

        // Per-day median first: readings on one day collapse to that day's
        // median before a week ever sees them, so three weigh-ins on Monday
        // can't out-vote the other six days.
        var readingsByDay: [Date: [Double]] = [:]
        for point in points {
            let day = calendar.startOfDay(for: point.day)
            guard day >= windowStart, day <= asOf else { continue }   // window filter is the boundary
            readingsByDay[day, default: []].append(point.value)
        }
        let dayMedians = readingsByDay.mapValues(median)

        var daysByWeek: [Date: [Date: Double]] = [:]   // weekStart -> day -> that day's median
        for (day, dayMedian) in dayMedians {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: day)!.start
            daysByWeek[weekStart, default: [:]][day] = dayMedian
        }
        let weeks = daysByWeek
            .map { weekStart, days in
                WeeklyPoint(weekStart: weekStart, value: median(Array(days.values)), dayCount: days.count)
            }
            .sorted { $0.weekStart < $1.weekStart }

        let daysInWindow = calendar.dateComponents([.day], from: windowStart, to: asOf).day! + 1
        let coverage = SeriesCoverage(
            daysWithData: dayMedians.count,
            daysInWindow: daysInWindow,
            weeksWithData: weeks.count,
            weeksInWindow: weeksBack
        )
        return (weeks, coverage)
    }

    /// The first calendar day of the window: `weeksBack` calendar weeks back
    /// from the start of the week containing `asOf`, inclusive of that week.
    /// Extracted out of `bucket` so this walk-back formula is composed in
    /// exactly one place — `TrajectoryService` (Task 5) needs the same
    /// window start to size its fetch interval and must call this rather
    /// than re-deriving it. `internal`: both callers live in this module.
    internal static func windowStart(weeksBack: Int, asOf: Date, calendar: Calendar) -> Date {
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: asOf)!.start
        return calendar.date(byAdding: .weekOfYear, value: -(weeksBack - 1), to: currentWeekStart)!
    }

    /// Middle value of a sorted copy of `xs`; even counts average the middle
    /// pair. Callers only ever pass a non-empty group of readings for a day
    /// (or a non-empty group of day medians for a week) that already exists.
    private static func median(_ xs: [Double]) -> Double {
        precondition(!xs.isEmpty)
        let sorted = xs.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
