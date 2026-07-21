// Dependency-injection seams for EnvironmentalDataService: an injectable network
// transport and an injectable location source. Production code paths default to
// the real URLSession / LocationService behavior; tests substitute stubs so
// fetches can be exercised deterministically without hitting the network or
// CoreLocation.

import Foundation
import CoreLocation

/// Minimal async networking seam. `URLSession` already implements
/// `data(from:)` with this exact signature, so conformance is free.
public protocol HTTPTransport: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

/// Injectable location source so location-dependent fetches (pressure, daily
/// forecast, air quality) can be tested with a fixed coordinate instead of
/// depending on CoreLocation / the real LocationService.
public protocol LocationProviding {
    var coordinate: CLLocationCoordinate2D? { get }
}
