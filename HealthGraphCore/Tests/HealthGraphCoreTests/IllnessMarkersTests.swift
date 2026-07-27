import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct IllnessMarkersTests {
    @Test func everyHealthKitIllnessIdentifierResolvesToARealCatalogKey() {
        let catalog = Set(SymptomCatalog.all.map(\.canonicalKey))
        #expect(!IllnessMarkers.healthKitIdentifierSubtypes.isEmpty)   // non-vacuous
        #expect(IllnessMarkers.healthKitIdentifierSubtypes.count == 8)
        for hk in IllnessMarkers.healthKitIdentifierSubtypes {
            let normalized = IllnessMarkers.normalize(healthKitSubtype: hk)
            #expect(catalog.contains(normalized))   // no HK identifier is left unmapped
        }
    }

    @Test func theTwoRealAliasesAreMapped() {
        #expect(IllnessMarkers.normalize(healthKitSubtype: "coughing") == "cough")
        #expect(IllnessMarkers.normalize(healthKitSubtype: "sinusCongestion") == "congestion")
    }

    @Test func theOtherSixAreIdentity() {
        for s in ["fever", "chills", "nightSweats", "soreThroat", "runnyNose", "generalizedBodyAche"] {
            #expect(IllnessMarkers.normalize(healthKitSubtype: s) == s)
        }
    }

    @Test func feverAloneQualifies() {
        #expect(IllnessMarkers.isIllnessDay(subtypes: ["fever"]))
    }

    @Test func twoCompositeMarkersQualify() {
        #expect(IllnessMarkers.isIllnessDay(subtypes: ["cough", "soreThroat"]))
    }

    @Test func oneCompositeMarkerDoesNot() {
        #expect(!IllnessMarkers.isIllnessDay(subtypes: ["cough"]))
        #expect(!IllnessMarkers.isIllnessDay(subtypes: ["chills"]))
        #expect(!IllnessMarkers.isIllnessDay(subtypes: ["nightSweats"]))
    }

    @Test func runnyNoseIsNormalizedButIsNotAMarker() {
        // Searchable and mapped, deliberately not a classifier input: too
        // common and nonspecific (allergies) to penalise every exposure that day.
        #expect(!IllnessMarkers.isIllnessDay(subtypes: ["runnyNose", "cough"]))
    }

    @Test func aliasedHealthKitSubtypesCountTowardTheComposite() {
        let normalized = ["coughing", "sinusCongestion"].map { IllnessMarkers.normalize(healthKitSubtype: $0) }
        #expect(IllnessMarkers.isIllnessDay(subtypes: Set(normalized)))
    }
}

@Suite struct IllnessDaysTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func symptom(_ subtype: String, dayOffset: Int) -> HealthEvent {
        let t = t0.addingTimeInterval(Double(dayOffset) * 86_400)
        return HealthEvent(timestamp: t, timezoneID: "UTC", category: .symptom,
                           subtype: subtype, value: 5, source: .manual, createdAt: t)
    }

    @Test func explicitIllnessEventsStillCount() async throws {
        let db = try AppDatabase.inMemory()
        let engine = EvidenceEngine(database: db)
        let e = HealthEvent(timestamp: t0, timezoneID: "UTC", category: .illness,
                            subtype: "cold", source: .manual, createdAt: t0)
        #expect(engine.illnessDays([e]).count == 1)
    }

    @Test func feverSymptomMarksTheDay() async throws {
        let db = try AppDatabase.inMemory()
        let engine = EvidenceEngine(database: db)
        #expect(engine.illnessDays([symptom("fever", dayOffset: 0)]).count == 1)
    }

    @Test func aLoneCoughDoesNotMarkTheDay() async throws {
        let db = try AppDatabase.inMemory()
        let engine = EvidenceEngine(database: db)
        #expect(engine.illnessDays([symptom("cough", dayOffset: 0)]).isEmpty)
    }

    @Test func twoMarkersOnTheSameDayMarkIt_butSpreadAcrossDaysDoNot() async throws {
        let db = try AppDatabase.inMemory()
        let engine = EvidenceEngine(database: db)
        let sameDay = [symptom("cough", dayOffset: 0), symptom("soreThroat", dayOffset: 0)]
        #expect(engine.illnessDays(sameDay).count == 1)

        let differentDays = [symptom("cough", dayOffset: 0), symptom("soreThroat", dayOffset: 3)]
        #expect(engine.illnessDays(differentDays).isEmpty)
    }
}
