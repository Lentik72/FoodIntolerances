import Testing
import Foundation
@testable import HealthGraphCore

struct EnvironmentalEventFactoryTests {
    let noon = Date(timeIntervalSince1970: 1_750_075_200)

    func reading(date: Date? = nil, pressure: Double? = 1013, previous: Double? = 1015,
                 moon: String? = "Full Moon 🌕", season: String? = "Summer",
                 retrograde: Bool = false) -> EnvironmentalReading {
        EnvironmentalReading(
            date: date ?? noon, pressureHPa: pressure, previousPressureHPa: previous,
            moonPhaseName: moon, season: season,
            isMercuryRetrograde: retrograde, timezoneID: "UTC")
    }

    @Test func emitsPressureMoonAndSeasonOnAQuietDay() throws {
        let events = EnvironmentalEventFactory.events(for: reading())
        #expect(events.count == 3) // pressure + moonPhase + season; no drop, no retrograde
        #expect(events.allSatisfy { $0.category == .environment })
        #expect(events.allSatisfy { $0.source == .weatherAPI })
        #expect(events.allSatisfy { $0.dedupKey != nil })
        let pressure = events.first { $0.subtype == "pressure" }
        #expect(pressure?.value == 1013)
        #expect(pressure?.unit == "hPa")
        let moon = try #require(events.first { $0.subtype == "moonPhase" })
        let moonMeta = try JSONDecoder().decode([String: String].self, from: moon.metadata ?? Data())
        #expect(moonMeta["phase"] == "Full Moon") // emoji stripped
        let season = try #require(events.first { $0.subtype == "season" })
        let seasonMeta = try JSONDecoder().decode([String: String].self, from: season.metadata ?? Data())
        #expect(seasonMeta["season"] == "Summer") // daily exposure, not a transition marker
    }

    @Test func emitsPressureDropAtThreshold() {
        let events = EnvironmentalEventFactory.events(for: reading(pressure: 1004, previous: 1010))
        let drop = events.first { $0.subtype == "pressureDrop" }
        #expect(drop?.value == 6)
        let noDrop = EnvironmentalEventFactory.events(for: reading(pressure: 1005, previous: 1010))
        #expect(!noDrop.contains { $0.subtype == "pressureDrop" })
    }

