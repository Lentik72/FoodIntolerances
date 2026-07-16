import Foundation

/// A correlation deliberately planted in generated data. Phase 2's engine
/// must find these and must NOT find patterns in the noise.
public struct PlantedPattern {
    public var exposureName: String
    public var exposureCategory: EventCategory
    public var outcomeSubtype: String
    public var lagHours: Double
    public var lagJitterHours: Double
    public var followProbability: Double
    public var exposureProbabilityPerDay: Double

    public init(exposureName: String, exposureCategory: EventCategory,
                outcomeSubtype: String, lagHours: Double, lagJitterHours: Double,
                followProbability: Double, exposureProbabilityPerDay: Double) {
        self.exposureName = exposureName
        self.exposureCategory = exposureCategory
        self.outcomeSubtype = outcomeSubtype
        self.lagHours = lagHours
        self.lagJitterHours = lagJitterHours
        self.followProbability = followProbability
        self.exposureProbabilityPerDay = exposureProbabilityPerDay
    }
}

/// Optional derived-signal and scenario toggles mined by the Phase 2A
/// Evidence Engine's acceptance suite. All default off so existing
/// generator behavior (and existing tests) are unaffected.
public struct DerivedScenarios: Sendable {
    public var shortSleepFatigue = false     // <6h nights → fatigue next day
    public var pressureHeadache = false      // pressureDrop → headache
    public var stressSymptom = false         // high stress → tension
    public var lutealSymptom = false         // luteal window → cramps
    public var protectiveSupplement = false  // magnesium → reduced migraine rate
    public var confounderPair = false        // espresso always with croissant (>60%)
    public var nullEffectSupplement = false  // vitaminX, ≥20 exposures/≥90d, no effect
    // Full public init: an explicit `init(){}` would suppress the memberwise
    // initializer AND be too `internal` to serve as SyntheticConfig's default.
    public init(shortSleepFatigue: Bool = false, pressureHeadache: Bool = false,
                stressSymptom: Bool = false, lutealSymptom: Bool = false,
                protectiveSupplement: Bool = false, confounderPair: Bool = false,
                nullEffectSupplement: Bool = false) {
        self.shortSleepFatigue = shortSleepFatigue; self.pressureHeadache = pressureHeadache
        self.stressSymptom = stressSymptom; self.lutealSymptom = lutealSymptom
        self.protectiveSupplement = protectiveSupplement; self.confounderPair = confounderPair
        self.nullEffectSupplement = nullEffectSupplement
    }
}

public struct SyntheticConfig {
    public var startDate: Date
    public var days: Int
    public var seed: UInt64
    public var patterns: [PlantedPattern]
    public var outcomeBaseRatePerDay: Double
    public var noiseFoodsPerDay: ClosedRange<Int>
    public var derivedScenarios = DerivedScenarios()

    public init(startDate: Date, days: Int, seed: UInt64, patterns: [PlantedPattern],
                outcomeBaseRatePerDay: Double, noiseFoodsPerDay: ClosedRange<Int>,
                derivedScenarios: DerivedScenarios = DerivedScenarios()) {
        self.startDate = startDate
        self.days = days
        self.seed = seed
        self.patterns = patterns
        self.outcomeBaseRatePerDay = outcomeBaseRatePerDay
        self.noiseFoodsPerDay = noiseFoodsPerDay
        self.derivedScenarios = derivedScenarios
    }
}

public struct SyntheticDataset {
    public var objects: [HealthObject]
    public var events: [HealthEvent]

    public func insert(into database: AppDatabase) async throws {
        let objectStore = GRDBObjectStore(database: database)
        let eventStore = GRDBEventStore(database: database)
        // findOrCreate remaps object ids; keep event objectIDs consistent.
        var idMap: [UUID: UUID] = [:]
        for object in objects {
            let saved = try await objectStore.findOrCreate(
                name: object.name, kind: object.kind, metadata: object.metadata)
            idMap[object.id] = saved.id
        }
        var remapped = events
        for i in remapped.indices {
            if let oid = remapped[i].objectID { remapped[i].objectID = idMap[oid] ?? oid }
        }
        try await eventStore.save(remapped)
    }
}

public enum SyntheticDataGenerator {
    static let noiseFoods = ["rice", "chicken", "banana", "oats", "salad", "apple"]

