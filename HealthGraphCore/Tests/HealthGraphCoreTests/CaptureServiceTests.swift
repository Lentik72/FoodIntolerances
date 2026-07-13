import Foundation
import Testing
@testable import HealthGraphCore

struct CaptureServiceTests {
    let base = Date(timeIntervalSince1970: 1_750_000_000)

    private func make() throws -> (AppDatabase, CaptureService, GRDBEventStore, GRDBObjectStore) {
        let db = try AppDatabase.inMemory()
        return (db, CaptureService(database: db), GRDBEventStore(database: db), GRDBObjectStore(database: db))
    }

    @Test func logSymptomWritesSeverityEvent() async throws {
        let (_, capture, store, _) = try make()
        let event = try await capture.logSymptom(canonicalKey: "headache", severity: 6, at: base, note: nil)
        #expect(event.category == .symptom)
        #expect(event.subtype == "headache")
        #expect(event.value == 6)
        #expect(event.unit == "severity")
        #expect(event.source == .manual)
        #expect(event.dedupKey == nil)
        #expect(event.confidence == 1.0)   // manual capture is full-confidence
        let page = try await store.eventsPage(before: nil, limit: 10, categories: nil, sources: nil)
        #expect(page.map(\.id) == [event.id])
    }

    @Test func logSymptomUnratedHasNoValueAndNoteGoesToMetadata() async throws {
        let (_, capture, _, _) = try make()
        let event = try await capture.logSymptom(canonicalKey: "nausea", severity: nil, at: base, note: "after lunch")
        #expect(event.value == nil)
        #expect(event.unit == nil)
        let dict = try JSONDecoder().decode([String: String].self, from: #require(event.metadata))
        #expect(dict["note"] == "after lunch")
    }

    @Test func logMealCreatesFoodObjectAndLinks() async throws {
        let (_, capture, _, objects) = try make()
        let event = try await capture.logMeal(name: "Oat milk latte", at: base)
        #expect(event.category == .food)
        #expect(event.subtype == "Oat milk latte")
        let obj = try await objects.object(id: #require(event.objectID))
        #expect(obj?.kind == .food)
        #expect(obj?.name == "Oat milk latte")
        // Logging the same meal reuses the one object (find-or-create).
        let again = try await capture.logMeal(name: "oat milk latte", at: base.addingTimeInterval(60))
        #expect(again.objectID == event.objectID)
        #expect(try await objects.count() == 1)
    }

    @Test func logDoseLinksMatchingKindObjectWithAmountUnitAndRoute() async throws {
        let (_, capture, _, objects) = try make()
        let event = try await capture.logDose(substance: "Semaglutide", kind: .peptide,
                                              amount: 0.25, unit: "mg", route: "subQ", at: base)
        #expect(event.category == .peptide)
        #expect(event.subtype == "Semaglutide")
        #expect(event.value == 0.25)
        #expect(event.unit == "mg")
        let obj = try await objects.object(id: #require(event.objectID))
        #expect(obj?.kind == .peptide)
        let dict = try JSONDecoder().decode([String: String].self, from: #require(event.metadata))
        #expect(dict["route"] == "subQ")
    }

    @Test func logNoteStoresTextInSubtype() async throws {
        let (_, capture, store, _) = try make()
        let event = try await capture.logNote(text: "Felt wired after coffee", at: base)
        #expect(event.category == .note)
        #expect(event.subtype == "Felt wired after coffee")
        // Searchable immediately via the v3 FTS over subtype.
        #expect(try await store.searchEvents(matching: "wired", limit: 10).map(\.id) == [event.id])
    }
}
