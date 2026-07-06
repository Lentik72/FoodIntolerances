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
}
