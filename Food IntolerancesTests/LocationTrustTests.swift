import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

struct LocationTrustTests {
    private let device = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)   // London
    private let cached = CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35)   // Paris
    private let manual = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0)   // Tokyo
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let freshness: TimeInterval = 300

    private func trusted(provenance: LocationProvenance,
                         cachedAt: Date?,
                         authorization: EnvironmentLocationAuthorization,
                         manual: CLLocationCoordinate2D? = nil) -> CLLocationCoordinate2D? {
        LocationTrust.trustedCoordinate(
            manual: manual, provenance: provenance,
            deviceCoordinate: device, cachedCoordinate: cached, cachedAt: cachedAt,
            authorization: authorization, now: now, freshness: freshness)
    }

    @Test func deviceProvenanceTrustedWhenAuthorized() {
        #expect(trusted(provenance: .device, cachedAt: nil, authorization: .authorized)?.latitude == device.latitude)
    }
    @Test func deviceRejectedWhenDenied() {
        // Between authorization flipping to denied and the async fallback re-stamping
        // provenance to .fabricated/.cached, a stale .device coordinate must NOT be
        // trusted — otherwise `locationDenied` stays masked.
        #expect(trusted(provenance: .device, cachedAt: nil, authorization: .denied) == nil)
    }
    @Test func deviceRejectedWhenRestricted() {
        #expect(trusted(provenance: .device, cachedAt: nil, authorization: .restricted) == nil)
    }
    @Test func fabricatedIsNeverTrusted() {
        #expect(trusted(provenance: .fabricated, cachedAt: now, authorization: .authorized) == nil)
    }
    @Test func cachedTrustedWhenAuthorizedAndFresh() {
        let at = now.addingTimeInterval(-120)   // 2 min old
        #expect(trusted(provenance: .cached, cachedAt: at, authorization: .authorized)?.latitude == cached.latitude)
    }
    @Test func cachedRejectedWhenStale() {
        let at = now.addingTimeInterval(-600)   // 10 min old
        #expect(trusted(provenance: .cached, cachedAt: at, authorization: .authorized) == nil)
    }
    @Test func cachedRejectedWhenDeniedEvenIfFresh() {
        let at = now.addingTimeInterval(-10)
        #expect(trusted(provenance: .cached, cachedAt: at, authorization: .denied) == nil)
    }
    @Test func cachedRejectedWhenTimestampMissing() {
        #expect(trusted(provenance: .cached, cachedAt: nil, authorization: .authorized) == nil)
    }
    @Test func manualWinsOverFabricatedAndStaleCache() {
        #expect(trusted(provenance: .fabricated, cachedAt: nil, authorization: .denied, manual: manual)?.latitude == manual.latitude)
    }
    @Test func failureCodableRoundTripsTimezone() throws {
        let f = EnvironmentFailure(at: now, reason: .rejected,
                                   scopeStart: now, scopeEnd: now, timezoneID: "America/Los_Angeles")
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(EnvironmentFailure.self, from: data)
        #expect(back == f)
        #expect(back.timezoneID == "America/Los_Angeles")
    }
}
