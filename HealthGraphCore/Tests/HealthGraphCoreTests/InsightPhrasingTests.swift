import Testing
import Foundation
@testable import HealthGraphCore

struct InsightPhrasingTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    func rel(type: RelationshipType, confidence: Double, toSubtype: String,
             strength: Double? = 5, lagHours: Double? = 12, ev: Int = 6, contra: Int = 2) -> Relationship {
        Relationship(fromCategory: "food", toCategory: "symptom", type: type,
                     evidenceCount: ev, contradictionCount: contra, confidence: confidence,
                     strength: strength, lagHours: lagHours, firstSeen: now, lastSeen: now,
                     lastRecomputed: now, status: .active, edgeKey: "k", toSubtype: toSubtype)
    }
    func resolved(_ r: Relationship, exposure: String = "Dairy", outcome: String = "bloating",
                  recent: [Bool] = []) -> ResolvedRelationship {
        ResolvedRelationship(relationship: r, exposureLabel: exposure, outcomeLabel: outcome,
                             exposureCategory: .food, recentOutcomes: recent)
    }

    @Test func triggerClaimBadgeSublineCountLine() {
        let rr = resolved(rel(type: .possibleTrigger, confidence: 0.6, toSubtype: "bloating"),
                          recent: [true, true, false, true, true, true, false, true])   // 6 of 8
        #expect(InsightPhrasing.claim(rr) == "Dairy → bloating")
        #expect(InsightPhrasing.badge(confidence: 0.6) == .moderate)
        let sub = InsightPhrasing.subline(rr)!
        #expect(sub.contains("~12h") && sub.contains("severity"))
        #expect(InsightPhrasing.countLine(rr) == "In 6 of your last 8 Dairy logs, bloating followed")
    }
    @Test func improvesPhrasesProtectivelyNoSubline() {
        let rr = resolved(rel(type: .improves, confidence: 0.6, toSubtype: "migraine"),
                          exposure: "Magnesium", outcome: "migraine", recent: [false, true, false])
        #expect(InsightPhrasing.claim(rr) == "Magnesium → fewer migraine")
        #expect(InsightPhrasing.subline(rr) == nil)       // no "+severity" on a protective card
    }
    @Test func noEffectClaimIsNullToneNoSubline() {
        let rr = resolved(rel(type: .noEffect, confidence: 0.55, toSubtype: "fatigue"),
                          exposure: "Vitamin D", outcome: "fatigue")
        #expect(InsightPhrasing.claim(rr) == "No measurable effect of Vitamin D on fatigue")
        #expect(!InsightPhrasing.claim(rr).contains("→"))   // not directional
        #expect(InsightPhrasing.subline(rr) == nil)
        #expect(InsightPhrasing.countLine(rr) == nil)       // no dot line for a null result
    }
    @Test func badgeTiers() {
        #expect(InsightPhrasing.badge(confidence: 0.4) == .earlySignal)
        #expect(InsightPhrasing.badge(confidence: 0.5) == .moderate)
        #expect(InsightPhrasing.badge(confidence: 0.75) == .moderate)   // ceiling: strong needs >0.75
        #expect(InsightPhrasing.badge(confidence: 0.8) == .strong)
    }
    @Test func derivedLabels() {
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "shortSleep") == "Short sleep")
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "cyclePhase.luteal") == "Luteal phase")
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "food") == nil)   // objects resolve via name
    }
    @Test func noCausalLanguage() {
        let forbidden = ["cause", "causes", "triggers ", "makes you", "guarantee"]
        for type in [RelationshipType.possibleTrigger, .improves, .noEffect] {
            let rr = resolved(rel(type: type, confidence: 0.6, toSubtype: "bloating"), recent: [true, false, true])
            let text = (InsightPhrasing.claim(rr) + " " + (InsightPhrasing.subline(rr) ?? "")
                        + " " + (InsightPhrasing.countLine(rr) ?? "")).lowercased()
            for word in forbidden { #expect(!text.contains(word), "phrasing must avoid causal word '\(word)'") }
        }
    }
}
