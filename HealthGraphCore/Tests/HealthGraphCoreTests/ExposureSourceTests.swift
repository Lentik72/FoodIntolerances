import Testing
import Foundation
@testable import HealthGraphCore

struct EvidenceConfigTests {
    @Test func lagWindowsByExposureKind() {
        let c = EvidenceConfig.default
        #expect(c.lagWindow(for: .object(UUID(), .food)) == 0...24)
        #expect(c.lagWindow(for: .object(UUID(), .supplement)) == 0...48)
        #expect(c.lagWindow(for: .derived(.shortSleep)) == 0...18)
        #expect(c.lagWindow(for: .derived(.cyclePhase(.luteal))) == 0...24)
        #expect(c.lagWindow(for: .derived(.fullMoon)) == 0...24)
        #expect(c.lagWindow(for: .derived(.mercuryRetrograde)) == 0...24)
        #expect(c.lagWindow(for: .derived(.hotDay)) == 0...24)
        #expect(c.lagWindow(for: .derived(.coldDay)) == 0...24)
        #expect(c.lagWindow(for: .derived(.humidDay)) == 0...24)
        #expect(c.lagWindow(for: .derived(.swingDay)) == 0...24)
        #expect(c.lagWindow(for: .derived(.poorAirDay)) == 0...24)
    }
    @Test func defaultsAreSane() {
        let c = EvidenceConfig.default
        #expect(c.minExposures == 5)
        #expect(c.observationalCeiling == 0.75)
        #expect(c.candidateRatioTrigger > 1.0)
        #expect(c.candidateRatioProtective < 1.0)
        #expect(c.lowMoodThreshold == 1)
        #expect(c.goodMoodThreshold == 3)
        #expect(c.minWeatherReadings == 20)
        #expect(c.weatherHighPercentile == 0.75)
        #expect(c.weatherLowPercentile == 0.25)
    }
}

struct ObjectExposureSourceTests {
    @Test func extractsObjectLinkedFoodMedSupplementPeptide() {
        let oid = UUID()
        let events = [
            HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .food,
                        subtype: "dairy", objectID: oid, source: .manual),
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .food,
                        subtype: "rice", objectID: nil, source: .manual),     // no object → skipped
            HealthEvent(timestamp: Date(timeIntervalSince1970: 300), category: .symptom,
                        subtype: "bloating", source: .manual),                 // outcome → skipped
        ]
        let occ = ObjectExposureSource().occurrences(from: events)
        #expect(occ.count == 1)
        #expect(occ.first?.key == .object(oid, .food))
        #expect(occ.first?.sourceEventID == events[0].id)
    }
}

struct OutcomeSourceTests {
    @Test func extractsSymptomsAndLowMood() {
        let events = [
            HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .symptom,
                        subtype: "headache", value: 6, source: .manual),
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .mood,
                        subtype: "mood", value: 1, source: .manual),           // Rough (≤1) → low mood
            HealthEvent(timestamp: Date(timeIntervalSince1970: 300), category: .mood,
                        subtype: "mood", value: 2, source: .manual),           // Okay → neither
        ]
        let occ = OutcomeSource(config: .default).occurrences(from: events)
        #expect(occ.contains { $0.key == .symptom("headache") && $0.value == 6 })
        #expect(occ.contains { $0.key == .lowMood })
        #expect(occ.count == 2)
    }
    @Test func moodThresholdIsOne() {
        let low = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .mood,
                              subtype: "mood", value: 1, source: .manual)   // Rough → low mood
        let okay = HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .mood,
                               subtype: "mood", value: 2, source: .manual)  // Okay → NOT low
        let occ = OutcomeSource(config: .default).occurrences(from: [low, okay])
        #expect(occ.filter { $0.key == .lowMood }.count == 1)
    }
    @Test func goodMoodAtThreshold() {
        let good = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .mood,
                               subtype: "mood", value: 3, source: .manual)   // Good → good mood
        let okay = HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .mood,
                               subtype: "mood", value: 2, source: .manual)   // Okay → neither
        let occ = OutcomeSource(config: .default).occurrences(from: [good, okay])
        #expect(occ.filter { $0.key == .goodMood }.count == 1)
        #expect(occ.count == 1)
    }
}

struct ShortSleepExposureSourceTests {
    // Build one night of contiguous core-sleep segments totalling `hours`.
    func night(startEpoch: Double, hours: Double) -> [HealthEvent] {
        let start = Date(timeIntervalSince1970: startEpoch)
        let end = start.addingTimeInterval(hours * 3600)
        return [HealthEvent(timestamp: start, timezoneID: "UTC", endTimestamp: end,
                            category: .sleep, subtype: "asleepCore", source: .healthKit)]
    }
    @Test func flagsNightsUnderSixHours() {
        // Night A: 5h (short) starting 1700000000 (a 23:00-ish UTC bedtime); Night B: 8h (ok) a day later.
        let events = night(startEpoch: 1_700_000_000, hours: 5)
            + night(startEpoch: 1_700_000_000 + 86_400, hours: 8)
        let occ = ShortSleepExposureSource(config: .default).occurrences(from: events)
        #expect(occ.count == 1)
        #expect(occ.first?.key == .derived(.shortSleep))
        // Timestamped at wake time = start + 5h.
        #expect(occ.first?.timestamp == Date(timeIntervalSince1970: 1_700_000_000 + 5 * 3600))
    }
}

