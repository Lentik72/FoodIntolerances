import Testing
@testable import HealthGraphCore

struct NameNormalizerTests {
    @Test func stripsDoseAndLowercases() {
        #expect(NameNormalizer.normalize("Magnesium Glycinate 400mg") == "magnesium glycinate")
    }
    @Test func stripsIUDose() {
        #expect(NameNormalizer.normalize("Vitamin D3 5000 IU") == "vitamin d3")
    }
    @Test func trimsAndCollapsesWhitespace() {
        #expect(NameNormalizer.normalize("  BPC-157   ") == "bpc-157")
    }
    @Test func plainNameUnchangedExceptCase() {
        #expect(NameNormalizer.normalize("Coffee") == "coffee")
    }
    @Test func stripsCapsuleCount() {
        #expect(NameNormalizer.normalize("Omega 3 2 capsules") == "omega 3")
    }
    @Test func enumRawValuesAreStable() {
        // These raw values are persisted to disk — a change is a schema migration.
        #expect(ObjectKind.careProtocol.rawValue == "protocol")
        #expect(EventCategory.protocolMarker.rawValue == "protocolMarker")
        #expect(EventSource.legacyImport.rawValue == "legacyImport")
    }
}
