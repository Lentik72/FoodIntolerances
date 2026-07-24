// Create a new file: EnvironmentalDataService.swift

import Foundation
import CoreLocation
import Combine
import SwiftUI
import UIKit
import HealthGraphCore

/// A single completed local day's retrospective AQI: either a value derived
/// from enough in-window hourly PM2.5 readings, or `.absent` when the day had
/// too little history coverage to trust.
enum AQIDayValue: Equatable {
    case value(Int)
    case absent
}

/// Result of a ranged retrospective-AQI fetch: either the whole request failed
/// (transport error OR a decode error — never conflated with per-day absence),
/// or a dictionary of local-day → `AQIDayValue`, keyed by `calendar.startOfDay(for:)`.
enum AQIRangeResult: Equatable {
    case fetchError(EnvironmentFailureReason)
    case cancelled
    case days([Date: AQIDayValue])
}

/// Result of a completed-day weather fetch (One Call day_summary): the request
/// failed (transport OR decode OR auth-error body — always retryable, never
/// conflated with absence), the provider has no temperature for the day, or the
/// day's observed values. `humidityPct` is the provider's observed AFTERNOON
/// humidity and can be missing independently of temperature (nil → the emitter
/// writes no observed humidity event for that day).
enum WeatherDayResult: Equatable {
    case fetchError(EnvironmentFailureReason)
    case cancelled
    case absent
    case value(highC: Double, lowC: Double, humidityPct: Double?)
}

class EnvironmentalDataService: ObservableObject {
    // Published properties for UI updates
    @Published var atmosphericPressure: String = ""
    @Published var atmosphericPressureCategory: String = "Loading..."
    @Published var currentPressure: Double = 0.0
    @Published var previousPressure: Double = 0.0
    @Published var suddenPressureChange: Bool = false
    // Optional (NOT 0-default): 0 °C / 0% are legitimate readings, and a `> 0` guard
    // would silently drop exactly the cold days the Cold-day exposure needs.
    @Published var currentTemperatureC: Double? = nil
    @Published var currentHumidityPct: Double? = nil
    // Next-24h daily high/low + mean humidity from the /forecast endpoint. Optional
    // (nil on fetch failure or < 3 in-window slots) so the emitter leaves the
    // temperature/humidity events unemitted rather than writing a false 0.
    @Published var forecastHighC: Double? = nil
    @Published var forecastLowC: Double? = nil
    @Published var forecastHumidity: Double? = nil
    // Next-24h mean PM2.5 → EPA AQI from the /air_pollution/forecast endpoint. Optional
    // (nil on fetch failure or < 3 in-window slots) so the emitter leaves the air
    // quality event unemitted rather than writing a false reading.
    @Published var forecastAQI: Int? = nil
    @Published var moonPhase: String = "Loading..."
    @Published var isMercuryRetrograde: Bool = false
    @Published var lastUpdated: Date = Date()
    @Published var showZipCodePrompt: Bool = false
    @Published private(set) var currentAtmosphericTask: Task<Void, Never>? = nil

    /// Bumped whenever a TRUSTED coordinate (re)appears — the location-recovery
    /// signal the App observes to fire a throttle/cooldown-bypassing emit so the
    /// live `locationDenied`/`locationUnavailable` markers self-heal in one pass
    /// (return-from-Settings, or a cold-launch fix that resolves seconds later).
    @Published private(set) var locationRecoveryTick: Int = 0

    /// The emitter's inputs. `latestFetchedPressure` is this refresh's genuine
    /// reading (nil on failure/fallback). `lastTrustedPressure` is the prior
    /// genuine reading, exposed only when recent enough to compare.
    @Published private(set) var latestFetchedPressure: Double? = nil
    @Published private(set) var lastTrustedPressure: Double? = nil
    /// The last genuine API reading + when it landed. Never cleared at refresh
    /// start, never written by a fallback/cancellation — the carry that makes the
    /// previous/current shift correct across refreshes.
    private var mostRecentGenuinePressure: (value: Double, at: Date)? = nil

    // Private properties
    private var pressureReadings: [(pressure: Double, timestamp: Date)] = []
    private let pressureChangeThreshold: Double = 6.0  // hPa threshold for sudden change
    private let pressureReadingInterval: TimeInterval = 3600  // 1 hour in seconds
    private var isFirstLoad: Bool = true
    private var locationManager: LocationService?
    private var manualLocation: CLLocationCoordinate2D?
    private var cancellables = Set<AnyCancellable>()
    private var lastRefreshRequest = Date.distantPast
    private let minimumRefreshInterval: TimeInterval = 300  // 5 minutes
    /// Trusted-cache window: a cached fix older than this is not ingested (it is
    /// still shown by the legacy display). Matches the existing 300 s location
    /// cadence used elsewhere in `LocationService`.
    static let locationFreshnessInterval: TimeInterval = 300

    // Dependency-injection seams. Default to real production behavior
    // (URLSession, wall-clock `Date`, the current calendar/timezone, and the
    // existing manualLocation → LocationService resolution) so nothing about
    // runtime behavior changes; tests substitute stubs to make fetches
    // deterministic.
    private let transport: HTTPTransport
    private let now: () -> Date
    private let calendar: Calendar
    private let injectedLocation: LocationProviding?
    /// The single source of truth for env-fetch health (Task 2). Optional with a
    /// `nil` default: `EnvironmentStatusStore` is `@MainActor`, so a constructed
    /// default argument would not compile at the non-`@MainActor` test call sites;
    /// a nil store makes every `recordToday*` a no-op. The App passes the real one.
    private let statusStore: EnvironmentStatusStore?
    /// Lazy because the default provider needs `self` — evaluated on first use,
    /// well after `init` has finished setting every other stored property.
    private lazy var locationProvider: LocationProviding = injectedLocation ?? DefaultLocationProvider(service: self)