struct DerivedEventExposureSourceTests {
    @Test func highStressAboveThreshold() {
        let events = [
            HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .stress, value: 8, source: .manual),
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .stress, value: 4, source: .manual),
        ]
        let occ = HighStressExposureSource(config: .default).occurrences(from: events)
        #expect(occ.map(\.key) == [.derived(.highStress)])
    }
    @Test func pressureDropReadsPreEventizedSubtype() {
        let events = [
            HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .environment,
                        subtype: "pressureDrop", value: 9, unit: "hPa", source: .weatherAPI),
            HealthEvent(timestamp: Date(timeIntervalSince1970: 200), category: .environment,
                        subtype: "pressure", value: 1005, unit: "hPa", source: .weatherAPI),
        ]
        let occ = PressureDropExposureSource().occurrences(from: events)
        #expect(occ.map(\.key) == [.derived(.pressureDrop)])
    }
}

struct OutsideFactorExposureSourceTests {
    private func env(_ subtype: String, phase: String? = nil) -> HealthEvent {
        let meta = phase.map { try? JSONEncoder().encode(["phase": $0]) } ?? nil
        return HealthEvent(timestamp: Date(timeIntervalSince1970: 100), timezoneID: "UTC",
                           category: .environment, subtype: subtype, source: .weatherAPI, metadata: meta ?? nil)
    }
    @Test func fullMoonExtractsOnlyFullMoonPhase() {
        let occ = FullMoonExposureSource().occurrences(from: [
            env("moonPhase", phase: "Full Moon"), env("moonPhase", phase: "Waning Gibbous"),
            env("mercuryRetrograde")])
        #expect(occ.map(\.key) == [.derived(.fullMoon)])
    }
    @Test func mercuryExtractsRetrogradeEvents() {
        let occ = MercuryRetrogradeExposureSource().occurrences(from: [
            env("mercuryRetrograde"), env("moonPhase", phase: "Full Moon")])
        #expect(occ.map(\.key) == [.derived(.mercuryRetrograde)])
    }
}

struct CyclePhaseExposureSourceTests {
    // Period starts (category .cycle, subtype "periodStart") 28 days apart.
    func periodStart(dayOffset: Int, hourOffset: Double = 0) -> HealthEvent {
        let base = 1_700_000_000.0
        return HealthEvent(timestamp: Date(timeIntervalSince1970: base + Double(dayOffset) * 86_400 + hourOffset * 3_600),
                           timezoneID: "UTC", category: .cycle, subtype: "periodStart", source: .manual)
    }
    @Test func derivesMenstrualAndLutealDays() {
        // Two cycles: starts on day 0, 28, 56.
        let events = [periodStart(dayOffset: 0), periodStart(dayOffset: 28), periodStart(dayOffset: 56)]
        let src = CyclePhaseExposureSource(config: .default, timeZone: TimeZone(identifier: "UTC")!)
        let occ = src.occurrences(from: events)
        // Luteal = 5 days before each *next* start → days 23–27 and 51–55.
        let luteal = occ.filter { $0.key == .derived(.cyclePhase(.luteal)) }
        #expect(luteal.count == 10)
        // Menstrual = the start day itself (v1: 1 day per logged start that has a known day).
        let menstrual = occ.filter { $0.key == .derived(.cyclePhase(.menstrual)) }
        #expect(menstrual.count >= 1)
    }
    @Test func dedupesSameDayPeriodStarts() {
        // Two period-start events on the SAME calendar day (e.g. a manual log
        // plus a HealthKit re-sync) plus one distinct start 28 days later.
        let events = [
            periodStart(dayOffset: 0, hourOffset: 0),
            periodStart(dayOffset: 0, hourOffset: 1),
            periodStart(dayOffset: 28),
        ]
        let src = CyclePhaseExposureSource(config: .default, timeZone: TimeZone(identifier: "UTC")!)
        let occ = src.occurrences(from: events)
        // The same-day pair collapses to a single distinct day → 2 distinct
        // start days total, so menstrual count reflects distinct days, not raw events.
        let menstrual = occ.filter { $0.key == .derived(.cyclePhase(.menstrual)) }
        #expect(menstrual.count == 2)
        // Luteal = 5 days before the one non-first start.
        let luteal = occ.filter { $0.key == .derived(.cyclePhase(.luteal)) }
        #expect(luteal.count == 5)
    }
    @Test func singleDistinctStartYieldsNothing() {
        // Two period-start events on the same day and no other distinct start:
        // only one distinct day, can't bound a luteal window.
        let events = [periodStart(dayOffset: 0, hourOffset: 0), periodStart(dayOffset: 0, hourOffset: 1)]
        let src = CyclePhaseExposureSource(config: .default, timeZone: TimeZone(identifier: "UTC")!)
        let occ = src.occurrences(from: events)
        #expect(occ.isEmpty)
    }
}
