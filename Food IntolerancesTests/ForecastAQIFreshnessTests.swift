import Testing
import Foundation
import CoreLocation
@testable import Food_Intolerances

@MainActor
@Suite struct ForecastAQIFreshnessTests {
    let at = Date(timeIntervalSince1970: 1_700_000_000)

    struct StubTransport: HTTPTransport {
        let payload: Data; let status: Int?; let error: Error?
        func data(from url: URL) async throws -> (Data, URLResponse) {
            if let error { throw error }
            let response: URLResponse = status.map {
                HTTPURLResponse(url: url, statusCode: $0, httpVersion: nil, headerFields: nil)!
            } ?? URLResponse(url: url, mimeType: "application/json",
                             expectedContentLength: payload.count, textEncodingName: "utf-8")
            return (payload, response)
        }
    }
    struct StubLocation: LocationProviding {
        var coordinate: CLLocationCoordinate2D? = .init(latitude: 42, longitude: -71)
        var authorization: EnvironmentLocationAuthorization = .authorized
    }
    func svc(_ payload: Data, status: Int? = 200, error: Error? = nil,
             location: LocationProviding = StubLocation()) -> EnvironmentalDataService {
        // Sibling env tests do this: without a key, APIConfig.airPollutionURL is nil and
        // the fetch never reaches the stub transport (it hits the not-configured branch).
        setenv("OPENWEATHER_API_KEY", "freshness-test-key", 1)
        return EnvironmentalDataService(transport: StubTransport(payload: payload, status: status, error: error),
                                        now: { self.at }, location: location)
    }
    // ≥3 next-24h slots whose mean PM2.5 (~40 µg/m³) → EPA AQI ≥ 101.
    func poorAirJSON() -> Data {
        let base = Int(at.timeIntervalSince1970)
        let slots = (1...4).map { "{\"dt\": \(base + $0*3600), \"components\": {\"pm2_5\": 40.0}}" }
            .joined(separator: ",")
        return Data("{\"list\": [\(slots)]}".utf8)
    }

