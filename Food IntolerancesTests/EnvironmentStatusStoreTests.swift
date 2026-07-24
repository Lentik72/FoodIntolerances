import Testing
import Foundation
@testable import Food_Intolerances

@MainActor
struct EnvironmentStatusStoreTests {
    private func ephemeral() -> UserDefaults {
        // A unique volatile suite per test so nothing leaks into `.standard`.
        let name = "test.env.status." + UUID().uuidString
        return UserDefaults(suiteName: name)!
    }
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func recordFailureSetsBothSlots() {
        let store = EnvironmentStatusStore(defaults: ephemeral())
        store.recordFailure(.observedWeather, reason: .rejected,
                            scopeStart: t0, scopeEnd: t0, timezoneID: "UTC", at: t0)
        let s = store.statuses[.observedWeather]
        #expect(s?.liveFailure?.reason == .rejected)
        #expect(s?.lastFailure?.reason == .rejected)
        #expect(s?.lastSuccess == nil)
    }

    @Test func recordSuccessClearsLiveButRetainsLast() {
        let store = EnvironmentStatusStore(defaults: ephemeral())
        store.recordFailure(.observedWeather, reason: .locationDenied,
                            scopeStart: t0, scopeEnd: t0, timezoneID: "UTC", at: t0)
        store.recordSuccess(.observedWeather, at: t0.addingTimeInterval(60))
        let s = store.statuses[.observedWeather]
        #expect(s?.liveFailure == nil)                 // healed
        #expect(s?.lastFailure?.reason == .locationDenied)   // retained
        #expect(s?.lastSuccess == t0.addingTimeInterval(60))
    }

    @Test func persistsAcrossInstancesIncludingTimezone() {
        let defaults = ephemeral()
        do {
            let store = EnvironmentStatusStore(defaults: defaults)
            store.recordFailure(.observedAirQuality, reason: .offline,
                                scopeStart: t0, scopeEnd: t0.addingTimeInterval(86_400),
                                timezoneID: "America/Los_Angeles", at: t0)
        }
        let reloaded = EnvironmentStatusStore(defaults: defaults)
        let f = reloaded.statuses[.observedAirQuality]?.liveFailure
        #expect(f?.reason == .offline)
        #expect(f?.timezoneID == "America/Los_Angeles")
    }
}
