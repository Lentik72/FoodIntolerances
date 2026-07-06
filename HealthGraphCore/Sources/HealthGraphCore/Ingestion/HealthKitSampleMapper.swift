import Foundation

// Plain value types: the package never imports HealthKit. The app target
// (and the export parser) convert their sources into these.

public struct QuantitySampleData: Sendable {
    public let identifier: String
    public let start: Date
    public let end: Date
    public let value: Double
    public let unit: String
    public let timezoneID: String?
    public init(identifier: String, start: Date, end: Date,
                value: Double, unit: String, timezoneID: String?) {
        self.identifier = identifier; self.start = start; self.end = end
        self.value = value; self.unit = unit; self.timezoneID = timezoneID
    }
}

public struct CategorySampleData: Sendable {
    public let identifier: String
    public let start: Date
    public let end: Date
    public let value: Int
    public let timezoneID: String?
    public init(identifier: String, start: Date, end: Date, value: Int, timezoneID: String?) {
        self.identifier = identifier; self.start = start; self.end = end
        self.value = value; self.timezoneID = timezoneID
    }
}

public struct WorkoutData: Sendable {
    public let activityName: String
    public let start: Date
    public let end: Date
    public let kcal: Double?
    public let distanceKm: Double?
    public let timezoneID: String?
    public init(activityName: String, start: Date, end: Date,
                kcal: Double?, distanceKm: Double?, timezoneID: String?) {
        self.activityName = activityName; self.start = start; self.end = end
        self.kcal = kcal; self.distanceKm = distanceKm; self.timezoneID = timezoneID
    }
}

public struct DailyStatData: Sendable {
    public let identifier: String
    public let dayStart: Date
    public let value: Double
    public let timezoneID: String?
    public init(identifier: String, dayStart: Date, value: Double, timezoneID: String?) {
        self.identifier = identifier; self.dayStart = dayStart
        self.value = value; self.timezoneID = timezoneID
    }
}

public enum DailyStatAggregation: Sendable, Equatable { case sum, average }

public enum HealthKitSampleMapper {
    // (category, subtype, canonical unit)
    private static let quantityTable: [String: (EventCategory, String, String)] = [
        "HKQuantityTypeIdentifierRestingHeartRate": (.vitals, "restingHeartRate", "bpm"),
        "HKQuantityTypeIdentifierBodyMass": (.bodyMetric, "weight", "kg"),
        "HKQuantityTypeIdentifierBloodPressureSystolic": (.vitals, "bloodPressureSystolic", "mmHg"),
        "HKQuantityTypeIdentifierBloodPressureDiastolic": (.vitals, "bloodPressureDiastolic", "mmHg"),
    ]

    private static let dailyTable: [String: (EventCategory, String, String, DailyStatAggregation)] = [
        "HKQuantityTypeIdentifierStepCount": (.exercise, "steps", "count", .sum),
        "HKQuantityTypeIdentifierHeartRate": (.vitals, "heartRate", "bpm", .average),
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": (.vitals, "hrv", "ms", .average),
        "HKQuantityTypeIdentifierRespiratoryRate": (.vitals, "respiratoryRate", "breaths/min", .average),
        "HKQuantityTypeIdentifierDietaryEnergyConsumed": (.food, "dietaryEnergy", "kcal", .sum),
        "HKQuantityTypeIdentifierDietaryProtein": (.food, "dietaryProtein", "g", .sum),
        "HKQuantityTypeIdentifierDietaryCarbohydrates": (.food, "dietaryCarbs", "g", .sum),
        "HKQuantityTypeIdentifierDietaryFatTotal": (.food, "dietaryFat", "g", .sum),
        "HKQuantityTypeIdentifierDietarySugar": (.food, "dietarySugar", "g", .sum),
        "HKQuantityTypeIdentifierDietarySodium": (.food, "dietarySodium", "mg", .sum),
    ]

    private static let sleepStages: [Int: String] = [
        0: "inBed", 1: "asleepUnspecified", 2: "awake",
        3: "asleepCore", 4: "asleepDeep", 5: "asleepREM",
    ]

