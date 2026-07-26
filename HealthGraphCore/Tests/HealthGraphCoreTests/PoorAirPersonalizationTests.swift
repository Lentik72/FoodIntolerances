import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct PoorAirPersonalizationTests {
    // Minimal edge builder — only the fields the pick reads.
    func edge(from: String? = "poorAirDay", to: String? = "symptom", type: RelationshipType = .possibleTrigger,
              status: RelStatus = .active, confidence: Double = 0.5, evidence: Int = 1,
              subtype: String?) -> Relationship {
        Relationship(fromCategory: from, toCategory: to, type: type,
                     evidenceCount: evidence, confidence: confidence,
                     firstSeen: Date(timeIntervalSince1970: 0), lastSeen: Date(timeIntervalSince1970: 0),
                     lastRecomputed: Date(timeIntervalSince1970: 0), status: status, toSubtype: subtype)
    }

    @Test func picksTheOnlyQualifyingEdge() {
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: [edge(subtype: "cough")]) == "cough")
    }
    @Test func nilWhenNoQualifyingEdge() {
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: []) == nil)
    }
    @Test func ignoresWrongStatusCategoryOrType() {
        let bad = [
            edge(status: .decayed, subtype: "a"),
            edge(from: "hotDay", subtype: "b"),
            edge(to: "mood", subtype: "c"),
            edge(type: .improves, subtype: "d"),
        ]
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: bad) == nil)
    }
    @Test func tiebreakByConfidenceThenEvidenceThenRawSubtype() {
        // Same confidence+evidence → lower raw subtype wins ("aaa" < "zzz").
        let a = edge(confidence: 0.7, evidence: 5, subtype: "zzz")
        let b = edge(confidence: 0.7, evidence: 5, subtype: "aaa")
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: [a, b]) == "aaa")
        // Higher confidence wins regardless of evidence/name.
        let c = edge(confidence: 0.9, evidence: 1, subtype: "zzz")
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: [b, c]) == "zzz")
        // Equal confidence → higher evidence wins.
        let d = edge(confidence: 0.7, evidence: 9, subtype: "mmm")
        #expect(PoorAirPersonalization.bestSymptomSubtype(from: [b, d]) == "mmm")
    }
}
