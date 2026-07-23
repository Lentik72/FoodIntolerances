import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

/// Orchestration tests for `EnvironmentalDataService.fetchAllData()`.
///
/// The #1 regression these guard against: `fetchAtmosphericPressure()` used to
/// cancel the shared `currentAtmosphericTask`, which — during `fetchAllData()` —
/// self-cancelled the very refresh task that was awaiting it. The subsequent
/// `if !Task.isCancelled` gates then skipped the forecast + air-quality fetches,
/// so a single `fetchAllData()` populated (at best) pressure but never
/// `forecastHighC` / `forecastAQI`.
///
/// A single `await fetchAllData()` must reach all three endpoints. The child
/// fetches are independent: any one failing must not suppress the other two.
struct EnvironmentalOrchestrationTests {

    /// Routes each request to the correct canned payload by inspecting the URL
    /// path (`/air_pollution/forecast`, `/forecast`, `/weather`). Endpoints named
    /// in `failing` throw instead of answering, so independent-failure isolation
    /// can be exercised without touching the network.
    private struct RoutingStubTransport: HTTPTransport {
        enum Endpoint: Sendable { case weather, forecast, airPollution }
        struct StubError: Error {}

        let weather: Data
        let forecast: Data
        let airPollution: Data
        var failing: Set<Endpoint> = []

        func endpoint(for url: URL) -> Endpoint {
            let s = url.absoluteString
            if s.contains("air_pollution") { return .airPollution }
            if s.contains("/forecast") { return .forecast }
            return .weather
        }

        func data(from url: URL) async throws -> (Data, URLResponse) {
            let ep = endpoint(for: url)
            if failing.contains(ep) { throw StubError() }
            let payload: Data
            switch ep {
            case .weather: payload = weather
            case .forecast: payload = forecast
            case .airPollution: payload = airPollution
            }
            let response = URLResponse(url: url, mimeType: "application/json",
                                       expectedContentLength: payload.count, textEncodingName: "utf-8")
            return (payload, response)
        }
    }

    private struct StubLocation: LocationProviding {
        var coordinate: CLLocationCoordinate2D?
        var authorization: EnvironmentLocationAuthorization = .authorized
    }

    /// `APIConfig.*URL()` returns nil — and the transport is never reached —
    /// unless an API key is configured. Set the documented `OPENWEATHER_API_KEY`
    /// process-environment hook so `fetchAllData` reaches the stub transport
    /// instead of short-circuiting on the URL guards (which would make every
    /// assertion below vacuous).
    private func ensureTestAPIKeyConfigured() {
        setenv("OPENWEATHER_API_KEY", "test-key", 1)
    }

    /// A distinctive pressure (1021) so a real `/weather` fetch is provably
    /// distinguishable from the 1013 hPa fallback that fires on error.
    private func weatherJSON(pressure: Int = 1021) -> Data {
        Data("""
        {"main": {"pressure": \(pressure), "temp": 18, "humidity": 55}}
        """.utf8)
    }

    /// Three in-window 3-hourly slots → daily high 24 / low 6.
    private func forecastJSON(base: TimeInterval) -> Data {
        Data("""
        {"list":[
          {"dt": \(base), "main": {"temp": 10, "humidity": 40}},
          {"dt": \(base + 3600), "main": {"temp": 24, "humidity": 60}},
          {"dt": \(base + 7200), "main": {"temp": 6, "humidity": 80}}
        ]}
        """.utf8)
    }

    /// Three in-window 3-hourly air-pollution slots → a non-nil forecast AQI.
    private func airPollutionJSON(base: TimeInterval) -> Data {
        Data("""
        {"list":[
          {"dt": \(base), "components": {"pm2_5": 12.0}},
          {"dt": \(base + 3600), "components": {"pm2_5": 18.0}},
          {"dt": \(base + 7200), "components": {"pm2_5": 24.0}}
        ]}
        """.utf8)
    }

    private func makeService(now: Date,
                             failing: Set<RoutingStubTransport.Endpoint> = []) -> EnvironmentalDataService {
        let base = now.timeIntervalSince1970
        let transport = RoutingStubTransport(
            weather: weatherJSON(),
            forecast: forecastJSON(base: base),
            airPollution: airPollutionJSON(base: base),
            failing: failing
        )
        let location = StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0))
        return EnvironmentalDataService(transport: transport, now: { now }, location: location)
    }

    /// The #1 regression, RED before the fix: one `fetchAllData()` must populate
    /// pressure AND forecast AND forecast-AQI. Before the single-owner fix,
    /// `fetchAtmosphericPressure` self-cancelled the refresh, so `forecastHighC`
    /// and `forecastAQI` stayed nil.
    @Test func fetchAllDataPopulatesPressureForecastAndAQI() async {
        ensureTestAPIKeyConfigured()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let service = makeService(now: now)

        await service.fetchAllData()

        #expect(service.currentPressure == 1021)
        #expect(service.forecastHighC == 24)
        #expect(service.forecastLowC == 6)
        #expect(service.forecastAQI != nil)
    }

    /// Independent failure — `/weather` throws: pressure falls back, but the
    /// forecast and AQI fetches must still populate.
    @Test func weatherFailureDoesNotSuppressForecastOrAQI() async {
        ensureTestAPIKeyConfigured()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let service = makeService(now: now, failing: [.weather])

        await service.fetchAllData()

        #expect(service.forecastHighC == 24)
        #expect(service.forecastAQI != nil)
    }

    /// Independent failure — `/forecast` throws: pressure and AQI must still
    /// populate; only the forecast values stay nil.
    @Test func forecastFailureDoesNotSuppressPressureOrAQI() async {
        ensureTestAPIKeyConfigured()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let service = makeService(now: now, failing: [.forecast])

        await service.fetchAllData()

        #expect(service.currentPressure == 1021)
        #expect(service.forecastAQI != nil)
        #expect(service.forecastHighC == nil)
    }

    /// Independent failure — `/air_pollution/forecast` throws: pressure and
    /// forecast must still populate; only the AQI stays nil.
    @Test func aqiFailureDoesNotSuppressPressureOrForecast() async {
        ensureTestAPIKeyConfigured()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let service = makeService(now: now, failing: [.airPollution])

        await service.fetchAllData()

        #expect(service.currentPressure == 1021)
        #expect(service.forecastHighC == 24)
        #expect(service.forecastAQI == nil)
    }
}
