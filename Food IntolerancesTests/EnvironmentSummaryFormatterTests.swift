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

    // Typed detail-line model — subtype preserved; AQI line carries the value for the badge.
    @Test func airQualityDetailLineCarriesSubtypeAndAQI() {
        let rows = EnvironmentSummaryFormatter.detailLines(day([temp(24, 12), airQuality(132)]), unit: c)
        let air = rows.first { $0.subtype == "airQuality" }
        #expect(air?.aqi == 132)                     // the badge's color input, structural (not label-matched)
        #expect(air?.value == "132 · Unhealthy for sensitive groups")
        let tempLine = rows.first { $0.subtype == "temperature" }
        #expect(tempLine?.aqi == nil)                // non-AQI lines carry no aqi
        #expect(tempLine?.subtype == "temperature")  // subtype preserved for every line
        // The detail line badges ALL bands, not just poor air — a good-air line still carries its aqi.
        let good = EnvironmentSummaryFormatter.detailLines(day([temp(24, 12), airQuality(42)]), unit: c)
        #expect(good.first { $0.subtype == "airQuality" }?.aqi == 42)   // guards against gating detail aqi to poor-air only
    }
    // poorAirAQI — mirrors exactly when the collapsed headline leads with AQI.
    @Test func poorAirAQIReturnsValueOnlyOnPoorAirDays() {
        #expect(EnvironmentSummaryFormatter.poorAirAQI(day([temp(24, 12), airQuality(132)])) == 132)   // >= 101 → poor
        #expect(EnvironmentSummaryFormatter.poorAirAQI(day([temp(24, 12), airQuality(42)])) == nil)    // < 101 → nil (temp leads)
        #expect(EnvironmentSummaryFormatter.poorAirAQI(day([temp(24, 12)])) == nil)                    // no AQI event → nil
        #expect(EnvironmentSummaryFormatter.poorAirAQI(day([airQuality(101)])) == 101)                 // == threshold → poor (pins >=, not >)
        #expect(EnvironmentSummaryFormatter.poorAirAQI(day([airQuality(100)])) == nil)                 // one below → nil
    }
    // Two same-day AQI events → each line's aqi matches ITS OWN displayed text (the dot can
    // never represent one value while the text shows another). The builder keeps both events.
    @Test func twoAirQualityEventsEachLineMatchesItsOwnValue() {
        let rows = EnvironmentSummaryFormatter.detailLines(day([airQuality(42), airQuality(180)]), unit: c)
        let air = rows.filter { $0.subtype == "airQuality" }
        #expect(air.count == 2)
        #expect(air.contains { $0.aqi == 42 && $0.value == "42 · Good" })
        #expect(air.contains { $0.aqi == 180 && $0.value == "180 · Unhealthy" })
    }
}
