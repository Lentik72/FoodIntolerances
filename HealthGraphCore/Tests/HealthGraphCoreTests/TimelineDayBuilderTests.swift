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
    }
}
