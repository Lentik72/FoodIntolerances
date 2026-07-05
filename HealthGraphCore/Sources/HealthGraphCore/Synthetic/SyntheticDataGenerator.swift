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

public struct SyntheticConfig {
    public var startDate: Date
    public var days: Int
    public var seed: UInt64
    public var patterns: [PlantedPattern]
    public var outcomeBaseRatePerDay: Double
    public var noiseFoodsPerDay: ClosedRange<Int>

    public init(startDate: Date, days: Int, seed: UInt64, patterns: [PlantedPattern],
                outcomeBaseRatePerDay: Double, noiseFoodsPerDay: ClosedRange<Int>) {
        self.startDate = startDate
        self.days = days
        self.seed = seed
        self.patterns = patterns
        self.outcomeBaseRatePerDay = outcomeBaseRatePerDay
        self.noiseFoodsPerDay = noiseFoodsPerDay
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
        }

        events.sort { $0.timestamp < $1.timestamp }
        return SyntheticDataset(objects: objects, events: events)
    }
}