    /// Reproduces the pre-DI location resolution exactly: a manual override
    /// (from `setLocation`) wins, otherwise the live `LocationService` reading.
    /// Nested so it can see `EnvironmentalDataService`'s private storage.
    private final class DefaultLocationProvider: LocationProviding {
        private unowned let service: EnvironmentalDataService
        init(service: EnvironmentalDataService) { self.service = service }
        var coordinate: CLLocationCoordinate2D? {
            guard let loc = service.locationManager else { return service.manualLocation }
            return LocationTrust.trustedCoordinate(
                manual: service.manualLocation,
                provenance: loc.provenance,
                deviceCoordinate: loc.currentLocation,
                cachedCoordinate: loc.lastKnownLocation,
                cachedAt: loc.cachedLocationAt,
                authorization: loc.authorization,
                now: service.now(),
                freshness: EnvironmentalDataService.locationFreshnessInterval)
        }
        var authorization: EnvironmentLocationAuthorization {
            service.locationManager?.authorization ?? .notDetermined
        }
    }

    init(locationManager: LocationService? = nil,
         transport: HTTPTransport = URLSession.shared,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }(),
         location: LocationProviding? = nil,
         statusStore: EnvironmentStatusStore? = nil) {
        self.transport = transport
        self.now = now
        self.calendar = calendar
        self.injectedLocation = location
        self.statusStore = statusStore
        if let locationManager = locationManager {
            self.locationManager = locationManager
        } else {
            // Create a new location service instance if none provided
            self.locationManager = LocationService()
        }

        // Location-recovery signal: when the device coordinate changes, defer to the
        // main queue so `apply()`'s follow-on `provenance` write (set right after
        // `currentLocation`) is visible, then bump the tick only if a TRUSTED
        // coordinate is now resolvable. The App observes this tick to fire a
        // throttle/cooldown-bypassing emit so location-failure markers self-heal.
        self.locationManager?.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.resolvedCoordinate() != nil { self.locationRecoveryTick += 1 }
            }
            .store(in: &cancellables)
    }
    
    func setLocation(latitude: Double, longitude: Double) {
        manualLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // MARK: - Public Methods
    
    func fetchAllData() async {
        // Cancel existing task if any
        currentAtmosphericTask?.cancel()
        
        let newTask = Task {
            // Fetch moon phase and Mercury retrograde data
            await fetchMoonPhase(for: now())
            self.isMercuryRetrograde = checkMercuryInRetrograde(for: now())
            
            // Make sure we're not cancelled before proceeding with potentially expensive operations
            if !Task.isCancelled {
                // Fetch atmospheric pressure (most important data)
                await fetchAtmosphericPressure()

                // Fetch the daily high/low + mean humidity from the forecast endpoint
                if !Task.isCancelled {
                    await fetchDailyForecast()
                }

                // Fetch the next-24h mean PM2.5 → EPA AQI from the air pollution endpoint
                if !Task.isCancelled {
                    await fetchAirQuality()
                }

                // Final update
                if !Task.isCancelled {
                    await MainActor.run {
                        self.lastUpdated = Date() // Trigger UI refresh
                    }
                }
            }
        }
        
        currentAtmosphericTask = newTask
        
        // Wait for task completion
        await newTask.value
    }
    
    func fetchWithReliableTimeout() async {
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 second timeout
            if !Task.isCancelled {
                await MainActor.run {
                    if self.atmosphericPressureCategory == "Loading..." {
                        setFallbackAtmosphericPressure()
                    }
                }
            }
        }
        
        // Run the actual fetch
        await fetchAtmosphericPressure()
        
        // Cancel the timeout if we completed normally
        timeoutTask.cancel()
    }
    
    
    func refreshEnvironmentalData() {
        Task {
            
            // Reset state before refresh
            await MainActor.run {
                resetPressureState()
                self.atmosphericPressureCategory = "Loading..."
            }
            
            guard let locationManager = locationManager else {
                self.atmosphericPressureCategory = "Location Manager Not Available"
                return
            }
            
            let locationUpdateTask = Task {
                locationManager.requestLocationUpdate()
                for _ in 0..<5 {
                    if locationManager.currentLocation != nil {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            
            _ = await locationUpdateTask.value
            
            if !Task.isCancelled {
                await fetchAtmosphericPressure()
                
                await MainActor.run {
                    self.lastUpdated = Date()
                }
            }
        }
    }
    
    func resetPressureState() {
        suddenPressureChange = false
        pressureReadings.removeAll()
        currentPressure = 0.0
        previousPressure = 0.0

        // Not a genuine reading: clear what the emitter would see, but preserve
        // the genuine carry so a later real reading can still compute a real drop.
        latestFetchedPressure = nil

        // Cancel any existing fetch tasks
        currentAtmosphericTask?.cancel()
        currentAtmosphericTask = nil
    }
    
    func isMercuryRetrogradeApproaching(for date: Date) -> Bool {
        for period in MercuryRetrograde.periods {
            let daysUntilRetrograde = calendar.dateComponents([.day], from: date, to: period.start).day ?? Int.max
            if daysUntilRetrograde >= 0 && daysUntilRetrograde <= 3 {
                return true
            }
        }
        return false
    }
    
    func categorizePressure(_ pressure: Double) -> String {
        PressureCategory.from(pressure: pressure).rawValue
    }
    
    // MARK: - Private Methods

    /// Resolves the coordinate to use for a fetch through the injected
    /// `LocationProviding` seam (defaults to manualLocation → LocationService).
    private func resolvedCoordinate() -> CLLocationCoordinate2D? {
        locationProvider.coordinate
    }

    /// Cancellation must never be recorded as a failure or a success.
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// The reason to record when there is no trusted coordinate.
    private func locationReason() -> EnvironmentFailureReason {
        switch locationProvider.authorization {
        case .denied, .restricted: return .locationDenied
        default:                   return .locationUnavailable
        }
    }

    /// Maps a thrown error into a reason (used in every fetch's `catch`).
    /// A `URLError` (not cancelled) is a connectivity failure; anything else
    /// reaching the catch is a decode/unexpected-shape failure.
    private func classifyThrown(_ error: Error) -> EnvironmentFailureReason {
        if let urlError = error as? URLError, urlError.code != .cancelled { return .offline }
        return .badResponse
    }

    /// A non-2xx HTTP status → a reason, checked BEFORE decode (a 401 body decodes
    /// to a throw that would otherwise be miscounted as `.badResponse`). nil for
    /// 2xx or a non-`HTTPURLResponse` stub (no status info → proceed to decode).
    /// Used by BOTH backfill fetches AND the three today fetches (Task 8).
    private func httpStatusReason(_ response: URLResponse?) -> EnvironmentFailureReason? {
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 || http.statusCode == 403 { return .rejected }
        if !(200...299).contains(http.statusCode) { return .badResponse }
        return nil
    }

    /// The scope a "today" fetch blocks when it fails: this local day only
    /// (start == end == today's local midnight), in the calendar's timezone.
    private func todayScope() -> (start: Date, end: Date, tz: String) {
        let d = calendar.startOfDay(for: now())
        return (d, d, calendar.timeZone.identifier)
    }

    /// Record a today-fetch success (a nil store is a no-op).
    @MainActor private func recordTodaySuccess(_ capability: EnvironmentCapability) {
        guard let statusStore else { return }
        statusStore.recordSuccess(capability, at: now())
    }

    /// Record a today-fetch failure scoped to this local day (a nil store is a no-op).
    @MainActor private func recordTodayFailure(_ capability: EnvironmentCapability, _ reason: EnvironmentFailureReason) {
        guard let statusStore else { return }
        let s = todayScope()
        statusStore.recordFailure(capability, reason: reason, scopeStart: s.start, scopeEnd: s.end, timezoneID: s.tz, at: now())
    }

    public func requestRefreshWithCooldown(bypassCooldown: Bool = false) async -> Bool {
        // Check if it's too soon for another refresh. A location-recovery pass
        // (`bypassCooldown`) skips ONLY this early-return — everything else runs.
        let currentTime = now()
        if !bypassCooldown, currentTime.timeIntervalSince(lastRefreshRequest) < minimumRefreshInterval {
            return false
        }

        lastRefreshRequest = currentTime
        
        // Cancel current task if any
        currentAtmosphericTask?.cancel()
        
        // Perform the actual refresh
        await fetchAllData()
        
        return true
    }
    
    /// Fetches the current atmospheric pressure and publishes it (plus temp /
    /// humidity). This is a plain inline `await` that returns only when the fetch
    /// resolves — it deliberately does NOT touch `currentAtmosphericTask`.
    ///
    /// `fetchAllData()` is the sole owner of the refresh task's lifecycle: when
    /// this ran as a self-cancelling fire-and-forget inner `Task`, calling it
    /// from inside `fetchAllData`'s task cancelled that very task, so the
    /// downstream forecast + air-quality fetches were skipped. Being an ordinary
    /// awaited call, it now composes cleanly — a new refresh supersedes an old
    /// one via `fetchAllData`'s outer task + `!Task.isCancelled` gates alone.
    public func fetchAtmosphericPressure() async {
        Logger.debug("Starting atmospheric pressure fetch", category: .network)

        // Ensure UI shows a loading state immediately.
        await MainActor.run {
            self.atmosphericPressureCategory = "Loading..."
        }

        // Start of a genuine attempt: clear any previously-fetched value so a
        // cancelled/failing refresh leaves nothing stale for the emitter to
        // restamp. The carry (`mostRecentGenuinePressure`) is untouched.
        await MainActor.run { self.clearFetchedPressure() }

        // Local timeout: if location never resolves / the fetch stalls, publish
        // fallback pressure after 5s so the UI doesn't sit on "Loading..." forever.
        // Scoped entirely to this call — it never references `currentAtmosphericTask`.
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if !Task.isCancelled {
                await MainActor.run {
                    if self.atmosphericPressureCategory == "Loading..." {
                        self.useFallbackPressureData()
                    }
                }
            }
        }
        defer { timeoutTask.cancel() }

        // Check if location is available
        guard let location = self.resolvedCoordinate() else {
            Logger.warning("No location available, using fallback pressure data.", category: .location)
            await MainActor.run {
                self.recordTodayFailure(.currentPressure, self.locationReason())
                self.useFallbackPressureData()
            }
            return
        }

        guard let url = APIConfig.weatherURL(latitude: location.latitude, longitude: location.longitude) else {
            Logger.error("Invalid URL for weather API", category: .network)
            await MainActor.run { self.recordTodayFailure(.currentPressure, .notConfigured) }
            return
        }

        do {
            let (data, response) = try await self.transport.data(from: url)
            // Cancelled AFTER a clean transport throws nothing → the catch can't see
            // it. Bail before recording/publishing so a superseding refresh wins.
            if Task.isCancelled { return }
            if let reason = httpStatusReason(response) {   // 401/403/non-2xx before decode
                await MainActor.run {
                    self.recordTodayFailure(.currentPressure, reason)
                    self.useFallbackPressureData()
                }
                return
            }
            let decodedResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)

            let pressureValue = Double(decodedResponse.main.pressure)
            let temp = decodedResponse.main.temp
            let humidity = decodedResponse.main.humidity.map(Double.init)

            if Task.isCancelled { return }
            await MainActor.run {
                self.updateAtmosphericPressure(pressureValue)
                self.atmosphericPressure = "\(Int(pressureValue)) hPa"
                self.atmosphericPressureCategory = self.categorizePressure(pressureValue)
                self.currentTemperatureC = temp
                self.currentHumidityPct = humidity
                self.lastUpdated = Date()
                self.recordGenuinePressure(pressureValue, at: self.now())
                self.recordTodaySuccess(.currentPressure)
            }
        } catch {
            // A cancelled fetch must not apply the legacy fallback and must record
            // nothing — a superseding refresh is coming. `clearFetchedPressure()`
            // already nil'd `latestFetchedPressure` at the start of this attempt.
            if self.isCancellation(error) { return }
            Logger.error(error, message: "Error fetching atmospheric pressure", category: .network)
            await MainActor.run {
                self.recordTodayFailure(.currentPressure, self.classifyThrown(error))
                self.useFallbackPressureData()
            }
        }
    }

    /// Pure reduction over 3-hourly forecast slots: the daily high (max temp), low
    /// (min temp) and mean humidity across the slots whose `dt` falls in the next
    /// 24h window `[now, now + 86_400]`. Requires ≥ 3 in-window slots (a partial
    /// window at the edge of a forecast run is not a trustworthy daily high/low);
    /// nil otherwise. Static + network-free so it can be unit-tested directly.
    static func aggregate24h(slots: [(dt: TimeInterval, temp: Double, humidity: Double)],
                             now: Date) -> (high: Double, low: Double, humidity: Double)? {
        let start = now.timeIntervalSince1970
        let end = start + 86_400
        let inWindow = slots.filter { $0.dt >= start && $0.dt <= end }
        guard inWindow.count >= 3 else { return nil }
        let temps = inWindow.map(\.temp)
        guard let high = temps.max(), let low = temps.min() else { return nil }
        let humidity = inWindow.map(\.humidity).reduce(0, +) / Double(inWindow.count)
        return (high, low, humidity)
    }

    /// GETs the /forecast endpoint (3-hourly slots) and publishes the next-24h daily
    /// high/low + mean humidity. Reuses the exact location resolution the pressure
    /// fetch uses (manual override → LocationService); no new location path.
    public func fetchDailyForecast() async {
        // Resolve location the same way fetchAtmosphericPressure does.
        guard let location = self.resolvedCoordinate() else {
            Logger.warning("No location available for daily forecast fetch.", category: .location)
            await MainActor.run {
                self.forecastHighC = nil
                self.forecastLowC = nil
                self.forecastHumidity = nil
                self.recordTodayFailure(.forecastWeather, self.locationReason())
            }
            return
        }

        guard let url = APIConfig.forecastURL(latitude: location.latitude, longitude: location.longitude) else {
            Logger.error("Invalid URL for forecast API", category: .network)
            await MainActor.run { self.recordTodayFailure(.forecastWeather, .notConfigured) }
            return
        }

        do {
            let (data, response) = try await transport.data(from: url)
            // Cancelled AFTER a clean transport throws nothing → bail before it can
            // clear a live failure or restamp a value (a superseding refresh wins).
            if Task.isCancelled { return }
            if let reason = httpStatusReason(response) {   // 401/403/non-2xx before decode
                await MainActor.run {
                    self.forecastHighC = nil
                    self.forecastLowC = nil
                    self.forecastHumidity = nil
                    self.recordTodayFailure(.forecastWeather, reason)
                }
                return
            }
            let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
            let slots = decoded.list.map {
                (dt: $0.dt, temp: $0.main.temp, humidity: Double($0.main.humidity))
            }
            // Extract plain scalars BEFORE the MainActor.run block so we don't
            // cross-actor-capture the (non-Sendable) tuple/decoded state.
            let aggregate = EnvironmentalDataService.aggregate24h(slots: slots, now: now())
            let high = aggregate?.high
            let low = aggregate?.low
            let humidity = aggregate?.humidity
            if Task.isCancelled { return }
            await MainActor.run {
                self.forecastHighC = high
                self.forecastLowC = low
                self.forecastHumidity = humidity
                if aggregate == nil { self.recordTodayFailure(.forecastWeather, .insufficientData) }
                else { self.recordTodaySuccess(.forecastWeather) }
            }
        } catch {
            if self.isCancellation(error) { return }
            Logger.error(error, message: "Error fetching daily forecast", category: .network)
            await MainActor.run {
                self.forecastHighC = nil
                self.forecastLowC = nil
                self.forecastHumidity = nil
                self.recordTodayFailure(.forecastWeather, self.classifyThrown(error))
            }
        }
    }

    /// Pure reduction over 3-hourly air-pollution forecast slots: the mean PM2.5
    /// across the slots whose `dt` falls in the next 24h window `[now, now + 86_400]`.
    /// Requires ≥ 3 in-window slots (mirrors `aggregate24h`); nil otherwise. Static +
    /// network-free so it can be unit-tested directly.
    static func meanPM25(slots: [(dt: TimeInterval, pm25: Double)], now: Date) -> Double? {
        let start = now.timeIntervalSince1970
        let end = start + 86_400
        let inWindow = slots.filter { $0.dt >= start && $0.dt <= end }
        guard inWindow.count >= 3 else { return nil }
        return inWindow.map(\.pm25).reduce(0, +) / Double(inWindow.count)
    }

    /// GETs the /air_pollution/forecast endpoint (3-hourly slots) and publishes the
    /// next-24h EPA AQI derived from mean PM2.5. Reuses the exact location resolution
    /// the pressure fetch uses (manual override → LocationService); no new location path.
    public func fetchAirQuality() async {
        // Resolve location the same way fetchAtmosphericPressure does.
        guard let location = self.resolvedCoordinate() else {
            Logger.warning("No location available for air quality fetch.", category: .location)
            await MainActor.run {
                self.forecastAQI = nil
                self.recordTodayFailure(.forecastAirQuality, self.locationReason())
            }
            return
        }

        guard let url = APIConfig.airPollutionURL(latitude: location.latitude, longitude: location.longitude) else {
            Logger.error("Invalid URL for air pollution API", category: .network)
            await MainActor.run { self.recordTodayFailure(.forecastAirQuality, .notConfigured) }
            return
        }

        do {
            let (data, response) = try await transport.data(from: url)
            // Cancelled AFTER a clean transport throws nothing → bail before it can
            // clear a live failure or restamp a value (a superseding refresh wins).
            if Task.isCancelled { return }
            if let reason = httpStatusReason(response) {   // 401/403/non-2xx before decode
                await MainActor.run {
                    self.forecastAQI = nil
                    self.recordTodayFailure(.forecastAirQuality, reason)
                }
                return
            }
            let decoded = try JSONDecoder().decode(AirPollutionResponse.self, from: data)
            let slots = decoded.list.map {
                (dt: $0.dt, pm25: $0.components.pm2_5)
            }
            // Extract plain scalars BEFORE the MainActor.run block so we don't
            // cross-actor-capture the (non-Sendable) tuple/decoded state.
            let mean = EnvironmentalDataService.meanPM25(slots: slots, now: now())
            let aqi = mean.map { AirQualityIndex.epaAQI(pm25: $0) }
            if Task.isCancelled { return }
            await MainActor.run {
                self.forecastAQI = aqi
                if mean == nil { self.recordTodayFailure(.forecastAirQuality, .insufficientData) }
                else { self.recordTodaySuccess(.forecastAirQuality) }
            }
        } catch {
            if self.isCancellation(error) { return }
            Logger.error(error, message: "Error fetching air quality", category: .network)
            await MainActor.run {
                self.forecastAQI = nil
                self.recordTodayFailure(.forecastAirQuality, self.classifyThrown(error))
            }
        }
    }

    /// Minimum distinct in-window hourly readings a completed local day needs
    /// before its retrospective mean PM2.5 is trusted (out of a possible 24). Below
    /// this, `dailyMeanPM25` returns nil rather than average a too-sparse sample.
    static let minAirQualityHours = 20

    /// The `[start, end)` window for a completed LOCAL day: local midnight of `D`
    /// through local midnight of `D + 1`. Deliberately computed via `Calendar`
    /// arithmetic (`startOfDay` + `date(byAdding: .day, ...)`), NOT a naive
    /// `+86_400`/UTC-calendar shortcut — those silently produce a 24h span even
    /// across DST transitions or month/year rollovers, which is wrong for a
    /// LOCAL calendar day (23h on spring-forward, 25h on fall-back).
    static func completedDayWindow(for day: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: day)!)
        return (start, end)
    }

    /// Pure reduction over hourly air-pollution HISTORY slots: the mean PM2.5
    /// across slots whose `dt` falls in the half-open window `[dayStart, dayEnd)`
    /// — a slot exactly at `dayEnd` belongs to the NEXT day and is excluded.
    /// Slots are de-duplicated by `dt` first (one pm2.5 per distinct hourly
    /// timestamp) so a duplicated timestamp can't inflate the coverage count or
    /// skew the mean; the `minHours` guard is checked against that DISTINCT
    /// count. Static + network-free so it can be unit-tested directly.
    static func dailyMeanPM25(slots: [(dt: TimeInterval, pm25: Double)], dayStart: Date, dayEnd: Date, minHours: Int) -> Double? {
        let start = dayStart.timeIntervalSince1970
        let end = dayEnd.timeIntervalSince1970
        let inWindow = slots.filter { $0.dt >= start && $0.dt < end }
        // De-duplicate by `dt`: keep one pm2.5 reading per distinct hourly timestamp.
        var byTimestamp: [TimeInterval: Double] = [:]
        for slot in inWindow {
            byTimestamp[slot.dt] = slot.pm25
        }
        guard byTimestamp.count >= minHours else { return nil }
        let values = byTimestamp.values
        return values.reduce(0, +) / Double(values.count)
    }

    /// GETs the /air_pollution/history endpoint ONCE for the whole `[startDay,
    /// endDay]` span (spanning `completedDayWindow(startDay).start` through
    /// `completedDayWindow(endDay).end`), then groups the returned hourly slots
    /// into each completed LOCAL day in the range via `dailyMeanPM25`. Reuses the
    /// exact location resolution the other fetches use (manual override →
    /// LocationService). A transport OR decode failure returns `.fetchError` for
    /// the WHOLE window — a decode error must trigger a retry of the whole
    /// window, never be mistaken for per-day absence.
    func fetchCompletedAirQualityRange(from startDay: Date, through endDay: Date) async -> AQIRangeResult {
        guard let location = self.resolvedCoordinate() else {
            Logger.warning("No location available for air quality range fetch.", category: .location)
            return .fetchError(locationReason())
        }

        let requestWindow = (
            start: EnvironmentalDataService.completedDayWindow(for: startDay, calendar: calendar).start,
            end: EnvironmentalDataService.completedDayWindow(for: endDay, calendar: calendar).end
        )

        guard let url = APIConfig.airPollutionHistoryURL(
            latitude: location.latitude,
            longitude: location.longitude,
            start: requestWindow.start.timeIntervalSince1970,
            end: requestWindow.end.timeIntervalSince1970
        ) else {
            Logger.error("Invalid URL for air pollution history API", category: .network)
            return .fetchError(.notConfigured)
        }

        do {
            let (data, response) = try await transport.data(from: url)
            if Task.isCancelled { return .cancelled }   // cancellation wins over classification (before httpStatusReason/decode)
            if let reason = httpStatusReason(response) { return .fetchError(reason) }   // 401/403 before decode
            let decoded = try JSONDecoder().decode(AirPollutionResponse.self, from: data)
            let slots = decoded.list.map {
                (dt: $0.dt, pm25: $0.components.pm2_5)
            }

            // Normalize to local-midnight up front and step whole calendar days from
            // there, so a caller passing a non-midnight `startDay`/`endDay` (or a
            // mismatched time-of-day between the two) still terminates and keys
            // correctly — the loop bound and the dictionary key are the same
            // `startOfDay` value.
            var byDay: [Date: AQIDayValue] = [:]
            var day = calendar.startOfDay(for: startDay)
            let lastDay = calendar.startOfDay(for: endDay)
            while day <= lastDay {
                let window = EnvironmentalDataService.completedDayWindow(for: day, calendar: calendar)
                let mean = EnvironmentalDataService.dailyMeanPM25(
                    slots: slots,
                    dayStart: window.start,
                    dayEnd: window.end,
                    minHours: EnvironmentalDataService.minAirQualityHours
                )
                byDay[day] = mean.map { AQIDayValue.value(AirQualityIndex.epaAQI(pm25: $0)) } ?? .absent
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
            if Task.isCancelled { return .cancelled }   // cancelled AFTER a clean transport → not a failure
            return .days(byDay)
        } catch {
            if isCancellation(error) { return .cancelled }
            Logger.error(error, message: "Error fetching air quality history range", category: .network)
            return .fetchError(classifyThrown(error))
        }
    }

    /// One Call 3.0 day_summary decode target — only the fields this feature reads.
    private struct DaySummaryResponse: Decodable {
        struct Temperature: Decodable { let min: Double?; let max: Double? }
        struct Humidity: Decodable { let afternoon: Double? }
        let temperature: Temperature?
        let humidity: Humidity?
    }

    /// GETs One Call day_summary for ONE completed local day. Same location
    /// resolution as every other fetch. A 401 "requires a separate subscription"
    /// body has no `temperature` field and fails decode-shape checks → treated as
    /// `.fetchError` (graceful degradation; the emitter's throttle paces retries).
    func fetchCompletedWeatherDay(for day: Date) async -> WeatherDayResult {
        guard let location = self.resolvedCoordinate() else {
            Logger.warning("No location available for weather day fetch.", category: .location)
            return .fetchError(locationReason())
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        // The app's calendar timezone is authoritative for the aggregation day —
        // date-SPECIFIC offset (DST changes it across the backfill window),
        // anchored at local NOON: on a DST-transition day the midnight offset
        // differs from the afternoon whose humidity value is being ingested
        // (LA 2025-11-02 is -07:00 at midnight but -08:00 that afternoon), and
        // OpenWeather defines humidity.afternoon as the noon reading.
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let seconds = calendar.timeZone.secondsFromGMT(for: noon)
        let tzOffset = String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+",
                              abs(seconds) / 3600, (abs(seconds) % 3600) / 60)
        guard let url = APIConfig.oneCallDaySummaryURL(
            latitude: location.latitude, longitude: location.longitude,
            date: formatter.string(from: day), tz: tzOffset) else {
            Logger.error("Invalid URL for One Call day_summary API", category: .network)
            return .fetchError(.notConfigured)
        }
        do {
            let (data, response) = try await transport.data(from: url)
            if Task.isCancelled { return .cancelled }   // cancellation wins over classification (before httpStatusReason/decode)
            if let reason = httpStatusReason(response) { return .fetchError(reason) }   // 401/403 before decode
            let decoded = try JSONDecoder().decode(DaySummaryResponse.self, from: data)
            guard let high = decoded.temperature?.max, let low = decoded.temperature?.min else {
                // An auth/error body decodes to an empty shell (no temperature) —
                // but so could a legitimate no-data day. Distinguish: an error body
                // always carries "message"; treat that as fetchError, else absent.
                if let errorBody = try? JSONDecoder().decode(OneCallErrorBody.self, from: data) {
                    Logger.error("One Call day_summary error body: \(errorBody.message)", category: .network)
                    return .fetchError(.rejected)   // not-subscribed / bad key — retryable, never absent
                }
                return .absent
            }
            if Task.isCancelled { return .cancelled }   // cancelled AFTER a clean transport → not a failure
            return .value(highC: high, lowC: low, humidityPct: decoded.humidity?.afternoon)
        } catch {
            if isCancellation(error) { return .cancelled }
            Logger.error(error, message: "Error fetching weather day summary", category: .network)
            return .fetchError(classifyThrown(error))
        }
    }

    /// One Call error envelope — a "message" field marks an API error body (401
    /// not-subscribed, 404 bad date, …), which must be retryable, not absent.
    /// (Keyed on "message" alone: OpenWeather's "cod" is inconsistently typed —
    /// Int on some endpoints, String on others.)
    private struct OneCallErrorBody: Decodable {
        let message: String
    }

    @MainActor
    func useFallbackPressureData() {
        
        // Use static value that will still allow the app to function
        let fallbackPressure = 1013.0  // Standard sea level pressure
        
        // Update UI with definitive values, not "Loading..."
        self.atmosphericPressure = "\(Int(fallbackPressure)) hPa"
        self.atmosphericPressureCategory = "Normal"
        self.currentPressure = fallbackPressure
        self.previousPressure = fallbackPressure
        self.suddenPressureChange = false

        // Important: update lastUpdated to trigger UI refresh
        self.lastUpdated = Date()

        // Not a genuine reading: clear what the emitter would see, but preserve
        // the genuine carry so a later real reading can still compute a real drop.
        self.latestFetchedPressure = nil
    }
    
    private func fetchMoonPhase(for date: Date) async {
        // Uses global getMoonPhase(for:) from GetMoonPhase.swift
        let phase = getMoonPhase(for: date)
        await MainActor.run {
            self.moonPhase = phase
        }
    }
    
   public func checkMercuryInRetrograde(for date: Date) -> Bool {
        MercuryRetrograde.isRetrograde(on: date)
    }
    
    /// Record a genuine API pressure reading: shift the carry and expose the prior
    /// genuine value ONLY if within `pressureReadingInterval`. This is the sole
    /// writer of `latestFetchedPressure`/`lastTrustedPressure`/`mostRecentGenuinePressure`.
    /// It deliberately does NOT touch `suddenPressureChange` — that legacy-dashboard
    /// flag is owned solely by `updateAtmosphericPressure` (the emitter never reads it;
    /// the core factory computes the mined drop from the two optionals).
    func recordGenuinePressure(_ value: Double, at: Date) {
        let prior = mostRecentGenuinePressure
        let comparable = prior.map { at.timeIntervalSince($0.at) <= pressureReadingInterval } ?? false
        lastTrustedPressure = comparable ? prior?.value : nil
        mostRecentGenuinePressure = (value, at)
        latestFetchedPressure = value
    }

    /// Clear the fetched reading at the start of a genuine refresh, so a cancelled
    /// refresh leaves nothing for the emitter to restamp. Carry untouched.
    func clearFetchedPressure() { latestFetchedPressure = nil }

    private func updateAtmosphericPressure(_ pressure: Double) {
        let currentTime = now()

        // Special handling for first pressure reading
        if isFirstLoad {
            pressureReadings = [(pressure: pressure, timestamp: currentTime)]
            currentPressure = pressure
            previousPressure = pressure
            atmosphericPressureCategory = categorizePressure(currentPressure)
            isFirstLoad = false
            return
        }

        // Add new reading and remove old ones
        pressureReadings.append((pressure: pressure, timestamp: currentTime))
        pressureReadings = pressureReadings.filter {
            currentTime.timeIntervalSince($0.timestamp) < 24 * 3600
        }
        
        // Update current pressure
        previousPressure = currentPressure
        currentPressure = pressure
        
        // Compare the last two readings only if we have more than one reading
        if pressureReadings.count >= 2 {
            let lastTwo = Array(pressureReadings.suffix(2))
            let pressureChange = abs(lastTwo[0].pressure - lastTwo[1].pressure)
            let timeChange = lastTwo[1].timestamp.timeIntervalSince(lastTwo[0].timestamp)
            suddenPressureChange = pressureChange >= pressureChangeThreshold &&
                                   timeChange <= pressureReadingInterval
        } else {
            suddenPressureChange = false
        }
        
        atmosphericPressureCategory = categorizePressure(currentPressure)

        Logger.debug("Sudden Change: \(suddenPressureChange)", category: .data)
    }
    
    @MainActor
    public func setFallbackAtmosphericPressure() {
        // Check if we have any previous cached data first
        if let cachedPressure = UserDefaults.standard.object(forKey: "lastKnownPressure") as? Double {
            Logger.debug("Using cached pressure data: \(cachedPressure)", category: .data)
            updateAtmosphericPressure(cachedPressure)
            self.atmosphericPressure = "\(Int(cachedPressure)) hPa"
            self.atmosphericPressureCategory = self.categorizePressure(cachedPressure)
            // Not a genuine reading: clear what the emitter would see, but
            // preserve the genuine carry.
            self.latestFetchedPressure = nil
            return
        }
        
        // If no cache, generate a realistic fallback with consistent random seed
        let day = calendar.component(.day, from: now())
        let month = calendar.component(.month, from: now())
        
        // Use date components to seed a deterministic "random" value
        let seed = Double(day + month * 31) / 100.0
        let basePressure = 1013.0  // Standard sea level pressure
        let deterministicVariation = sin(seed * 6.28) * 10.0 // ±10 hPa variation
        let fallbackPressure = basePressure + deterministicVariation
        
        
        // Update the UI
        updateAtmosphericPressure(fallbackPressure)
        self.atmosphericPressure = "\(Int(fallbackPressure)) hPa"
        self.atmosphericPressureCategory = self.categorizePressure(fallbackPressure)
        // Not a genuine reading: clear what the emitter would see, but preserve
        // the genuine carry.
        self.latestFetchedPressure = nil

        // Cache this value for future fallbacks
        UserDefaults.standard.set(fallbackPressure, forKey: "lastKnownPressure")
    }

    // MARK: - Model for Weather Data

    struct WeatherResponse: Codable {
        struct Main: Codable {
            let pressure: Int
            let temp: Double?
            let humidity: Int?
        }
        let main: Main
    }

    /// OpenWeather /forecast payload: 3-hourly slots, each with a Unix `dt` and a
    /// `main` block carrying temp (°C, units=metric) and humidity (%).
    struct ForecastResponse: Codable {
        struct Slot: Codable {
            struct Main: Codable {
                let temp: Double
                let humidity: Int
            }
            let dt: TimeInterval
            let main: Main
        }
        let list: [Slot]
    }

    /// OpenWeather /air_pollution/forecast payload: 3-hourly slots, each with a Unix
    /// `dt` and a `components` block carrying PM2.5 concentration (µg/m³).
    struct AirPollutionResponse: Codable {
        struct Slot: Codable {
            struct Components: Codable {
                let pm2_5: Double
            }
            let dt: TimeInterval
            let components: Components
        }
        let list: [Slot]
    }

    deinit {
        // Cancel any pending tasks
        currentAtmosphericTask?.cancel()

        // Cancel Combine subscriptions
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}

// Location service extracted to its own class for better separation of concerns
class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocationCoordinate2D?
    /// Where `currentLocation` came from. Default `.fabricated` so an un-set state
    /// is untrusted (safe default); every real assignment stamps it via `apply(_:provenance:)`.
    @Published private(set) var provenance: LocationProvenance = .fabricated
    private var timeoutTask: Task<Void, Never>?

    // Add location caching
    @AppStorage("lastKnownLatitude") private var cachedLatitude: Double?
    @AppStorage("lastKnownLongitude") private var cachedLongitude: Double?
    /// Epoch of the last DEVICE fix, persisted alongside the cached lat/lon so the
    /// cache's age is knowable. Nil until a device fix has ever landed.
    @AppStorage("lastKnownLocationAt") private var cachedLocationAtEpoch: Double = 0

    var cachedLocationAt: Date? { cachedLocationAtEpoch == 0 ? nil : Date(timeIntervalSince1970: cachedLocationAtEpoch) }

    /// App-level authorization, mapped from the private `CLLocationManager`.
    var authorization: EnvironmentLocationAuthorization {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return .authorized
        case .denied:      return .denied
        case .restricted:  return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:  return .notDetermined
        }
    }

    /// Single choke point for setting `currentLocation` with its provenance, so no
    /// call site can set the coordinate without also declaring where it came from.
    private func apply(_ coordinate: CLLocationCoordinate2D?, provenance: LocationProvenance) {
        self.currentLocation = coordinate
        self.provenance = provenance
    }
    
    // Add these tracking variables to reduce logging
    private var hasLoggedPermissionRequest = false
    private var hasLoggedPermissionDenied = false
    private var lastLoggedLocation: CLLocationCoordinate2D?
    private let significantDistanceThreshold: Double = 100 // in meters
    private var isDashboardActive = false
    private var appStateObserver: AnyCancellable?
    private var refreshTimer: Timer?
    private var lastLocationUpdateTime: Date?
    
    var lastKnownLocation: CLLocationCoordinate2D? {
        guard let lat = cachedLatitude, let lon = cachedLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    override init() {
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
        locationManager.distanceFilter = 100 // Only update when moved 100m
        
        // Only request location if we haven't shown the alert before
        if !UserDefaults.standard.bool(forKey: "hasShownLocationAlert") {
            switch locationManager.authorizationStatus {
                case .authorizedWhenInUse, .authorizedAlways:
                    requestLocationUpdate(silent: true) // Silent initial request
                case .notDetermined:
                    if !hasLoggedPermissionRequest {
                        hasLoggedPermissionRequest = true
                    }
                    locationManager.requestWhenInUseAuthorization()
                default:
                    startLocationUpdatesWhenAppIsActive()
            }
        }
        
        NotificationCenter.default.addObserver(self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    private func setupAppStateObserving() {
        appStateObserver = NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.locationManager.stopUpdatingLocation()
                self?.refreshTimer?.invalidate()
                self?.refreshTimer = nil
                Logger.debug("App in background - stopping location updates", category: .location)
            }
    }
    
    func setDashboardActive(_ active: Bool) {
        let wasActive = isDashboardActive
        isDashboardActive = active
        
        if active && !wasActive {
            // Dashboard became active - request location if stale
            let timeSinceLastUpdate = Date().timeIntervalSince(lastLocationUpdateTime ?? .distantPast)
            if timeSinceLastUpdate > 300 { // 5 minutes
                requestLocationUpdate(silent: true)
            }
            
            // Start periodic refresh timer for when dashboard is active
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
                Logger.debug("Periodic location refresh timer fired", category: .location)
                self?.requestLocationUpdate(silent: true)
            }
        } else if !active && wasActive {
            // Dashboard inactive - suspend continuous updates
            locationManager.stopUpdatingLocation()
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    
    func requestLocationUpdate(silent: Bool = false) {
        if !silent {
        }
        locationManager.stopUpdatingLocation()
        
        // Check current authorization status first
        let status = locationManager.authorizationStatus
        if status == .denied || status == .restricted {
            if !hasLoggedPermissionDenied {
                hasLoggedPermissionDenied = true
            }
            handleLocationPermissionDenied()
            return
        }
        
        // Cancel existing timeout task
        timeoutTask?.cancel()
        
        // Create new timeout task
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 second timeout
            if !Task.isCancelled && currentLocation == nil {
                await MainActor.run {
                    // Use cached location if available
                    if let cached = lastKnownLocation {
                        self.apply(cached, provenance: .cached)
                    } else {
                        // Fallback to a default location if we've never had one
                        if !silent {
                        }
                        self.apply(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), provenance: .fabricated) // NYC as fallback
                    }
                }
            }
        }
        
        locationManager.requestLocation()
    }
    
    private func handleLocationPermissionDenied() {
        Task {
            await MainActor.run {
                // Try to use cached location first
                if let cached = lastKnownLocation {
                    self.apply(cached, provenance: .cached)
                } else {
                    // Use fallback location
                    self.apply(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), provenance: .fabricated) // NYC as fallback
                }
            }
        }
    }
    
    @objc private func appDidEnterBackground() {
        locationManager.stopUpdatingLocation()
        timeoutTask?.cancel()
    }
    
    func startLocationUpdatesWhenAppIsActive() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        requestLocationUpdate()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        // Cancel timeout task since we got a location
        timeoutTask?.cancel()
        timeoutTask = nil
        
        // Add a timestamp check to limit frequency
           let lastRequestTime = UserDefaults.standard.object(forKey: "lastLocationRequestTime") as? Date ?? Date.distantPast
           let now = Date()
           
           // Only request location if it's been at least 5 minutes since last request
           if now.timeIntervalSince(lastRequestTime) > 300 {
               requestLocationUpdate()
               UserDefaults.standard.set(now, forKey: "lastLocationRequestTime")
           } else {
           }
       
        // Calculate distance from last logged location
        let shouldLog: Bool
        if let lastLocation = lastLoggedLocation {
            let lastLocationObj = CLLocation(latitude: lastLocation.latitude, longitude: lastLocation.longitude)
            let distance = lastLocationObj.distance(from: newLocation)
            shouldLog = distance > significantDistanceThreshold
        } else {
            // Always log the first location
            shouldLog = true
        }
        
        DispatchQueue.main.async {
            self.apply(newLocation.coordinate, provenance: .device)

            // Cache the location
            self.cachedLatitude = newLocation.coordinate.latitude
            self.cachedLongitude = newLocation.coordinate.longitude
            self.cachedLocationAtEpoch = Date().timeIntervalSince1970

            // Only log if it's a significant change
            if shouldLog {
                self.lastLoggedLocation = newLocation.coordinate
            }
            
            // Stop further location updates
            self.locationManager.stopUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                if !hasLoggedPermissionDenied {
                    Logger.warning("Location access denied. Prompting user to enable permissions.", category: .location)
                    hasLoggedPermissionDenied = true
                }
                Task { @MainActor in
                    await self.handleLocationDenied()
                }
            default:
                Logger.error("Location Error: \(clError.localizedDescription)", category: .location)
            }
        }
    }
    
    @MainActor
    private func handleLocationDenied() async {
        await MainActor.run {
            // Use a cached location if available
            if let cachedLat = cachedLatitude, let cachedLon = cachedLongitude {
                self.apply(CLLocationCoordinate2D(latitude: cachedLat, longitude: cachedLon), provenance: .cached)
            } else {
                // Use a default fallback location (NYC)
                self.apply(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), provenance: .fabricated)
            }
            
            // Persist that we've handled location denial
            UserDefaults.standard.set(true, forKey: "hasHandledLocationDenial")
            
            // Post notification for UI to update
            NotificationCenter.default.post(
                name: Notification.Name("LocationPermissionStatus"),
                object: ["status": "denied"]
            )
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            requestLocationUpdate()
        case .denied, .restricted:
            if !hasLoggedPermissionDenied {
                Logger.warning("Location access denied. Using alternative data source.", category: .location)
                hasLoggedPermissionDenied = true
            }
            Task { @MainActor in
                // Use cached location if available or a reasonable default
                if let cachedLat = cachedLatitude, let cachedLon = cachedLongitude {
                    apply(CLLocationCoordinate2D(latitude: cachedLat, longitude: cachedLon), provenance: .cached)
                } else {
                    // Use a default location (NYC) as absolute fallback
                    apply(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), provenance: .fabricated)
                }
                
                // Rather than show an intrusive alert, use a non-blocking notification
                NotificationCenter.default.post(name: Notification.Name("LocationAccessDenied"), object: nil)
            }
        case .notDetermined:
            if !hasLoggedPermissionRequest {
                Logger.debug("Location permission not determined.", category: .location)
                hasLoggedPermissionRequest = true
            }
            // Only request once
            if !UserDefaults.standard.bool(forKey: "hasRequestedLocation") {
                locationManager.requestWhenInUseAuthorization()
                UserDefaults.standard.set(true, forKey: "hasRequestedLocation")
            }
        @unknown default:
            break
        }
    }
    
    deinit {
        // Cancel any pending tasks
        timeoutTask?.cancel()

        // Invalidate timer
        refreshTimer?.invalidate()
        refreshTimer = nil

        // Cancel Combine subscription
        appStateObserver?.cancel()

        // Stop location updates and clear delegate
        locationManager.stopUpdatingLocation()
        locationManager.delegate = nil

        // Remove all notification observers
        NotificationCenter.default.removeObserver(self)
    }
}
