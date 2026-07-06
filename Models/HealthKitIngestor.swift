import Foundation
import HealthKit
import HealthGraphCore

struct BackfillProgress {
    var completedSteps: Int
    var totalSteps: Int
    var currentStep: String
    var eventsIngested: Int
}

/// HealthKit → event graph ingestion (spec §5.1). Thin HK plumbing only:
/// all mapping and dedup logic lives in HealthGraphCore (package-tested).
@MainActor
final class HealthKitIngestor: ObservableObject {
    @Published var isRunning = false
    @Published var progress: BackfillProgress?

    private let healthStore = HKHealthStore()
    private let database: AppDatabase
    private let pipeline: IngestPipeline

    static let backfillCompletedKey = "hg.hk.backfillCompleted"

    init(database: AppDatabase = HealthGraphProvider.shared) {
        self.database = database
        self.pipeline = IngestPipeline(database: database)
    }

    static func anchorKey(_ identifier: String) -> String { "hg.hk.anchor.\(identifier)" }

    // MARK: - Types

    static var perSampleTypes: [HKSampleType] {
        var types: [HKSampleType] = []
        for id in HealthKitSampleMapper.perSampleQuantityIdentifiers {
            if let t = HKObjectType.quantityType(forIdentifier: .init(rawValue: id)) { types.append(t) }
        }
        for id in HealthKitSampleMapper.categoryIdentifiers {
            if let t = HKObjectType.categoryType(forIdentifier: .init(rawValue: id)) { types.append(t) }
        }
        types.append(HKObjectType.workoutType())
        return types
    }

    static var dailyStatTypes: [HKQuantityType] {
        HealthKitSampleMapper.dailyStatIdentifiers.compactMap {
            HKObjectType.quantityType(forIdentifier: .init(rawValue: $0))
        }
    }

