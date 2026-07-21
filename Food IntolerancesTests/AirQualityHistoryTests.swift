import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

/// Retrospective-AQI primitives: a DST-correct completed-local-day window, a
/// distinct-hourly-timestamp daily PM2.5 mean, and a single ranged history
/// fetch that groups hourly slots into local days.
struct AirQualityHistoryTests {

    // MARK: - dailyMeanPM25

    @Test func dailyMeanPM25AveragesInWindowSlotsAndExcludesOutside() {
        let dayStart = Date(timeIntervalSince1970: 1_000_000)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let t = dayStart.timeIntervalSince1970
        // 20 distinct in-window hourly slots averaging 10; an out-of-window slot
        // with a mean-changing value must not move the result.
        var slots: [(dt: TimeInterval, pm25: Double)] = (0..<20).map { (t + Double($0) * 3600, 10) }
        slots.append((t - 3600, 999))            // just before dayStart → excluded
        #expect(EnvironmentalDataService.dailyMeanPM25(slots: slots, dayStart: dayStart, dayEnd: dayEnd, minHours: 20) == 10)
    }

    @Test func dailyMeanPM25HalfOpenExcludesSlotExactlyAtDayEnd() {
        let dayStart = Date(timeIntervalSince1970: 1_000_000)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let t = dayStart.timeIntervalSince1970
        var slots: [(dt: TimeInterval, pm25: Double)] = (0..<20).map { (t + Double($0) * 3600, 10) }
        // A slot exactly at dayEnd, with a mean-changing value, must be excluded
        // (half-open range) — if it counted, minHours would be satisfied by 21
        // slots and the mean would shift away from 10.
        slots.append((dayEnd.timeIntervalSince1970, 999))
        #expect(EnvironmentalDataService.dailyMeanPM25(slots: slots, dayStart: dayStart, dayEnd: dayEnd, minHours: 20) == 10)
    }

    @Test func dailyMeanPM25BoundaryTwentyDistinctHoursReturnsValue() {
        let dayStart = Date(timeIntervalSince1970: 1_000_000)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let t = dayStart.timeIntervalSince1970
        let slots: [(dt: TimeInterval, pm25: Double)] = (0..<20).map { (t + Double($0) * 3600, 10) }
        #expect(EnvironmentalDataService.dailyMeanPM25(slots: slots, dayStart: dayStart, dayEnd: dayEnd, minHours: 20) == 10)
    }

    @Test func dailyMeanPM25BoundaryNineteenDistinctHoursReturnsNil() {
        let dayStart = Date(timeIntervalSince1970: 1_000_000)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let t = dayStart.timeIntervalSince1970
        let slots: [(dt: TimeInterval, pm25: Double)] = (0..<19).map { (t + Double($0) * 3600, 10) }
        #expect(EnvironmentalDataService.dailyMeanPM25(slots: slots, dayStart: dayStart, dayEnd: dayEnd, minHours: 20) == nil)
    }

    /// 20 in-window slots, but two of them share a `dt` — only 19 DISTINCT hourly
    /// timestamps. A raw-count/raw-mean implementation would see `count == 20`,
    /// pass the `minHours` guard, and average all 20 (skewing the mean toward the
    /// duplicated value). Pins distinct-timestamp counting/de-duplication.
    @Test func dailyMeanPM25DuplicateTimestampsCollapseAndDontSatisfyThreshold() {
        let dayStart = Date(timeIntervalSince1970: 1_000_000)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let t = dayStart.timeIntervalSince1970
        var slots: [(dt: TimeInterval, pm25: Double)] = (0..<18).map { (t + Double($0) * 3600, 10) }
        // Two slots sharing the same `dt` (hour 18) with a mean-skewing value —
        // 20 total slots, but only 19 DISTINCT hourly timestamps (18 + 1).
        slots.append((t + 18 * 3600, 10))
        slots.append((t + 18 * 3600, 1000))
        #expect(slots.count == 20)
        #expect(EnvironmentalDataService.dailyMeanPM25(slots: slots, dayStart: dayStart, dayEnd: dayEnd, minHours: 20) == nil)
    }

