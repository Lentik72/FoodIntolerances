import CoreLocation
import SwiftUI

class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    private var locationRetryCount = 0
    private let maxRetries = 3

    @Published var userLocation: CLLocation?
    @Published var locationPermissionDenied = false
    @Published var showPermissionPrompt = false
    
    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocation() {
        let status = locationManager.authorizationStatus

        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // Stop requesting if denied; only show manual enable prompt
            if locationRetryCount >= 3 { return }
            locationPermissionDenied = true
            showPermissionPrompt = true
            locationRetryCount += 1
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        @unknown default:
            locationPermissionDenied = true
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            DispatchQueue.main.async {
                self.userLocation = location
                self.locationPermissionDenied = false
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .denied {
            locationPermissionDenied = true
            showPermissionPrompt = true
        } else {
            print("❌ Location error: \(error.localizedDescription)")
        }
    }
}
