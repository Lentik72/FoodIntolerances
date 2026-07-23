import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

/// Orchestration tests for `EnvironmentalEventEmitter.emitIfNeeded` — the
/// contiguous-watermark AQI backfill, the retry throttle, DST-safe stepping,
/// provenance stamping, and today's forecast-only (no observed AQI) emit.
///
/// Everything is deterministic: an injected clock + calendar (timezone), an
/// in-memory `WatermarkStore`, an in-memory `AppDatabase`, and a stub
/// `EnvironmentalDataProviding` returning a scripted `AQIRangeResult`. The SAME
/// timezone is injected into the emitter's calendar AND the scripted range's
/// day-keys AND (implicitly) each emitted reading, so `startOfDay` lookups line up.
@MainActor
struct EnvironmentalEmitterTests {

    // MARK: - Test doubles

    /// A canned `EnvironmentalDataProviding`: fixed forecast/pressure values and a
    /// scripted `AQIRangeResult`, counting range calls and recording the last span.
    private final class StubProvider: EnvironmentalDataProviding, @unchecked Sendable {
        var currentPressure: Double = 1015
        var previousPressure: Double = 1015
        var forecastHighC: Double? = 24
        var forecastLowC: Double? = 6
        var forecastHumidity: Double? = 55

        var rangeResult: AQIRangeResult = .days([:])
        private(set) var rangeCallCount = 0
        private(set) var lastFrom: Date?
        private(set) var lastThrough: Date?
        private(set) var refreshCount = 0

        func requestRefreshWithCooldown() async -> Bool {
            refreshCount += 1
            return true
        }

        func fetchCompletedAirQualityRange(from: Date, through: Date) async -> AQIRangeResult {
            rangeCallCount += 1
            lastFrom = from
            lastThrough = through
            return rangeResult
        }

        /// Scripted per-day weather; days not listed return `weatherDefault`.
        /// Default `.fetchError` keeps every pre-existing AQI/orchestration test
        /// meaningful unchanged: the weather pass aborts, emits nothing.
        var weatherByDay: [Date: WeatherDayResult] = [:]
        var weatherDefault: WeatherDayResult = .fetchError(.badResponse)
        private(set) var weatherCallCount = 0
        private(set) var weatherDaysRequested: [Date] = []

        func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult {
            weatherCallCount += 1
            weatherDaysRequested.append(day)
            return weatherByDay[day] ?? weatherDefault
        }
    }

    /// In-memory `WatermarkStore` (no `UserDefaults`).
    private final class MemoryWatermarkStore: WatermarkStore, @unchecked Sendable {
        private var storage: [String: Date] = [:]
        func date(for key: String) -> Date? { storage[key] }
        func set(_ date: Date, for key: String) { storage[key] = date }
    }

