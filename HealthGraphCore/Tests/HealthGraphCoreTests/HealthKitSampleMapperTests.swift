import Testing
import Foundation
@testable import HealthGraphCore

struct HealthKitSampleMapperTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func dedupKeyFormatsAreStable() {
        #expect(DedupKey.point(.symptom, "headache", t0) == "symptom|headache|29166666")
        #expect(DedupKey.duration(.sleep, "asleepCore", start: t0, end: t0.addingTimeInterval(3600))
                == "sleep|asleepCore|29166666|29166726")
        #expect(DedupKey.daily(.exercise, "steps", dayStart: t0) == "exercise|steps|day|29166666")
        #expect(DedupKey.point(.food, nil, t0) == "food||29166666")
    }

    @Test func mapsRestingHeartRateSample() {
        let e = HealthKitSampleMapper.map(
            QuantitySampleData(identifier: "HKQuantityTypeIdentifierRestingHeartRate",
                               start: t0, end: t0, value: 58, unit: "bpm", timezoneID: "Europe/Paris"),
            source: .healthKit)
        #expect(e?.category == .vitals)
        #expect(e?.subtype == "restingHeartRate")
        #expect(e?.value == 58)
        #expect(e?.unit == "bpm")
        #expect(e?.timezoneID == "Europe/Paris")
        #expect(e?.dedupKey == DedupKey.point(.vitals, "restingHeartRate", t0))
        #expect(e?.source == .healthKit)
    }

    @Test func convertsPoundsToKilograms() {
        let e = HealthKitSampleMapper.map(
            QuantitySampleData(identifier: "HKQuantityTypeIdentifierBodyMass",
                               start: t0, end: t0, value: 180, unit: "lb", timezoneID: nil),
            source: .healthExportFile)
        #expect(e?.category == .bodyMetric)
        #expect(e?.unit == "kg")
        #expect(abs((e?.value ?? 0) - 81.6466) < 0.001)
    }

    @Test func unknownIdentifierReturnsNil() {
        let e = HealthKitSampleMapper.map(
            QuantitySampleData(identifier: "HKQuantityTypeIdentifierVO2Max",
                               start: t0, end: t0, value: 40, unit: "mL/kg·min", timezoneID: nil),
            source: .healthKit)
        #expect(e == nil)
    }

    @Test func mapsSleepStageWithDurationMinutes() {
        let e = HealthKitSampleMapper.map(
            CategorySampleData(identifier: "HKCategoryTypeIdentifierSleepAnalysis",
                               start: t0, end: t0.addingTimeInterval(5400), value: 4, timezoneID: nil),
            source: .healthKit)
        #expect(e?.category == .sleep)
        #expect(e?.subtype == "asleepDeep")
        #expect(e?.value == 90) // minutes
        #expect(e?.endTimestamp == t0.addingTimeInterval(5400))
        #expect(e?.dedupKey == DedupKey.duration(.sleep, "asleepDeep",
                                                 start: t0, end: t0.addingTimeInterval(5400)))
    }

    @Test func mapsSymptomSeverities() {
        func severity(_ raw: Int) -> HealthEvent? {
            HealthKitSampleMapper.map(
                CategorySampleData(identifier: "HKCategoryTypeIdentifierHeadache",
                                   start: t0, end: t0, value: raw, timezoneID: nil),
                source: .healthKit)
        }
        #expect(severity(1) == nil)          // notPresent -> skip
        #expect(severity(0)?.value == nil)   // unspecified -> present, unrated
        #expect(severity(2)?.value == 2)     // mild
        #expect(severity(3)?.value == 5)     // moderate
        #expect(severity(4)?.value == 8)     // severe
        #expect(severity(2)?.category == .symptom)
        #expect(severity(2)?.subtype == "headache")
    }

    @Test func menstrualFlowMapsAndSkipsNone() {
        func flow(_ raw: Int) -> HealthEvent? {
            HealthKitSampleMapper.map(
                CategorySampleData(identifier: "HKCategoryTypeIdentifierMenstrualFlow",
                                   start: t0, end: t0, value: raw, timezoneID: nil),
                source: .healthKit)
        }
        #expect(flow(5) == nil)        // none
        #expect(flow(2)?.value == 1)   // light
        #expect(flow(4)?.value == 3)   // heavy
        #expect(flow(2)?.category == .cycle)
    }

    @Test func mapsWorkoutWithMetadata() throws {
        let e = HealthKitSampleMapper.map(
            WorkoutData(activityName: "running", start: t0,
                        end: t0.addingTimeInterval(1800), kcal: 412, distanceKm: 5.2,
                        timezoneID: nil),
            source: .healthKit)
        #expect(e?.category == .exercise)
        #expect(e?.subtype == "running")
        #expect(e?.value == 30)
        let meta = try JSONDecoder().decode([String: String].self, from: e?.metadata ?? Data())
        #expect(meta["kcal"] == "412")
        #expect(meta["distanceKm"] == "5.2")
    }

    @Test func dailyStatBecomesDayLongDurationEvent() {
        let e = HealthKitSampleMapper.map(
            DailyStatData(identifier: "HKQuantityTypeIdentifierStepCount",
                          dayStart: t0, value: 8200, timezoneID: nil),
            source: .healthKit)
        #expect(e?.category == .exercise)
        #expect(e?.subtype == "steps")
        #expect(e?.value == 8200)
        #expect(e?.endTimestamp == t0.addingTimeInterval(86_400))
        #expect(e?.dedupKey == DedupKey.daily(.exercise, "steps", dayStart: t0))
    }

    @Test func exportCategoryValueStringsResolve() {
        #expect(HealthKitSampleMapper.categoryValue(
            fromExportString: "HKCategoryValueSleepAnalysisAsleepDeep") == 4)
        #expect(HealthKitSampleMapper.categoryValue(
            fromExportString: "HKCategoryValueSeverityMild") == 2)
        #expect(HealthKitSampleMapper.categoryValue(
            fromExportString: "HKCategoryValueMenstrualFlowHeavy") == 4)
        #expect(HealthKitSampleMapper.categoryValue(fromExportString: "HKCategoryValueNotApplicable") == 0)
        #expect(HealthKitSampleMapper.categoryValue(fromExportString: "SomethingUnknown") == nil)
    }

    @Test func identifierSetsAreConsistent() {
        #expect(HealthKitSampleMapper.perSampleQuantityIdentifiers.count == 4)
        #expect(HealthKitSampleMapper.dailyStatIdentifiers.count == 10)
        #expect(HealthKitSampleMapper.symptomIdentifiers.contains("HKCategoryTypeIdentifierHeadache"))
        #expect(HealthKitSampleMapper.dailyStatOptions(
            for: "HKQuantityTypeIdentifierStepCount") == .sum)
        #expect(HealthKitSampleMapper.dailyStatOptions(
            for: "HKQuantityTypeIdentifierHeartRate") == .average)
    }
}
