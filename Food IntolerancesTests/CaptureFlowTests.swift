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
}
