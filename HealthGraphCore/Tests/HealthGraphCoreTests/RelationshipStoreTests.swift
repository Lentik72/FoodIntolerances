import Testing
import Foundation
@testable import HealthGraphCore

struct RelationshipStoreTests {
    func rel(confidence: Double, status: RelStatus, from: UUID? = nil) -> Relationship {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        return Relationship(
            fromObjectID: from, fromCategory: from == nil ? "food" : nil,
            toCategory: "symptom", type: .possibleTrigger,
            confidence: confidence, firstSeen: now, lastSeen: now,
            lastRecomputed: now, status: status
        )
    }

    @Test func saveUpsertsById() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBRelationshipStore(database: db)
        var r = rel(confidence: 0.4, status: .candidate)
        try await store.save(r)
        r.confidence = 0.7
        r.status = .active
        try await store.save(r)
        let total = try await store.count()
        #expect(total == 1)
        let fetched = try await store.relationship(id: r.id)
        #expect(fetched?.confidence == 0.7)
        #expect(fetched?.status == .active)
    }

    @Test func filtersByStatusOrderedByConfidence() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBRelationshipStore(database: db)
        try await store.save(rel(confidence: 0.5, status: .active))
        try await store.save(rel(confidence: 0.9, status: .active))
        try await store.save(rel(confidence: 0.2, status: .decayed))
        let active = try await store.relationships(status: .active)
        #expect(active.map(\.confidence) == [0.9, 0.5])
        let all = try await store.relationships(status: nil)
        #expect(all.count == 3)
    }

    @Test func filtersByFromObject() async throws {
        let db = try AppDatabase.inMemory()
        let objects = GRDBObjectStore(database: db)
        let dairy = try await objects.findOrCreate(name: "Dairy", kind: .food, metadata: nil)
        let store = GRDBRelationshipStore(database: db)
        try await store.save(rel(confidence: 0.6, status: .active, from: dairy.id))
        try await store.save(rel(confidence: 0.3, status: .candidate))
        let forDairy = try await store.relationships(fromObjectID: dairy.id)
        #expect(forDairy.count == 1)
    }
}
