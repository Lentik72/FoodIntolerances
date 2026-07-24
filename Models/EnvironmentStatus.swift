import Foundation
import CoreLocation

/// One environmental fetch that can fail independently of the others.
enum EnvironmentCapability: String, CaseIterable, Codable {
    case currentPressure, forecastWeather, forecastAirQuality
    case observedAirQuality, observedWeather
}

/// Why a fetch could not produce a usable value.
enum EnvironmentFailureReason: String, Codable {
    case notConfigured        // no API key in the build
    case rejected             // 401/403: key invalid/revoked, or One Call not subscribed
    case locationDenied       // authorization .denied / .restricted — user-fixable
    case locationUnavailable  // authorized/.notDetermined, or only a fabricated coord
    case offline              // URLError, excluding .cancelled
    case insufficientData     // 2xx, but the response held no usable value for the day
    case badResponse          // decode failure, unexpected shape, other HTTP error
}

/// A recorded failure and the day-range (in its own timezone) it blocked.
struct EnvironmentFailure: Codable, Equatable {
    let at: Date
    let reason: EnvironmentFailureReason
    let scopeStart: Date    // local start-of-day, inclusive
    let scopeEnd: Date      // local start-of-day, inclusive
    let timezoneID: String  // the calendar tz the scope was computed in
}

/// Per-capability health. `liveFailure` self-heals (drives the Timeline);
/// `lastFailure` is retained history (drives the Health "why").
struct EnvironmentCapabilityStatus: Codable, Equatable {
    var lastSuccess: Date?
    var liveFailure: EnvironmentFailure?
    var lastFailure: EnvironmentFailure?
}

/// Where `LocationService.currentLocation` came from — the fabricated NYC
/// fallback must never be ingested into the graph.
enum LocationProvenance { case device, cached, fabricated }

/// App-level mirror of `CLAuthorizationStatus`, so the injectable location seam
/// need not import CoreLocation's enum. Public: it appears in the public
/// `LocationProviding` protocol's requirements.
public enum EnvironmentLocationAuthorization { case denied, restricted, authorized, notDetermined }

/// Pure decision: the coordinate the graph is allowed to ingest, or nil if none
/// is trustworthy. Manual always wins; device always trusted; cached trusted
/// only when authorized AND fresh; fabricated never trusted.
enum LocationTrust {
    static func trustedCoordinate(
        manual: CLLocationCoordinate2D?,
        provenance: LocationProvenance,
        deviceCoordinate: CLLocationCoordinate2D?,
        cachedCoordinate: CLLocationCoordinate2D?,
        cachedAt: Date?,
        authorization: EnvironmentLocationAuthorization,
        now: Date,
        freshness: TimeInterval
    ) -> CLLocationCoordinate2D? {
        if let manual { return manual }                        // user-set: always trusted
        // Denied/restricted must never be masked by a still-.device provenance that
        // the async fallback hasn't overwritten yet. Reject every non-manual fix.
        if authorization == .denied || authorization == .restricted { return nil }
        switch provenance {
        case .device:
            return deviceCoordinate
        case .cached:
            guard authorization == .authorized,
                  let cachedCoordinate, let cachedAt,
                  now.timeIntervalSince(cachedAt) <= freshness else { return nil }
            return cachedCoordinate
        case .fabricated:
            return nil
        }
    }
}
