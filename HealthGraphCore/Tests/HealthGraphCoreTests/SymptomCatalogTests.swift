import Foundation
import Testing
@testable import HealthGraphCore

struct SymptomCatalogTests {
    @Test func catalogIsNonEmptyAndDeduped() {
        #expect(SymptomCatalog.all.count >= 100)
        let keys = SymptomCatalog.all.map(\.canonicalKey)
        #expect(Set(keys).count == keys.count)   // no dupes
    }
    @Test func canonicalKeyRoundTripsWithEventDisplay() {
        #expect(SymptomCatalog.canonicalKey(for: "Headache") == "headache")
        #expect(SymptomCatalog.canonicalKey(for: "Sinus Pain") == "sinusPain")
        // A brand-new symptom the user types canonicalizes the same way.
        #expect(SymptomCatalog.canonicalKey(for: "Weird New Thing") == "weirdNewThing")
    }
    @Test func searchIsCaseInsensitiveAndRanksPrefix() {
        let hits = SymptomCatalog.search("head")
        #expect(hits.contains { $0.displayName == "Headache" })
        #expect(SymptomCatalog.search("   ").isEmpty)
    }
    @Test func displayNameReversesKnownKeyElseTitleCases() {
        #expect(SymptomCatalog.displayName(for: "headache") == "Headache")
        #expect(SymptomCatalog.displayName(for: "sinusPain") == "Sinus Pain")
    }
}
