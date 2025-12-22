// Create a new file: EnvironmentalDataService.swift

import Foundation
import CoreLocation
import Combine
import SwiftUI
import UIKit

class EnvironmentalDataService: ObservableObject {
    // Published properties for UI updates
    @Published var atmosphericPressure: String = ""
    @Published var atmosphericPressureCategory: String = "Loading..."
    @Published var currentPressure: Double = 0.0
    @Published var previousPressure: Double = 0.0
    @Published var suddenPressureChange: Bool = false
    @Published var moonPhase: String = "Loading..."
    @Published var isMercuryRetrograde: Bool = false
    @Published var lastUpdated: Date = Date()
    @Published var showZipCodePrompt: Bool = false
    @Published private(set) var currentAtmosphericTask: Task<Void, Never>? = nil
    
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
    
    init(locationManager: LocationService? = nil) {
        if let locationManager = locationManager {
            self.locationManager = locationManager
        } else {
            // Create a new location service instance if none provided
            self.locationManager = LocationService()
        }
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
            await fetchMoonPhase(for: Date())
            self.isMercuryRetrograde = checkMercuryInRetrograde(for: Date())
            
            // Make sure we're not cancelled before proceeding with potentially expensive operations
            if !Task.isCancelled {
                // Fetch atmospheric pressure (most important data)
                await fetchAtmosphericPressure()
                
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
        
        // Cancel any existing fetch tasks
        currentAtmosphericTask?.cancel()
        currentAtmosphericTask = nil
    }
    
    func isMercuryRetrogradeApproaching(for date: Date) -> Bool {
        for period in MercuryRetrograde.periods {
            let daysUntilRetrograde = Calendar.current.dateComponents([.day], from: date, to: period.start).day ?? Int.max
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
    
    public func requestRefreshWithCooldown() async -> Bool {
        // Check if it's too soon for another refresh
        let now = Date()
        if now.timeIntervalSince(lastRefreshRequest) < minimumRefreshInterval {
            return false
        }
        
        lastRefreshRequest = now
        
        // Cancel current task if any
        currentAtmosphericTask?.cancel()
        
        // Perform the actual refresh
        await fetchAllData()
        
        return true
    }
    
    public func fetchAtmosphericPressure() async {
        print("🌦️ Starting atmospheric pressure fetch")

        // Cancel any existing task before starting a new one
        currentAtmosphericTask?.cancel()

        let newTask = Task {
            // Ensure UI updates immediately
            await MainActor.run {
                self.atmosphericPressureCategory = "Loading..."
            }

            // Delay to prevent UI flickering
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms debounce

            // Ensure task is not cancelled before proceeding
            if Task.isCancelled { return }
            
            // IMPORTANT: Add a timeout in case location is never available
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


            // Check if location is available
            let location: CLLocationCoordinate2D
            if let manualLoc = self.manualLocation {
                // Use manually set location (from refresh)
                location = manualLoc
            } else if let serviceLoc = self.locationManager?.currentLocation {
                // Use location from service
                location = serviceLoc
            } else {
                // No location available
                print("❌ No location available, using fallback pressure data.")
                timeoutTask.cancel() // Cancel timeout task first
                await MainActor.run { self.useFallbackPressureData() }
                return
            }

            guard let url = APIConfig.weatherURL(latitude: location.latitude, longitude: location.longitude) else {
                print("❌ Invalid URL for weather API")
                return
            }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decodedResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)

                let pressureValue = Double(decodedResponse.main.pressure)

                await MainActor.run {
                    self.updateAtmosphericPressure(pressureValue)
                    self.atmosphericPressure = "\(Int(pressureValue)) hPa"
                    self.atmosphericPressureCategory = self.categorizePressure(pressureValue)
                    self.lastUpdated = Date()
                }

            } catch {
                print("❌ Error fetching atmospheric pressure: \(error.localizedDescription)")
                await MainActor.run { self.useFallbackPressureData() }
            }
            
            timeoutTask.cancel()
            
        }

        currentAtmosphericTask = newTask
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
    
    private func updateAtmosphericPressure(_ pressure: Double) {
        let now = Date()
        
        // Special handling for first pressure reading
        if isFirstLoad {
            pressureReadings = [(pressure: pressure, timestamp: now)]
            currentPressure = pressure
            previousPressure = pressure
            atmosphericPressureCategory = categorizePressure(currentPressure)
            isFirstLoad = false
            return
        }
        
        // Add new reading and remove old ones
        pressureReadings.append((pressure: pressure, timestamp: now))
        pressureReadings = pressureReadings.filter {
            now.timeIntervalSince($0.timestamp) < 24 * 3600
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
        
        print("⚡ Sudden Change: \(suddenPressureChange)")
    }
    
    @MainActor
    public func setFallbackAtmosphericPressure() {
        // Check if we have any previous cached data first
        if let cachedPressure = UserDefaults.standard.object(forKey: "lastKnownPressure") as? Double {
            print("📊 Using cached pressure data: \(cachedPressure)")
            updateAtmosphericPressure(cachedPressure)
            self.atmosphericPressure = "\(Int(cachedPressure)) hPa"
            self.atmosphericPressureCategory = self.categorizePressure(cachedPressure)
            return
        }
        
        // If no cache, generate a realistic fallback with consistent random seed
        let calendar = Calendar.current
        let day = calendar.component(.day, from: Date())
        let month = calendar.component(.month, from: Date())
        
        // Use date components to seed a deterministic "random" value
        let seed = Double(day + month * 31) / 100.0
        let basePressure = 1013.0  // Standard sea level pressure
        let deterministicVariation = sin(seed * 6.28) * 10.0 // ±10 hPa variation
        let fallbackPressure = basePressure + deterministicVariation
        
        
        // Update the UI
        updateAtmosphericPressure(fallbackPressure)
        self.atmosphericPressure = "\(Int(fallbackPressure)) hPa"
        self.atmosphericPressureCategory = self.categorizePressure(fallbackPressure)
        
        // Cache this value for future fallbacks
        UserDefaults.standard.set(fallbackPressure, forKey: "lastKnownPressure")
    }

    // MARK: - Model for Weather Data

    struct WeatherResponse: Codable {
        struct Main: Codable {
            let pressure: Int
        }
        let main: Main
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
    private var timeoutTask: Task<Void, Never>?
    
    // Add location caching
    @AppStorage("lastKnownLatitude") private var cachedLatitude: Double?
    @AppStorage("lastKnownLongitude") private var cachedLongitude: Double?
    
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
                print("📱 App in background - stopping location updates")
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
                print("⏰ Periodic location refresh timer fired")
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
                        self.currentLocation = cached
                    } else {
                        // Fallback to a default location if we've never had one
                        if !silent {
                        }
                        self.currentLocation = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) // NYC as fallback
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
                    self.currentLocation = cached
                } else {
                    // Use fallback location
                    self.currentLocation = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) // NYC as fallback
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
            self.currentLocation = newLocation.coordinate
            
            // Cache the location
            self.cachedLatitude = newLocation.coordinate.latitude
            self.cachedLongitude = newLocation.coordinate.longitude
            
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
                    print("❌ Location access denied. Prompting user to enable permissions.")
                    hasLoggedPermissionDenied = true
                }
                Task { @MainActor in
                    await self.handleLocationDenied()
                }
            default:
                print("❌ Location Error: \(clError.localizedDescription)")
            }
        }
    }
    
    @MainActor
    private func handleLocationDenied() async {
        await MainActor.run {
            // Use a cached location if available
            if let cachedLat = cachedLatitude, let cachedLon = cachedLongitude {
                self.currentLocation = CLLocationCoordinate2D(latitude: cachedLat, longitude: cachedLon)
            } else {
                // Use a default fallback location (NYC)
                self.currentLocation = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
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
                print("❌ Location access denied. Using alternative data source.")
                hasLoggedPermissionDenied = true
            }
            Task { @MainActor in
                // Use cached location if available or a reasonable default
                if let cachedLat = cachedLatitude, let cachedLon = cachedLongitude {
                    currentLocation = CLLocationCoordinate2D(latitude: cachedLat, longitude: cachedLon)
                } else {
                    // Use a default location (NYC) as absolute fallback
                    currentLocation = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
                }
                
                // Rather than show an intrusive alert, use a non-blocking notification
                NotificationCenter.default.post(name: Notification.Name("LocationAccessDenied"), object: nil)
            }
        case .notDetermined:
            if !hasLoggedPermissionRequest {
                print("❓ Location permission not determined.")
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