    public static let symptomIdentifiers: Set<String> = Set([
        "Headache", "AbdominalCramps", "Bloating", "Nausea", "Vomiting", "Diarrhea",
        "Constipation", "Heartburn", "Fatigue", "Dizziness", "ChestTightnessOrPain",
        "ShortnessOfBreath", "Coughing", "Fever", "Chills", "SoreThroat", "RunnyNose",
        "SinusCongestion", "MoodChanges", "SleepChanges", "AppetiteChanges", "HotFlashes",
        "Acne", "DrySkin", "HairLoss", "NightSweats", "PelvicPain", "MemoryLapse",
        "GeneralizedBodyAche", "LowerBackPain", "SkippedHeartbeat",
        "RapidPoundingOrFlutteringHeartbeat", "BladderIncontinence", "LossOfSmell",
        "LossOfTaste", "Wheezing", "BreastPain", "VaginalDryness", "Fainting",
    ].map { "HKCategoryTypeIdentifier\($0)" })

    public static var perSampleQuantityIdentifiers: Set<String> { Set(quantityTable.keys) }
    public static var dailyStatIdentifiers: Set<String> { Set(dailyTable.keys) }
    public static var categoryIdentifiers: Set<String> {
        symptomIdentifiers.union([
            "HKCategoryTypeIdentifierSleepAnalysis",
            "HKCategoryTypeIdentifierMindfulSession",
            "HKCategoryTypeIdentifierMenstrualFlow",
        ])
    }

    public static func dailyStatOptions(for identifier: String) -> DailyStatAggregation {
        dailyTable[identifier]?.3 ?? .sum
    }

    /// Canonical workout subtype shared by the live-HealthKit and export-file
    /// paths (spec §5.2: identical mapping and dedup keys so the two compose).
    /// Input: a raw activity name with the "HKWorkoutActivityType" prefix
    /// already stripped and the first letter lowercased.
    public static func canonicalActivityName(_ name: String) -> String {
        switch name {
        case "running": return "running"
        case "walking": return "walking"
        case "cycling": return "cycling"
        case "swimming": return "swimming"
        case "yoga": return "yoga"
        case "functionalStrengthTraining", "traditionalStrengthTraining",
             "strengthTraining": return "strengthTraining"
        case "highIntensityIntervalTraining", "hIIT", "hiit": return "hiit"
        case "hiking": return "hiking"
        case "pilates": return "pilates"
        case "rowing": return "rowing"
        case "elliptical": return "elliptical"
        case "stairClimbing": return "stairClimbing"
        case "dance": return "dance"
        case "tennis": return "tennis"
        case "basketball": return "basketball"
        case "soccer": return "soccer"
        case "golf": return "golf"
        case "paddleSports": return "paddleSports"
        case "martialArts": return "martialArts"
        case "coreTraining": return "coreTraining"
        default: return "other"
        }
    }

    // MARK: - Unit Conversion

    private static func convertUnit(_ value: Double, from inputUnit: String,
                                   to canonicalUnit: String) -> (Double, Bool) {
        // Returns (converted value, isUnknownUnit)
        if inputUnit == canonicalUnit {
            return (value, false)
        }

        // Conversions
        if inputUnit == "lb" && canonicalUnit == "kg" {
            return (value * 0.45359237, false)
        }
        if inputUnit == "g" && canonicalUnit == "kg" {
            return (value / 1000, false)
        }
        if inputUnit == "count/min" && (canonicalUnit == "bpm" || canonicalUnit == "breaths/min") {
            return (value, false)
        }
        if inputUnit == "s" && canonicalUnit == "ms" {
            return (value * 1000, false)
        }
        if inputUnit == "kJ" && canonicalUnit == "kcal" {
            return (value * 0.239006, false)
        }
        if (inputUnit == "Cal" || inputUnit == "kcal") && canonicalUnit == "kcal" {
            return (value, false)
        }
        if inputUnit == "g" && canonicalUnit == "mg" {
            return (value * 1000, false)
        }

        // Unknown unit: keep value but flag confidence
        return (value, true)
    }

