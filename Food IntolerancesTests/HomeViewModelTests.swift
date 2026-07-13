import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct HomeViewModelTests {
    @Test func sumsAsleepStagesAcrossMidnightAndSkipsInBed() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let tz = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let todayNoon = cal.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let lastNight = cal.startOfDay(for: Date()).addingTimeInterval(-2 * 3600) // 22:00 yesterday
        try await store.save([
            HealthEvent(timestamp: lastNight, endTimestamp: lastNight.addingTimeInterval(4 * 3600),
                        category: .sleep, subtype: "asleepCore", value: 240, unit: "min",
                        source: .healthKit, createdAt: lastNight),
            HealthEvent(timestamp: lastNight.addingTimeInterval(4 * 3600),
                        endTimestamp: lastNight.addingTimeInterval(6 * 3600),
                        category: .sleep, subtype: "asleepREM", value: 120, unit: "min",
                        source: .healthKit, createdAt: lastNight),
            HealthEvent(timestamp: lastNight, endTimestamp: lastNight.addingTimeInterval(8 * 3600),
                        category: .sleep, subtype: "inBed", value: 480, unit: "min",
                        source: .healthKit, createdAt: lastNight),
        ])
        let vm = HomeViewModel(store: store, timeZone: tz, now: { todayNoon })
        await vm.refresh()
        #expect(vm.sleepSummary == "6h")          // 240 + 120 min; inBed excluded
    }

    @Test func readsTodaysStepsDailyStat() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBEventStore(database: db)
        let tz = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let today = cal.startOfDay(for: Date())
        try await store.save(HealthEvent(timestamp: today, endTimestamp: today.addingTimeInterval(86_400),
                                         category: .exercise, subtype: "steps", value: 8214,
                                         unit: "count", source: .healthKit, createdAt: today))
        let vm = HomeViewModel(store: store, timeZone: tz, now: { today.addingTimeInterval(13 * 3600) })
        await vm.refresh()
        #expect(vm.stepsSummary == "8,214")
        #expect(vm.sleepSummary == nil)
    }
}
