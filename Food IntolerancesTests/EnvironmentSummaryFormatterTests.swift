import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

struct EnvironmentSummaryFormatterTests {
    private let tz = TimeZone(identifier: "UTC")!
    private func day(_ evs: [HealthEvent]) -> EnvironmentDaySummary {
        EnvironmentDaySummaryBuilder.summaries(from: evs, timeZone: tz)[0]
    }
    private func ev(_ subtype: String, value: Double? = nil, unit: String? = nil, meta: [String: String]? = nil) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200), timezoneID: "UTC",
                    category: .environment, subtype: subtype, value: value, unit: unit,
                    source: .weatherAPI, metadata: meta.map { try! JSONEncoder().encode($0) })
    }
    private func temp(_ high: Double, _ low: Double) -> HealthEvent { ev("temperature", value: high, unit: "°C", meta: ["low": String(low)]) }
    private func humidity(_ v: Double) -> HealthEvent { ev("humidity", value: v, unit: "%") }
    private func pressure(_ v: Double) -> HealthEvent { ev("pressure", value: v, unit: "hPa") }
    private func drop(_ v: Double) -> HealthEvent { ev("pressureDrop", value: v, unit: "hPa") }
    private func moon(_ s: String) -> HealthEvent { ev("moonPhase", meta: ["phase": s]) }
    private func season(_ s: String) -> HealthEvent { ev("season", meta: ["season": s]) }
    private func mercury() -> HealthEvent { ev("mercuryRetrograde") }
    private func airQuality(_ aqi: Double) -> HealthEvent { ev("airQuality", value: aqi) }
    private let c = TemperatureUnit.celsius, f = TemperatureUnit.fahrenheit

    // Headline — all four branches + both degenerate sub-branches.
    @Test func headlineTempAndHumidity() {
        let s = day([temp(24, 12), humidity(69)])
        #expect(EnvironmentSummaryFormatter.headline(s, unit: c) == "12–24°C · 69%")   // EN DASH U+2013
        #expect(EnvironmentSummaryFormatter.headline(s, unit: f) == "54–75°F · 69%")
    }
    @Test func headlineTempOnlyHasNoTrailingSeparator() {
        #expect(EnvironmentSummaryFormatter.headline(day([temp(24, 12)]), unit: c) == "12–24°C")   // no " · "
    }
    @Test func headlineBackfillMoonAndSeason() {
        #expect(EnvironmentSummaryFormatter.headline(day([moon("Waxing gibbous"), season("Summer")]), unit: c) == "Waxing gibbous · Summer")
    }
    @Test func headlineMoonOnly() {
        #expect(EnvironmentSummaryFormatter.headline(day([moon("Full moon")]), unit: c) == "Full moon")   // no season → no separator
    }
    @Test func headlineDegenerateSeasonOnly() {
        #expect(EnvironmentSummaryFormatter.headline(day([season("Summer")]), unit: c) == "Season: Summer")
    }
    @Test func headlineDegenerateMercuryOnlyIsBareLabel() {
        #expect(EnvironmentSummaryFormatter.headline(day([mercury()]), unit: c) == "Mercury retrograde")   // value nil → bare label, never empty
    }
    @Test func poorAirDayLeadsHeadlineOverTemperature() {
        // temperature IS present → proves the AQI branch is FIRST (wins over temp), not merely non-empty.
        let s = day([temp(24, 12), humidity(69), airQuality(132)])
        #expect(EnvironmentSummaryFormatter.headline(s, unit: c) == "AQI 132 · Unhealthy for sensitive groups")
    }
    @Test func goodAirDoesNotLeadAndSortsAfterHumidity() {
        let s = day([temp(24, 12), humidity(69), airQuality(42)])
        #expect(EnvironmentSummaryFormatter.headline(s, unit: c) == "12–24°C · 69%")   // AQI 42 < 101 → temp still leads
        let rows = EnvironmentSummaryFormatter.detailLines(s, unit: c)
        #expect(rows.map(\.label) == ["Temperature", "Humidity", "Air quality"])       // pins the canonical position
        #expect(rows.first(where: { $0.label == "Air quality" })?.value == "42 · Good")
    }

    // Detail lines.
    @Test func detailLinesOrderedLabeledAndFolded() {
        let s = day([temp(24, 12), humidity(69), pressure(1013), drop(7), moon("Waxing gibbous"), season("Summer"), mercury()])
        let rows = EnvironmentSummaryFormatter.detailLines(s, unit: c)
        #expect(rows.map(\.label) == ["Temperature", "Humidity", "Air pressure", "Moon phase", "Season", "Mercury retrograde"])
        #expect(rows.first(where: { $0.label == "Air pressure" })?.value == "1013 hPa · ↓7 hPa")   // drop folded, no separate row
        #expect(rows.first(where: { $0.label == "Mercury retrograde" })?.value == nil)               // presence line
        #expect(rows.first(where: { $0.label == "Temperature" })?.value == "12–24°C")
    }
    @Test func detailLinesTemperatureHonorsUnit() {
        #expect(EnvironmentSummaryFormatter.detailLines(day([temp(24, 12)]), unit: f).first?.value == "54–75°F")
    }

    // Expandability seam — the row uses detailLines(...).count >= 2 (see spec §3D).
    @Test func detailLineCountDrivesExpandability() {
        #expect(EnvironmentSummaryFormatter.detailLines(day([season("Summer")]), unit: c).count == 1)          // one line → not expandable
        #expect(EnvironmentSummaryFormatter.detailLines(day([pressure(1013), drop(7)]), unit: c).count == 1)   // folded → one line → not expandable
        #expect(EnvironmentSummaryFormatter.detailLines(day([temp(24, 12), humidity(69)]), unit: c).count >= 2)
    }
}
