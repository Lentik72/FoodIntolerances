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
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "fullMoon") == "Full moon")
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "mercuryRetrograde") == "Mercury retrograde")
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "hotDay") == "Hot days")
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "coldDay") == "Cold days")
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "humidDay") == "Humid days")
        #expect(InsightPhrasing.derivedExposureLabel(fromCategory: "swingDay") == "Big temperature swings")
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

    func moodRel(_ subtype: String, _ type: RelationshipType, lagHours: Double? = 12) -> Relationship {
        Relationship(fromCategory: "shortSleep", toCategory: "mood", type: type,
                     evidenceCount: 6, contradictionCount: 2, confidence: 0.6,
                     strength: 5, lagHours: lagHours, firstSeen: now, lastSeen: now,
                     lastRecomputed: now, status: .active, edgeKey: "k", toSubtype: subtype)
    }
    func moodResolved(_ r: Relationship, exposure: String, recent: [Bool] = []) -> ResolvedRelationship {
        ResolvedRelationship(relationship: r, exposureLabel: exposure,
                             outcomeLabel: InsightPhrasing.outcomeLabel(for: r),
                             exposureCategory: .food, recentOutcomes: recent)
    }

    @Test func moodClaims() {
        #expect(InsightPhrasing.claim(moodResolved(moodRel("good", .possibleTrigger), exposure: "Exercise"))
                == "Exercise seems to lift your mood")
        #expect(InsightPhrasing.claim(moodResolved(moodRel("low", .improves), exposure: "Magnesium"))
                == "Magnesium seems to protect against low moods")
        #expect(InsightPhrasing.claim(moodResolved(moodRel("low", .possibleTrigger), exposure: "Short sleep"))
                == "Short sleep is linked to lower mood")
        #expect(InsightPhrasing.claim(moodResolved(moodRel("good", .improves), exposure: "Alcohol"))
                == "Alcohol seems to weigh on your mood")
        #expect(InsightPhrasing.claim(moodResolved(moodRel("low", .noEffect), exposure: "Coffee"))
                == "No clear link between Coffee and your mood")
    }
    @Test func moodOutcomeLabelIsANaturalNoun() {
        #expect(InsightPhrasing.outcomeLabel(for: moodRel("good", .possibleTrigger)) == "a good mood")
        #expect(InsightPhrasing.outcomeLabel(for: moodRel("low", .possibleTrigger)) == "a low mood")
    }
    @Test func moodTriggerSublineHasLagButNoSeverity() {
        let sub = InsightPhrasing.subline(moodResolved(moodRel("low", .possibleTrigger), exposure: "Short sleep"))
        #expect(sub != nil)
        #expect(sub!.contains("~12h"))
        #expect(!sub!.contains("severity"))   // severity is a symptom concept, omitted for mood
    }
    @Test func moodCountLineUsesTheNaturalNoun() {
        let rr = moodResolved(moodRel("good", .possibleTrigger), exposure: "Exercise", recent: [true, false, true])
        #expect(InsightPhrasing.countLine(rr) == "In 2 of your last 3 Exercise logs, a good mood followed")
    }
    @Test func moodPhrasingHasNoCausalLanguage() {   // spec §7 — the honesty rule binds to mood too
        let forbidden = ["cause", "causes", "triggers ", "makes you", "guarantee"]
        let cases: [(String, RelationshipType)] = [("good", .possibleTrigger), ("low", .improves),
            ("low", .possibleTrigger), ("good", .improves), ("low", .noEffect)]
        for (sub, type) in cases {
            let rr = moodResolved(moodRel(sub, type), exposure: "Exercise", recent: [true, false, true])
            let text = (InsightPhrasing.claim(rr) + " " + (InsightPhrasing.subline(rr) ?? "")
                        + " " + (InsightPhrasing.countLine(rr) ?? "")).lowercased()
            for word in forbidden { #expect(!text.contains(word), "mood phrasing must avoid '\(word)'") }
        }
    }
}
