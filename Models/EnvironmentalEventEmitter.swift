import Foundation
import HealthGraphCore

/// The emitter's narrow view of the environmental service: today's forecast /
/// current-conditions readings, the ranged retrospective-AQI fetch, and the
/// per-day observed-weather fetch. Lets tests substitute a deterministic stub
/// for `EnvironmentalDataService`.
protocol EnvironmentalDataProviding {
    var latestFetchedPressure: Double? { get }   // this refresh's genuine reading; nil on failure/fallback
    var lastTrustedPressure: Double? { get }      // prior genuine reading, only if recent enough to compare
    var forecastHighC: Double? { get }
    var forecastLowC: Double? { get }
    var forecastHumidity: Double? { get }
    func requestRefreshWithCooldown(bypassCooldown: Bool) async -> Bool
    func fetchCompletedAirQualityRange(from: Date, through: Date) async -> AQIRangeResult
    func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult
}

extension EnvironmentalDataService: EnvironmentalDataProviding {}

/// Persists the per-signal watermarks — the last successfully-ingested completed
/// day and the last attempt time for each backfill (AQI and observed weather).
/// Injectable so day math and watermarks are deterministic in tests. Values are
/// epoch `Double`s; a missing key reads back as `nil` (NOT epoch 0).
protocol WatermarkStore {
    func date(for key: String) -> Date?
    func set(_ date: Date, for key: String)
}

/// Production `WatermarkStore`, backed by `UserDefaults` (epoch `Double`).
struct UserDefaultsWatermarkStore: WatermarkStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func date(for key: String) -> Date? {
        guard let epoch = defaults.object(forKey: key) as? Double else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }
    func set(_ date: Date, for key: String) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }
}

/// Emits daily environment exposure events on app foreground (spec §6.6).
///
/// No global daily lock: today's forecast weather + current pressure + the
/// deterministic date-facts (moon/mercury) emit every foreground (the
/// service's own cooldown throttles the actual network refresh; dedup keys make
/// the re-emit idempotent). Retrospective AQI (one ranged request) and observed
/// completed-day weather (one day_summary call per missed day) are backfilled
/// from independent contiguous per-day watermarks, each gated by its own retry
/// throttle.
enum EnvironmentalEventEmitter {
    /// Last completed local day whose observed AQI is ingested + watermarked.
    static let lastAQIDayKey = "hg.env.lastAQIDay"
    /// Last time the AQI range was attempted (retry-throttle watermark).
    static let lastAQIAttemptKey = "hg.env.lastAQIAttempt"

    /// Backfill window cap: at most this many completed days per foreground.
    static let maxBackfillDays = 30
    /// The last `gracePartialDays` completed days (yesterday + the day before)
    /// are "recent": a recent absent day is likely provider lag → hold the
    /// watermark and retry; the cutoff day itself is OLD.
    static let gracePartialDays = 2
    /// Minimum spacing between AQI range fetches. Independent of the pressure /
    /// forecast cooldown: while the tail day is a recent gap or the range keeps
    /// failing, `start` stays ≤ yesterday, so without this a rapid foreground
    /// would re-download the 30-day range every time.
    static let minAQIRetryInterval: TimeInterval = 3600   // 1 hour

    /// Last completed local day whose observed weather is ingested + watermarked.
    static let lastWeatherDayKey = "hg.env.lastWeatherDay"
    /// Last time the weather backfill was attempted (retry-throttle watermark).
    static let lastWeatherAttemptKey = "hg.env.lastWeatherAttempt"
    /// Minimum spacing between weather backfill passes (peer of `minAQIRetryInterval`;
    /// its own constant so the two backfills stay independently tunable).
    static let minWeatherRetryInterval: TimeInterval = 3600   // 1 hour

    private static func defaultCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    @MainActor
    static func emitIfNeeded(database: AppDatabase = HealthGraphProvider.shared,
                             service: EnvironmentalDataProviding,
                             now: @escaping () -> Date = Date.init,
                             calendar: Calendar = defaultCalendar(),
                             store: WatermarkStore = UserDefaultsWatermarkStore(),
                             statusStore: EnvironmentStatusStore? = nil,
                             bypassThrottles: Bool = false) async {
        let pipeline = IngestPipeline(database: database)
        let tz = calendar.timeZone.identifier

        // TODAY — forecast weather (display) + current pressure + deterministic
        // date-facts. The service's own cooldown decides whether this refetches;
        // we emit today's reading regardless (dedup makes the re-emit idempotent).
        // NO airQuality: today's completed-day AQI does not exist yet.
        _ = await service.requestRefreshWithCooldown(bypassCooldown: bypassThrottles)
        let today = now()
        let todayReading = EnvironmentalReading(
            date: today,
            pressureHPa: service.latestFetchedPressure,
            previousPressureHPa: service.lastTrustedPressure,
            moonPhaseName: getMoonPhase(for: today),
            isMercuryRetrograde: MercuryRetrograde.isRetrograde(on: today),
            timezoneID: tz,
            temperatureHighC: service.forecastHighC,
            temperatureLowC: service.forecastLowC,
            humidityPct: service.forecastHumidity,
            airQualityAQI: nil)
        do {
            _ = try await pipeline.ingest(EnvironmentalEventFactory.events(for: todayReading))
        } catch {
            Logger.info("Environmental today-emit failed; will retry on next foreground", category: .data)
        }

        await backfillObservedAQI(pipeline: pipeline, service: service, now: now, calendar: calendar, store: store, tz: tz, statusStore: statusStore, bypassThrottles: bypassThrottles)
        await backfillObservedWeather(pipeline: pipeline, service: service, now: now, calendar: calendar, store: store, tz: tz, statusStore: statusStore, bypassThrottles: bypassThrottles)
    }

