import Foundation
import HealthKit
import SwiftData
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
    @Published var lastBackfillFailures: [String] = []
    /// From the HealthKit biological-sex characteristic, populated on a
    /// granted authorization. Not persisted anywhere (no schema change this
    /// round, and nothing consumes it yet) — capturing it now is what makes
    /// a later consumer possible without a second HealthKit round-trip.
    @Published private(set) var biologicalSex: BiologicalSex?

    private let healthStore = HKHealthStore()
    private let database: AppDatabase
    private let pipeline: IngestPipeline

    /// Set once at launch (FoodIntolerancesApp) so a granted authorization
    /// can populate `UserProfile.dateOfBirth`. Optional and fail-open: nil
    /// simply skips the profile write, never blocks authorization or ingest.
    var modelContainer: ModelContainer?

    static let backfillCompletedKey = "hg.hk.backfillCompleted"

    /// Tombstone for `UserProfileView`'s "Remove Date of Birth": once set, a
    /// later authorization pass must never silently repopulate the DOB it
    /// just removed. Written by hand at the two UI sites that change intent
    /// (remove / manually pick a new one) — see `shouldPopulateDateOfBirth`.
    static let dobRemovedKey = "hg.profile.dobRemoved"

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

    /// Read-only characteristics (date of birth, biological sex): the
    /// profile's "read from HealthKit where permitted" source (spec §
    /// "The profile"). `characteristicType(forIdentifier:)` never returns
    /// nil for these two well-known identifiers; `compactMap` only guards
    /// the API's optional signature.
    static var characteristicTypes: [HKCharacteristicType] {
        [HKObjectType.characteristicType(forIdentifier: .dateOfBirth),
         HKObjectType.characteristicType(forIdentifier: .biologicalSex)].compactMap { $0 }
    }

    static var readTypes: Set<HKObjectType> {
        Set(perSampleTypes as [HKObjectType])
            .union(Set(dailyStatTypes as [HKObjectType]))
            .union(Set(characteristicTypes as [HKObjectType]))
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
        // A successful return does NOT imply every type was actually
        // granted (Apple reports denied reads as "not determined", never a
        // throw) — the characteristic reads below simply throw/no-op for
        // whichever of the two was denied, same fail-open shape as the rest
        // of this class.
        populateProfileFromHealthKitCharacteristics()
    }

    /// Reads the DOB and biological-sex characteristics (each independently
    /// optional — either may be denied or unset) and writes what HealthKit
    /// answers into the profile. Never overwrites an existing
    /// `dateOfBirth` — a value already on the profile (HK-sourced or
    /// user-entered via `UserProfileView`'s "ask") wins over a later HK
    /// read, and a user-removed DOB (the tombstone) stays removed. Biological
    /// sex has no profile column (no schema change this round) so it is only
    /// cached on `self`.
    private func populateProfileFromHealthKitCharacteristics() {
        if let sexObject = try? healthStore.biologicalSex() {
            biologicalSex = BiologicalSex(sexObject.biologicalSex)
        }

        guard let modelContainer,
              let components = try? healthStore.dateOfBirthComponents(),
              let dob = Calendar(identifier: .gregorian).date(from: components) else { return }

        let context = modelContainer.mainContext
        do {
            let profile = try context.fetch(FetchDescriptor<UserProfile>()).first ?? {
                let created = Self.newProfileSeededWithGlobalUnits()
                context.insert(created)
                return created
            }()
            guard Self.shouldPopulateDateOfBirth(
                storedDOB: profile.dateOfBirth,
                tombstone: UserDefaults.standard.bool(forKey: Self.dobRemovedKey)) else { return }
            profile.dateOfBirth = dob
            profile.lastUpdated = Date()
            try context.save()
        } catch {
            Logger.error(error, message: "Failed to populate profile from HealthKit characteristics", category: .data)
        }
    }

    /// A freshly-created profile seeded exactly like every other profile
    /// creator (`OnboardingContainerView`, `UserProfileView`) seeds it: the
    /// resolved global measurement system, never the bare `UserProfile()`
    /// default ("imperial" regardless of locale — see
    /// `UnitSystem.newProfileUnitPreference`). `defaults`/`locale` are
    /// injectable so the seeding is testable without standing up HealthKit.
    nonisolated static func newProfileSeededWithGlobalUnits(defaults: UserDefaults = .standard,
                                                             locale: Locale = .current) -> UserProfile {
        let profile = UserProfile()
        profile.unitPreference = UnitSystem.newProfileUnitPreference(
            global: defaults.string(forKey: UnitPreferenceBootstrap.globalKey) ?? "", locale: locale)
        return profile
    }

    /// Pure guard for the DOB-population write: only when the profile has no
    /// DOB yet AND the user never explicitly removed one (the
    /// `dobRemovedKey` tombstone, written by hand at `UserProfileView`'s
    /// "Remove Date of Birth" action and cleared when the user manually
    /// picks a new DOB there).
    nonisolated static func shouldPopulateDateOfBirth(storedDOB: Date?, tombstone: Bool) -> Bool {
        storedDOB == nil && !tombstone
    }

    // MARK: - Backfill

    func backfill(years: Int = 1) async throws -> IngestSummary {
        // Self-request: presents the permission sheet only when not yet
        // determined; a no-op afterwards. Prevents the "Authorization not
        // determined" trap when backfill is tapped before the request button.
        try await requestAuthorization()
        isRunning = true
        lastBackfillFailures = []
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
            do {
                total = total + (try await backfillSampleType(type, predicate: window))
            } catch {
                lastBackfillFailures.append("\(type.identifier): \(error.localizedDescription)")
            }
            done += 1
        }
        for type in Self.dailyStatTypes {
            progress = BackfillProgress(completedSteps: done, totalSteps: steps,
                                        currentStep: type.identifier,
                                        eventsIngested: total.inserted + total.updated)
            do {
                total = total + (try await ingestDailyStats(for: type, from: start, to: Date()))
            } catch {
                lastBackfillFailures.append("\(type.identifier): \(error.localizedDescription)")
            }
            done += 1
        }
        UserDefaults.standard.set(true, forKey: Self.backfillCompletedKey)
        // A CLEAN backfill run by this (fixed) code already wrote whole days,
        // so there is nothing for the one-shot repair to correct: stamp it
        // done rather than make a fresh install re-read a year for nothing. An
        // install whose backfill ran on the old code has no stamp, so the
        // repair runs once on its next launch.
        if lastBackfillFailures.isEmpty {
            // Guarded: the loop above swallows a per-type throw into
            // `lastBackfillFailures`, so a daily type that failed here left
            // rows missing or stale — stamping would disarm the one mechanism
            // that would ever re-read them. Leave the repair armed instead.
            UserDefaults.standard.set(DailyStatRepair.currentVersion, forKey: DailyStatRepair.versionKey)
        }
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

    /// The whole-calendar-day range a daily-statistics query covers. `start`
    /// is floored to local midnight so the HealthKit sample predicate and the
    /// bucket enumeration begin at the SAME instant — a time-of-day reaching
    /// the predicate is exactly the defect this pins (the day-2 bucket summed
    /// only the samples after that time of day and overwrote the full-day row).
    nonisolated static func dailyStatRange(from start: Date, to end: Date,
                                           calendar: Calendar = .current) -> DateInterval {
        let dayStart = calendar.startOfDay(for: start)
        // `max` only so a caller that inverts the arguments gets an empty
        // range instead of a `DateInterval` precondition trap.
        return DateInterval(start: dayStart, end: max(dayStart, end))
    }

    /// The trailing window `recomputeRecentDailyStats` re-reads: the start of
    /// the calendar day two days before `now`, through `now`.
    nonisolated static func recentDailyStatWindow(now: Date,
                                                  calendar: Calendar = .current) -> DateInterval {
        let twoDaysBack = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        return dailyStatRange(from: twoDaysBack, to: now, calendar: calendar)
    }

    func ingestDailyStats(for type: HKQuantityType, from start: Date,
                          to end: Date) async throws -> IngestSummary {
        let identifier = type.identifier
        let aggregation = HealthKitSampleMapper.dailyStatOptions(for: identifier)
        let options: HKStatisticsOptions = aggregation == .sum ? .cumulativeSum : .discreteAverage
        // ONE range, used by the predicate, the anchor and the enumeration
        // alike: whole calendar days, so no bucket can cover a partial day.
        let range = Self.dailyStatRange(from: start, to: end)

        let collection: HKStatisticsCollection = try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: range.start, end: range.end),
                options: options,
                anchorDate: range.start,
                intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, result, error in
                if let error { cont.resume(throwing: error) }
                else if let result { cont.resume(returning: result) }
                else { cont.resume(throwing: CocoaError(.featureUnsupported)) }
            }
            healthStore.execute(query)
        }

        var events: [HealthEvent] = []
        collection.enumerateStatistics(from: range.start, to: range.end) { stats, _ in
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

    // MARK: - Live ingestion

    private var observerQueries: [HKObserverQuery] = []

    /// Registers observer queries + background delivery for all read types.
    /// Idempotent per process (re-calling replaces the query list).
    func startObserving() {
        guard HKHealthStore.isHealthDataAvailable(),
              UserDefaults.standard.bool(forKey: Self.backfillCompletedKey) else { return }
        for query in observerQueries { healthStore.stop(query) }
        observerQueries = []

        for type in Self.perSampleTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) {
                [weak self] _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor [weak self] in
                    await self?.ingestNewSamples(for: type)
                    completion()
                }
            }
            healthStore.execute(query)
            observerQueries.append(query)
            healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
        for type in Self.dailyStatTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) {
                [weak self] _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor [weak self] in
                    await self?.recomputeRecentDailyStats(for: type)
                    completion()
                }
            }
            healthStore.execute(query)
            observerQueries.append(query)
            healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    /// Incremental anchored fetch from the persisted anchor.
    private func ingestNewSamples(for type: HKSampleType) async {
        do {
            let (samples, newAnchor) = try await fetchAnchored(
                type: type, predicate: nil,
                anchor: loadAnchor(for: type.identifier), limit: HKObjectQueryNoLimit)
            if !samples.isEmpty {
                _ = try await pipeline.ingest(samples.compactMap(Self.mapSample))
            }
            persistAnchor(newAnchor, for: type.identifier)
        } catch {
            // Observer fires again on the next change; never log health data.
            Logger.error("HK live ingest failed for a sample type", category: .data)
        }
    }

    /// Daily-stat types have no anchors: recompute the trailing 2 whole
    /// calendar days — dedupKeys make the re-ingest an idempotent same-day
    /// update, which is why the window must never start mid-day (a partial
    /// day would overwrite the correct row, not add to it).
    private func recomputeRecentDailyStats(for type: HKQuantityType) async {
        let window = Self.recentDailyStatWindow(now: Date())
        do {
            _ = try await ingestDailyStats(for: type, from: window.start, to: window.end)
        } catch {
            Logger.error(error, message: "HK daily-stat recompute failed for \(type.identifier)",
                         category: .data)
        }
    }

    /// Re-reads every daily-statistics type over the last `years` and writes
    /// the whole-day values through the normal pipeline (in-place updates via
    /// the existing dedup keys). Used by `DailyStatRepair` only. Throws if ANY
    /// type failed — after re-ingesting the rest — so a caller can refuse to
    /// mark the repair done. Touches none of the user-facing import state
    /// (`isRunning`, `progress`, `lastBackfillFailures`, `HealthImportStatusStore`):
    /// this is a silent background pass the user never asked for.
    /// No `requestAuthorization()` here — the repair only runs after a
    /// completed backfill, which already asked.
    func reingestDailyStats(years: Int = 1) async throws -> IngestSummary {
        let start = Calendar.current.date(byAdding: .year, value: -years, to: Date())!
        var total = IngestSummary()
        var failed: [String] = []
        for type in Self.dailyStatTypes {
            do {
                total = total + (try await ingestDailyStats(for: type, from: start, to: Date()))
            } catch {
                failed.append(type.identifier)
            }
        }
        guard failed.isEmpty else { throw DailyStatRepairError.typesFailed(failed) }
        return total
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
        // The writing app's bundle ID and (when Health has one) the physical
        // device name. Stored, not yet consumed — see HealthKitSampleMapper's
        // Source Provenance section.
        let sourceBundleID = sample.sourceRevision.source.bundleIdentifier
        let deviceName = sample.device?.name
        if let workout = sample as? HKWorkout {
            var name = workout.workoutActivityType.hgActivityName
            name = name.prefix(1).lowercased() + name.dropFirst()
            let canonicalName = HealthKitSampleMapper.canonicalActivityName(name)
            let kcal = workout.statistics(
                for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?
                .doubleValue(for: .kilocalorie())
            let distance = workout.statistics(
                for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?
                .doubleValue(for: .meterUnit(with: .kilo))
            return HealthKitSampleMapper.map(
                WorkoutData(activityName: canonicalName, start: workout.startDate, end: workout.endDate,
                            kcal: kcal, distanceKm: distance, timezoneID: timezoneID,
                            sourceBundleID: sourceBundleID, deviceName: deviceName),
                source: .healthKit)
        }
        if let quantity = sample as? HKQuantitySample {
            let id = quantity.quantityType.identifier
            return HealthKitSampleMapper.map(
                QuantitySampleData(identifier: id, start: quantity.startDate, end: quantity.endDate,
                                   value: quantity.quantity.doubleValue(for: hkUnit(for: id)),
                                   unit: unitString(for: id), timezoneID: timezoneID,
                                   sourceBundleID: sourceBundleID, deviceName: deviceName),
                source: .healthKit)
        }
        if let category = sample as? HKCategorySample {
            // HKMetadataKeyMenstrualCycleStart is stored as an NSNumber boolean.
            // Absent -> nil (unknown), which keeps the sample inference-eligible.
            let cycleStart = (category.metadata?[HKMetadataKeyMenstrualCycleStart] as? NSNumber)?.boolValue
            return HealthKitSampleMapper.map(
                CategorySampleData(identifier: category.categoryType.identifier,
                                   start: category.startDate, end: category.endDate,
                                   value: category.value, timezoneID: timezoneID,
                                   menstrualCycleStart: cycleStart,
                                   sourceBundleID: sourceBundleID, deviceName: deviceName),
                source: .healthKit)
        }
        return nil
    }
}

extension BiologicalSex {
    /// `.notSet` (never permitted, or the user declined in Health) maps to
    /// `nil` — there is no `BiologicalSex.notSet` case, deliberately: an
    /// unanswered characteristic is absence, not a fourth category.
    init?(_ hk: HKBiologicalSex) {
        switch hk {
        case .female: self = .female
        case .male: self = .male
        case .other: self = .other
        case .notSet: return nil
        @unknown default: return nil
        }
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
