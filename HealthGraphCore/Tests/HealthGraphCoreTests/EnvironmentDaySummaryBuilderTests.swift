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

    private func weather(_ subtype: String, day: Int, provenance: TemporalProvenance,
                         created: TimeInterval = 0, id: UUID = UUID()) -> HealthEvent {
        HealthEvent(id: id,
                    timestamp: Date(timeIntervalSince1970: Double(day) * 86_400 + 43_200),
                    timezoneID: "UTC", category: .environment, subtype: subtype,
                    value: 20, source: .weatherAPI,
                    metadata: try! JSONEncoder().encode(["provenance": provenance.rawValue]),
                    createdAt: Date(timeIntervalSince1970: created))
    }

    // Observed-wins display precedence (presentation-only; per day + subtype).
    @Test func observedSuppressesSameDaySameSubtypeForecastOnly() {
        let events = [weather("temperature", day: 0, provenance: .forecast),
                      weather("temperature", day: 0, provenance: .observedCompletedDay),
                      weather("humidity", day: 0, provenance: .forecast),          // no observed sibling → stays
                      weather("temperature", day: 1, provenance: .forecast)]       // other day → stays
        let s = EnvironmentDaySummaryBuilder.summaries(from: events, timeZone: tz)
        #expect(s.count == 2)
        let day0 = s.first { $0.dayStart == Date(timeIntervalSince1970: 0) }!
        #expect(day0.events.filter { $0.subtype == "temperature" }.count == 1)
        #expect(day0.events.first { $0.subtype == "temperature" }?.temporalProvenance == .observedCompletedDay)
        #expect(day0.events.contains { $0.subtype == "humidity" })                 // mixed availability: one of each
        let day1 = s.first { $0.dayStart == Date(timeIntervalSince1970: 86_400) }!
        #expect(day1.events.first { $0.subtype == "temperature" }?.temporalProvenance == .forecast)
    }
    @Test func duplicateObservedResolvesDeterministicallyByCreatedAt() {
        let older = weather("temperature", day: 0, provenance: .observedCompletedDay, created: 100)
        let newer = weather("temperature", day: 0, provenance: .observedCompletedDay, created: 200)
        for input in [[older, newer], [newer, older]] {   // input order must not matter
            let s = EnvironmentDaySummaryBuilder.summaries(from: input, timeZone: tz)
            #expect(s[0].events.map(\.id) == [newer.id])
        }
    }
    /// Secondary tie-break: identical createdAt → the documented winner is the
    /// larger id.uuidString, regardless of input order.
    @Test func duplicateObservedWithEqualCreatedAtTieBreaksOnUUIDString() {
        let low = weather("temperature", day: 0, provenance: .observedCompletedDay, created: 100,
                          id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let high = weather("temperature", day: 0, provenance: .observedCompletedDay, created: 100,
                           id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        for input in [[low, high], [high, low]] {
            let s = EnvironmentDaySummaryBuilder.summaries(from: input, timeZone: tz)
            #expect(s[0].events.map(\.id) == [high.id])
        }
    }
    /// Only forecast + duplicate observed are dropped — .currentSnapshot and
    /// provenance-less events of the same day+subtype pass through untouched.
    @Test func precedenceDropsOnlyForecastAndDuplicateObserved() {
        let observed = weather("temperature", day: 0, provenance: .observedCompletedDay)
        let forecast = weather("temperature", day: 0, provenance: .forecast)
        let snapshot = weather("temperature", day: 0, provenance: .currentSnapshot)
        let unflagged = HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200),
                                    timezoneID: "UTC", category: .environment, subtype: "temperature",
                                    value: 20, source: .weatherAPI)   // no provenance metadata at all
        let s = EnvironmentDaySummaryBuilder.summaries(from: [observed, forecast, snapshot, unflagged], timeZone: tz)
        let ids = Set(s[0].events.map(\.id))
        #expect(ids == Set([observed.id, snapshot.id, unflagged.id]))   // forecast gone; others preserved
    }
    @Test func forecastOnlyDayAndNonWeatherSubtypesPassThrough() {
        let events = [weather("temperature", day: 0, provenance: .forecast),
                      weather("humidity", day: 0, provenance: .forecast),
                      env("moonPhase", 0), env("pressure", 0)]
        let s = EnvironmentDaySummaryBuilder.summaries(from: events, timeZone: tz)
        #expect(s[0].events.count == 4)   // nothing dropped without an observed sibling
    }
}
