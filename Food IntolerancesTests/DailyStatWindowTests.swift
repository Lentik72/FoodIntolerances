import Testing
import Foundation
@testable import Food_Intolerances

/// Pins the whole-calendar-day rule for daily-statistics queries.
///
/// The defect these tests exist for: `recomputeRecentDailyStats` passed a
/// time-of-day (`now − 2 days`) into `ingestDailyStats`, whose HealthKit
/// sample predicate started at that instant while its buckets started at
/// local midnight. The oldest bucket therefore summed only the samples after
/// that time of day and overwrote the correct full-day row in place — on the
/// owner's phone, Apple Health's 3,504–3,718 steps/day for Aug 9–22 were
/// stored as 18–656.
///
/// Both statics are pure with an injectable calendar, so every case here runs
/// against a fixed America/New_York calendar — never `.current`.
struct DailyStatWindowTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    /// year/month/day/hour/minute in the test's calendar, so assertions never
    /// depend on seconds arithmetic across a DST transition.
    private func parts(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private func parts(_ year: Int, _ month: Int, _ day: Int,
                       _ hour: Int = 0, _ minute: Int = 0) -> DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    }

    // MARK: - dailyStatRange

    @Test func dailyStatRangeFloorsStartToMidnight() {
        let range = HealthKitIngestor.dailyStatRange(
            from: date(2026, 8, 28, 23, 10),
            to: date(2026, 8, 30, 12, 0),
            calendar: calendar)
        #expect(parts(range.start) == parts(2026, 8, 28))
        #expect(range.end == date(2026, 8, 30, 12, 0))   // the end passed, untouched
    }

    @Test func dailyStatRangeIsIdentityAtMidnight() {
        let start = date(2026, 8, 28)
        let end = date(2026, 8, 30, 12, 0)
        let range = HealthKitIngestor.dailyStatRange(from: start, to: end, calendar: calendar)
        #expect(range.start == start)
        #expect(range.end == end)
    }

    // MARK: - recentDailyStatWindow

    @Test func recentWindowStartsAtMidnightTwoDaysBack() {
        // The exact input that produced the 18-step days: a late-evening
        // observer fire. The window must reach back to midnight, not 23:10.
        let now = date(2026, 8, 30, 23, 10)
        let window = HealthKitIngestor.recentDailyStatWindow(now: now, calendar: calendar)
        #expect(parts(window.start) == parts(2026, 8, 28))
        #expect(window.end == now)
    }

    @Test func recentWindowSurvivesDSTFallBack() {
        // The Monday after fall-back: the two days back span a 25-hour day,
        // so only calendar arithmetic lands on midnight.
        let now = date(2025, 11, 3, 8, 0)
        let window = HealthKitIngestor.recentDailyStatWindow(now: now, calendar: calendar)
        #expect(parts(window.start) == parts(2025, 11, 1))
        #expect(window.end == now)
    }
}