    // MARK: - Helpers

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private var losAngeles: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    /// Local midnight (== `startOfDay`) of the given 2025 date in `cal`.
    private func day(_ cal: Calendar, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: 2025, month: month, day: day))!
    }

    private func allEvents(_ db: AppDatabase) async throws -> [HealthEvent] {
        try await GRDBEventStore(database: db).recentEvents(limit: 1000)
    }

    private func airQualityDays(_ db: AppDatabase, _ cal: Calendar) async throws -> Set<Date> {
        let events = try await allEvents(db)
        return Set(events.filter { $0.subtype == "airQuality" }.map { cal.startOfDay(for: $0.timestamp) })
    }

    private let dayKey = EnvironmentalEventEmitter.lastAQIDayKey

    // MARK: - Whole-range fetch error

    /// A whole-range `.fetchError` advances no watermark and emits no AQI; a later
    /// foreground (past the retry throttle) re-requests and, on success, emits.
    @Test func wholeRangeFetchErrorDoesNotAdvanceOrEmitThenRetriesLater() async throws {
        let cal = utc
        let now0 = day(cal, 6, 11).addingTimeInterval(10 * 3600)   // yesterday = 06-10
        let db = try AppDatabase.inMemory()
        let store = MemoryWatermarkStore()
        let provider = StubProvider()
        provider.rangeResult = .fetchError(.badResponse)

        var clock = now0
        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { clock }, calendar: cal, store: store)

        #expect(store.date(for: dayKey) == nil)          // unchanged
        #expect(try await airQualityDays(db, cal).isEmpty)
        #expect(provider.rangeCallCount == 1)

        // Past the throttle, with a real value for yesterday → retries + emits.
        clock = now0.addingTimeInterval(EnvironmentalEventEmitter.minAQIRetryInterval + 60)
        provider.rangeResult = .days([cal.startOfDay(for: day(cal, 6, 10)): .value(80)])
        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { clock }, calendar: cal, store: store)

        #expect(provider.rangeCallCount == 2)
        #expect(try await airQualityDays(db, cal).contains(cal.startOfDay(for: day(cal, 6, 10))))
    }

    // MARK: - Contiguous watermark stops at a gap (#1-intent test)

    /// yesterday = 06-10, gracePartialDays = 2. `[06-08 .value, 06-09 .absent
    /// (recent), 06-10 .value]` → BOTH 06-08 and 06-10 emit, but the watermark
    /// holds at 06-08 (it does NOT jump past the 06-09 gap). A break-out-of-switch
    /// or skip-the-gap bug lands the watermark at 06-10.
    @Test func contiguousWatermarkStopsAtRecentGap() async throws {
        let cal = utc
        let now = day(cal, 6, 11).addingTimeInterval(10 * 3600)    // yesterday = 06-10
        let db = try AppDatabase.inMemory()
        let store = MemoryWatermarkStore()
        store.set(day(cal, 6, 7), for: dayKey)                      // start = 06-08
        let provider = StubProvider()
        provider.rangeResult = .days([
            cal.startOfDay(for: day(cal, 6, 8)): .value(60),
            cal.startOfDay(for: day(cal, 6, 9)): .absent,
            cal.startOfDay(for: day(cal, 6, 10)): .value(70),
        ])

        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { now }, calendar: cal, store: store)

        #expect(try await airQualityDays(db, cal) ==
                Set([cal.startOfDay(for: day(cal, 6, 8)), cal.startOfDay(for: day(cal, 6, 10))]))
        #expect(store.date(for: dayKey) == cal.startOfDay(for: day(cal, 6, 8)))
    }

    // MARK: - Grace boundary (`>` vs `>=`)

    /// yesterday = 06-10, graceCutoff = 06-08. An absent 06-07 (old) → advance; an
    /// absent 06-08 (== cutoff) → treated OLD → advance; an absent 06-09 (recent) →
    /// hold. Watermark lands exactly on 06-08, and 06-10's value still emits past
    /// the recent gap.
    @Test func graceBoundaryTreatsCutoffDayAsOld() async throws {
        let cal = utc
        let now = day(cal, 6, 11).addingTimeInterval(10 * 3600)    // yesterday = 06-10
        let db = try AppDatabase.inMemory()
        let store = MemoryWatermarkStore()
        store.set(day(cal, 6, 6), for: dayKey)                      // start = 06-07
        let provider = StubProvider()
        provider.rangeResult = .days([
            cal.startOfDay(for: day(cal, 6, 7)): .absent,   // old → advance
            cal.startOfDay(for: day(cal, 6, 8)): .absent,   // == cutoff → old → advance
            cal.startOfDay(for: day(cal, 6, 9)): .absent,   // recent → hold
            cal.startOfDay(for: day(cal, 6, 10)): .value(90),
        ])

        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { now }, calendar: cal, store: store)

        #expect(store.date(for: dayKey) == cal.startOfDay(for: day(cal, 6, 8)))
        #expect(try await airQualityDays(db, cal) == Set([cal.startOfDay(for: day(cal, 6, 10))]))
    }

    // MARK: - Today has no observed AQI

    /// A foreground emits today's forecast temperature/humidity (`.forecast`) +
    /// pressure (`.currentSnapshot`) but NO `airQuality` event dated today.
    @Test func todayEmitsForecastWeatherAndPressureButNoObservedAQI() async throws {
        let cal = utc
        let now = day(cal, 6, 11).addingTimeInterval(10 * 3600)
        let db = try AppDatabase.inMemory()
        let store = MemoryWatermarkStore()
        store.set(day(cal, 6, 10), for: dayKey)                     // start = 06-11 > yesterday → no backfill
        let provider = StubProvider()

        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { now }, calendar: cal, store: store)

        #expect(provider.rangeCallCount == 0)                       // backfill returned before any fetch
        let events = try await allEvents(db)
        let temp = events.first { $0.subtype == "temperature" }
        #expect(temp != nil)
        #expect(temp?.temporalProvenance == .forecast)
        #expect(events.contains { $0.subtype == "humidity" && $0.temporalProvenance == .forecast })
        #expect(events.contains { $0.subtype == "pressure" && $0.temporalProvenance == .currentSnapshot })
        #expect(!events.contains { $0.subtype == "airQuality" })
        #expect(cal.startOfDay(for: temp!.timestamp) == cal.startOfDay(for: now))
    }

    // MARK: - Backfill cap + single request

    /// An unset (nil) watermark → exactly ONE range request spanning
    /// `[yesterday−29, yesterday]` (30 days); emitted events dated to each day's
    /// local noon.
    @Test func nilWatermarkBackfillsThirtyDayCapInOneRequest() async throws {
        let cal = utc
        let now = day(cal, 6, 30).addingTimeInterval(10 * 3600)     // yesterday = 06-29
        let yesterday = cal.startOfDay(for: day(cal, 6, 29))
        let capFloor = cal.date(byAdding: .day, value: -29, to: yesterday)!   // 05-31
        let db = try AppDatabase.inMemory()
        let store = MemoryWatermarkStore()
        let provider = StubProvider()
        provider.rangeResult = .days([capFloor: .value(40), yesterday: .value(50)])

        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { now }, calendar: cal, store: store)

        #expect(provider.rangeCallCount == 1)
        #expect(provider.lastFrom == capFloor)
        #expect(provider.lastThrough == yesterday)

        let aqi = try await allEvents(db).filter { $0.subtype == "airQuality" }
        let capNoon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: capFloor)!
        let ydayNoon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday)!
        #expect(aqi.contains { $0.timestamp == capNoon })
        #expect(aqi.contains { $0.timestamp == ydayNoon })
    }

    // MARK: - DST-safe stepping

    /// America/Los_Angeles, clock = 2025-11-03 → yesterday = 11-02 (the 25-hour
    /// fall-back day). A 3-day backfill emits AQI for exactly {10-31, 11-01, 11-02}
    /// — three distinct local days, no repeat/skip. A naive `+86_400` step lands at
    /// 23:00 and repeats/skips a day across the transition.
    @Test func backfillStepsDistinctLocalDaysAcrossDSTFallBack() async throws {
        let cal = losAngeles
        let now = day(cal, 11, 3).addingTimeInterval(10 * 3600)     // yesterday = 11-02
        let db = try AppDatabase.inMemory()
        let store = MemoryWatermarkStore()
        store.set(day(cal, 10, 30), for: dayKey)                    // start = 10-31
        let provider = StubProvider()
        provider.rangeResult = .days([
            cal.startOfDay(for: day(cal, 10, 31)): .value(41),
            cal.startOfDay(for: day(cal, 11, 1)): .value(42),
            cal.startOfDay(for: day(cal, 11, 2)): .value(43),
        ])

        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { now }, calendar: cal, store: store)

        #expect(provider.rangeCallCount == 1)
        #expect(provider.lastFrom == cal.startOfDay(for: day(cal, 10, 31)))
        #expect(provider.lastThrough == cal.startOfDay(for: day(cal, 11, 2)))

        let days = try await airQualityDays(db, cal)
        #expect(days == Set([
            cal.startOfDay(for: day(cal, 10, 31)),
            cal.startOfDay(for: day(cal, 11, 1)),
            cal.startOfDay(for: day(cal, 11, 2)),
        ]))
        #expect(days.count == 3)
    }

    // MARK: - Retry throttle

    /// A second foreground within `minAQIRetryInterval` makes NO second range call
    /// even though the watermark is still behind (a recent-gap tail); after the
    /// interval it re-requests.
    @Test func retryThrottleBlocksSecondFetchWithinIntervalThenAllowsAfter() async throws {
        let cal = utc
        let now0 = day(cal, 6, 11).addingTimeInterval(10 * 3600)    // yesterday = 06-10
        let db = try AppDatabase.inMemory()
        let store = MemoryWatermarkStore()
        store.set(day(cal, 6, 7), for: dayKey)                      // start = 06-08
        let provider = StubProvider()
        provider.rangeResult = .days([
            cal.startOfDay(for: day(cal, 6, 8)): .value(60),
            cal.startOfDay(for: day(cal, 6, 9)): .absent,           // recent gap → watermark holds at 06-08
            cal.startOfDay(for: day(cal, 6, 10)): .value(70),
        ])

        var clock = now0
        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { clock }, calendar: cal, store: store)
        #expect(provider.rangeCallCount == 1)

        clock = now0.addingTimeInterval(EnvironmentalEventEmitter.minAQIRetryInterval - 60)
        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { clock }, calendar: cal, store: store)
        #expect(provider.rangeCallCount == 1)                       // throttled

        clock = now0.addingTimeInterval(EnvironmentalEventEmitter.minAQIRetryInterval + 60)
        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { clock }, calendar: cal, store: store)
        #expect(provider.rangeCallCount == 2)                       // past interval → re-requests
    }

    // MARK: - Provenance-correct emits

    @Test func emitsObservedAQIProvenanceAndForecastWeatherProvenance() async throws {
        let cal = utc
        let now = day(cal, 6, 11).addingTimeInterval(10 * 3600)
        let db = try AppDatabase.inMemory()
        let store = MemoryWatermarkStore()
        store.set(day(cal, 6, 9), for: dayKey)                      // start = 06-10 = yesterday
        let provider = StubProvider()
        provider.rangeResult = .days([cal.startOfDay(for: day(cal, 6, 10)): .value(88)])

        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { now }, calendar: cal, store: store)

        let events = try await allEvents(db)
        #expect(events.first { $0.subtype == "airQuality" }?.temporalProvenance == .observedCompletedDay)
        #expect(events.first { $0.subtype == "temperature" }?.temporalProvenance == .forecast)
        #expect(events.first { $0.subtype == "humidity" }?.temporalProvenance == .forecast)
    }

    // MARK: - Idempotent re-emit

    /// Two foregrounds (past the throttle) that both cover 06-10 (a value beyond a
    /// recent gap, re-emitted each time) → the day yields exactly ONE row (dedup
    /// updates in place).
    @Test func idempotentReEmitOverSameDayProducesOneRow() async throws {
        let cal = utc
        let now0 = day(cal, 6, 11).addingTimeInterval(10 * 3600)
        let db = try AppDatabase.inMemory()
        let store = MemoryWatermarkStore()
        store.set(day(cal, 6, 7), for: dayKey)                      // start = 06-08
        let provider = StubProvider()
        provider.rangeResult = .days([
            cal.startOfDay(for: day(cal, 6, 8)): .value(60),
            cal.startOfDay(for: day(cal, 6, 9)): .absent,           // recent gap → 06-10 re-emitted each foreground
            cal.startOfDay(for: day(cal, 6, 10)): .value(70),
        ])

        var clock = now0
        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { clock }, calendar: cal, store: store)
        clock = now0.addingTimeInterval(EnvironmentalEventEmitter.minAQIRetryInterval + 60)
        await EnvironmentalEventEmitter.emitIfNeeded(
            database: db, service: provider, now: { clock }, calendar: cal, store: store)

        let aqi = try await allEvents(db).filter { $0.subtype == "airQuality" }
        #expect(aqi.count == 2)                                     // 06-08 + 06-10, not duplicated
        let day10 = aqi.filter { cal.startOfDay(for: $0.timestamp) == cal.startOfDay(for: day(cal, 6, 10)) }
        #expect(day10.count == 1)
    }

    // MARK: - Observed-weather backfill

    private let weatherDayKey = EnvironmentalEventEmitter.lastWeatherDayKey

    private func observedWeatherDays(_ db: AppDatabase, _ cal: Calendar) async throws -> Set<Date> {
        let events = try await allEvents(db)
        return Set(events.filter { $0.subtype == "temperature" && $0.temporalProvenance == .observedCompletedDay }
            .map { cal.startOfDay(for: $0.timestamp) })
    }

    /// Value days emit observed temp (+humidity when present) and advance the
    /// weather watermark; a nil afternoon humidity emits NO humidity event.
    @Test func weatherBackfillEmitsObservedDaysAndMissingHumidityEmitsNoEvent() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)   // 2025-06-10 09:00
        let d8 = day(cal, 6, 8), d9 = day(cal, 6, 9)
        store.set(day(cal, 6, 7), for: weatherDayKey)            // watermark → start = 06-08
        stub.weatherByDay = [d8: .value(highC: 24, lowC: 12, humidityPct: 64),
                             d9: .value(highC: 30, lowC: 18, humidityPct: nil)]
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        let events = try await allEvents(db)
        let observed = try await observedWeatherDays(db, cal)
        #expect(observed == [d8, d9])
        let d8Humidity = events.first { $0.subtype == "humidity" && cal.startOfDay(for: $0.timestamp) == d8 }
        #expect(d8Humidity?.temporalProvenance == .observedCompletedDay)
        #expect(d8Humidity?.value == 64)
        #expect(!events.contains { $0.subtype == "humidity" && $0.temporalProvenance == .observedCompletedDay
            && cal.startOfDay(for: $0.timestamp) == d9 })        // nil afternoon → no observed humidity event
        #expect(store.date(for: weatherDayKey) == d9)
        #expect(stub.weatherCallCount == 2)
        // Today's forecast events are still forecast — precedence is display-side, not ingest-side.
        #expect(events.contains { $0.subtype == "temperature" && $0.temporalProvenance == .forecast })
    }

    /// A per-day fetchError aborts the WHOLE pass: nothing ingested, watermark held.
    @Test func weatherFetchErrorAbortsPassWithoutIngestOrAdvance() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)
        store.set(day(cal, 6, 7), for: weatherDayKey)
        stub.weatherByDay = [day(cal, 6, 8): .value(highC: 24, lowC: 12, humidityPct: 64)]
        // 06-09 falls to weatherDefault = .fetchError → abort; even 06-08's fetched value must not ingest.
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        #expect(try await observedWeatherDays(db, cal).isEmpty)
        #expect(store.date(for: weatherDayKey) == day(cal, 6, 7))   // held
    }

    /// A per-day fetchError records ONE observedWeather failure scoped to the whole
    /// intended range (start…yesterday), even though the pass aborts on day 2.
    @Test func weatherFetchErrorRecordsScopeOverWholeIntendedRange() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let status = EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!)
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)   // yesterday = 06-09
        store.set(day(cal, 6, 6), for: weatherDayKey)            // start = 06-07
        stub.weatherByDay = [day(cal, 6, 7): .value(highC: 20, lowC: 10, humidityPct: 50)]
        stub.weatherDefault = .fetchError(.rejected)             // 06-08 fails → abort
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
            now: { now }, calendar: cal, store: store, statusStore: status)
        let f = status.statuses[.observedWeather]?.liveFailure
        #expect(f?.reason == .rejected)
        #expect(f?.scopeStart == day(cal, 6, 7))
        #expect(f?.scopeEnd == day(cal, 6, 9))                   // yesterday, not day-of-abort
        // The emitter records `calendar.timeZone.identifier`; Foundation normalizes
        // the `utc` helper's TimeZone(identifier: "UTC") to "GMT" (verified: they
        // share the +0 zone), so the recorded identifier is "GMT".
        #expect(f?.timezoneID == "GMT")
    }

    /// A cancelled weather day records NOTHING: no status, watermark held.
    @Test func weatherCancelledRecordsNothing() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let status = EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!)
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)
        store.set(day(cal, 6, 7), for: weatherDayKey)
        stub.weatherDefault = .cancelled
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
            now: { now }, calendar: cal, store: store, statusStore: status)
        #expect(status.statuses[.observedWeather] == nil)        // nothing recorded
        #expect(store.date(for: weatherDayKey) == day(cal, 6, 7))
    }

    /// A completed weather pass records observedWeather success.
    @Test func weatherSuccessfulPassRecordsSuccess() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let status = EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!)
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)
        store.set(day(cal, 6, 8), for: weatherDayKey)            // start = 06-09 = yesterday
        stub.weatherByDay = [day(cal, 6, 9): .value(highC: 22, lowC: 11, humidityPct: 55)]
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
            now: { now }, calendar: cal, store: store, statusStore: status)
        #expect(status.statuses[.observedWeather]?.lastSuccess != nil)
        #expect(status.statuses[.observedWeather]?.liveFailure == nil)
    }

    /// Recent absent day (grace) holds the contiguous watermark; old absent advances it.
    @Test func weatherWatermarkStopsAtRecentGapButAdvancesOverOldGap() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)   // yesterday = 06-09; graceCutoff = 06-07
        store.set(day(cal, 6, 5), for: weatherDayKey)            // start = 06-06
        stub.weatherByDay = [day(cal, 6, 6): .absent,             // old gap → resolved-absent, advances
                             day(cal, 6, 7): .value(highC: 20, lowC: 10, humidityPct: 50),
                             day(cal, 6, 8): .absent,             // RECENT gap → holds contiguity
                             day(cal, 6, 9): .value(highC: 22, lowC: 11, humidityPct: 55)]
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        let observed = try await observedWeatherDays(db, cal)
        #expect(observed == [day(cal, 6, 7), day(cal, 6, 9)])     // beyond-gap value still emits (idempotent)
        #expect(store.date(for: weatherDayKey) == day(cal, 6, 7)) // stopped before the recent gap
    }

    /// Unset watermark → the weather loop requests EXACTLY the capped window:
    /// 30 distinct calendar days, yesterday−29 through yesterday, stepped
    /// correctly across the LA fall-back DST transition (its own loop — the AQI
    /// cap test cannot protect it).
    @Test func weatherNilWatermarkRequestsExactlyThirtyDaysAcrossDSTFallBack() async throws {
        let cal = losAngeles
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        stub.weatherDefault = .absent                             // every day resolves; loop must run the full window
        let now = day(cal, 11, 9).addingTimeInterval(9 * 3600)    // 2025-11-09 09:00 PST; fall-back was 11-02
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        #expect(stub.weatherCallCount == 30)
        let requested = stub.weatherDaysRequested.map { cal.startOfDay(for: $0) }
        #expect(Set(requested).count == 30)                       // 30 DISTINCT local days (no DST double-step)
        #expect(requested.first == day(cal, 10, 10))              // yesterday − 29
        #expect(requested.last == day(cal, 11, 8))                // yesterday
        var expected = day(cal, 10, 10)
        for d in requested {                                      // contiguous local-day stepping
            #expect(d == expected)
            expected = cal.date(byAdding: .day, value: 1, to: expected)!
        }
    }

    /// Weather self-throttling: a second foreground within the hour makes no
    /// weather calls; after the hour it retries.
    @Test func weatherRetryThrottleBlocksSecondFetchWithinIntervalThenAllowsAfter() async throws {
        let cal = utc
        let db = try AppDatabase.inMemory()
        let stub = StubProvider()
        let store = MemoryWatermarkStore()
        var now = day(cal, 6, 10).addingTimeInterval(9 * 3600)
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        let firstCalls = stub.weatherCallCount
        #expect(firstCalls >= 1)
        now = now.addingTimeInterval(600)                        // +10 min → throttled
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        #expect(stub.weatherCallCount == firstCalls)
        now = now.addingTimeInterval(3600)                       // past the hour → retries
        await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                     now: { now }, calendar: cal, store: store)
        #expect(stub.weatherCallCount > firstCalls)
    }

    /// Throttle INDEPENDENCE: a recent AQI attempt watermark must not block the
    /// weather pass, and vice versa — each backfill has its own attempt key.
    @Test func eachBackfillRunsWhenOnlyTheOtherIsThrottled() async throws {
        let cal = utc
        let now = day(cal, 6, 10).addingTimeInterval(9 * 3600)
        // AQI throttled → weather still fetches.
        do {
            let db = try AppDatabase.inMemory()
            let stub = StubProvider()
            let store = MemoryWatermarkStore()
            store.set(now.addingTimeInterval(-60), for: EnvironmentalEventEmitter.lastAQIAttemptKey)
            await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                         now: { now }, calendar: cal, store: store)
            #expect(stub.rangeCallCount == 0)       // AQI pass throttled
            #expect(stub.weatherCallCount >= 1)     // weather pass unaffected
        }
        // Weather throttled → AQI still fetches.
        do {
            let db = try AppDatabase.inMemory()
            let stub = StubProvider()
            let store = MemoryWatermarkStore()
            store.set(now.addingTimeInterval(-60), for: EnvironmentalEventEmitter.lastWeatherAttemptKey)
            await EnvironmentalEventEmitter.emitIfNeeded(database: db, service: stub,
                                                         now: { now }, calendar: cal, store: store)
            #expect(stub.rangeCallCount == 1)       // AQI pass unaffected
            #expect(stub.weatherCallCount == 0)     // weather pass throttled
        }
    }
}
