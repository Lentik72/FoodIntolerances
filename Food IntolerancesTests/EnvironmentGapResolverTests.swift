import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

struct EnvironmentGapResolverTests {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func day(_ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: 2025, month: m, day: d))!
    }
    private func summary(_ dayStart: Date, subtypes: [String]) -> EnvironmentDaySummary {
        let noon = utc.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)!
        let events = subtypes.map {
            HealthEvent(timestamp: noon, category: .environment, subtype: $0,
                        value: 1, unit: nil, source: .weatherAPI)
        }
        return EnvironmentDaySummary(dayStart: dayStart, timestamp: noon, events: events)
    }
    private func failure(_ start: Date, _ end: Date, reason: EnvironmentFailureReason = .rejected) -> EnvironmentFailure {
        EnvironmentFailure(at: start, reason: reason, scopeStart: start, scopeEnd: end, timezoneID: "UTC")
    }
    private func status(_ pairs: [(EnvironmentCapability, EnvironmentFailure)]) -> [EnvironmentCapability: EnvironmentCapabilityStatus] {
        var out: [EnvironmentCapability: EnvironmentCapabilityStatus] = [:]
        for (cap, f) in pairs { out[cap] = EnvironmentCapabilityStatus(lastSuccess: nil, liveFailure: f, lastFailure: f) }
        return out
    }
    /// Resolve with an explicit "now" so today-vs-completed-day routing is deterministic.
    private func resolve(_ s: EnvironmentDaySummary,
                         _ st: [EnvironmentCapability: EnvironmentCapabilityStatus],
                         on today: Date) -> EnvironmentGap? {
        EnvironmentGapResolver.gap(for: s, status: st, now: today, calendar: utc)
    }

    @Test func completedDayInsideObservedScopeMarksWeather() {
        let g = resolve(summary(day(6, 10), subtypes: ["moonPhase"]),
                        status([(.observedWeather, failure(day(6, 1), day(6, 10)))]), on: day(6, 11))
        #expect(g == .weather)
    }
    @Test func insideScopeButReadingPresentIsNil() {
        let g = resolve(summary(day(6, 10), subtypes: ["temperature", "moonPhase"]),
                        status([(.observedWeather, failure(day(6, 1), day(6, 10)))]), on: day(6, 11))
        #expect(g == nil)
    }
    @Test func outsideEveryScopeIsNil() {   // the 200-day-old moon-only row
        let g = resolve(summary(day(1, 1), subtypes: ["moonPhase"]),
                        status([(.observedWeather, failure(day(6, 1), day(6, 10)))]), on: day(6, 11))
        #expect(g == nil)
    }
    @Test func missingBothMarksWeatherOnly() {
        let g = resolve(summary(day(6, 10), subtypes: ["moonPhase"]),
                        status([(.observedWeather, failure(day(6, 1), day(6, 10))),
                                (.observedAirQuality, failure(day(6, 1), day(6, 10)))]), on: day(6, 11))
        #expect(g == .weather)
    }
    @Test func missingOnlyAQIMarksAirQuality() {
        let g = resolve(summary(day(6, 10), subtypes: ["temperature"]),
                        status([(.observedAirQuality, failure(day(6, 1), day(6, 10)))]), on: day(6, 11))
        #expect(g == .airQuality)
    }
    @Test func insufficientDataTodayMarksWeather() {
        let d = day(6, 10)
        let g = resolve(summary(d, subtypes: ["moonPhase"]),
                        status([(.forecastWeather, failure(d, d, reason: .insufficientData))]), on: d)
        #expect(g == .weather)
    }
    @Test func forecastFailureDoesNotMarkCompletedDayAfterRollover() {
        // A forecastWeather failure scoped July 23 must NOT mark the July 23 row on
        // July 24 — a completed day consults only observedWeather (which here has no failure).
        let jul23 = day(7, 23)
        let g = resolve(summary(jul23, subtypes: ["moonPhase"]),
                        status([(.forecastWeather, failure(jul23, jul23))]), on: day(7, 24))
        #expect(g == nil)
    }
    @Test func staleForecastFailureDoesNotMarkTodayRow() {
        // On July 24, a forecastWeather liveFailure still scoped July 23 (no July-24
        // attempt yet) must NOT mark today's July 24 row.
        let g = resolve(summary(day(7, 24), subtypes: ["moonPhase"]),
                        status([(.forecastWeather, failure(day(7, 23), day(7, 23)))]), on: day(7, 24))
        #expect(g == nil)
    }
    @Test func pressureOnlyFailureNeverMarks() {
        let d = day(6, 10)
        let g = resolve(summary(d, subtypes: ["moonPhase"]),
                        status([(.currentPressure, failure(d, d))]), on: d)
        #expect(g == nil)
    }
    @Test func todayNeverMarksAirQuality() {
        // Completed-day AQI doesn't exist for today by design.
        let d = day(6, 10)
        let g = resolve(summary(d, subtypes: ["moonPhase"]),
                        status([(.observedAirQuality, failure(d, d))]), on: d)
        #expect(g == nil)
    }
    @Test func containmentUsesFailureTimezoneNotDeviceCalendar() {
        // Resolver's calendar (UTC) DIVERGES from the failure's own timezone (LA) so this
        // pins that liveScopeContains uses failure.timezoneID: LA-midnight of 6/10 is 07:00Z,
        // which is OUTSIDE a UTC-day [6/10] scope but INSIDE the LA-day scope. Correct code
        // → .weather; a version that reused the resolver's UTC calendar → nil.
        var la = Calendar(identifier: .gregorian); la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let laDay = la.date(from: DateComponents(year: 2025, month: 6, day: 10))!   // 2025-06-10T07:00Z
        let noon = la.date(bySettingHour: 12, minute: 0, second: 0, of: laDay)!
        let s = EnvironmentDaySummary(dayStart: laDay, timestamp: noon,
            events: [HealthEvent(timestamp: noon, category: .environment, subtype: "moonPhase",
                                 value: 1, unit: nil, source: .weatherAPI)])
        let f = EnvironmentFailure(at: laDay, reason: .rejected, scopeStart: laDay, scopeEnd: laDay,
                                   timezoneID: "America/Los_Angeles")
        let status: [EnvironmentCapability: EnvironmentCapabilityStatus] =
            [.observedWeather: EnvironmentCapabilityStatus(lastSuccess: nil, liveFailure: f, lastFailure: f)]
        let nowUTC = utc.date(from: DateComponents(year: 2025, month: 6, day: 11))!   // 6/10 is a completed day in UTC
        #expect(EnvironmentGapResolver.gap(for: s, status: status, now: nowUTC, calendar: utc) == .weather)
    }
}
