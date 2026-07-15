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
    }
    @Test func defaultsAreSane() {
        let c = EvidenceConfig.default
        #expect(c.minExposures == 5)
        #expect(c.observationalCeiling == 0.75)
        #expect(c.candidateRatioTrigger > 1.0)
        #expect(c.candidateRatioProtective < 1.0)
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
                        subtype: "mood", value: 2, source: .manual),           // ≤3 → low mood
            HealthEvent(timestamp: Date(timeIntervalSince1970: 300), category: .mood,
                        subtype: "mood", value: 8, source: .manual),           // high → skipped
        ]
        let occ = OutcomeSource(config: .default).occurrences(from: events)
        #expect(occ.contains { $0.key == .symptom("headache") && $0.value == 6 })
        #expect(occ.contains { $0.key == .lowMood })
        #expect(occ.count == 2)
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

struct CyclePhaseExposureSourceTests {
    // Period starts (category .cycle, subtype "periodStart") 28 days apart.
    func periodStart(dayOffset: Int) -> HealthEvent {
        let base = 1_700_000_000.0
        return HealthEvent(timestamp: Date(timeIntervalSince1970: base + Double(dayOffset) * 86_400),
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
}
