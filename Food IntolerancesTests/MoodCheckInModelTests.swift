import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct MoodCheckInModelTests {
    // Fixed at a clearly-non-default offset (UTC+13) — not UTC — so a future regression to
    // `Calendar.current` fails on any CI runner regardless of its local timezone.
    private var fixedOffsetCal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 13 * 3600)!; return c
    }
    // A fixed "today" at 12:00 in the fixed-offset zone — the +1h/+2h offsets below stay within the same day.
    private var noon: Date { fixedOffsetCal.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 12))! }
    private func model(_ db: AppDatabase, at t: Date) -> MoodCheckInModel {
        MoodCheckInModel(database: db,
                         defaults: UserDefaults(suiteName: "mood-\(UUID().uuidString)")!,
                         calendar: fixedOffsetCal, now: { t })
    }

    @Test func logThenLoadShowsTodaysMood() async throws {
        let db = try AppDatabase.inMemory()
        let m = model(db, at: noon)
        await m.log(.good)
        #expect(m.todaysMood?.level == .good)
        let m2 = model(db, at: noon)         // a fresh model on the same DB/day loads it back
        await m2.load()
        #expect(m2.todaysMood?.level == .good)
    }

    @Test func latestOfMultipleLogsTodayWins() async throws {
        let db = try AppDatabase.inMemory()
        await model(db, at: noon).log(.rough)
        await model(db, at: noon.addingTimeInterval(3600)).log(.good)   // later, same day
        let fresh = model(db, at: noon.addingTimeInterval(7200))
        await fresh.load()
        #expect(fresh.todaysMood?.level == .good)   // latest by timestamp, not first-logged
    }

    @Test func previousDaysMoodDoesNotCountAsToday() async throws {
        let db = try AppDatabase.inMemory()
        await model(db, at: noon).log(.good)
        let tomorrow = model(db, at: noon.addingTimeInterval(24 * 3600))
        await tomorrow.load()
        #expect(tomorrow.todaysMood == nil)
    }

    @Test func undoRemovesTodaysMood() async throws {
        let db = try AppDatabase.inMemory()
        let m = model(db, at: noon)
        await m.log(.rough)
        await m.undo()
        #expect(m.todaysMood == nil)
    }

    @Test func dismissForTodayPersistsPerDay() throws {
        let db = try AppDatabase.inMemory()
        let defaults = UserDefaults(suiteName: "mood-\(UUID().uuidString)")!
        func mk(_ t: Date) -> MoodCheckInModel {
            MoodCheckInModel(database: db, defaults: defaults, calendar: fixedOffsetCal, now: { t })
        }
        let m = mk(noon)
        #expect(m.dismissedToday == false)
        m.dismissForToday()
        #expect(m.dismissedToday == true)
        #expect(mk(noon).dismissedToday == true)                                // same day sees it
        #expect(mk(noon.addingTimeInterval(24 * 3600)).dismissedToday == false)  // next day cleared
    }

    @Test func outOfRangeStoredMoodTodayStillShowsAsLogged() async throws {
        let db = try AppDatabase.inMemory()
        // A pre-refinement value (old "Good" = 4) written directly, bypassing logMood.
        try await GRDBEventStore(database: db).save(
            HealthEvent(timestamp: noon, category: .mood, subtype: "mood", value: 4, source: .manual))
        let m = model(db, at: noon.addingTimeInterval(3600))
        await m.load()
        #expect(m.todaysMood?.level == .good)   // clamped to nearest valid level, not silently dropped
    }
}