    public static func generate(config: SyntheticConfig) -> SyntheticDataset {
        var rng = SeededGenerator(seed: config.seed)
        var objects: [HealthObject] = []
        var events: [HealthEvent] = []

        var exposureObjects: [String: HealthObject] = [:]
        for pattern in config.patterns {
            let kind: ObjectKind = pattern.exposureCategory == .food ? .food : .supplement
            let object = HealthObject(kind: kind, name: pattern.exposureName)
            exposureObjects[pattern.exposureName] = object
            objects.append(object)
        }
        var noiseObjects: [String: HealthObject] = [:]
        for name in Self.noiseFoods {
            let object = HealthObject(kind: .food, name: name)
            noiseObjects[name] = object
            objects.append(object)
        }

        let scenarios = config.derivedScenarios
        var magnesium: HealthObject?, espresso: HealthObject?, croissant: HealthObject?, vitaminX: HealthObject?
        if scenarios.protectiveSupplement {
            let o = HealthObject(kind: .supplement, name: "magnesium"); magnesium = o; objects.append(o)
        }
        if scenarios.confounderPair {
            let e = HealthObject(kind: .food, name: "espresso"); espresso = e; objects.append(e)
            let c = HealthObject(kind: .food, name: "croissant"); croissant = c; objects.append(c)
        }
        if scenarios.nullEffectSupplement {
            let o = HealthObject(kind: .supplement, name: "vitaminX"); vitaminX = o; objects.append(o)
        }

        let tz = "UTC"
        for day in 0..<config.days {
            let dayStart = config.startDate.addingTimeInterval(Double(day) * 86_400)

            for pattern in config.patterns {
                guard Double.random(in: 0..<1, using: &rng) < pattern.exposureProbabilityPerDay
                else { continue }
                let jitter = Double.random(in: 0..<4, using: &rng) * 3600
                let exposureTime = dayStart.addingTimeInterval(9 * 3600 + jitter)
                events.append(HealthEvent(
                    timestamp: exposureTime, timezoneID: tz,
                    category: pattern.exposureCategory,
                    subtype: pattern.exposureName,
                    objectID: exposureObjects[pattern.exposureName]?.id,
                    source: .manual
                ))
                if Double.random(in: 0..<1, using: &rng) < pattern.followProbability {
                    let lag = pattern.lagHours
                        + Double.random(in: -pattern.lagJitterHours...pattern.lagJitterHours, using: &rng)
                    events.append(HealthEvent(
                        timestamp: exposureTime.addingTimeInterval(lag * 3600),
                        timezoneID: tz, category: .symptom,
                        subtype: pattern.outcomeSubtype,
                        value: Double(Int.random(in: 3...8, using: &rng)),
                        source: .manual
                    ))
                }
            }

            if Double.random(in: 0..<1, using: &rng) < config.outcomeBaseRatePerDay,
               let subtype = config.patterns.first?.outcomeSubtype {
                let hour = Double.random(in: 7..<22, using: &rng)
                events.append(HealthEvent(
                    timestamp: dayStart.addingTimeInterval(hour * 3600),
                    timezoneID: tz, category: .symptom, subtype: subtype,
                    value: Double(Int.random(in: 2...6, using: &rng)),
                    source: .manual
                ))
            }

            let noiseCount = Int.random(in: config.noiseFoodsPerDay, using: &rng)
            for _ in 0..<noiseCount {
                let name = Self.noiseFoods[Int.random(in: 0..<Self.noiseFoods.count, using: &rng)]
                let hour = Double.random(in: 7..<21, using: &rng)
                events.append(HealthEvent(
                    timestamp: dayStart.addingTimeInterval(hour * 3600),
                    timezoneID: tz, category: .food, subtype: name,
                    objectID: noiseObjects[name]?.id, source: .manual
                ))
            }

            let s = config.derivedScenarios
            // Short sleep → fatigue (about half the nights are short).
            if s.shortSleepFatigue {
                let short = Double.random(in: 0..<1, using: &rng) < 0.5
                let hours = short ? Double.random(in: 4.0..<5.5, using: &rng)
                                  : Double.random(in: 7.0..<8.5, using: &rng)
                let bed = dayStart.addingTimeInterval(-2 * 3600)         // ~22:00 previous
                let wake = bed.addingTimeInterval(hours * 3600)
                events.append(HealthEvent(timestamp: bed, timezoneID: tz, endTimestamp: wake,
                                          category: .sleep, subtype: "asleepCore", source: .healthKit))
                if short && Double.random(in: 0..<1, using: &rng) < 0.7 {
                    events.append(HealthEvent(timestamp: wake.addingTimeInterval(3 * 3600),
                                              timezoneID: tz, category: .symptom, subtype: "fatigue",
                                              value: Double(Int.random(in: 3...7, using: &rng)), source: .manual))
                }
            }
            // Pressure drop → headache.
            if s.pressureHeadache, Double.random(in: 0..<1, using: &rng) < 0.3 {
                let t = dayStart.addingTimeInterval(8 * 3600)
                events.append(HealthEvent(timestamp: t, timezoneID: tz, category: .environment,
                                          subtype: "pressureDrop", value: 9, unit: "hPa", source: .weatherAPI))
                if Double.random(in: 0..<1, using: &rng) < 0.7 {
                    events.append(HealthEvent(timestamp: t.addingTimeInterval(5 * 3600), timezoneID: tz,
                                              category: .symptom, subtype: "headache",
                                              value: Double(Int.random(in: 4...8, using: &rng)), source: .manual))
                }
            }
            // High stress → tension.
            if s.stressSymptom, Double.random(in: 0..<1, using: &rng) < 0.4 {
                let t = dayStart.addingTimeInterval(14 * 3600)
                events.append(HealthEvent(timestamp: t, timezoneID: tz, category: .stress,
                                          value: Double(Int.random(in: 7...10, using: &rng)), source: .manual))
                if Double.random(in: 0..<1, using: &rng) < 0.65 {
                    events.append(HealthEvent(timestamp: t.addingTimeInterval(3 * 3600), timezoneID: tz,
                                              category: .symptom, subtype: "tension",
                                              value: Double(Int.random(in: 3...7, using: &rng)), source: .manual))
                }
            }
            // Protective: magnesium ~half the days; migraine rare on magnesium days, common off.
            if s.protectiveSupplement {
                let onMag = Double.random(in: 0..<1, using: &rng) < 0.5
                if onMag {
                    events.append(HealthEvent(timestamp: dayStart.addingTimeInterval(8 * 3600), timezoneID: tz,
                                              category: .supplement, subtype: "magnesium",
                                              objectID: magnesium?.id, source: .manual))
                }
                if Double.random(in: 0..<1, using: &rng) < (onMag ? 0.05 : 0.30) {
                    events.append(HealthEvent(timestamp: dayStart.addingTimeInterval(16 * 3600), timezoneID: tz,
                                              category: .symptom, subtype: "migraine",
                                              value: Double(Int.random(in: 4...8, using: &rng)), source: .manual))
                }
            }
            // Confounder: espresso & croissant ALWAYS logged together → jitters. Not separable.
            if s.confounderPair, Double.random(in: 0..<1, using: &rng) < 0.5 {
                let t = dayStart.addingTimeInterval(7 * 3600)
                events.append(HealthEvent(timestamp: t, timezoneID: tz, category: .food,
                                          subtype: "espresso", objectID: espresso?.id, source: .manual))
                events.append(HealthEvent(timestamp: t.addingTimeInterval(300), timezoneID: tz, category: .food,
                                          subtype: "croissant", objectID: croissant?.id, source: .manual))
                if Double.random(in: 0..<1, using: &rng) < 0.7 {
                    events.append(HealthEvent(timestamp: t.addingTimeInterval(2 * 3600), timezoneID: tz,
                                              category: .symptom, subtype: "jitters",
                                              value: Double(Int.random(in: 3...7, using: &rng)), source: .manual))
                }
            }
            // Null effect: vitaminX taken ~half the days, influences nothing (balanced for a clean base rate).
            if s.nullEffectSupplement, Double.random(in: 0..<1, using: &rng) < 0.5 {
                events.append(HealthEvent(timestamp: dayStart.addingTimeInterval(12 * 3600), timezoneID: tz,
                                          category: .supplement, subtype: "vitaminX",
                                          objectID: vitaminX?.id, source: .manual))
            }
        }

        events.sort { $0.timestamp < $1.timestamp }

        // Menstrual cycles every 28 days; cramps concentrated in the luteal window.
        if config.derivedScenarios.lutealSymptom {
            var day = 0
            while day < config.days {
                let start = config.startDate.addingTimeInterval(Double(day) * 86_400)
                events.append(HealthEvent(timestamp: start, timezoneID: tz, category: .cycle,
                                          subtype: "periodStart", source: .manual))
                for back in 1...5 {   // luteal = 5 days before the next start
                    if day + 28 - back < config.days,
                       Double.random(in: 0..<1, using: &rng) < 0.6 {
                        let t = config.startDate.addingTimeInterval(Double(day + 28 - back) * 86_400 + 10 * 3600)
                        events.append(HealthEvent(timestamp: t, timezoneID: tz, category: .symptom,
                                                  subtype: "cramps", value: Double(Int.random(in: 3...7, using: &rng)),
                                                  source: .manual))
                    }
                }
                day += 28
            }
            events.sort { $0.timestamp < $1.timestamp }
        }

        return SyntheticDataset(objects: objects, events: events)
    }
}
