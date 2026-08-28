import Foundation
import Testing
@testable import HealthGraphCore

struct TrajectorySeriesTests {
    /// 2025-06-15 00:00:00 UTC — exact UTC midnight, fixed for offset math.
    static let t0 = Date(timeIntervalSince1970: 1_749_945_600)

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func weightIsReadFromBodyMetricEvents() {
        let e = HealthEvent(timestamp: Self.t0.addingTimeInterval(8 * 3600), category: .bodyMetric,
                            subtype: "weight", value: 70.5, unit: "kg", source: .healthKit)
        let points = TrajectorySeries.weight.dailyPoints(from: [e], calendar: utc)
        #expect(points.count == 1)
        #expect(points[0].value == 70.5)
    }

    @Test func sleepUsesNightSessionsAndIsAttributedToTheWakingDay() {
        // A night starting 23:00 Monday and ending 07:00 Tuesday is TUESDAY's
        // sleep — attributing it to Monday shifts every night by one.
        var asleep = HealthEvent(timestamp: Self.t0.addingTimeInterval(23 * 3600), category: .sleep,
                                 subtype: "asleepCore", value: 8 * 3600, unit: "s", source: .healthKit)
        let wake = Self.t0.addingTimeInterval(31 * 3600)
        asleep.endTimestamp = wake
        let points = TrajectorySeries.sleepDuration.dailyPoints(from: [asleep], calendar: utc)
        #expect(points[0].day == utc.startOfDay(for: wake))
        #expect(abs(points[0].value - 8.0) < 0.01)          // hours, not minutes
    }

    @Test func aSeriesReadsOnlyItsOwnSubtype() {
        // restingHeartRate and heartRate share a unit; reading both would average
        // a resting rate with exercise peaks.
        let events = [HealthEvent(timestamp: Self.t0, category: .vitals, subtype: "heartRate",
                                  value: 150, unit: "bpm", source: .healthKit),
                      HealthEvent(timestamp: Self.t0, category: .vitals, subtype: "restingHeartRate",
                                  value: 58, unit: "bpm", source: .healthKit)]
        let points = TrajectorySeries.restingHeartRate.dailyPoints(from: events, calendar: utc)
        #expect(points.count == 1)
        #expect(points[0].value == 58)
    }

    @Test func deletedEventsAreExcluded() {
        var deleted = HealthEvent(timestamp: Self.t0.addingTimeInterval(8 * 3600), category: .bodyMetric,
                                  subtype: "weight", value: 70.5, unit: "kg", source: .healthKit)
        deleted.deletedAt = Self.t0.addingTimeInterval(9 * 3600)
        #expect(TrajectorySeries.weight.dailyPoints(from: [deleted], calendar: utc).isEmpty)
    }

    @Test func theCatalogIsExactlyTheSixSeriesWeSupport() {
        // Protects the copy sweep in Task 8 from passing over an empty
        // collection, and pins blood pressure OUT.
        #expect(TrajectorySeries.allCases.count == 6)
        #expect(!TrajectorySeries.allCases.contains { $0.displayName.isEmpty || $0.unit.isEmpty })
        #expect(!TrajectorySeries.allCases.contains { "\($0)".localizedCaseInsensitiveContains("bloodPressure") })
    }
}
