#if DEBUG
import Foundation
import HealthKit
import HealthGraphCore

/// DEBUG-only HealthKit diagnostic: for one quantity type, report what the
/// raw sample query sees AND what the exact daily-statistics query the
/// ingestor runs (`HealthKitIngestor.ingestDailyStats`) returns, side by
/// side. Exists because a denied/empty/incompatible read type is otherwise
/// indistinguishable from "no data" — HealthKit hides denials, and the
/// ingestor's daily path swallows the difference (device gate, 2026-08-30:
/// HRV present in Apple Health, permission on, zero rows ingested).
@MainActor
enum HealthKitProbe {
    private static let store = HKHealthStore()

    static func report(identifier: String, days: Int = 14) async -> String {
        var out: [String] = ["== \(identifier) =="]
        guard let type = HKObjectType.quantityType(forIdentifier: .init(rawValue: identifier)) else {
            return out.joined(separator: "\n") + "\nquantityType(forIdentifier:) returned nil"
        }
        out.append("aggregation style: \(type.aggregationStyle.rawValue) (0=cumulative 1=discreteArithmetic 2=discreteTemporallyWeighted 3=discreteEquivalentContinuousLevel)")
        out.append("share authorizationStatus (reads are hidden by HK): \(store.authorizationStatus(for: type).rawValue)")
        let unit = HealthKitIngestor.hkUnit(for: identifier)
        out.append("ingestor unit: \(unit.unitString)")

        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now)!

        // 1. Raw samples in the window (what a per-sample read would see).
        do {
            let samples = try await samples(type: type,
                                            predicate: HKQuery.predicateForSamples(withStart: start, end: now),
                                            limit: HKObjectQueryNoLimit)
            out.append("raw samples, last \(days)d: \(samples.count)")
            for s in samples.prefix(4) {
                out.append(describe(s, unit: unit))
            }
        } catch { out.append("raw sample query THREW: \(error)") }

        // 2. Latest sample ever (no date predicate) — catches "data exists but outside the window".
        do {
            let latest = try await samples(type: type, predicate: nil, limit: 1)
            out.append("latest sample ever: " + (latest.first.map { describe($0, unit: unit) } ?? "none"))
        } catch { out.append("latest-sample query THREW: \(error)") }

        // 3. The EXACT statistics query the ingestor runs (trailing 7 days).
        let statStart = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        out.append(contentsOf: await statistics(type: type, identifier: identifier, unit: unit,
                                                 from: statStart, to: now, samplePredicate: true))
        // 4. Same query WITHOUT the sample predicate, to isolate the predicate.
        out.append(contentsOf: await statistics(type: type, identifier: identifier, unit: unit,
                                                 from: statStart, to: now, samplePredicate: false))
        return out.joined(separator: "\n")
    }

    private static func describe(_ s: HKQuantitySample, unit: HKUnit) -> String {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
        let compatible = s.quantity.is(compatibleWith: unit)
        let value = compatible ? String(format: "%.2f %@", s.quantity.doubleValue(for: unit), unit.unitString) : "INCOMPATIBLE UNIT"
        return "  \(f.string(from: s.startDate))–\(f.string(from: s.endDate)) \(s.quantity) → \(value) · src=\(s.sourceRevision.source.bundleIdentifier) dev=\(s.device?.name ?? "-") meta=\(s.metadata?.keys.sorted().joined(separator: ",") ?? "-")"
    }

    private static func samples(type: HKQuantityType, predicate: NSPredicate?, limit: Int) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, results, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: (results as? [HKQuantitySample]) ?? []) }
            }
            store.execute(q)
        }
    }

    private static func statistics(type: HKQuantityType, identifier: String, unit: HKUnit,
                                   from start: Date, to end: Date, samplePredicate: Bool) async -> [String] {
        // Mirrors HealthKitIngestor.ingestDailyStats line for line.
        let aggregation = HealthKitSampleMapper.dailyStatOptions(for: identifier)
        let options: HKStatisticsOptions = aggregation == .sum ? .cumulativeSum : .discreteAverage
        let dayStart = Calendar.current.startOfDay(for: start)
        var out = ["statistics (\(samplePredicate ? "with" : "WITHOUT") sample predicate), \(aggregation == .sum ? "cumulativeSum" : "discreteAverage"), 7d:"]
        do {
            let collection: HKStatisticsCollection = try await withCheckedThrowingContinuation { cont in
                let query = HKStatisticsCollectionQuery(
                    quantityType: type,
                    quantitySamplePredicate: samplePredicate ? HKQuery.predicateForSamples(withStart: start, end: end) : nil,
                    options: options,
                    anchorDate: dayStart,
                    intervalComponents: DateComponents(day: 1))
                query.initialResultsHandler = { _, result, error in
                    if let error { cont.resume(throwing: error) }
                    else if let result { cont.resume(returning: result) }
                    else { cont.resume(throwing: CocoaError(.featureUnsupported)) }
                }
                store.execute(query)
            }
            let f = DateFormatter(); f.dateFormat = "MM-dd"
            var days = 0
            collection.enumerateStatistics(from: dayStart, to: end) { stats, _ in
                days += 1
                let q = aggregation == .sum ? stats.sumQuantity() : stats.averageQuantity()
                let v = q.map { $0.is(compatibleWith: unit) ? String(format: "%.2f", $0.doubleValue(for: unit)) : "INCOMPATIBLE(\($0))" } ?? "nil"
                out.append("  \(f.string(from: stats.startDate)): \(v) · sources=\(stats.sources?.count ?? 0)")
            }
            out.append("  (\(days) day buckets enumerated; collection.statistics().count=\(collection.statistics().count))")
        } catch {
            out.append("  THREW: \(error)")
        }
        return out
    }
}
#endif
