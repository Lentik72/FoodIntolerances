import Testing
import Foundation
import SwiftData
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct SwiftDataMigratorTests {
    func makeContext() throws -> ModelContext {
        StringArrayTransformer.register()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LogEntry.self, TrackedItem.self, AvoidedItem.self, CabinetItem.self,
            OngoingSymptom.self, SymptomCheckIn.self, TherapyProtocol.self,
            TherapyProtocolItem.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func migratesSymptomLogEntry() async throws {
        let context = try makeContext()
        let entry = LogEntry(
            itemName: "Headache", itemType: .symptom, category: "Neurological",
            symptoms: ["Headache"], severity: 4, notes: "after lunch",
            date: Date(timeIntervalSince1970: 1_740_000_000),
            moonPhase: "Full Moon", atmosphericPressure: "Falling",
            suddenChange: true, isMercuryRetrograde: false, season: "Winter"
        )
        context.insert(entry)
        try context.save()

        let db = try AppDatabase.inMemory()
        let report = try await SwiftDataMigrator.run(context: context, database: db, force: true)

        #expect(report.logEntriesMigrated == 1)
        #expect(report.eventsCreated == 1)
        let events = GRDBEventStore(database: db)
        let all = try await events.recentEvents(limit: 10)
        #expect(all.count == 1)
        #expect(all.first?.category == .symptom)
        #expect(all.first?.subtype == "Headache")
        #expect(all.first?.value == 4)
        #expect(all.first?.source == .legacyImport)
        let meta = try JSONDecoder().decode(
            [String: String].self, from: all.first?.metadata ?? Data())
        #expect(meta["legacyID"] == entry.id.uuidString)
        #expect(meta["moonPhase"] == "Full Moon")
        #expect(meta["notes"] == "after lunch")
    }

    @Test func migratesTrackedItemsWithDedup() async throws {
        let context = try makeContext()
        context.insert(TrackedItem(name: "Magnesium Glycinate 400mg", type: .supplement))
        context.insert(TrackedItem(name: "magnesium glycinate", type: .supplement))
        context.insert(TrackedItem(name: "Ibuprofen", type: .medication, isActive: false))
        try context.save()

        let db = try AppDatabase.inMemory()
        let report = try await SwiftDataMigrator.run(context: context, database: db, force: true)

        #expect(report.trackedItemsMigrated == 3)
        let objects = GRDBObjectStore(database: db)
        let objectCount = try await objects.count()
        #expect(objectCount == 2) // magnesium deduped
        let meds = try await objects.objects(kind: .medication, includeArchived: true)
        #expect(meds.first?.isArchived == true) // inactive -> archived
    }

    @Test func migratesOngoingSymptomWithCheckIns() async throws {
        let context = try makeContext()
        let ongoing = OngoingSymptom(
            name: "Back pain",
            startDate: Date(timeIntervalSince1970: 1_740_000_000)
        )
        context.insert(ongoing)
        context.insert(SymptomCheckIn(
            parentSymptomID: ongoing.id,
            date: Date(timeIntervalSince1970: 1_740_086_400),
            severity: 5
        ))
        try context.save()

        let db = try AppDatabase.inMemory()
        let report = try await SwiftDataMigrator.run(context: context, database: db, force: true)

        #expect(report.ongoingSymptomsMigrated == 1)
        #expect(report.checkInsMigrated == 1)
        let events = GRDBEventStore(database: db)
        let all = try await events.recentEvents(limit: 10)
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.category == .symptom })
        #expect(all.contains { $0.subtype == "Back pain" && $0.value == 5 }) // check-in inherits name
    }

    @Test func forcedMigrationIsIdempotent() async throws {
        // Multi-entity fixture: one of each proven-crash-safe legacy model.
        // (TherapyProtocol/AvoidedItem/CabinetItem are deliberately excluded —
        // see the KNOWN ISSUE comment on migratesObjectsFromAvoidedCabinetAndProtocols;
        // their idempotence rides the same deterministic-UUID mechanism.)
        let context = try makeContext()
        context.insert(LogEntry(
            itemName: "Headache", itemType: .symptom, category: "Neurological",
            symptoms: ["Headache"], severity: 5, notes: "",
            date: Date(timeIntervalSince1970: 1_740_010_000),
            moonPhase: "", atmosphericPressure: "Normal",
            suddenChange: false, isMercuryRetrograde: false, season: "Winter",
            treatments: [Treatment(
                type: "Medication", name: "Ibuprofen",
                startDate: Date(timeIntervalSince1970: 1_740_012_000),
                endDate: nil, dosage: "400mg", effectiveness: 4, notes: nil)]
        ))
        context.insert(LogEntry(
            itemName: "Lunch", itemType: .foodDrink, category: "Food",
            symptoms: [], severity: 1, notes: "",
            date: Date(timeIntervalSince1970: 1_740_000_000),
            moonPhase: "", atmosphericPressure: "Normal",
            suddenChange: false, isMercuryRetrograde: false, season: "Winter",
            foodDrinkItem: "Cheese sandwich"
        ))
        context.insert(TrackedItem(name: "Magnesium", type: .supplement))
        let ongoing = OngoingSymptom(
            name: "Back pain", startDate: Date(timeIntervalSince1970: 1_740_000_000))
        context.insert(ongoing)
        context.insert(SymptomCheckIn(
            parentSymptomID: ongoing.id,
            date: Date(timeIntervalSince1970: 1_740_086_400), severity: 5))
        try context.save()

        let db = try AppDatabase.inMemory()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try await SwiftDataMigrator.run(
            context: context, database: db, force: true, attachmentsDirectory: dir)
        let eventsAfterFirst = try await GRDBEventStore(database: db).count()
        let objectsAfterFirst = try await GRDBObjectStore(database: db).count()
        #expect(eventsAfterFirst == 5) // symptom + treatment + food + ongoing + check-in

        _ = try await SwiftDataMigrator.run(
            context: context, database: db, force: true, attachmentsDirectory: dir)
        let eventsAfterSecond = try await GRDBEventStore(database: db).count()
        let objectsAfterSecond = try await GRDBObjectStore(database: db).count()
        #expect(eventsAfterSecond == eventsAfterFirst) // deterministic ids: upsert, never duplicate
        #expect(objectsAfterSecond == objectsAfterFirst)
    }

    @Test func migratesTreatmentsOnFoodDrinkEntries() async throws {
        let context = try makeContext()
        context.insert(LogEntry(
            itemName: "Dinner", itemType: .foodDrink, category: "Food",
            symptoms: [], severity: 1, notes: "",
            date: Date(timeIntervalSince1970: 1_740_000_000),
            moonPhase: "", atmosphericPressure: "Normal",
            suddenChange: false, isMercuryRetrograde: false, season: "Winter",
            foodDrinkItem: "Curry",
            treatments: [Treatment(
                type: "Medication", name: "Antacid",
                startDate: Date(timeIntervalSince1970: 1_740_003_600),
                endDate: nil, dosage: "10mg", effectiveness: 3, notes: nil)]
        ))
        try context.save()

        let db = try AppDatabase.inMemory()
        let report = try await SwiftDataMigrator.run(context: context, database: db, force: true)

        #expect(report.eventsCreated == 2) // food + its treatment
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.contains { $0.category == .medication && $0.subtype == "Antacid" })
    }

    @Test func migratesFoodEntryAndTreatments() async throws {
        let context = try makeContext()
        let food = LogEntry(
            itemName: "Lunch", itemType: .foodDrink, category: "Food",
            symptoms: [], severity: 1, notes: "",
            date: Date(timeIntervalSince1970: 1_740_000_000),
            moonPhase: "", atmosphericPressure: "Normal",
            suddenChange: false, isMercuryRetrograde: false, season: "Winter",
            foodDrinkItem: "Cheese sandwich"
        )
        let symptom = LogEntry(
            itemName: "Headache", itemType: .symptom, category: "Neurological",
            symptoms: ["Headache"], severity: 5, notes: "",
            date: Date(timeIntervalSince1970: 1_740_010_000),
            moonPhase: "", atmosphericPressure: "Normal",
            suddenChange: false, isMercuryRetrograde: false, season: "Winter",
            treatments: [Treatment(
                type: "Medication", name: "Ibuprofen",
                startDate: Date(timeIntervalSince1970: 1_740_012_000),
                endDate: nil, dosage: "400mg", effectiveness: 4, notes: nil)]
        )
        context.insert(food)
        context.insert(symptom)
        try context.save()

        let db = try AppDatabase.inMemory()
        let report = try await SwiftDataMigrator.run(context: context, database: db, force: true)

        #expect(report.eventsCreated == 3) // food + symptom + treatment
        let all = try await GRDBEventStore(database: db).recentEvents(limit: 10)
        #expect(all.contains { $0.category == .food && $0.subtype == "Cheese sandwich" })
        #expect(all.contains { $0.category == .medication && $0.subtype == "Ibuprofen" })
        let objectCount = try await GRDBObjectStore(database: db).count()
        #expect(objectCount == 2) // cheese sandwich + ibuprofen
    }

    /// KNOWN ISSUE: This test crashes during Apple's SwiftData/CoreData teardown machinery.
    /// Root cause (extensively bisected): inserting and saving a bare TherapyProtocol @Model
    /// (which uses @Attribute(.transformable(by: StringArrayTransformer.self))) into an
    /// in-memory ModelContainer triggers a framework-level crash. This is a pre-existing defect
    /// in either the Apple framework or the TherapyProtocol/StringArrayTransformer model code.
    /// Reproduced reliably on iOS 18.5 and 26.5 simulator runtimes after full DerivedData wipes.
    /// WORKAROUND: Run this suite with `-parallel-testing-enabled NO`. Under default parallel
    /// execution, the crash kills a simulator clone mid-batch, causing all 8 tests on that clone
    /// to report "failed (0.000s)" even if 7 genuinely passed — masking the real status.
    /// DO NOT disable or skip this test; the workaround is a test-run flag, not code changes.
    @Test func migratesObjectsFromAvoidedCabinetAndProtocols() async throws {
        let context = try makeContext()
        context.insert(AvoidedItem(name: "Gluten", type: .food, reason: "bloating"))
        context.insert(CabinetItem(name: "Ibuprofen", category: "Medications", currentStock: 12))
        let proto = TherapyProtocol(
            title: "Migraine protocol", category: "Pain Management",
            instructions: "Dark room + magnesium", frequency: "As needed",
            timeOfDay: "Evening", duration: "1 week", symptoms: ["Headache"],
            startDate: Date(timeIntervalSince1970: 1_740_000_000)
        )
        context.insert(proto)
        let item = TherapyProtocolItem(itemName: "Magnesium", parentProtocol: proto,
                                       dosageOrQuantity: "400mg")
        context.insert(item)
        proto.items.append(item)
        try context.save()

        let db = try AppDatabase.inMemory()
        let report = try await SwiftDataMigrator.run(context: context, database: db, force: true)

        #expect(report.avoidedItemsMigrated == 1)
        #expect(report.cabinetItemsMigrated == 1)
        #expect(report.protocolsMigrated == 1)
        let protocols = try await GRDBObjectStore(database: db)
            .objects(kind: .careProtocol, includeArchived: true)
        #expect(protocols.count == 1)
        let meta = try JSONDecoder().decode(
            [String: String].self, from: protocols.first?.metadata ?? Data())
        #expect(meta["items"]?.contains("Magnesium") == true)
        #expect(meta["category"] == "Pain Management")
    }

    @Test func sourceStoreUntouchedAndFlagRespected() async throws {
        let context = try makeContext()
        context.insert(TrackedItem(name: "Zinc", type: .supplement))
        try context.save()
        let db = try AppDatabase.inMemory()
        _ = try await SwiftDataMigrator.run(context: context, database: db, force: true)
        // legacy store is unchanged (read-only source)
        let legacyCount = try context.fetchCount(FetchDescriptor<TrackedItem>())
        #expect(legacyCount == 1)
        // the completed flag short-circuits non-forced runs
        UserDefaults.standard.set(true, forKey: SwiftDataMigrator.completedFlagKey)
        defer { UserDefaults.standard.removeObject(forKey: SwiftDataMigrator.completedFlagKey) }
        let skipped = try await SwiftDataMigrator.run(context: context, database: db, force: false)
        #expect(skipped == SwiftDataMigrator.Report())
    }

    @Test func savesAttachmentFileToDisk() async throws {
        let context = try makeContext()
        let entry = LogEntry(
            itemName: "Rash", itemType: .symptom, category: "Skin",
            symptoms: ["Rash"], severity: 3, notes: "",
            date: Date(timeIntervalSince1970: 1_740_000_000),
            moonPhase: "", atmosphericPressure: "Normal",
            suddenChange: false, isMercuryRetrograde: false, season: "Winter",
            symptomPhotoData: Data([0xFF, 0xD8, 0xFF, 0xE0])
        )
        context.insert(entry)
        try context.save()

        let db = try AppDatabase.inMemory()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let report = try await SwiftDataMigrator.run(
            context: context, database: db, force: true, attachmentsDirectory: dir)

        #expect(report.attachmentsSaved == 1)
        #expect(report.attachmentFailures == 0)
        let file = dir.appendingPathComponent("\(entry.id.uuidString).jpg")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
