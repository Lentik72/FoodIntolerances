import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

struct WeatherValueFormatterTests {
    private func env(_ subtype: String, _ v: Double) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .environment,
                    subtype: subtype, value: v, source: .weatherAPI)
    }
    @Test func temperatureCelsiusRoundsWhole() {
        #expect(WeatherValueFormatter.line(for: env("temperature", 20), unit: .celsius) == "20°C")
        #expect(WeatherValueFormatter.line(for: env("temperature", 19.6372), unit: .celsius) == "20°C")   // ≥.5 → round up
        #expect(WeatherValueFormatter.line(for: env("temperature", 20.5), unit: .celsius) == "21°C")      // exact .5 tie → away-from-zero
    }
    @Test func temperatureFahrenheitConvertsThenRounds() {
        #expect(WeatherValueFormatter.line(for: env("temperature", 20), unit: .fahrenheit) == "68°F")       // 20·9/5+32
        #expect(WeatherValueFormatter.line(for: env("temperature", 19.6372), unit: .fahrenheit) == "67°F")  // 67.35 → 67 (round-then-convert would give 68 — pins order)
        #expect(WeatherValueFormatter.line(for: env("temperature", 15.5), unit: .fahrenheit) == "60°F")     // 59.9 → 60 (round=60, truncate=59 — discriminates round vs trunc)
        #expect(WeatherValueFormatter.line(for: env("temperature", 0), unit: .fahrenheit) == "32°F")
        #expect(WeatherValueFormatter.line(for: env("temperature", -5), unit: .fahrenheit) == "23°F")       // -5·9/5+32
    }
    @Test func humidityRoundsWholePercentRegardlessOfUnit() {
        #expect(WeatherValueFormatter.line(for: env("humidity", 69.3915), unit: .fahrenheit) == "69%")
        #expect(WeatherValueFormatter.line(for: env("humidity", 69.3915), unit: .celsius) == "69%")
        #expect(WeatherValueFormatter.line(for: env("humidity", 69.6), unit: .celsius) == "70%")            // ≥.5 (round=70, truncate=69 — discriminates)
    }
    @Test func nonWeatherEventReturnsNil() {   // caller falls back to EventDisplay.valueLine
        let symptom = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .symptom,
                                  subtype: "migraine", value: 5, source: .manual)
        #expect(WeatherValueFormatter.line(for: symptom, unit: .fahrenheit) == nil)
        #expect(WeatherValueFormatter.line(for: env("pressure", 1013), unit: .fahrenheit) == nil)   // env but not temp/humidity
        let noValue = HealthEvent(timestamp: Date(timeIntervalSince1970: 100), category: .environment,
                                  subtype: "temperature", value: nil, source: .weatherAPI)
        #expect(WeatherValueFormatter.line(for: noValue, unit: .fahrenheit) == nil)   // no value → nil (the `let v` guard)
    }
    @Test func localeDefaultAndResolution() {
        #expect(TemperatureUnit.localeDefault(for: Locale(identifier: "en_US")) == .fahrenheit)
        #expect(TemperatureUnit.localeDefault(for: Locale(identifier: "en_GB")) == .celsius)
        #expect(TemperatureUnit.localeDefault(for: Locale(identifier: "de_DE")) == .celsius)
        #expect(TemperatureUnit.resolved(from: "F", locale: Locale(identifier: "de_DE")) == .fahrenheit)  // explicit wins
        #expect(TemperatureUnit.resolved(from: "C", locale: Locale(identifier: "en_US")) == .celsius)
        #expect(TemperatureUnit.resolved(from: "", locale: Locale(identifier: "en_US")) == .fahrenheit)   // empty → locale
        #expect(TemperatureUnit.resolved(from: "garbage", locale: Locale(identifier: "de_DE")) == .celsius)
    }
}
