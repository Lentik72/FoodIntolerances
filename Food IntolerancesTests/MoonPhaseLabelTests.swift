import Testing
import Foundation
import UIKit
import HealthGraphCore
@testable import Food_Intolerances

struct MoonPhaseLabelTests {
    // Mapping — all eight cleaned canonical names → their exact moonphase.* symbol.
    @Test func mapsAllEightCanonicalPhases() {
        #expect(moonPhaseSymbolName(for: "New Moon") == "moonphase.new.moon")
        #expect(moonPhaseSymbolName(for: "Waxing Crescent") == "moonphase.waxing.crescent")
        #expect(moonPhaseSymbolName(for: "First Quarter") == "moonphase.first.quarter")
        #expect(moonPhaseSymbolName(for: "Waxing Gibbous") == "moonphase.waxing.gibbous")
        #expect(moonPhaseSymbolName(for: "Full Moon") == "moonphase.full.moon")
        #expect(moonPhaseSymbolName(for: "Waning Gibbous") == "moonphase.waning.gibbous")
        #expect(moonPhaseSymbolName(for: "Last Quarter") == "moonphase.last.quarter")
        #expect(moonPhaseSymbolName(for: "Waning Crescent") == "moonphase.waning.crescent")
    }
    // String equality alone can't prove the symbol NAMES are real — resolve each
    // against the system symbol catalog so a typo'd name fails here, not on device.
    @Test func allMappedSymbolNamesExist() throws {
        let phases = [
            "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
            "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent",
        ]
        for phase in phases {
            let name = try #require(moonPhaseSymbolName(for: phase))
            #expect(UIImage(systemName: name) != nil)
        }
    }
    @Test func normalizesCaseAndWhitespace() {
        #expect(moonPhaseSymbolName(for: "full moon") == "moonphase.full.moon")
        #expect(moonPhaseSymbolName(for: "FULL MOON") == "moonphase.full.moon")
        #expect(moonPhaseSymbolName(for: "  Full Moon ") == "moonphase.full.moon")
        #expect(moonPhaseSymbolName(for: "Full Moon\n") == "moonphase.full.moon")
    }
    @Test func unknownPhaseReturnsNil() {
        #expect(moonPhaseSymbolName(for: "Blood Moon") == nil)
        #expect(moonPhaseSymbolName(for: "") == nil)
    }

    // Extractor — structural gate (.environment + "moonPhase") + metadata decode.
    private func event(category: EventCategory = .environment, subtype: String? = "moonPhase",
                       metadata: Data?) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 43_200), category: category,
                    subtype: subtype, source: .weatherAPI, metadata: metadata)
    }
    private func phaseMeta(_ phase: String) -> Data { try! JSONEncoder().encode(["phase": phase]) }

    @Test func extractsPhaseFromWellFormedEvent() {
        #expect(moonPhaseName(for: event(metadata: phaseMeta("Waxing Gibbous"))) == "Waxing Gibbous")
    }
    @Test func wrongSubtypeOrCategoryReturnsNil() {
        #expect(moonPhaseName(for: event(subtype: "season", metadata: phaseMeta("Full Moon"))) == nil)
        #expect(moonPhaseName(for: event(subtype: "airQuality", metadata: phaseMeta("Full Moon"))) == nil)
        #expect(moonPhaseName(for: event(subtype: nil, metadata: phaseMeta("Full Moon"))) == nil)
        #expect(moonPhaseName(for: event(category: .symptom, metadata: phaseMeta("Full Moon"))) == nil)
    }
    @Test func missingOrMalformedMetadataReturnsNil() {
        #expect(moonPhaseName(for: event(metadata: nil)) == nil)
        #expect(moonPhaseName(for: event(metadata: Data([0xFF, 0x00]))) == nil)               // undecodable bytes
        #expect(moonPhaseName(for: event(metadata: try! JSONEncoder().encode(["other": "x"]))) == nil)   // no "phase" key
    }
}