    // MARK: - Symptom Severity Mapping

    private static func symptomSeverityValue(_ raw: Int) -> Int? {
        switch raw {
        case 0: return nil       // unspecified -> present unrated
        case 1: return nil       // notPresent -> skip (caller returns nil)
        case 2: return 2         // mild
        case 3: return 5         // moderate
        case 4: return 8         // severe
        default: return nil
        }
    }

    // MARK: - Export String Mapping

    private static let exportStringMap: [String: Int] = [
        "HKCategoryValueNotApplicable": 0,
        "HKCategoryValueSleepAnalysisInBed": 0,
        "HKCategoryValueSleepAnalysisAsleep": 1,
        "HKCategoryValueSleepAnalysisAsleepUnspecified": 1,
        "HKCategoryValueSleepAnalysisAwake": 2,
        "HKCategoryValueSleepAnalysisAsleepCore": 3,
        "HKCategoryValueSleepAnalysisAsleepDeep": 4,
        "HKCategoryValueSleepAnalysisAsleepREM": 5,
        "HKCategoryValueSeverityUnspecified": 0,
        "HKCategoryValueSeverityNotPresent": 1,
        "HKCategoryValueSeverityMild": 2,
        "HKCategoryValueSeverityModerate": 3,
        "HKCategoryValueSeveritySevere": 4,
        "HKCategoryValueMenstrualFlowUnspecified": 1,
        "HKCategoryValueMenstrualFlowLight": 2,
        "HKCategoryValueMenstrualFlowMedium": 3,
        "HKCategoryValueMenstrualFlowHeavy": 4,
        "HKCategoryValueMenstrualFlowNone": 5,
    ]

    public static func categoryValue(fromExportString exportString: String) -> Int? {
        exportStringMap[exportString]
    }

    // MARK: - Map Overloads

    public static func map(_ sample: QuantitySampleData, source: EventSource) -> HealthEvent? {
        guard let (category, subtype, canonicalUnit) = quantityTable[sample.identifier] else {
            return nil
        }

        let (convertedValue, isUnknownUnit) = convertUnit(sample.value, from: sample.unit, to: canonicalUnit)
        let confidence = isUnknownUnit ? 0.8 : 1.0
        let timezoneID = sample.timezoneID ?? TimeZone.current.identifier

        return HealthEvent(
            timestamp: sample.start,
            timezoneID: timezoneID,
            endTimestamp: nil,
            category: category,
            subtype: subtype,
            value: convertedValue,
            unit: canonicalUnit,
            source: source,
            confidence: confidence,
            metadata: nil,
            dedupKey: DedupKey.point(category, subtype, sample.start)
        )
    }

