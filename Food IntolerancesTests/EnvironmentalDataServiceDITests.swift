import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

/// Smoke tests for the dependency-injection seams added to
/// `EnvironmentalDataService` (transport / clock / calendar / location).
/// Exercises `fetchDailyForecast()` specifically because — unlike
/// `fetchAtmosphericPressure()` — it does its work directly on the calling
/// task rather than spawning a detached, self-cancelling inner `Task`; awaiting
/// it is deterministic. (`fetchAtmosphericPressure`'s fire-and-forget structure
/// is left alone here and fixed in a later task.)
struct EnvironmentalDataServiceDITests {
    private struct StubTransport: HTTPTransport {
        let payload: Data
        func data(from url: URL) async throws -> (Data, URLResponse) {
            let response = URLResponse(url: url, mimeType: "application/json",
                                        expectedContentLength: payload.count, textEncodingName: "utf-8")
            return (payload, response)
        }
    }

    private struct StubLocation: LocationProviding {
        var coordinate: CLLocationCoordinate2D?
        var authorization: EnvironmentLocationAuthorization = .authorized
    }

    /// `APIConfig.forecastURL` (like `weatherURL`/`airPollutionURL`) returns nil
    /// — and the fetch never reaches `transport` — unless an API key is
    /// configured. `APIConfig` explicitly supports `OPENWEATHER_API_KEY` via the
    /// process environment "for CI/testing"; set it so these seam tests reach
    /// the transport call instead of short-circuiting on the URL guard.
    private func ensureTestAPIKeyConfigured() {
        setenv("OPENWEATHER_API_KEY", "di-smoke-test-key", 1)
    }

    /// OpenWeather /forecast-shaped JSON with three 3-hourly slots starting at `base`.
    private func forecastJSON(base: TimeInterval) -> Data {
        let json = """
        {"list":[
          {"dt": \(base), "main": {"temp": 10, "humidity": 40}},
          {"dt": \(base + 3600), "main": {"temp": 24, "humidity": 60}},
          {"dt": \(base + 7200), "main": {"temp": 6, "humidity": 80}}
        ]}
        """
        return Data(json.utf8)
    }

    @Test func fetchDailyForecastRoutesThroughInjectedTransportAndLocation() async {
        ensureTestAPIKeyConfigured()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let transport = StubTransport(payload: forecastJSON(base: now.timeIntervalSince1970))
        let location = StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0))

        let service = EnvironmentalDataService(transport: transport, now: { now }, location: location)
        await service.fetchDailyForecast()

        #expect(service.forecastHighC == 24)
        #expect(service.forecastLowC == 6)
        #expect(service.forecastHumidity == 60)
    }

    /// Same stubbed slots, but the injected clock places "now" ten days later, so
    /// every slot falls outside the next-24h window. If the fetch were still
    /// reading the wall clock instead of the injected `now`, this would flake
    /// depending on when the test happened to run — proof the clock seam is wired.
    @Test func fetchDailyForecastUsesInjectedClockForWindowing() async {
        ensureTestAPIKeyConfigured()
        let slotBase = Date(timeIntervalSince1970: 1_000_000).timeIntervalSince1970
        let farFutureNow = Date(timeIntervalSince1970: slotBase + 10 * 86_400)
        let transport = StubTransport(payload: forecastJSON(base: slotBase))
        let location = StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0))

        let service = EnvironmentalDataService(transport: transport, now: { farFutureNow }, location: location)
        await service.fetchDailyForecast()

        #expect(service.forecastHighC == nil)
        #expect(service.forecastLowC == nil)
        #expect(service.forecastHumidity == nil)
    }

    /// No location seam injected and no coordinate available anywhere → the
    /// fetch takes the "no location" branch without touching the network.
    @Test func fetchDailyForecastWithNoLocationLeavesForecastNil() async {
        let transport = StubTransport(payload: forecastJSON(base: 1_000_000))
        let location = StubLocation(coordinate: nil)

        let service = EnvironmentalDataService(transport: transport, now: { Date(timeIntervalSince1970: 1_000_000) }, location: location)
        await service.fetchDailyForecast()

        #expect(service.forecastHighC == nil)
        #expect(service.forecastLowC == nil)
        #expect(service.forecastHumidity == nil)
    }

    @Test func productionDefaultsStillConstruct() {
        // Behavior-preservation check: the defaulted init (no seams supplied)
        // still builds a usable instance, matching pre-DI call sites like
        // `EnvironmentalDataService()` / `EnvironmentalDataService(locationManager:)`.
        _ = EnvironmentalDataService()
    }
}
