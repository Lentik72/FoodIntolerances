import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct PressureTrustTests {
    private let t = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Service-side carry/time-gate (recordGenuinePressure)

    @Test func firstGenuineReadingHasNoTrustedPrevious() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1010, at: t)
        #expect(s.latestFetchedPressure == 1010)
        #expect(s.lastTrustedPressure == nil)           // no prior carry
    }
    @Test func secondGenuineWithinWindowExposesPreviousAndComputesDrop() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        s.recordGenuinePressure(1006, at: t.addingTimeInterval(600))   // 10 min later, 7 hPa fall
        #expect(s.latestFetchedPressure == 1006)
        #expect(s.lastTrustedPressure == 1013)
    }
    @Test func genuineAfterFallbackDoesNotFabricateDrop() {
        let s = EnvironmentalDataService()
        s.useFallbackPressureData()                      // 1013 legacy fallback — not genuine
        s.recordGenuinePressure(1006, at: t)             // first genuine → no prior carry
        #expect(s.latestFetchedPressure == 1006)
        #expect(s.lastTrustedPressure == nil)            // no fabricated 7 hPa drop
    }
    @Test func twoGenuineReadingsBeyondWindowEmitNoDrop() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        s.recordGenuinePressure(1006, at: t.addingTimeInterval(7200))  // 2 h later > 1 h window
        #expect(s.lastTrustedPressure == nil)            // stale prior → not comparable
    }
    @Test func thirdConsecutiveGenuineStillExposesAPrevious() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        s.recordGenuinePressure(1012, at: t.addingTimeInterval(300))
        s.recordGenuinePressure(1005, at: t.addingTimeInterval(600))   // carry regression guard
        #expect(s.lastTrustedPressure == 1012)           // NOT equal to latest → drop still possible
    }
    @Test func setFallbackRouteDoesNotContaminateCarry() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        s.setFallbackAtmosphericPressure()               // cached/fabricated route
        s.recordGenuinePressure(1006, at: t.addingTimeInterval(7200))  // > window → no drop off the stale genuine
        #expect(s.lastTrustedPressure == nil)
    }

    // Fix 5: every fallback/reset entry point clears latestFetchedPressure (spec's
    // "nil on failure or fallback") while preserving the genuine carry.
    @Test func useFallbackClearsLatestButPreservesCarryForNextGenuine() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        #expect(s.latestFetchedPressure == 1013)
        s.useFallbackPressureData()
        #expect(s.latestFetchedPressure == nil)          // stale genuine no longer exposed
        s.recordGenuinePressure(1006, at: t.addingTimeInterval(300))  // within window → carry preserved
        #expect(s.lastTrustedPressure == 1013)           // a real drop is still computable
    }
    @Test func setFallbackClearsLatestFetchedPressure() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        s.setFallbackAtmosphericPressure()
        #expect(s.latestFetchedPressure == nil)
    }
    @Test func resetPressureStateClearsLatestFetchedPressure() {
        let s = EnvironmentalDataService()
        s.recordGenuinePressure(1013, at: t)
        s.resetPressureState()
        #expect(s.latestFetchedPressure == nil)
    }

    // MARK: Emitter-side (protocol optionals → factory)

    private final class PressureStub: EnvironmentalDataProviding, @unchecked Sendable {
        var latestFetchedPressure: Double?
        var lastTrustedPressure: Double?
        var forecastHighC: Double?; var forecastLowC: Double?; var forecastHumidity: Double?
        func requestRefreshWithCooldown(bypassCooldown: Bool) async -> Bool { true }
        func fetchCompletedAirQualityRange(from: Date, through: Date) async -> AQIRangeResult { .days([:]) }
        func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult { .cancelled }
    }
    private func utc() -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private final class MemStore: WatermarkStore, @unchecked Sendable {
        private var s: [String: Date] = [:]
        func date(for key: String) -> Date? { s[key] }
        func set(_ date: Date, for key: String) { s[key] = date }
    }
    private func pressureEvents(_ db: AppDatabase) async throws -> [HealthEvent] {
        try await GRDBEventStore(database: db).recentEvents(limit: 1000)
            .filter { $0.subtype == "pressure" || $0.subtype == "pressureDrop" }
    }

    @Test func emitterEmitsNoPressureWhenLatestNil() async throws {
        let cal = utc(); let now = cal.date(from: DateComponents(year: 2025, month: 6, day: 11))!.addingTimeInterval(36_000)
        let db = try AppDatabase.inMemory()
        let stub = PressureStub()   // latestFetchedPressure nil (a failed/absent fetch)
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub, now: { now }, calendar: cal,
            store: MemStore(), statusStore: EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!))
        #expect(try await pressureEvents(db).isEmpty)
    }
    @Test func emitterEmitsNoDropWhenPreviousNil() async throws {
        let cal = utc(); let now = cal.date(from: DateComponents(year: 2025, month: 6, day: 11))!.addingTimeInterval(36_000)
        let db = try AppDatabase.inMemory()
        let stub = PressureStub(); stub.latestFetchedPressure = 1006; stub.lastTrustedPressure = nil
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub, now: { now }, calendar: cal,
            store: MemStore(), statusStore: EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!))
        let events = try await pressureEvents(db)
        #expect(events.contains { $0.subtype == "pressure" })
        #expect(!events.contains { $0.subtype == "pressureDrop" })   // no fabricated drop
    }
    @Test func emitterEmitsRealDropWhenPreviousPresent() async throws {
        let cal = utc(); let now = cal.date(from: DateComponents(year: 2025, month: 6, day: 11))!.addingTimeInterval(36_000)
        let db = try AppDatabase.inMemory()
        let stub = PressureStub(); stub.latestFetchedPressure = 1006; stub.lastTrustedPressure = 1013
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub, now: { now }, calendar: cal,
            store: MemStore(), statusStore: EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!))
        #expect(try await pressureEvents(db).contains { $0.subtype == "pressureDrop" && ($0.value ?? 0) >= 6 })
    }
}