    // MARK: - completedDayWindow (DST-correct local-day window)

    private var losAngelesCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    @Test func completedDayWindowIsTwentyThreeHoursOnSpringForward() {
        let calendar = losAngelesCalendar
        let day = calendar.date(from: DateComponents(year: 2025, month: 3, day: 9))!
        let window = EnvironmentalDataService.completedDayWindow(for: day, calendar: calendar)
        #expect(window.end.timeIntervalSince(window.start) == 23 * 3600)
    }

    @Test func completedDayWindowIsTwentyFiveHoursOnFallBack() {
        let calendar = losAngelesCalendar
        let day = calendar.date(from: DateComponents(year: 2025, month: 11, day: 2))!
        let window = EnvironmentalDataService.completedDayWindow(for: day, calendar: calendar)
        #expect(window.end.timeIntervalSince(window.start) == 25 * 3600)
    }

    @Test func completedDayWindowRollsOverMonthBoundary() {
        let calendar = losAngelesCalendar
        let day = calendar.date(from: DateComponents(year: 2025, month: 1, day: 31))!
        let window = EnvironmentalDataService.completedDayWindow(for: day, calendar: calendar)
        let expectedEnd = calendar.date(from: DateComponents(year: 2025, month: 2, day: 1))!
        #expect(window.end == expectedEnd)
    }

