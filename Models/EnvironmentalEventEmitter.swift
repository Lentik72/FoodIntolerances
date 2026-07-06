import Foundation
import HealthGraphCore

/// Emits daily environment exposure events on app foreground (spec §6.6).
/// Once per calendar day; dedupKeys make accidental re-runs idempotent
/// (same-day re-emission updates the pressure value in place).
enum EnvironmentalEventEmitter {
    static let lastEmitDayKey = "hg.env.lastEmitDay"

    static func emitIfNeeded(database: AppDatabase = HealthGraphProvider.shared,
                             service: EnvironmentalDataService) async {
        let today = ISO8601DateFormatter.hgDayString(from: Date())
        guard UserDefaults.standard.string(forKey: lastEmitDayKey) != today else { return }

        _ = await service.requestRefreshWithCooldown()
        let now = Date()
        let reading = EnvironmentalReading(
            date: now,
            pressureHPa: service.currentPressure > 0 ? service.currentPressure : nil,
            previousPressureHPa: service.previousPressure > 0 ? service.previousPressure : nil,
            moonPhaseName: getMoonPhase(for: now),
            season: getCurrentSeason(for: now),
            isMercuryRetrograde: MercuryRetrograde.isRetrograde(on: now),
            timezoneID: TimeZone.current.identifier
        )
        do {
            _ = try await IngestPipeline(database: database)
                .ingest(EnvironmentalEventFactory.events(for: reading))
            UserDefaults.standard.set(today, forKey: lastEmitDayKey)
        } catch {
            Logger.info("Environmental emit failed; will retry on next foreground", category: .data)
        }
    }

    /// Historical backfill of the date-derived signals (moon phase, season,
    /// Mercury retrograde) — pure functions of the date, so a year of exposure
    /// history is free (spec §5 cold-start rationale). No historical pressure:
    /// the weather API has no history. Idempotent via daily dedupKeys.
    /// NOTE: MercuryRetrograde.periods covers 2025–2026 only; days before its
    /// table simply emit no retrograde events (correct absence semantics).
    static func backfillDerived(days: Int = 365,
                                database: AppDatabase = HealthGraphProvider.shared) async throws -> IngestSummary {
        let pipeline = IngestPipeline(database: database)
        let tz = TimeZone.current.identifier
        var events: [HealthEvent] = []
        let noonToday = Calendar.current.date(
            bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        for dayOffset in 1...days {
            let date = noonToday.addingTimeInterval(-Double(dayOffset) * 86_400)
            let reading = EnvironmentalReading(
                date: date, pressureHPa: nil, previousPressureHPa: nil,
                moonPhaseName: getMoonPhase(for: date),
                season: getCurrentSeason(for: date),
                isMercuryRetrograde: MercuryRetrograde.isRetrograde(on: date),
                timezoneID: tz
            )
            events.append(contentsOf: EnvironmentalEventFactory.events(for: reading))
        }
        return try await pipeline.ingest(events)
    }
}

extension ISO8601DateFormatter {
    static func hgDayString(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f.string(from: date)
    }
}
