import Testing
import Foundation
@testable import Food_Intolerances

struct EnvironmentStatusPresentationTests {
    private let t = Date(timeIntervalSince1970: 1_000_000)
    private func fail(_ reason: EnvironmentFailureReason, at: Date) -> EnvironmentFailure {
        EnvironmentFailure(at: at, reason: reason, scopeStart: at, scopeEnd: at, timezoneID: "UTC")
    }

    @Test func summaryNotCheckedWhenAllNil() {
        #expect(EnvironmentStatusPresentation.summary([:]) == .notChecked)
    }
    @Test func summaryUsesLeastRecentSuccess() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .currentPressure:   .init(lastSuccess: t.addingTimeInterval(500), liveFailure: nil, lastFailure: nil),
            .forecastWeather:   .init(lastSuccess: t.addingTimeInterval(100), liveFailure: nil, lastFailure: nil),
            .forecastAirQuality:.init(lastSuccess: t.addingTimeInterval(300), liveFailure: nil, lastFailure: nil),
            .observedAirQuality:.init(lastSuccess: t.addingTimeInterval(400), liveFailure: nil, lastFailure: nil),
            .observedWeather:   .init(lastSuccess: t.addingTimeInterval(200), liveFailure: nil, lastFailure: nil),
        ]
        #expect(EnvironmentStatusPresentation.summary(s) == .updated(t.addingTimeInterval(100)))
    }
    @Test func summaryNotCheckedIfAnyEndpointNeverRan() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .currentPressure: .init(lastSuccess: t, liveFailure: nil, lastFailure: nil)
            // others absent → nil lastSuccess
        ]
        #expect(EnvironmentStatusPresentation.summary(s) == .notChecked)
    }
    @Test func summaryNamesEarliestFailingGroup() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .observedWeather:   .init(lastSuccess: nil, liveFailure: fail(.rejected, at: t), lastFailure: fail(.rejected, at: t)),
            .observedAirQuality:.init(lastSuccess: nil, liveFailure: fail(.offline, at: t), lastFailure: fail(.offline, at: t)),
        ]
        #expect(EnvironmentStatusPresentation.summary(s) == .unavailable("Weather history unavailable"))
    }
    @Test func explanationLiveLocationDeniedShowsOpenSettings() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .forecastWeather: .init(lastSuccess: nil, liveFailure: fail(.locationDenied, at: t), lastFailure: fail(.locationDenied, at: t)),
        ]
        let e = EnvironmentStatusPresentation.explanation(s)
        #expect(e?.isResolved == false)
        #expect(e?.showOpenSettings == true)
        #expect(e?.heading == "Why it stopped")
    }
    @Test func explanationResolvedIsPastTenseNoAction() {
        // liveFailure cleared, lastFailure retained → resolved.
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .forecastWeather: .init(lastSuccess: t.addingTimeInterval(60), liveFailure: nil, lastFailure: fail(.locationDenied, at: t)),
        ]
        let e = EnvironmentStatusPresentation.explanation(s)
        #expect(e?.isResolved == true)
        #expect(e?.showOpenSettings == false)     // no action even though it was locationDenied
        #expect(e?.heading == "Last issue — resolved")
    }
    @Test func observedWeatherRejectedUsesNeutralKeyOrSubscriptionCopy() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .observedWeather: .init(lastSuccess: nil, liveFailure: fail(.rejected, at: t), lastFailure: fail(.rejected, at: t)),
        ]
        #expect(EnvironmentStatusPresentation.explanation(s)?.body
                == "Historical weather may need a valid API key or an active One Call subscription.")
    }
    @Test func rowStatusPerCapability() {
        let s: [EnvironmentCapability: EnvironmentCapabilityStatus] = [
            .currentPressure: .init(lastSuccess: t, liveFailure: nil, lastFailure: nil),
            .observedWeather: .init(lastSuccess: nil, liveFailure: fail(.rejected, at: t), lastFailure: fail(.rejected, at: t)),
        ]
        let rows = EnvironmentStatusPresentation.rows(s)
        let pressure = rows.first { $0.capability == .currentPressure }
        let obsWeather = rows.first { $0.capability == .observedWeather }
        let obsAQI = rows.first { $0.capability == .observedAirQuality }
        #expect(pressure?.status == .updated(t))
        #expect(obsWeather?.status == .unavailable)
        #expect(obsAQI?.status == .notChecked)
        #expect(rows.count == 5)
    }
}