    @Test func emitsRetrogradeOnlyWhenTrue() {
        #expect(EnvironmentalEventFactory.events(for: reading(retrograde: true))
            .contains { $0.subtype == "mercuryRetrograde" })
        #expect(!EnvironmentalEventFactory.events(for: reading(retrograde: false))
            .contains { $0.subtype == "mercuryRetrograde" })
    }

    @Test func nilPressureSkipsPressureEventsOnly() {
        // historical backfill shape: no pressure available, derived signals still emit
        let events = EnvironmentalEventFactory.events(for: reading(pressure: nil, previous: nil))
        #expect(!events.contains { $0.subtype == "pressure" })
        #expect(!events.contains { $0.subtype == "pressureDrop" })
        #expect(events.contains { $0.subtype == "moonPhase" })
        #expect(events.contains { $0.subtype == "season" })
    }

    @Test func distinctDaysProduceDistinctDailyKeys() {
        let dayOne = EnvironmentalEventFactory.events(for: reading())
        let dayTwo = EnvironmentalEventFactory.events(
            for: reading(date: noon.addingTimeInterval(86_400)))
        let keysOne = Set(dayOne.compactMap(\.dedupKey))
        let keysTwo = Set(dayTwo.compactMap(\.dedupKey))
        #expect(keysOne.isDisjoint(with: keysTwo)) // backfill loop never collides across days
    }

    @Test func dailyKeysMakeReemissionIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let pipeline = IngestPipeline(database: db)
        _ = try await pipeline.ingest(EnvironmentalEventFactory.events(for: reading()))
        _ = try await pipeline.ingest(EnvironmentalEventFactory.events(for: reading(pressure: 1012)))
        let store = GRDBEventStore(database: db)
        #expect(try await store.count() == 3) // same day: updated, not duplicated
        let pressure = try await store.recentEvents(limit: 10).first { $0.subtype == "pressure" }
        #expect(pressure?.value == 1012) // latest reading wins (equal rank -> update)
    }

    @Test func emitsNoTempHumidityWhenNil() {
        let r = EnvironmentalReading(date: Date(timeIntervalSince1970: 1_700_000_000),
            pressureHPa: 1013, previousPressureHPa: nil, moonPhaseName: nil, season: nil,
            isMercuryRetrograde: false, timezoneID: "UTC")   // temp/humidity default nil
        let events = EnvironmentalEventFactory.events(for: r)
        #expect(!events.contains { $0.subtype == "temperature" || $0.subtype == "humidity" })
    }

    @Test func emitsExactlyOneCombinedTemperatureWithLowInMetadata() {
        let r = EnvironmentalReading(date: Date(timeIntervalSince1970: 1_700_000_000),
            pressureHPa: nil, previousPressureHPa: nil, moonPhaseName: nil, season: nil,
            isMercuryRetrograde: false, timezoneID: "UTC",
            temperatureHighC: 24, temperatureLowC: 12, humidityPct: 68)
        let events = EnvironmentalEventFactory.events(for: r)
        #expect(events.filter { $0.subtype == "temperature" }.count == 1)   // ONE combined event, not two
        let temp = events.first { $0.subtype == "temperature" }
        #expect(temp?.value == 24 && temp?.unit == "°C" && temp?.dedupKey != nil)
        let meta = temp?.metadata.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        #expect(meta?["low"] == "12.0")
        #expect(events.first { $0.subtype == "humidity" }?.value == 68)
    }
    // Either pole nil → no temperature event; humidity is INDEPENDENT (still emits).
    @Test func skipsTemperatureWhenEitherPoleNilButKeepsHumidity() {
        func temps(high: Double?, low: Double?) -> [HealthEvent] {
            EnvironmentalEventFactory.events(for: EnvironmentalReading(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                pressureHPa: nil, previousPressureHPa: nil, moonPhaseName: nil, season: nil,
                isMercuryRetrograde: false, timezoneID: "UTC",
                temperatureHighC: high, temperatureLowC: low, humidityPct: 55))
        }
        #expect(!temps(high: 24, low: nil).contains { $0.subtype == "temperature" })   // low-nil branch
        #expect(!temps(high: nil, low: 12).contains { $0.subtype == "temperature" })   // high-nil branch
        #expect(temps(high: 24, low: nil).contains { $0.subtype == "humidity" })       // humidity independent
    }

    @Test func emitsAirQualityWhenAQIPresent() {
        let r = EnvironmentalReading(date: Date(timeIntervalSince1970: 1_700_000_000),
            pressureHPa: nil, previousPressureHPa: nil, moonPhaseName: nil, season: nil,
            isMercuryRetrograde: false, timezoneID: "UTC", airQualityAQI: 132)
        let events = EnvironmentalEventFactory.events(for: r)
        #expect(events.count == 1)   // no pressure/moon/season/temp/humidity this day
        let aq = events.first { $0.subtype == "airQuality" }
        #expect(aq?.value == 132)
        #expect(aq?.unit == nil)
        #expect(aq?.dedupKey != nil)
    }

    @Test func nilAirQualityAQISkipsAirQualityEvent() {
        let r = EnvironmentalReading(date: Date(timeIntervalSince1970: 1_700_000_000),
            pressureHPa: nil, previousPressureHPa: nil, moonPhaseName: nil, season: nil,
            isMercuryRetrograde: false, timezoneID: "UTC")   // airQualityAQI defaults nil
        let events = EnvironmentalEventFactory.events(for: r)
        #expect(!events.contains { $0.subtype == "airQuality" })
    }

    // Provenance is intrinsic to each signal's real source (spec: env ingestion
    // correctness). It rides in metadata AND scopes the dedup key so a forecast
    // reading never collides with an observed one for the same day.
    @Test func stampsPerSignalProvenanceOnEveryEvent() {
        let r = EnvironmentalReading(
            date: noon, pressureHPa: 1004, previousPressureHPa: 1015,   // pressure + pressureDrop
            moonPhaseName: "Full Moon 🌕", season: "Summer",
            isMercuryRetrograde: true, timezoneID: "UTC",
            temperatureHighC: 24, temperatureLowC: 12, humidityPct: 68, airQualityAQI: 132)
        let events = EnvironmentalEventFactory.events(for: r)
        func provenance(_ subtype: String) -> TemporalProvenance? {
            events.first { $0.subtype == subtype }?.temporalProvenance
        }
        // Weather forecasts are future-facing → never mined.
        #expect(provenance("temperature") == .forecast)
        #expect(provenance("humidity") == .forecast)
        // Current-conditions readings.
        #expect(provenance("pressure") == .currentSnapshot)
        #expect(provenance("pressureDrop") == .currentSnapshot)
        // Deterministic date-facts / completed-day observations → mineable.
        #expect(provenance("moonPhase") == .observedCompletedDay)
        #expect(provenance("season") == .observedCompletedDay)
        #expect(provenance("mercuryRetrograde") == .observedCompletedDay)
        // New emitter: AQI is an observed completed-day reading (mineable). The
        // migration classifies LEGACY airQuality as forecast — a documented split.
        #expect(provenance("airQuality") == .observedCompletedDay)
        // Every env event carries a provenance in metadata.
        #expect(events.allSatisfy { $0.temporalProvenance != nil })
    }

    @Test func provenanceIsFoldedIntoTheDedupKey() {
        let events = EnvironmentalEventFactory.events(for: reading())
        let moon = events.first { $0.subtype == "moonPhase" }
        // The observed provenance rawValue appears in the daily key.
        #expect(moon?.dedupKey?.contains("observedCompletedDay") == true)
    }
}
