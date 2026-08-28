import Foundation
import Testing
@testable import HealthGraphCore

struct WeeklyBucketingTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private var nyc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    /// Builds a Date from year/month/day components in the given calendar —
    /// never a raw epoch offset, so fixtures stay correct under DST.
    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func p(_ year: Int, _ month: Int, _ day: Int, _ value: Double) -> DailyPoint {
        p(year, month, day, value, in: utc)
    }

    private func p(_ year: Int, _ month: Int, _ day: Int, _ value: Double, in calendar: Calendar) -> DailyPoint {
        DailyPoint(day: date(year, month, day, in: calendar), value: value)
    }

    /// The window's day count, computed independently of `WeeklyBucketing` via
    /// calendar day-counting (never seconds) — so this can't share a bug with
    /// the implementation it is checking.
    private func expectedDays(weeksBack: Int, asOf: Date, calendar: Calendar) -> Int {
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: asOf)!.start
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -(weeksBack - 1), to: currentWeekStart)!
        return calendar.dateComponents([.day], from: windowStart, to: asOf).day! + 1
    }

    @Test func aReadingLandsInTheSameWeekWhicheverDayTheAnalysisRuns() {
        // Calendar anchoring, the actual stability property. Analyse the same
        // corpus on Tuesday and again on Wednesday: every reading keeps its week.
        let reading = [DailyPoint(day: date(2026, 8, 12, in: utc), value: 70)]
        let tue = WeeklyBucketing.bucket(reading, weeksBack: 13, asOf: date(2026, 8, 18, in: utc), calendar: utc)
        let wed = WeeklyBucketing.bucket(reading, weeksBack: 13, asOf: date(2026, 8, 19, in: utc), calendar: utc)
        #expect(tue.weeks.map(\.weekStart) == wed.weeks.map(\.weekStart))
        #expect(tue.weeks.map(\.value) == wed.weeks.map(\.value))
    }

    @Test func weeksRespectTheUsersFirstWeekday() {
        // Monday-start calendar: Sunday and Monday readings are DIFFERENT weeks.
        var cal = utc; cal.firstWeekday = 2
        let pts = [DailyPoint(day: date(2026, 8, 16, in: cal), value: 1),   // Sunday
                   DailyPoint(day: date(2026, 8, 17, in: cal), value: 2)]   // Monday
        let out = WeeklyBucketing.bucket(pts, weeksBack: 13, asOf: date(2026, 8, 18, in: cal), calendar: cal)
        #expect(out.weeks.count == 2)
    }

    @Test func aWeeksValueIsItsMedianNotItsMean() {
        // One bad reading — a different scale, a suitcase — must not move the week.
        let pts = [p(2026, 8, 10, 70), p(2026, 8, 11, 70.5), p(2026, 8, 12, 71), p(2026, 8, 13, 200)]
        let out = WeeklyBucketing.bucket(pts, weeksBack: 13, asOf: date(2026, 8, 15, in: utc), calendar: utc)
        #expect(out.weeks.last!.value == 70.75)   // median, not the mean of 102.9
    }

    @Test func emptyWeeksAreAbsentNotZero() {
        // A week with no readings is missing data. Emitting 0 makes a gap look
        // like a crash to the floor — the worst rendering error available here.
        let pts = [p(2026, 6, 1, 70), p(2026, 8, 10, 71)]
        let out = WeeklyBucketing.bucket(pts, weeksBack: 13, asOf: date(2026, 8, 15, in: utc), calendar: utc)
        #expect(out.weeks.count == 2)
        #expect(!out.weeks.contains { $0.value == 0 })
    }

    @Test func multipleReadingsOnOneDayCollapseToThatDaysMedianFirst() {
        // Three weigh-ins on Monday must not out-vote the other six days.
        let pts = [p(2026, 8, 10, 70), p(2026, 8, 10, 72), p(2026, 8, 10, 74), p(2026, 8, 11, 80)]
        let out = WeeklyBucketing.bucket(pts, weeksBack: 13, asOf: date(2026, 8, 15, in: utc), calendar: utc)
        #expect(out.coverage.daysWithData == 2)    // two days, not four readings
        #expect(out.weeks.last!.value == 76.0)     // median of [72, 80]
        #expect(out.weeks.last!.dayCount == 2)
    }

    @Test func coverageDenominatorEndsAtToday() {
        // Mid-week, a perfect logger must be at 100% — the denominator stops at
        // asOf, not at the end of the partial week.
        var cal = utc; cal.firstWeekday = 2
        let pts = (0..<3).map { p(2026, 8, 17 + $0, 70) }                    // Mon–Wed
        let out = WeeklyBucketing.bucket(pts, weeksBack: 1, asOf: date(2026, 8, 19, in: cal), calendar: cal)
        #expect(out.coverage.daysInWindow == 3)
        #expect(out.coverage.daysWithData == 3)
    }

    @Test func dstSpringForwardDoesNotBendTheWindow() {
        // The bug the previous plan's convention shipped: 86 400-second math
        // across 2026-03-08 in America/New_York yields a window one day wrong.
        // expectedDays is computed independently via calendar day-counting.
        let pts = [p(2026, 3, 6, 70, in: nyc), p(2026, 3, 9, 71, in: nyc)]
        let out = WeeklyBucketing.bucket(pts, weeksBack: 13, asOf: date(2026, 3, 12, in: nyc), calendar: nyc)
        #expect(out.weeks.count == 2)                                   // different weeks
        #expect(out.coverage.daysInWindow == expectedDays(weeksBack: 13, asOf: date(2026, 3, 12, in: nyc), calendar: nyc))
    }
}