    static var readTypes: Set<HKObjectType> {
        Set(perSampleTypes as [HKObjectType]).union(Set(dailyStatTypes as [HKObjectType]))
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: - Backfill

    func backfill(years: Int = 1) async throws -> IngestSummary {
        isRunning = true
        defer { isRunning = false; progress = nil }
        let start = Calendar.current.date(byAdding: .year, value: -years, to: Date())!
        let window = HKQuery.predicateForSamples(withStart: start, end: Date())
        var total = IngestSummary()
        let steps = Self.perSampleTypes.count + Self.dailyStatTypes.count
        var done = 0

        for type in Self.perSampleTypes {
            progress = BackfillProgress(completedSteps: done, totalSteps: steps,
                                        currentStep: type.identifier,
                                        eventsIngested: total.inserted + total.updated)
            total = total + (try await backfillSampleType(type, predicate: window))
            done += 1
        }
        for type in Self.dailyStatTypes {
            progress = BackfillProgress(completedSteps: done, totalSteps: steps,
                                        currentStep: type.identifier,
                                        eventsIngested: total.inserted + total.updated)
            total = total + (try await ingestDailyStats(for: type, from: start, to: Date()))
            done += 1
        }
        UserDefaults.standard.set(true, forKey: Self.backfillCompletedKey)
        return total
    }

    /// Anchored pagination so live ingestion (started later) resumes from the
    /// exact point backfill reached. Batches of 1000.
    private func backfillSampleType(_ type: HKSampleType,
                                    predicate: NSPredicate) async throws -> IngestSummary {
        var summary = IngestSummary()
        var anchor: HKQueryAnchor? = nil
        while true {
            let (samples, newAnchor) = try await fetchAnchored(
                type: type, predicate: predicate, anchor: anchor, limit: 1000)
            anchor = newAnchor
            if !samples.isEmpty {
                summary = summary + (try await pipeline.ingest(samples.compactMap(Self.mapSample)))
            }
            if samples.count < 1000 { break }
        }
        persistAnchor(anchor, for: type.identifier)
        return summary
    }

    func fetchAnchored(type: HKSampleType, predicate: NSPredicate?,
                       anchor: HKQueryAnchor?, limit: Int) async throws -> ([HKSample], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type, predicate: predicate, anchor: anchor, limit: limit
            ) { _, samples, _, newAnchor, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples ?? [], newAnchor)) }
            }
            healthStore.execute(query)
        }
    }

    func persistAnchor(_ anchor: HKQueryAnchor?, for identifier: String) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(
                withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: Self.anchorKey(identifier))
    }

    func loadAnchor(for identifier: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: Self.anchorKey(identifier)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    // MARK: - Daily statistics

    func ingestDailyStats(for type: HKQuantityType, from start: Date,
                          to end: Date) async throws -> IngestSummary {
        let identifier = type.identifier
        let aggregation = HealthKitSampleMapper.dailyStatOptions(for: identifier)
        let options: HKStatisticsOptions = aggregation == .sum ? .cumulativeSum : .discreteAverage
        let dayStart = Calendar.current.startOfDay(for: start)

        let collection: HKStatisticsCollection = try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: options,
                anchorDate: dayStart,
                intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, result, error in
                if let error { cont.resume(throwing: error) }
                else if let result { cont.resume(returning: result) }
                else { cont.resume(throwing: CocoaError(.featureUnsupported)) }
            }
            healthStore.execute(query)
        }

        var events: [HealthEvent] = []
        collection.enumerateStatistics(from: dayStart, to: end) { stats, _ in
            let quantity = aggregation == .sum ? stats.sumQuantity() : stats.averageQuantity()
            guard let quantity else { return }
            let value = quantity.doubleValue(for: Self.hkUnit(for: identifier))
            if let event = HealthKitSampleMapper.map(
                DailyStatData(identifier: identifier, dayStart: stats.startDate,
                              value: value, timezoneID: nil),
                source: .healthKit) {
                events.append(event)
            }
        }
        return try await pipeline.ingest(events)
    }

    // MARK: - HK → DTO conversion

    static func hkUnit(for identifier: String) -> HKUnit {
        switch identifier {
        case "HKQuantityTypeIdentifierStepCount": return .count()
        case "HKQuantityTypeIdentifierHeartRate",
             "HKQuantityTypeIdentifierRestingHeartRate",
             "HKQuantityTypeIdentifierRespiratoryRate":
            return HKUnit.count().unitDivided(by: .minute())
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            return .secondUnit(with: .milli)
        case "HKQuantityTypeIdentifierBodyMass": return .gramUnit(with: .kilo)
        case "HKQuantityTypeIdentifierBloodPressureSystolic",
             "HKQuantityTypeIdentifierBloodPressureDiastolic":
            return .millimeterOfMercury()
        case "HKQuantityTypeIdentifierDietaryEnergyConsumed": return .kilocalorie()
        case "HKQuantityTypeIdentifierDietaryProtein",
             "HKQuantityTypeIdentifierDietaryCarbohydrates",
             "HKQuantityTypeIdentifierDietaryFatTotal",
             "HKQuantityTypeIdentifierDietarySugar": return .gram()
        case "HKQuantityTypeIdentifierDietarySodium": return .gramUnit(with: .milli)
        default: return .count()
        }
    }

    static func unitString(for identifier: String) -> String {
        switch identifier {
        case "HKQuantityTypeIdentifierStepCount": return "count"
        case "HKQuantityTypeIdentifierHeartRate",
             "HKQuantityTypeIdentifierRestingHeartRate": return "bpm"
        case "HKQuantityTypeIdentifierRespiratoryRate": return "breaths/min"
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": return "ms"
        case "HKQuantityTypeIdentifierBodyMass": return "kg"
        case "HKQuantityTypeIdentifierBloodPressureSystolic",
             "HKQuantityTypeIdentifierBloodPressureDiastolic": return "mmHg"
        case "HKQuantityTypeIdentifierDietaryEnergyConsumed": return "kcal"
        case "HKQuantityTypeIdentifierDietaryProtein",
             "HKQuantityTypeIdentifierDietaryCarbohydrates",
             "HKQuantityTypeIdentifierDietaryFatTotal",
             "HKQuantityTypeIdentifierDietarySugar": return "g"
        case "HKQuantityTypeIdentifierDietarySodium": return "mg"
        default: return "count"
        }
    }

    static func mapSample(_ sample: HKSample) -> HealthEvent? {
        let timezoneID = sample.metadata?[HKMetadataKeyTimeZone] as? String
        if let workout = sample as? HKWorkout {
            var name = workout.workoutActivityType.hgActivityName
            name = name.prefix(1).lowercased() + name.dropFirst()
            let kcal = workout.statistics(
                for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?
                .doubleValue(for: .kilocalorie())
            let distance = workout.statistics(
                for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?
                .doubleValue(for: .meterUnit(with: .kilo))
            return HealthKitSampleMapper.map(
                WorkoutData(activityName: name, start: workout.startDate, end: workout.endDate,
                            kcal: kcal, distanceKm: distance, timezoneID: timezoneID),
                source: .healthKit)
        }
        if let quantity = sample as? HKQuantitySample {
            let id = quantity.quantityType.identifier
            return HealthKitSampleMapper.map(
                QuantitySampleData(identifier: id, start: quantity.startDate, end: quantity.endDate,
                                   value: quantity.quantity.doubleValue(for: hkUnit(for: id)),
                                   unit: unitString(for: id), timezoneID: timezoneID),
                source: .healthKit)
        }
        if let category = sample as? HKCategorySample {
            return HealthKitSampleMapper.map(
                CategorySampleData(identifier: category.categoryType.identifier,
                                   start: category.startDate, end: category.endDate,
                                   value: category.value, timezoneID: timezoneID),
                source: .healthKit)
        }
        return nil
    }
}

extension HKWorkoutActivityType {
    /// Common activity names; everything else falls back to "other".
    var hgActivityName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "StrengthTraining"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hiking: return "Hiking"
        case .pilates: return "Pilates"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "StairClimbing"
        case .dance: return "Dance"
        case .tennis: return "Tennis"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .golf: return "Golf"
        case .paddleSports: return "PaddleSports"
        case .martialArts: return "MartialArts"
        case .coreTraining: return "CoreTraining"
        default: return "Other"
        }
    }
}
