import Testing
import Foundation
@testable import HealthGraphCore

struct EnvironmentDaySummaryBuilderTests {
    private let tz = TimeZone(identifier: "UTC")!
    private func env(_ subtype: String, _ day: Int) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: Double(day) * 86_400 + 43_200),
                    timezoneID: "UTC", category: .environment, subtype: subtype,
                    value: subtype == "pressure" ? 1013 : nil, unit: subtype == "pressure" ? "hPa" : nil,
                    source: .weatherAPI)
    }

    @Test func groupsOneDayIntoOneSummaryInCanonicalOrder() {
        // REVERSE-canonical input → forces every adjacent pair (incl. temperature vs humidity) through the comparator
        let events = [env("mercuryRetrograde", 0), env("season", 0), env("moonPhase", 0),
                      env("humidity", 0), env("temperature", 0)]
        let summaries = EnvironmentDaySummaryBuilder.summaries(from: events, timeZone: tz)
        #expect(summaries.count == 1)
        #expect(summaries[0].events.map { $0.subtype } ==
                ["temperature", "humidity", "moonPhase", "mercuryRetrograde"])   // canonical; season retired → filtered
        #expect(summaries[0].dayStart == Date(timeIntervalSince1970: 0))
    }
    @Test func idIsDeterministicPerDayAndDistinctAcrossDays() {
        let a = EnvironmentDaySummaryBuilder.summaries(from: [env("moonPhase", 5)], timeZone: tz)[0]
        let a2 = EnvironmentDaySummaryBuilder.summaries(from: [env("moonPhase", 5)], timeZone: tz)[0]
        let b = EnvironmentDaySummaryBuilder.summaries(from: [env("moonPhase", 6)], timeZone: tz)[0]
        #expect(a.id == a2.id && a.id != b.id)
    }
    @Test func ignoresNonEnvironmentAndEmptyWhenNone() {
        let symptom = HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200), timezoneID: "UTC",
                                  category: .symptom, subtype: "migraine", value: 5, source: .manual)
        #expect(EnvironmentDaySummaryBuilder.summaries(from: [symptom], timeZone: tz).isEmpty)
        #expect(EnvironmentDaySummaryBuilder.summaries(from: [], timeZone: tz).isEmpty)
        let mixed = EnvironmentDaySummaryBuilder.summaries(from: [symptom, env("temperature", 0)], timeZone: tz)
        #expect(mixed.count == 1 && mixed[0].events.count == 1)
    }
    @Test func multipleDaysSortNewestFirst() {
        let s = EnvironmentDaySummaryBuilder.summaries(from: [env("moonPhase", 1), env("moonPhase", 3)], timeZone: tz)
        #expect(s.map { $0.dayStart } == [Date(timeIntervalSince1970: 3 * 86_400), Date(timeIntervalSince1970: 86_400)])
    }
    @Test func retiredSubtypeOnlyDayProducesNoSummary() {
        // Filter runs BEFORE grouping — a stored-season-only day yields no row, not an empty row.
        #expect(EnvironmentDaySummaryBuilder.summaries(from: [env("season", 0)], timeZone: tz).isEmpty)
    }
}
