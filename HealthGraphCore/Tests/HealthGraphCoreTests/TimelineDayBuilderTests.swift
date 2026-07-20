import Foundation
import Testing
@testable import HealthGraphCore

struct TimelineDayBuilderTests {
    let tz = TimeZone(identifier: "America/New_York")!
    // 22:00 EDT and 06:00 EDT the next day — straddle local midnight
    let lateNight = Date(timeIntervalSince1970: 1_783_216_800)  // 2026-07-04 22:00 EDT
    let nextMorning = Date(timeIntervalSince1970: 1_783_245_600) // 2026-07-05 06:00 EDT

    @Test func groupsByLocalDayNewestFirst() {
        let older = HealthEvent(timestamp: lateNight, category: .food, subtype: "dinner",
                                source: .manual, createdAt: lateNight)
        let newer = HealthEvent(timestamp: nextMorning, category: .symptom, subtype: "headache",
                                value: 5, unit: "severity", source: .manual, createdAt: nextMorning)
        let days = TimelineDayBuilder.days(from: [newer, older], timeZone: tz)
        #expect(days.count == 2)
        #expect(days[0].events.map(\.id) == [newer.id])   // newest day first
        #expect(days[1].events.map(\.id) == [older.id])
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        #expect(days[0].dayStart == cal.startOfDay(for: nextMorning))
    }

    @Test func severityPointsAreChronologicalSymptomValuesOnly() {
        let s1 = HealthEvent(timestamp: nextMorning, category: .symptom, subtype: "headache",
                             value: 5, unit: "severity", source: .manual, createdAt: nextMorning)
        let s2 = HealthEvent(timestamp: nextMorning.addingTimeInterval(3600), category: .symptom,
                             subtype: "nausea", value: 3, unit: "severity", source: .manual,
                             createdAt: nextMorning)
        let unrated = HealthEvent(timestamp: nextMorning.addingTimeInterval(7200), category: .symptom,
                                  subtype: "fatigue", source: .manual, createdAt: nextMorning)
        let food = HealthEvent(timestamp: nextMorning.addingTimeInterval(300), category: .food,
                               subtype: "eggs", value: 2, source: .manual, createdAt: nextMorning)
        let days = TimelineDayBuilder.days(from: [unrated, s2, food, s1], timeZone: tz)
        #expect(days.count == 1)
        #expect(days[0].severityPoints.map(\.value) == [5, 3])         // chronological, symptoms with value only
        #expect(days[0].severityPoints[0].time < days[0].severityPoints[1].time)
    }

    @Test func displayTitlesCoverKnownSubtypesAndFallBack() {
        func event(_ cat: EventCategory, _ sub: String?) -> HealthEvent {
            HealthEvent(timestamp: lateNight, category: cat, subtype: sub,
                        source: .healthKit, createdAt: lateNight)
        }
        #expect(EventDisplay.title(for: event(.sleep, "asleepCore")) == "Core sleep")
        #expect(EventDisplay.title(for: event(.sleep, "asleepREM")) == "REM sleep")
        #expect(EventDisplay.title(for: event(.exercise, "strengthTraining")) == "Strength training")
        #expect(EventDisplay.title(for: event(.exercise, "hiit")) == "HIIT")
        #expect(EventDisplay.title(for: event(.vitals, "restingHeartRate")) == "Resting heart rate")
        #expect(EventDisplay.title(for: event(.environment, "mercuryRetrograde")) == "Mercury retrograde")
        #expect(EventDisplay.title(for: event(.food, "oat milk latte")) == "Oat milk latte")
        #expect(EventDisplay.title(for: event(.note, nil)) == "Note")
    }

