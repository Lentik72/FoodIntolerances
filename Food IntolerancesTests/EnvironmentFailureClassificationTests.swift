import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

@MainActor
struct EnvironmentFailureClassificationTests {
    private func store() -> EnvironmentStatusStore { EnvironmentStatusStore(defaults: UserDefaults(suiteName: "t." + UUID().uuidString)!) }
    private func key() { setenv("OPENWEATHER_API_KEY", "cls-test-key", 1) }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private struct StatusTransport: HTTPTransport {
        let payload: Data
        let status: Int?          // nil → plain URLResponse (no HTTP status)
        let error: Error?
        func data(from url: URL) async throws -> (Data, URLResponse) {
            if let error { throw error }
            let response: URLResponse = status.map {
                HTTPURLResponse(url: url, statusCode: $0, httpVersion: nil, headerFields: nil)!
            } ?? URLResponse(url: url, mimeType: "application/json", expectedContentLength: payload.count, textEncodingName: "utf-8")
            return (payload, response)
        }
    }
    private struct StubLocation: LocationProviding {
        var coordinate: CLLocationCoordinate2D?
        var authorization: EnvironmentLocationAuthorization = .authorized
    }
    private func forecastJSON(_ base: TimeInterval, slots: Int = 3) -> Data {
        let items = (0..<slots).map { #"{"dt": \#(base + Double($0) * 3600), "main": {"temp": 12, "humidity": 50}}"# }
        return Data(("{\"list\":[" + items.joined(separator: ",") + "]}").utf8)
    }

    @Test func forecast401RecordsRejected() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: Data("{}".utf8), status: 401, error: nil),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure?.reason == .rejected)
    }
    @Test func forecastOfflineRecordsOffline() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: Data(), status: nil, error: URLError(.notConnectedToInternet)),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure?.reason == .offline)
    }
    @Test func forecastThinResponseRecordsInsufficientDataScopedToday() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: forecastJSON(self.at.timeIntervalSince1970, slots: 2), status: 200, error: nil),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        let f = s.statuses[.forecastWeather]?.liveFailure
        #expect(f?.reason == .insufficientData)
        #expect(f?.scopeStart == utc.startOfDay(for: at))
        #expect(f?.scopeEnd == utc.startOfDay(for: at))
        // Assert against the calendar's own identifier rather than a hardcoded
        // "UTC": modern Foundation normalizes TimeZone(identifier: "UTC") so its
        // `.identifier` reads back as "GMT" (same zone). `todayScope()` records
        // exactly `calendar.timeZone.identifier`, so this matches on any Foundation.
        #expect(f?.timezoneID == utc.timeZone.identifier)
    }
    @Test func forecastSuccessRecordsSuccessAndClearsLive() async {
        key()
        let s = store()
        s.recordFailure(.forecastWeather, reason: .offline, scopeStart: at, scopeEnd: at, timezoneID: "UTC", at: at)
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: forecastJSON(self.at.timeIntervalSince1970), status: 200, error: nil),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure == nil)
        #expect(s.statuses[.forecastWeather]?.lastSuccess == at)
    }
    @Test func forecastDeniedLocationRecordsLocationDenied() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: Data(), status: nil, error: nil),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: nil, authorization: .denied), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure?.reason == .locationDenied)
    }
    @Test func forecastUnavailableLocationRecordsLocationUnavailable() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: Data(), status: nil, error: nil),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: nil, authorization: .authorized), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure?.reason == .locationUnavailable)
    }
    // NOTE: `.notConfigured` (URL-nil) is intentionally NOT unit-tested. Forcing the
    // URL to nil requires the API key to be absent, but `APIConfig.openWeatherAPIKey`
    // reads the built bundle's Info.plist FIRST — which carries a real key whenever
    // Secrets.xcconfig is present — so `setenv("…","")` can't reliably force nil. The
    // `.notConfigured` code path (URL guard → recordTodayFailure) is trivial and is
    // confirmed by the device pass (a keyless build shows the marker + Health reason).
    @Test func forecastThrownCancellationRecordsNothing() async {
        key()
        let s = store()
        let svc = EnvironmentalDataService(transport: StatusTransport(payload: Data(), status: nil, error: URLError(.cancelled)),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather] == nil)   // no write at all
    }
    @Test func forecastPostTransportCancellationRecordsNothing() async {
        // Transport returns a CLEAN 3-slot 200 (no throw) but cancels its own calling
        // task → the post-transport Task.isCancelled guard must bail before publishing
        // or recording success (Fix 4). A pre-set failure must survive (not be cleared).
        struct SelfCancellingTransport: HTTPTransport {
            let payload: Data
            func data(from url: URL) async throws -> (Data, URLResponse) {
                withUnsafeCurrentTask { $0?.cancel() }
                return (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        key()
        let s = store()
        s.recordFailure(.forecastWeather, reason: .offline, scopeStart: at, scopeEnd: at, timezoneID: "UTC", at: at)
        let svc = EnvironmentalDataService(transport: SelfCancellingTransport(payload: forecastJSON(self.at.timeIntervalSince1970)),
            now: { self.at }, calendar: utc, location: StubLocation(coordinate: .init(latitude: 40, longitude: -74)), statusStore: s)
        await svc.fetchDailyForecast()
        #expect(s.statuses[.forecastWeather]?.liveFailure?.reason == .offline)   // pre-set failure NOT cleared
    }
}