    @Test func completedDayWindowRollsOverYearBoundary() {
        let calendar = losAngelesCalendar
        let day = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31))!
        let window = EnvironmentalDataService.completedDayWindow(for: day, calendar: calendar)
        let expectedEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        #expect(window.end == expectedEnd)
    }

    // MARK: - fetchCompletedAirQualityRange

    private struct CountingStubTransport: HTTPTransport {
        let payload: Data
        let makeError: Bool
        let callCount: Counter

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var count = 0
            func increment() { lock.lock(); count += 1; lock.unlock() }
        }

        func data(from url: URL) async throws -> (Data, URLResponse) {
            callCount.increment()
            struct StubError: Error {}
            if makeError { throw StubError() }
            let response = URLResponse(url: url, mimeType: "application/json",
                                        expectedContentLength: payload.count, textEncodingName: "utf-8")
            return (payload, response)
        }
    }

    private struct StubLocation: LocationProviding {
        let coordinate: CLLocationCoordinate2D?
    }

    private func ensureTestAPIKeyConfigured() {
        setenv("OPENWEATHER_API_KEY", "test-key", 1)
    }

    /// UTC calendar so day boundaries are simple 86_400s multiples for the test's
    /// own bookkeeping (the production `calendar` seam still drives the fetch).
    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Builds `/air_pollution/history`-shaped JSON with 24 hourly slots per day
    /// for each day in `dayStarts`, except that `sparseDay` (if given) gets only
    /// `sparseHours` slots.
    private func historyJSON(dayStarts: [TimeInterval], sparseDay: TimeInterval? = nil, sparseHours: Int = 10) -> Data {
        var entries: [String] = []
        for dayStart in dayStarts {
            let hours = (dayStart == sparseDay) ? sparseHours : 24
            for h in 0..<hours {
                let dt = dayStart + Double(h) * 3600
                entries.append(#"{"dt": \#(dt), "components": {"pm2_5": 12.0}}"#)
            }
        }
        return Data("{\"list\":[\(entries.joined(separator: ","))]}".utf8)
    }

    @Test func fetchCompletedAirQualityRangeMakesExactlyOneRequestAndReturnsValueForEveryDay() async {
        ensureTestAPIKeyConfigured()
        let calendar = utcCalendar
        let day0 = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!
        let day1 = calendar.date(from: DateComponents(year: 2025, month: 6, day: 2))!
        let day2 = calendar.date(from: DateComponents(year: 2025, month: 6, day: 3))!
        let payload = historyJSON(dayStarts: [day0, day1, day2].map(\.timeIntervalSince1970))
        let counter = CountingStubTransport.Counter()
        let transport = CountingStubTransport(payload: payload, makeError: false, callCount: counter)
        let location = StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0))
        let service = EnvironmentalDataService(transport: transport, calendar: calendar, location: location)

        let result = await service.fetchCompletedAirQualityRange(from: day0, through: day2)

        #expect(counter.count == 1)
        guard case .days(let days) = result else {
            Issue.record("expected .days, got \(result)")
            return
        }
        #expect(days.count == 3)
        for day in [day0, day1, day2] {
            let key = calendar.startOfDay(for: day)
            guard case .value(let aqi) = days[key] else {
                Issue.record("expected .value for \(day), got \(String(describing: days[key]))")
                continue
            }
            #expect(aqi > 0)
        }
    }

    @Test func fetchCompletedAirQualityRangeMarksSparseDayAbsentButKeepsOthersValued() async {
        ensureTestAPIKeyConfigured()
        let calendar = utcCalendar
        let day0 = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!
        let day1 = calendar.date(from: DateComponents(year: 2025, month: 6, day: 2))!
        let day2 = calendar.date(from: DateComponents(year: 2025, month: 6, day: 3))!
        let payload = historyJSON(
            dayStarts: [day0, day1, day2].map(\.timeIntervalSince1970),
            sparseDay: day1.timeIntervalSince1970,
            sparseHours: 19
        )
        let counter = CountingStubTransport.Counter()
        let transport = CountingStubTransport(payload: payload, makeError: false, callCount: counter)
        let location = StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0))
        let service = EnvironmentalDataService(transport: transport, calendar: calendar, location: location)

        let result = await service.fetchCompletedAirQualityRange(from: day0, through: day2)

        #expect(counter.count == 1)
        guard case .days(let days) = result else {
            Issue.record("expected .days, got \(result)")
            return
        }
        #expect(days[calendar.startOfDay(for: day0)] != .absent)
        #expect(days[calendar.startOfDay(for: day1)] == .absent)
        #expect(days[calendar.startOfDay(for: day2)] != .absent)
    }

    @Test func fetchCompletedAirQualityRangeTransportFailureReturnsFetchError() async {
        ensureTestAPIKeyConfigured()
        let calendar = utcCalendar
        let day0 = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!
        let counter = CountingStubTransport.Counter()
        let transport = CountingStubTransport(payload: Data(), makeError: true, callCount: counter)
        let location = StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0))
        let service = EnvironmentalDataService(transport: transport, calendar: calendar, location: location)

        let result = await service.fetchCompletedAirQualityRange(from: day0, through: day0)

        #expect(result == .fetchError)
        #expect(counter.count == 1)
    }

    /// Malformed/garbage JSON (decode throws) must return `.fetchError` for the
    /// WHOLE window, never be silently interpreted as per-day absence.
    @Test func fetchCompletedAirQualityRangeMalformedJSONReturnsFetchError() async {
        ensureTestAPIKeyConfigured()
        let calendar = utcCalendar
        let day0 = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!
        let counter = CountingStubTransport.Counter()
        let garbage = Data("not valid json at all { [ }".utf8)
        let transport = CountingStubTransport(payload: garbage, makeError: false, callCount: counter)
        let location = StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0))
        let service = EnvironmentalDataService(transport: transport, calendar: calendar, location: location)

        let result = await service.fetchCompletedAirQualityRange(from: day0, through: day0)

        #expect(result == .fetchError)
        #expect(counter.count == 1)
    }

    @Test func fetchCompletedAirQualityRangeWithNoLocationReturnsFetchErrorWithoutTouchingTransport() async {
        ensureTestAPIKeyConfigured()
        let calendar = utcCalendar
        let day0 = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!
        let counter = CountingStubTransport.Counter()
        let transport = CountingStubTransport(payload: Data(), makeError: false, callCount: counter)
        let location = StubLocation(coordinate: nil)
        let service = EnvironmentalDataService(transport: transport, calendar: calendar, location: location)

        let result = await service.fetchCompletedAirQualityRange(from: day0, through: day0)

        #expect(result == .fetchError)
        #expect(counter.count == 0)
    }
}