    @Test func valueLinesFormatByUnit() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        func event(_ cat: EventCategory, _ sub: String?, _ value: Double?, _ unit: String?,
                   end: Date? = nil, metadata: [String: String]? = nil) -> HealthEvent {
            HealthEvent(timestamp: base, endTimestamp: end, category: cat, subtype: sub,
                        value: value, unit: unit, source: .healthKit,
                        metadata: metadata.map { try! JSONEncoder().encode($0) }, createdAt: base)
        }
        #expect(EventDisplay.valueLine(for: event(.sleep, "asleepCore", 452, "min",
                                                  end: base.addingTimeInterval(452 * 60))) == "7h 32m")
        #expect(EventDisplay.valueLine(for: event(.symptom, "headache", 5, "severity")) == "severity 5")
        #expect(EventDisplay.valueLine(for: event(.exercise, "steps", 8214, "count")) == "8,214 steps")
        #expect(EventDisplay.valueLine(for: event(.bodyMetric, "weight", 81.4, "kg")) == "81.4 kg")
        #expect(EventDisplay.valueLine(for: event(.vitals, "restingHeartRate", 52, "bpm")) == "52 bpm")
        #expect(EventDisplay.valueLine(for: event(.environment, "moonPhase", nil, nil,
                                                  metadata: ["phase": "Waxing gibbous"])) == "Waxing gibbous")
        #expect(EventDisplay.valueLine(for: event(.cycle, "menstrualFlow", 2, "level")) == "medium")
        #expect(EventDisplay.valueLine(for: event(.note, nil, nil, nil)) == nil)
        #expect(EventDisplay.durationString(minutes: 45) == "45m")
        #expect(EventDisplay.durationString(minutes: 420) == "7h")
    }

    @Test func noteAndDoseDisplay() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        func ev(_ cat: EventCategory, _ sub: String?, _ value: Double?, _ unit: String?) -> HealthEvent {
            HealthEvent(timestamp: base, category: cat, subtype: sub, value: value, unit: unit,
                        source: .manual, createdAt: base)
        }
        // A note shows its text as the title (not the category name).
        #expect(EventDisplay.title(for: ev(.note, "Felt wired after coffee", nil, nil)) == "Felt wired after coffee")
        // A multi-word symptom subtype title-cases consistently with SymptomCatalog.displayName.
        #expect(EventDisplay.title(for: ev(.symptom, "sinusPain", nil, nil)) == "Sinus Pain")
        // A dose shows amount + unit.
        #expect(EventDisplay.valueLine(for: ev(.peptide, "Semaglutide", 0.25, "mg")) == "0.25 mg")
        #expect(EventDisplay.valueLine(for: ev(.supplement, "Vitamin D3", 2000, "iu")) == "2000 iu")
        // A nutrition daily-stat (category .food, mg) still rounds to an integer (not the dose bucket).
        #expect(EventDisplay.valueLine(for: ev(.food, "dietarySodium", 675.1, "mg")) == "675 mg")
    }

    @Test func dropsSubMinuteDurationMicroSegments() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let micro = HealthEvent(timestamp: base, endTimestamp: base.addingTimeInterval(20),
                                category: .exercise, subtype: "walking", value: 0, unit: "min",
                                source: .healthKit, createdAt: base)
        let real = HealthEvent(timestamp: base.addingTimeInterval(100), endTimestamp: base.addingTimeInterval(100 + 600),
                               category: .exercise, subtype: "running", value: 10, unit: "min",
                               source: .healthKit, createdAt: base)
        let days = TimelineDayBuilder.days(from: [real, micro], timeZone: TimeZone(identifier: "UTC")!)
        #expect(days.flatMap(\.events).map(\.subtype) == ["running"])   // micro dropped
    }
    @Test func keepsPointEventsEvenWithZeroValue() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let point = HealthEvent(timestamp: base, category: .symptom, subtype: "headache",
                                value: 0, unit: "severity", source: .manual, createdAt: base)
        let days = TimelineDayBuilder.days(from: [point], timeZone: TimeZone(identifier: "UTC")!)
        #expect(days.flatMap(\.events).count == 1)   // point event kept
    }

    @Test func keepsExactlySixtySecondDuration() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let sixty = HealthEvent(timestamp: base, endTimestamp: base.addingTimeInterval(60),
                                category: .exercise, subtype: "walking", value: 1, unit: "min",
                                source: .healthKit, createdAt: base)
        let days = TimelineDayBuilder.days(from: [sixty], timeZone: TimeZone(identifier: "UTC")!)
        #expect(days.flatMap(\.events).count == 1)
    }

    /// A cross-midnight night collapses to ONE session item on the WAKE-UP day.
    @Test func sleepCollapsesIntoWakeDaySession() {
        // 22:00 EDT core (60m) + 23:00 EDT rem (420m, ends 06:00 EDT July 5).
        let core = HealthEvent(timestamp: lateNight, endTimestamp: lateNight.addingTimeInterval(3600),
                               category: .sleep, subtype: "asleepCore", value: 60, unit: "min",
                               source: .healthKit, createdAt: lateNight)
        let rem = HealthEvent(timestamp: lateNight.addingTimeInterval(3600), endTimestamp: nextMorning,
                              category: .sleep, subtype: "asleepREM", value: 420, unit: "min",
                              source: .healthKit, createdAt: lateNight)
        let dinner = HealthEvent(timestamp: lateNight, category: .food, subtype: "dinner",
                                 source: .manual, createdAt: lateNight)
        let days = TimelineDayBuilder.days(from: [rem, core, dinner], timeZone: tz)
        #expect(days.count == 2)
        // Newest day (July 5) holds ONLY the session; no raw sleep rows anywhere.
        #expect(days[0].items.count == 1)
        guard case .sleepSession(let s) = days[0].items[0] else {
            Issue.record("expected a sleepSession item"); return
        }
        #expect(s.asleepMinutes == 480)
        #expect(s.end == nextMorning)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        #expect(days[0].dayStart == cal.startOfDay(for: nextMorning))
        // Older day (July 4) holds the dinner only.
        #expect(days[1].events.map(\.subtype) == ["dinner"])
        #expect(days.flatMap(\.events).allSatisfy { $0.category != .sleep })
    }

    /// Search mode keeps raw stage rows (a filtered subset must not sessionize).
    @Test func searchModeKeepsRawSleepRows() {
        let core = HealthEvent(timestamp: lateNight, endTimestamp: lateNight.addingTimeInterval(3600),
                               category: .sleep, subtype: "asleepCore", value: 60, unit: "min",
                               source: .healthKit, createdAt: lateNight)
        let rem = HealthEvent(timestamp: lateNight.addingTimeInterval(3600), endTimestamp: nextMorning,
                              category: .sleep, subtype: "asleepREM", value: 420, unit: "min",
                              source: .healthKit, createdAt: lateNight)
        let days = TimelineDayBuilder.days(from: [rem, core], timeZone: tz, sessionizeSleep: false)
        // Both group by START day (July 4), as raw rows.
        #expect(days.count == 1)
        #expect(days[0].events.count == 2)
        #expect(days[0].items.allSatisfy { if case .event = $0 { true } else { false } })
    }

    /// A session sorts within its day by wake time, between neighboring events.
    @Test func sessionRowInterleavesByWakeTime() {
        let sleep = HealthEvent(timestamp: nextMorning.addingTimeInterval(-7 * 3600),
                                endTimestamp: nextMorning,   // 23:00 -> 06:00
                                category: .sleep, subtype: "asleepCore", value: 420, unit: "min",
                                source: .healthKit, createdAt: nextMorning)
        let earlier = HealthEvent(timestamp: nextMorning.addingTimeInterval(-600),  // 05:50
                                  category: .symptom, subtype: "headache", value: 4, unit: "severity",
                                  source: .manual, createdAt: nextMorning)
        let later = HealthEvent(timestamp: nextMorning.addingTimeInterval(600),     // 06:10
                                category: .food, subtype: "coffee", source: .manual, createdAt: nextMorning)
        let days = TimelineDayBuilder.days(from: [later, earlier, sleep], timeZone: tz)
        #expect(days.count == 1)
        let kinds = days[0].items.map { item -> String in
            switch item {
            case .event(let e): e.subtype ?? ""
            case .sleepSession: "session"
            case .environmentSummary: "env"
            }
        }
        #expect(kinds == ["coffee", "session", "headache"])   // 06:10 > 06:00 > 05:50
    }

    /// Defensive: a point .sleep event (no endTimestamp) stays a raw row.
    @Test func pointSleepEventsPassThroughAsRawRows() {
        let point = HealthEvent(timestamp: nextMorning, category: .sleep, subtype: "item0",
                                source: .healthKit, createdAt: nextMorning)
        let days = TimelineDayBuilder.days(from: [point], timeZone: tz)
        #expect(days.count == 1)
        #expect(days[0].events.map(\.id) == [point.id])
    }

    /// Parity with the ≥60s row filter: an isolated sub-minute sleep fragment
    /// must not become a permanent "0m" session row.
    @Test func isolatedSubMinuteSleepFragmentProducesNoSessionRow() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let fragment = HealthEvent(timestamp: base, endTimestamp: base.addingTimeInterval(30),
                                   category: .sleep, subtype: "asleepCore", value: 0, unit: "min",
                                   source: .healthKit, createdAt: base)
        let days = TimelineDayBuilder.days(from: [fragment], timeZone: TimeZone(identifier: "UTC")!)
        #expect(days.isEmpty)
    }

    @Test func environmentEventsCollapseIntoOneSummaryInBrowse() {
        let tz = TimeZone(identifier: "UTC")!
        func env(_ s: String) -> HealthEvent { HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200),
            timezoneID: "UTC", category: .environment, subtype: s, source: .weatherAPI) }
        let symptom = HealthEvent(timestamp: Date(timeIntervalSince1970: 40_000), timezoneID: "UTC",
                                  category: .symptom, subtype: "migraine", value: 5, source: .manual)
        let days = TimelineDayBuilder.days(from: [env("temperature"), env("humidity"), env("moonPhase"), symptom],
                                           timeZone: tz)
        let envItems = days[0].items.filter { if case .environmentSummary = $0 { true } else { false } }
        #expect(envItems.count == 1)                                   // one collapsed row
        if case .environmentSummary(let s) = envItems[0] {             // and it actually carries the 3 env events
            #expect(s.events.count == 3)
        } else { Issue.record("expected an environmentSummary item") }
        #expect(days[0].events.map { $0.subtype } == ["migraine"])     // env excluded from raw .event rows
        // Sort: summary sortDate = its timestamp (43_200) > the earlier symptom (40_000); items are newest-first.
        // A bug returning dayStart/midnight (0) would mis-sort the summary to the bottom and this would fail.
        #expect({ if case .environmentSummary = days[0].items.first { true } else { false } }())
    }
    @Test func searchLeavesEnvironmentRaw() {
        let tz = TimeZone(identifier: "UTC")!
        func env(_ s: String) -> HealthEvent { HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200),
            timezoneID: "UTC", category: .environment, subtype: s, source: .weatherAPI) }
        let days = TimelineDayBuilder.days(from: [env("temperature"), env("humidity")], timeZone: tz,
                                           sessionizeSleep: false, groupEnvironment: false)
        #expect(days[0].items.allSatisfy { if case .event = $0 { true } else { false } })   // raw rows, no summary
        #expect(days[0].events.count == 2)
    }
}