    @Test func startsPendingThenSettlesToValueOnHealthyFetch() async {
        let s = svc(poorAirJSON())
        #expect(s.forecastAQIState == .pending)               // initial
        await s.fetchAirQuality()
        if case .value(let aqi) = s.forecastAQIState { #expect(aqi >= 101) }
        else { Issue.record("expected .value, got \(s.forecastAQIState)") }
        #expect(s.forecastAQI == s.forecastAQIState.valueOrNil)   // both consistent
    }

    @Test func httpErrorSettlesUnavailableAndClearsValue() async {
        let s = svc(Data("{}".utf8), status: 401)
        await s.fetchAirQuality()
        #expect(s.forecastAQIState == .unavailable)
        #expect(s.forecastAQI == nil)
    }

    @Test func thrownErrorSettlesUnavailableAndClearsValue() async {
        let s = svc(Data(), status: nil, error: URLError(.notConnectedToInternet))
        await s.fetchAirQuality()
        #expect(s.forecastAQIState == .unavailable)
        #expect(s.forecastAQI == nil)
    }

    @Test func insufficientSlotsSettleUnavailable() async {
        // A clean 200 with only 1 slot → mean == nil → .unavailable, no value.
        let base = Int(at.timeIntervalSince1970)
        let oneSlot = Data("{\"list\": [{\"dt\": \(base + 3600), \"components\": {\"pm2_5\": 40.0}}]}".utf8)
        let s = svc(oneSlot)
        await s.fetchAirQuality()
        #expect(s.forecastAQIState == .unavailable)
        #expect(s.forecastAQI == nil)
    }

    @Test func noLocationSettlesUnavailableAndClearsValue() async {
        // The no-location branch — part of the P1 fix. StubLocation with a nil coordinate.
        let s = svc(poorAirJSON(), location: StubLocation(coordinate: nil))
        await s.fetchAirQuality()
        #expect(s.forecastAQIState == .unavailable)
        #expect(s.forecastAQI == nil)
    }

    @Test func cancelledPassDoesNotSettleToAStaleValue() async {
        // A pass whose transport self-cancels after a clean 200 bails at the post-transport
        // Task.isCancelled guard — it must NOT settle; state stays .pending for the superseding
        // pass to resolve (never a stale .value/.unavailable). Mirrors EnvironmentFailure-
        // ClassificationTests.SelfCancellingTransport.
        struct SelfCancellingTransport: HTTPTransport {
            let payload: Data
            func data(from url: URL) async throws -> (Data, URLResponse) {
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                withUnsafeCurrentTask { $0?.cancel() }        // cancel our own calling task
                return (payload, resp)
            }
        }
        setenv("OPENWEATHER_API_KEY", "freshness-test-key", 1)
        let s = EnvironmentalDataService(transport: SelfCancellingTransport(payload: poorAirJSON()),
                                         now: { self.at }, location: StubLocation())
        await s.fetchAirQuality()
        #expect(s.forecastAQIState == .pending)               // never settled to a stale value
    }

    @Test func stateFlipsToPendingWhileTransportSuspended() async {
        // Seed an OLD .value first (otherwise the service already starts .pending and the
        // assertion is not discriminating). While the transport is suspended, the state
        // must flip to .pending — an old value is never surfaced mid-flight.
        actor Latch {   // entry handshake + open-before-wait safe
            private var releaseCont: CheckedContinuation<Void, Never>?
            private var enteredCont: CheckedContinuation<Void, Never>?
            private var entered = false, released = false
            func enterAndWait() async {
                entered = true; enteredCont?.resume(); enteredCont = nil
                if !released { await withCheckedContinuation { releaseCont = $0 } }
            }
            func waitUntilEntered() async { if entered { return }; await withCheckedContinuation { enteredCont = $0 } }
            func open() { released = true; releaseCont?.resume(); releaseCont = nil }
        }
        struct GatedTransport: HTTPTransport {
            let latch: Latch; let payload: Data
            func data(from url: URL) async throws -> (Data, URLResponse) {
                await latch.enterAndWait()                    // suspend here (signals entry first)
                return (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        setenv("OPENWEATHER_API_KEY", "freshness-test-key", 1)
        let latch = Latch()
        let s = EnvironmentalDataService(transport: GatedTransport(latch: latch, payload: poorAirJSON()),
                                         now: { self.at }, location: StubLocation())
        s.forecastAQIState = .value(150)                      // seed a STALE value
        async let fetch: Void = s.fetchAirQuality()
        await latch.waitUntilEntered()                        // deterministic: transport is suspended
        #expect(s.forecastAQIState == .pending)               // flipped to pending despite the stale value
        await latch.open()
        await fetch
        if case .value = s.forecastAQIState {} else { Issue.record("should settle to .value after resume") }
    }

    @Test func acceptedFullRefreshPublishesPendingBeforeFirstEndpoint() async {
        // Step 4b: an ACCEPTED requestRefreshWithCooldown() marks AQI .pending at PASS START,
        // before pressure/forecast/AQI. fetchAllData() is SEQUENTIAL with fetchAirQuality LAST,
        // so blocking the FIRST endpoint (pressure) proves .pending is set before AQI even runs
        // — the tests that call fetchAirQuality() directly would NOT catch a missing pass-start
        // assignment.
        actor FirstLatch {   // blocks ONLY the first call; entry handshake; open-before-wait safe
            private var releaseCont, enteredCont: CheckedContinuation<Void, Never>?
            private var entered = false, released = false, calls = 0
            func enterOnFirstCall() async {
                calls += 1; guard calls == 1 else { return }
                entered = true; enteredCont?.resume(); enteredCont = nil
                if !released { await withCheckedContinuation { releaseCont = $0 } }
            }
            func waitUntilEntered() async { if entered { return }; await withCheckedContinuation { enteredCont = $0 } }
            func open() { released = true; releaseCont?.resume(); releaseCont = nil }
        }
        struct FirstCallGatedTransport: HTTPTransport {
            let latch: FirstLatch; let payload: Data
            func data(from url: URL) async throws -> (Data, URLResponse) {
                await latch.enterOnFirstCall()                // block only the first endpoint (pressure)
                return (payload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        setenv("OPENWEATHER_API_KEY", "freshness-test-key", 1)
        let latch = FirstLatch()
        let s = EnvironmentalDataService(transport: FirstCallGatedTransport(latch: latch, payload: poorAirJSON()),
                                         now: { self.at }, location: StubLocation())
        s.forecastAQIState = .value(150)                      // seed a STALE value
        async let refresh: Bool = s.requestRefreshWithCooldown(bypassCooldown: true)  // ACCEPTED refresh
        await latch.waitUntilEntered()                        // first endpoint (pressure) blocked; AQI has NOT run
        #expect(s.forecastAQIState == .pending)               // published at PASS START, before any endpoint settled
        await latch.open()
        _ = await refresh
        if case .value = s.forecastAQIState {} else { Issue.record("AQI should settle to .value after the pass") }
    }
}

// Small test helper — add to the test file.
private extension EnvironmentalDataService.ForecastAQIState {
    var valueOrNil: Int? { if case .value(let v) = self { v } else { nil } }
}
