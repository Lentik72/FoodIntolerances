import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

/// One Call 3.0 day_summary fetch: URL shape, decode (incl. optional afternoon
/// humidity), absence vs fetch-error discipline, and auth-failure degradation.
struct WeatherHistoryTests {

    private struct StubTransport: HTTPTransport {
        let payload: Data
        let makeError: Bool
        let statusCode: Int?                    // nil → plain URLResponse (no HTTP status)
        let requestedURLs: URLBox
        init(payload: Data, makeError: Bool = false, statusCode: Int? = nil, requestedURLs: URLBox = URLBox()) {
            self.payload = payload; self.makeError = makeError; self.statusCode = statusCode; self.requestedURLs = requestedURLs
        }
        final class URLBox: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var urls: [URL] = []
            func append(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        }
        func data(from url: URL) async throws -> (Data, URLResponse) {
            requestedURLs.append(url)
            if makeError { throw URLError(.timedOut) }
            let response: URLResponse = statusCode.map {
                HTTPURLResponse(url: url, statusCode: $0, httpVersion: nil, headerFields: nil)!
            } ?? URLResponse(url: url, mimeType: "application/json", expectedContentLength: payload.count, textEncodingName: "utf-8")
            return (payload, response)
        }
    }
    private struct StubLocation: LocationProviding {
        var coordinate: CLLocationCoordinate2D?
        var authorization: EnvironmentLocationAuthorization = .authorized
    }
    private func ensureTestAPIKeyConfigured() { setenv("OPENWEATHER_API_KEY", "test-key", 1) }
    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func makeService(payload: Data, makeError: Bool = false) -> EnvironmentalDataService {
        ensureTestAPIKeyConfigured()
        return EnvironmentalDataService(
            transport: StubTransport(payload: payload, makeError: makeError),
            calendar: utcCalendar,
            location: StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)))
    }
    private let day = Date(timeIntervalSince1970: 1_750_000_000)   // 2025-06-15 UTC

    // MARK: - URL builder

    @Test func daySummaryURLUsesOneCallBaseDateAndEncodedTZ() throws {
        ensureTestAPIKeyConfigured()
        let url = try #require(APIConfig.oneCallDaySummaryURL(latitude: 40.0, longitude: -74.0,
                                                              date: "2025-06-15", tz: "+00:00"))
        let s = url.absoluteString
        #expect(s.contains("/data/3.0/onecall/day_summary"))
        #expect(s.contains("date=2025-06-15"))
        #expect(s.contains("tz=%2B00:00"))            // "+" must be percent-encoded
        #expect(s.contains("units=metric"))
        #expect(s.contains("lat=40.0") && s.contains("lon=-74.0"))
        let negative = try #require(APIConfig.oneCallDaySummaryURL(latitude: 40.0, longitude: -74.0,
                                                                   date: "2025-01-15", tz: "-08:00"))
        #expect(negative.absoluteString.contains("tz=-08:00"))   // "-" needs no encoding
    }

    // MARK: - fetchCompletedWeatherDay

    @Test func decodesHighLowAndAfternoonHumidity() async {
        let json = #"{"temperature":{"min":12.3,"max":24.6},"humidity":{"afternoon":64.0}}"#
        let result = await makeService(payload: Data(json.utf8)).fetchCompletedWeatherDay(for: day)
        #expect(result == .value(highC: 24.6, lowC: 12.3, humidityPct: 64.0))
    }
    @Test func missingAfternoonHumidityYieldsNilHumidityNotAbsent() async {
        let json = #"{"temperature":{"min":12.3,"max":24.6},"humidity":{}}"#
        let result = await makeService(payload: Data(json.utf8)).fetchCompletedWeatherDay(for: day)
        #expect(result == .value(highC: 24.6, lowC: 12.3, humidityPct: nil))
    }
    @Test func missingTemperatureIsAbsentNotError() async {
        let json = #"{"humidity":{"afternoon":64.0}}"#
        let result = await makeService(payload: Data(json.utf8)).fetchCompletedWeatherDay(for: day)
        #expect(result == .absent)
    }
    @Test func transportErrorIsFetchError() async {
        let result = await makeService(payload: Data(), makeError: true).fetchCompletedWeatherDay(for: day)
        #expect(result == .fetchError(.offline))
    }
    @Test func malformedPayloadIsFetchError() async {
        let result = await makeService(payload: Data("not json".utf8)).fetchCompletedWeatherDay(for: day)
        #expect(result == .fetchError(.badResponse))
    }
    /// A One Call 401 (subscription not active) returns a JSON error body — not a
    /// throw. It must decode-fail into .fetchError, never be mistaken for absence.
    @Test func authErrorBodyIsFetchError() async {
        let json = #"{"cod":401,"message":"Please note that using One Call 3.0 requires a separate subscription"}"#
        let result = await makeService(payload: Data(json.utf8)).fetchCompletedWeatherDay(for: day)
        #expect(result == .fetchError(.rejected))
    }
    /// The tz offset is DATE-specific from the injected calendar and anchored at
    /// local NOON: plain PST/PDT days get their standard offsets, and on the DST
    /// transition days themselves the AFTERNOON offset wins (the midnight offset
    /// differs there — the noon anchor is what matches humidity.afternoon).
    @Test func fetchPassesNoonAnchoredCalendarTZOffset() async throws {
        ensureTestAPIKeyConfigured()
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let box = StubTransport.URLBox()
        let json = #"{"temperature":{"min":1.0,"max":2.0},"humidity":{"afternoon":50.0}}"#
        let service = EnvironmentalDataService(
            transport: StubTransport(payload: Data(json.utf8), requestedURLs: box),
            calendar: la,
            location: StubLocation(coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -118.0)))
        for (m, d) in [(1, 15), (7, 15), (3, 9), (11, 2)] {
            _ = await service.fetchCompletedWeatherDay(for: la.date(from: DateComponents(year: 2025, month: m, day: d))!)
        }
        let urls = box.urls.map(\.absoluteString)
        #expect(urls.count == 4)
        #expect(urls[0].contains("date=2025-01-15") && urls[0].contains("tz=-08:00"))   // PST
        #expect(urls[1].contains("date=2025-07-15") && urls[1].contains("tz=-07:00"))   // PDT
        #expect(urls[2].contains("date=2025-03-09") && urls[2].contains("tz=-07:00"))   // spring-forward day: noon is PDT
        #expect(urls[3].contains("date=2025-11-02") && urls[3].contains("tz=-08:00"))   // fall-back day: noon is PST
    }

    @Test func noLocationIsFetchError() async {
        ensureTestAPIKeyConfigured()
        let service = EnvironmentalDataService(
            transport: StubTransport(payload: Data(), makeError: false),
            calendar: utcCalendar, location: StubLocation(coordinate: nil))
        let result = await service.fetchCompletedWeatherDay(for: day)
        #expect(result == .fetchError(.locationUnavailable))
    }

    @Test func httpRejectionStatusIsRejectedBeforeDecode() async {
        // 401 with a body that would otherwise decode to .absent — status wins.
        ensureTestAPIKeyConfigured()
        let svc = EnvironmentalDataService(
            transport: StubTransport(payload: Data(#"{"humidity":{"afternoon":64.0}}"#.utf8), statusCode: 401),
            calendar: utcCalendar,
            location: StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -74)))
        #expect(await svc.fetchCompletedWeatherDay(for: day) == .fetchError(.rejected))
    }
    @Test func postTransportCancellationReturnsCancelled() async {
        // A transport that cancels its OWN calling task, then returns a clean 200 — no
        // throw, so only the post-transport `Task.isCancelled` guard can catch it (Fix 4).
        struct SelfCancellingTransport: HTTPTransport {
            let payload: Data
            func data(from url: URL) async throws -> (Data, URLResponse) {
                withUnsafeCurrentTask { $0?.cancel() }
                return (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        ensureTestAPIKeyConfigured()
        let json = #"{"temperature":{"min":12.3,"max":24.6},"humidity":{"afternoon":64.0}}"#
        let svc = EnvironmentalDataService(
            transport: SelfCancellingTransport(payload: Data(json.utf8)),
            calendar: utcCalendar,
            location: StubLocation(coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -74)))
        #expect(await svc.fetchCompletedWeatherDay(for: day) == .cancelled)   // clean transport+decode, bailed at the guard
    }
}
