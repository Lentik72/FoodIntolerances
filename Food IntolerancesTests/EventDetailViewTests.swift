import Testing
@testable import Food_Intolerances

/// Pins `EventDetailView`'s presentation-only metadata filter (I1):
/// provenance-class keys never render as a raw Details-card row.
struct EventDetailViewTests {
    @Test func hidesProvenanceClassKeys() {
        #expect(!EventDetailView.isPresentationVisible(key: "provenance", value: "true"))
        #expect(!EventDetailView.isPresentationVisible(key: "sourceBundleID", value: "com.apple.health"))
        #expect(!EventDetailView.isPresentationVisible(key: "deviceName", value: "Apple Watch"))
    }

    @Test func hidesOnlyAFalseCycleStart() {
        #expect(!EventDetailView.isPresentationVisible(key: "menstrualCycleStart", value: "false"))
        #expect(EventDetailView.isPresentationVisible(key: "menstrualCycleStart", value: "true"))
    }

    @Test func leavesOtherMetadataKeysVisible() {
        // Non-vacuous: an ordinary, unmapped key still renders — the filter
        // hides exactly the provenance-class keys, not everything unknown.
        #expect(EventDetailView.isPresentationVisible(key: "kcal", value: "250"))
        #expect(EventDetailView.isPresentationVisible(key: "someImportedField", value: "x"))
    }
}
