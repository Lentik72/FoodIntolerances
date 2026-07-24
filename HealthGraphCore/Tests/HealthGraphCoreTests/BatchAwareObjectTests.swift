import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct BatchAwareObjectTests {

    @Test func healthObjectInitDerivesNamespacedNameForDemoBatch() {
        // Model-boundary invariant: a synthetic object namespaces its normalizedName
        // from the batch, WITHOUT any store-side override, while keeping display `name`.
        let real = HealthObject(kind: .food, name: "Coffee")
        let demo = HealthObject(kind: .food, name: "Coffee", syntheticBatch: DemoBatch.mood)
        #expect(real.normalizedName == "coffee")
        #expect(demo.normalizedName == "demo:mood|coffee")
        #expect(demo.name == "Coffee")
        #expect(demo.syntheticBatch == "mood")
    }

    @Test func demoObjectCoexistsWithRealObjectOfSameNameAndKind() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)

        let real = try await store.findOrCreate(name: "Coffee", kind: .food, metadata: nil)
        let demo = try await store.findOrCreate(name: "Coffee", kind: .food, metadata: nil,
                                                syntheticBatch: DemoBatch.mood)

        #expect(real.id != demo.id)                       // distinct rows
        #expect(real.syntheticBatch == nil)
        #expect(demo.syntheticBatch == "mood")
        #expect(real.normalizedName == "coffee")
        #expect(demo.normalizedName == "demo:mood|coffee")
        #expect(real.name == "Coffee" && demo.name == "Coffee")   // display unchanged
        #expect(try await store.count() == 2)             // real row untouched, not merged
    }

    @Test func demoFindOrCreateReusesItsOwnBatchRow() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        let a = try await store.findOrCreate(name: "Magnesium", kind: .supplement, metadata: nil,
                                             syntheticBatch: DemoBatch.mood)
        let b = try await store.findOrCreate(name: "Magnesium", kind: .supplement, metadata: nil,
                                             syntheticBatch: DemoBatch.mood)
        #expect(a.id == b.id)                             // same batch → reuse, no duplicate
        #expect(try await store.count() == 1)
    }

    @Test func demoInsertMarksObjectsAndEventsAndLinksToTheDemoObject() async throws {
        let db = try AppDatabase.inMemory()
        // Seed a real "Coffee" first so the demo must NOT merge into it.
        let realCoffee = try await GRDBObjectStore(database: db)
            .findOrCreate(name: "Coffee", kind: .food, metadata: nil)

        let config = SyntheticConfig(
            startDate: Date(timeIntervalSince1970: 0), days: 10, seed: 1,
            patterns: [PlantedPattern(exposureName: "Coffee", exposureCategory: .food,
                                      outcomeSubtype: "mood", lagHours: 4, lagJitterHours: 2,
                                      followProbability: 0.8, exposureProbabilityPerDay: 0.6)],
            outcomeBaseRatePerDay: 0, noiseFoodsPerDay: 0...0)
        // generate() is neutral; the batch is supplied to insert().
        try await SyntheticDataGenerator.generate(config: config)
            .insert(into: db, batch: DemoBatch.mood)

        // The real Coffee is still present and unmarked; a demo Coffee exists too.
        let coffees = try await GRDBObjectStore(database: db).objects(kind: .food, includeArchived: true)
            .filter { $0.name == "Coffee" }
        #expect(coffees.count == 2)
        #expect(coffees.contains { $0.syntheticBatch == nil })
        let demoCoffee = coffees.first { $0.syntheticBatch == "mood" }
        #expect(demoCoffee != nil)

        // Every seeded event is marked.
        let events = try await GRDBEventStore(database: db)
            .events(in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.syntheticBatch == "mood" })

        // Spec T6: the seeded Coffee EXPOSURE events reference the DEMO Coffee's id,
        // NOT the real one — the exact regression the namespacing prevents.
        let coffeeExposures = events.filter { $0.subtype == "Coffee" && $0.objectID != nil }
        #expect(!coffeeExposures.isEmpty)
        #expect(coffeeExposures.allSatisfy { $0.objectID == demoCoffee?.id })
        #expect(coffeeExposures.allSatisfy { $0.objectID != realCoffee.id })
    }
}