    /// BACKFILL — observed AQI for each completed local day, from a contiguous
    /// watermark up to yesterday, via ONE range request (retry-throttled).
    @MainActor
    private static func backfillObservedAQI(pipeline: IngestPipeline, service: EnvironmentalDataProviding,
                                            now: () -> Date, calendar: Calendar,
                                            store: WatermarkStore, tz: String,
                                            statusStore: EnvironmentStatusStore?,
                                            bypassThrottles: Bool) async {
        let watermark: Date? = store.date(for: lastAQIDayKey)   // nil when unset
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now()))!
        let capFloor = calendar.date(byAdding: .day, value: -(maxBackfillDays - 1), to: yesterday)!
        let start: Date = watermark.map { max(calendar.date(byAdding: .day, value: 1, to: $0)!, capFloor) } ?? capFloor
        guard start <= yesterday else { return }
        // Throttle: while the tail day is a recent gap or the range keeps failing,
        // `start` stays ≤ yesterday, so without this a rapid foreground would
        // re-download the 30-day range every time (independent of the
        // pressure/forecast cooldown). Own interval, own attempt watermark.
        if !bypassThrottles, let last = store.date(for: lastAQIAttemptKey), now().timeIntervalSince(last) < minAQIRetryInterval { return }
        store.set(now(), for: lastAQIAttemptKey)
        let byDay: [Date: AQIDayValue]
        switch await service.fetchCompletedAirQualityRange(from: start, through: yesterday) {
        case .cancelled:
            return                                     // no status, watermark held
        case .fetchError(let reason):
            statusStore?.recordFailure(.observedAirQuality, reason: reason,
                                       scopeStart: start, scopeEnd: yesterday, timezoneID: tz, at: now())
            return                                     // watermark unchanged, retry after the throttle interval
        case .days(let d):
            byDay = d
        }

        // "recent" = the last `gracePartialDays` completed days (provider-lag grace).
        // With gracePartialDays = 2 and yesterday = 2025-06-10: graceCutoff =
        // 2025-06-08, so recent = {2025-06-09, 2025-06-10} and 2025-06-08 (and
        // older) are "old".
        let graceCutoff = calendar.date(byAdding: .day, value: -gracePartialDays, to: yesterday)!
        var newWatermark: Date? = watermark, contiguous = true
        var aqiEvents: [HealthEvent] = []
        // Reading dated D's local noon with ONLY airQualityAQI set → the factory
        // stamps `.observedCompletedDay`, timestamps + groups under day D.
        func emitObservedAQI(_ aqi: Int, on day: Date) {
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
            let reading = EnvironmentalReading(
                date: noon, pressureHPa: nil, previousPressureHPa: nil,
                moonPhaseName: nil, isMercuryRetrograde: false,
                timezoneID: tz, airQualityAQI: aqi)
            aqiEvents.append(contentsOf: EnvironmentalEventFactory.events(for: reading))
        }
        var D = start
        while D <= yesterday {
            switch byDay[calendar.startOfDay(for: D)] ?? .absent {
            case .value(let aqi):
                emitObservedAQI(aqi, on: D)                 // value days beyond a recent gap still emit (dedup-idempotent)
                if contiguous { newWatermark = D }
            case .absent:
                if D > graceCutoff { contiguous = false }   // recent → provider lag; retry, don't advance past
                else if contiguous { newWatermark = D }     // old gap → resolved-absent; advance so it can't block forever
            }
            D = calendar.date(byAdding: .day, value: 1, to: D)!
        }
        // Advance the watermark only once the emitted days are actually persisted;
        // a failed ingest holds it for retry (same as `.fetchError`).
        do {
            if !aqiEvents.isEmpty {
                _ = try await pipeline.ingest(aqiEvents)
            }
            if let nw = newWatermark { store.set(nw, for: lastAQIDayKey) }
            statusStore?.recordSuccess(.observedAirQuality, at: now())   // full pass persisted
        } catch {
            Logger.info("Environmental AQI backfill ingest failed; watermark held for retry", category: .data)
        }
    }

    /// BACKFILL — observed completed-day weather (One Call day_summary), same
    /// contiguous-watermark/cap/grace policy as AQI but ONE CALL PER MISSED DAY
    /// (day_summary has no range endpoint). A per-day `.fetchError` aborts the
    /// whole pass — nothing ingested, watermark held (dedup makes the eventual
    /// re-fetch idempotent; the throttle paces retries, incl. the not-subscribed
    /// 401 case, which the service maps to `.fetchError`).
    @MainActor
    private static func backfillObservedWeather(pipeline: IngestPipeline, service: EnvironmentalDataProviding,
                                                now: () -> Date, calendar: Calendar,
                                                store: WatermarkStore, tz: String,
                                                statusStore: EnvironmentStatusStore?,
                                                bypassThrottles: Bool) async {
        let watermark: Date? = store.date(for: lastWeatherDayKey)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now()))!
        let capFloor = calendar.date(byAdding: .day, value: -(maxBackfillDays - 1), to: yesterday)!
        let start: Date = watermark.map { max(calendar.date(byAdding: .day, value: 1, to: $0)!, capFloor) } ?? capFloor
        guard start <= yesterday else { return }
        if !bypassThrottles, let last = store.date(for: lastWeatherAttemptKey), now().timeIntervalSince(last) < minWeatherRetryInterval { return }
        store.set(now(), for: lastWeatherAttemptKey)

        let scopeStart = start, scopeEnd = yesterday    // intended range, captured before the loop
        let graceCutoff = calendar.date(byAdding: .day, value: -gracePartialDays, to: yesterday)!
        var newWatermark: Date? = watermark, contiguous = true
        var weatherEvents: [HealthEvent] = []
        // Reading dated D's local noon with ONLY weather fields + observed
        // provenance → the factory stamps `.observedCompletedDay` (mineable);
        // nil humidity emits no humidity event (missing afternoon observation).
        func emitObservedWeather(highC: Double, lowC: Double, humidityPct: Double?, on day: Date) {
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
            let reading = EnvironmentalReading(
                date: noon, pressureHPa: nil, previousPressureHPa: nil,
                moonPhaseName: nil, isMercuryRetrograde: false,
                timezoneID: tz, temperatureHighC: highC, temperatureLowC: lowC,
                humidityPct: humidityPct, weatherProvenance: .observedCompletedDay)
            weatherEvents.append(contentsOf: EnvironmentalEventFactory.events(for: reading))
        }
        var D = start
        while D <= yesterday {
            switch await service.fetchCompletedWeatherDay(for: D) {
            case .cancelled:
                return   // no status, nothing ingested, watermark held
            case .fetchError(let reason):
                statusStore?.recordFailure(.observedWeather, reason: reason,
                                           scopeStart: scopeStart, scopeEnd: scopeEnd, timezoneID: tz, at: now())
                return   // abort the WHOLE pass: nothing ingested, watermark held (spec §3B)
            case .value(let high, let low, let humidity):
                emitObservedWeather(highC: high, lowC: low, humidityPct: humidity, on: D)
                if contiguous { newWatermark = D }
            case .absent:
                if D > graceCutoff { contiguous = false }
                else if contiguous { newWatermark = D }
            }
            D = calendar.date(byAdding: .day, value: 1, to: D)!
        }
        do {
            if !weatherEvents.isEmpty {
                _ = try await pipeline.ingest(weatherEvents)
            }
            if let nw = newWatermark { store.set(nw, for: lastWeatherDayKey) }
            statusStore?.recordSuccess(.observedWeather, at: now())   // full pass persisted
        } catch {
            Logger.info("Environmental weather backfill ingest failed; watermark held for retry", category: .data)
        }
    }

    /// Historical backfill of the date-derived signals (moon phase, Mercury
    /// retrograde) — pure functions of the date, so a year of exposure
    /// history is free (spec §5 cold-start rationale). No historical pressure:
    /// the weather API has no history. Idempotent via daily dedupKeys.
    /// NOTE: MercuryRetrograde.periods covers 2025–2026 only; days before its
    /// table simply emit no retrograde events (correct absence semantics).
    static func backfillDerived(days: Int = 365,
                                database: AppDatabase = HealthGraphProvider.shared) async throws -> IngestSummary {
        let pipeline = IngestPipeline(database: database)
        let tz = TimeZone.current.identifier
        var events: [HealthEvent] = []
        let noonToday = Calendar.current.date(
            bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        for dayOffset in 1...days {
            let date = noonToday.addingTimeInterval(-Double(dayOffset) * 86_400)
            let reading = EnvironmentalReading(
                date: date, pressureHPa: nil, previousPressureHPa: nil,
                moonPhaseName: getMoonPhase(for: date),
                isMercuryRetrograde: MercuryRetrograde.isRetrograde(on: date),
                timezoneID: tz
            )
            events.append(contentsOf: EnvironmentalEventFactory.events(for: reading))
        }
        return try await pipeline.ingest(events)
    }
}