    public static func map(_ sample: CategorySampleData, source: EventSource) -> HealthEvent? {
        let timezoneID = sample.timezoneID ?? TimeZone.current.identifier

        // Sleep Analysis
        if sample.identifier == "HKCategoryTypeIdentifierSleepAnalysis" {
            guard let subtype = sleepStages[sample.value] else { return nil }
            let durationMinutes = Int(sample.end.timeIntervalSince(sample.start) / 60)
            return HealthEvent(
                timestamp: sample.start,
                timezoneID: timezoneID,
                endTimestamp: sample.end,
                category: .sleep,
                subtype: subtype,
                value: Double(durationMinutes),
                unit: "min",
                source: source,
                confidence: 1.0,
                metadata: nil,
                dedupKey: DedupKey.duration(.sleep, subtype, start: sample.start, end: sample.end)
            )
        }

        // Mindful Session
        if sample.identifier == "HKCategoryTypeIdentifierMindfulSession" {
            let durationMinutes = Int(sample.end.timeIntervalSince(sample.start) / 60)
            return HealthEvent(
                timestamp: sample.start,
                timezoneID: timezoneID,
                endTimestamp: sample.end,
                category: .stress,
                subtype: "mindfulness",
                value: Double(durationMinutes),
                unit: "min",
                source: source,
                confidence: 1.0,
                metadata: nil,
                dedupKey: DedupKey.duration(.stress, "mindfulness", start: sample.start, end: sample.end)
            )
        }

        // Menstrual Flow
        if sample.identifier == "HKCategoryTypeIdentifierMenstrualFlow" {
            let flowValue: Int?
            switch sample.value {
            case 5: return nil      // none -> skip
            case 1: flowValue = nil // unspecified -> present unrated
            case 2: flowValue = 1   // light
            case 3: flowValue = 2   // medium
            case 4: flowValue = 3   // heavy
            default: return nil
            }

            return HealthEvent(
                timestamp: sample.start,
                timezoneID: timezoneID,
                endTimestamp: nil,
                category: .cycle,
                subtype: "menstrualFlow",
                value: flowValue.map { Double($0) },
                unit: "level",
                source: source,
                confidence: 1.0,
                metadata: nil,
                dedupKey: DedupKey.point(.cycle, "menstrualFlow", sample.start)
            )
        }

        // Symptoms
        if symptomIdentifiers.contains(sample.identifier) {
            // Strip HKCategoryTypeIdentifier prefix and lowercase first char
            let prefix = "HKCategoryTypeIdentifier"
            guard let range = sample.identifier.range(of: prefix) else { return nil }
            var subtype = String(sample.identifier[range.upperBound...])
            if !subtype.isEmpty {
                let first = subtype.removeFirst()
                subtype = first.lowercased() + subtype
            }

            // Severity mapping
            if sample.value == 1 { return nil }  // notPresent -> skip
            let eventValue = symptomSeverityValue(sample.value)

            return HealthEvent(
                timestamp: sample.start,
                timezoneID: timezoneID,
                endTimestamp: nil,
                category: .symptom,
                subtype: subtype,
                value: eventValue.map { Double($0) },
                unit: "severity",
                source: source,
                confidence: 1.0,
                metadata: nil,
                dedupKey: DedupKey.point(.symptom, subtype, sample.start)
            )
        }

        return nil
    }

    public static func map(_ sample: WorkoutData, source: EventSource) -> HealthEvent? {
        let durationMinutes = Int(sample.end.timeIntervalSince(sample.start) / 60)
        let timezoneID = sample.timezoneID ?? TimeZone.current.identifier

        // Build metadata JSON
        var metaDict: [String: String] = [:]
        if let kcal = sample.kcal {
            metaDict["kcal"] = "\(Int(kcal))"
        }
        if let distanceKm = sample.distanceKm {
            metaDict["distanceKm"] = String(format: "%.1f", distanceKm)
        }

        let metadata = try? JSONEncoder().encode(metaDict)

        return HealthEvent(
            timestamp: sample.start,
            timezoneID: timezoneID,
            endTimestamp: sample.end,
            category: .exercise,
            subtype: sample.activityName,
            value: Double(durationMinutes),
            unit: "min",
            source: source,
            confidence: 1.0,
            metadata: metadata,
            dedupKey: DedupKey.duration(.exercise, sample.activityName,
                                       start: sample.start, end: sample.end)
        )
    }

    public static func map(_ sample: DailyStatData, source: EventSource) -> HealthEvent? {
        guard let (category, subtype, canonicalUnit, _) = dailyTable[sample.identifier] else {
            return nil
        }

        let timezoneID = sample.timezoneID ?? TimeZone.current.identifier
        let dayEnd = sample.dayStart.addingTimeInterval(86_400)

        return HealthEvent(
            timestamp: sample.dayStart,
            timezoneID: timezoneID,
            endTimestamp: dayEnd,
            category: category,
            subtype: subtype,
            value: sample.value,
            unit: canonicalUnit,
            source: source,
            confidence: 1.0,
            metadata: nil,
            dedupKey: DedupKey.daily(category, subtype, dayStart: sample.dayStart)
        )
    }
}
