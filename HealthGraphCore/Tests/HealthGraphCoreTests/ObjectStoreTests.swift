import Testing
import Foundation
import GRDB
@testable import HealthGraphCore

struct ObjectStoreTests {
    @Test func findOrCreateDedupsOnNormalizedName() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        let a = try await store.findOrCreate(name: "Magnesium Glycinate 400mg", kind: .supplement, metadata: nil)
        let b = try await store.findOrCreate(name: "magnesium glycinate", kind: .supplement, metadata: nil)
        #expect(a.id == b.id)
        let total = try await store.count()
        #expect(total == 1)
    }

    @Test func sameNameDifferentKindCreatesSeparateObjects() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        let food = try await store.findOrCreate(name: "Ginger", kind: .food, metadata: nil)
        let supp = try await store.findOrCreate(name: "Ginger", kind: .supplement, metadata: nil)
        #expect(food.id != supp.id)
        let total = try await store.count()
        #expect(total == 2)
    }

    @Test func archivedObjectsAreHiddenByDefault() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        let obj = try await store.findOrCreate(name: "Old Med", kind: .medication, metadata: nil)
        try await store.setArchived(id: obj.id, true)
        let visible = try await store.objects(kind: .medication, includeArchived: false)
        #expect(visible.isEmpty)
        let all = try await store.objects(kind: .medication, includeArchived: true)
        #expect(all.count == 1)
    }

    @Test func kindNilReturnsAllKinds() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        _ = try await store.findOrCreate(name: "Coffee", kind: .food, metadata: nil)
        _ = try await store.findOrCreate(name: "BPC-157", kind: .peptide, metadata: nil)
        let all = try await store.objects(kind: nil, includeArchived: false)
        #expect(all.count == 2)
    }

    @Test func databaseEnforcesUniqueNormalizedNamePerKind() throws {
        // The uniqueKey constraint backs up findOrCreate at the DB layer:
        // even a direct insert cannot create a duplicate.
        let db = try AppDatabase.inMemory()
        let a = HealthObject(kind: .supplement, name: "Zinc 25mg")
        let b = HealthObject(kind: .supplement, name: "zinc")
        try db.dbWriter.write { try a.insert($0) }
        #expect(throws: (any Error).self) {
            try db.dbWriter.write { try b.insert($0) }
        }
    }

    @Test func findOrCreateMatchKeepsExistingMetadata() async throws {
        let db = try AppDatabase.inMemory()
        let store = GRDBObjectStore(database: db)
        let original = try JSONEncoder().encode(["brand": "NOW Foods"])
        let first = try await store.findOrCreate(name: "Zinc 25mg", kind: .supplement,
                                                 metadata: original)
        // The migrator and ingest paths depend on this: a match returns the
        // EXISTING object untouched — later metadata never overwrites earlier.
        let second = try await store.findOrCreate(name: "zinc", kind: .supplement,
                                                  metadata: try JSONEncoder().encode(["brand": "other"]))
        #expect(second.id == first.id)
        #expect(second.metadata == original)
        let refetched = try await store.object(id: first.id)
        #expect(refetched?.metadata == original)
    }
}
