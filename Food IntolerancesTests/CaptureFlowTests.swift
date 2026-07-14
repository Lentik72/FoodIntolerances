import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct CaptureFlowTests {
    private func db() throws -> AppDatabase { try AppDatabase.inMemory() }

    @Test func symptomModelRanksChipsAndLogsAtSeverity() async throws {
        let database = try db()
        let store = GRDBEventStore(database: database)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save([
            HealthEvent(timestamp: base, category: .symptom, subtype: "headache", value: 5, unit: "severity", source: .manual, createdAt: base),
            HealthEvent(timestamp: base, category: .symptom, subtype: "headache", value: 6, unit: "severity", source: .manual, createdAt: base),
            HealthEvent(timestamp: base, category: .symptom, subtype: "nausea", value: 3, unit: "severity", source: .manual, createdAt: base),
        ])
        let model = SymptomCaptureModel(database: database, now: { base })
        await model.loadChips()
        #expect(model.chipKeys.first == "headache")   // most frequent+recent
        // Chip → severity tap logs immediately; save strictly later so it sorts first.
        let e = await model.log(key: "headache", severity: 7, note: nil, at: base.addingTimeInterval(60))
        #expect(e?.value == 7)
        let page = try await store.eventsPage(before: nil, limit: 10, categories: [.symptom], sources: nil)
        #expect(page.count == 4)                       // 3 seeded + 1 logged
        #expect(page.first?.value == 7)                // the just-logged (newest) event
    }
    @Test func symptomNewKeyCanonicalizesTypedText() async throws {
        let model = SymptomCaptureModel(database: try db())
        model.searchText = "Sinus Pain"
        #expect(model.newKey() == "sinusPain")
    }
    @Test func mealModelLogsFoodEventAndObject() async throws {
        let database = try db()
        let objects = GRDBObjectStore(database: database)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let model = MealCaptureModel(database: database)
        let e = await model.log(name: "Oat milk latte", at: base)
        #expect(e?.category == .food)
        #expect(try await objects.count() == 1)
    }
    @Test func doseModelFormLogsLinkedPeptideEvent() async throws {
        let database = try db()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let model = DoseCaptureModel(database: database)
        model.kind = .peptide; model.substance = "Semaglutide"; model.amountText = "0.25"; model.unit = "mg"; model.route = "subQ"
        let e = await model.saveForm(at: base)
        #expect(e?.category == .peptide)
        #expect(e?.value == 0.25)
        #expect(e?.objectID != nil)
    }
    @Test func doseChipRepeatsLastAmountForSubstance() async throws {
        let database = try db()
        let store = GRDBEventStore(database: database)
        let objects = GRDBObjectStore(database: database)
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let obj = try await objects.findOrCreate(name: "Vitamin D3", kind: .supplement, metadata: nil)
        try await store.save(HealthEvent(timestamp: base, category: .supplement, subtype: "Vitamin D3",
                                         objectID: obj.id, value: 2000, unit: "iu", source: .manual, createdAt: base))
        let model = DoseCaptureModel(database: database, now: { base })
        await model.loadChips()
        let e = await model.logChip(substance: "Vitamin D3", at: base.addingTimeInterval(60))
        #expect(e?.value == 2000)   // repeats the last logged amount
        #expect(e?.unit == "iu")
    }
}
