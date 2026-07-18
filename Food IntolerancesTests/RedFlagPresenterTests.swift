import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
struct RedFlagPresenterTests {
    // `SymptomCatalog` is qualified `HealthGraphCore.SymptomCatalog` throughout — the app
    // target has its own legacy `SymptomCatalog`, so an unqualified reference is AMBIGUOUS
    // in this dual-import (`import HealthGraphCore` + `@testable import Food_Intolerances`) module.
    private func presenter(mutedKeys: [String] = []) -> RedFlagPresenter {
        let store = RedFlagMuteStore(defaults: UserDefaults(suiteName: "rf-\(UUID().uuidString)")!)
        mutedKeys.forEach(store.mute)
        return RedFlagPresenter(muteStore: store)
    }
    private func key(_ name: String) -> String { HealthGraphCore.SymptomCatalog.canonicalKey(for: name) }
    private func symptom(_ displayName: String, severity: Double? = nil) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                    category: .symptom, subtype: key(displayName), value: severity, source: .manual)
    }

    @Test func redFlagSymptomSetsPending() {
        let p = presenter()
        p.consider(symptom("Chest Pain"))
        #expect(p.pending?.symptomKey == key("Chest Pain"))
    }

    @Test func firesRegardlessOfSeverity() {
        // Decision 1 (central): severity-independent. A low, EXPLICIT severity must still fire —
        // this is the layer where a future dev could wrongly add a severity gate.
        for severity in [1.0, 5.0, 10.0] {
            let p = presenter()
            p.consider(symptom("Chest Pain", severity: severity))
            #expect(p.pending?.symptomKey == key("Chest Pain"), "severity \(severity) must still fire")
        }
    }

    @Test func nonRedFlagSymptomLeavesPendingNil() {
        let p = presenter()
        p.consider(symptom("Headache"))
        #expect(p.pending == nil)
    }

    @Test func mutedRedFlagLeavesPendingNil() {
        let p = presenter(mutedKeys: [key("Chest Pain")])
        p.consider(symptom("Chest Pain"))
        #expect(p.pending == nil)
    }

    @Test func nonSymptomEventIgnored() {
        let p = presenter()
        p.consider(HealthEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                               category: .food, subtype: "dairy", source: .manual))
        #expect(p.pending == nil)
    }

    @Test func firstCoOccurringRedFlagWins() {
        // Spec §7.1: co-occurring red-flags show the FIRST; a second consider() before
        // dismiss must not overwrite the pending match.
        let p = presenter()
        p.consider(symptom("Chest Pain"))
        p.consider(symptom("Severe Allergic Reaction"))
        #expect(p.pending?.symptomKey == key("Chest Pain"))
    }

    @Test func firesAgainOnRepeatLogAfterDismiss() {
        // Decision 4: no hidden throttle — the same symptom fires again after a dismiss.
        let p = presenter()
        p.consider(symptom("Chest Pain")); p.dismiss()
        p.consider(symptom("Chest Pain"))
        #expect(p.pending != nil)
    }

    @Test func muteClearsPendingAndSuppressesRepeat() {
        let p = presenter()
        p.consider(symptom("Chest Pain"))
        p.mute(key("Chest Pain"))
        #expect(p.pending == nil)
        #expect(p.muteStore.isMuted(key("Chest Pain")) == true)
        p.consider(symptom("Chest Pain"))          // same instance, now muted → suppressed
        #expect(p.pending == nil)
    }

    @Test func crisisSymptomSetsPendingWithMentalHealthCrisisCategory() {
        let p = presenter()
        p.consider(symptom("Thoughts of self-harm or suicide"))
        #expect(p.pending?.symptomKey == key("Thoughts of self-harm or suicide"))
        #expect(p.pending?.category == .mentalHealthCrisis)
    }

    @Test func moodEventNeverTriggersRedFlag() {
        let p = presenter()
        p.consider(HealthEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                               category: .mood, subtype: "mood", value: 1, source: .manual))
        #expect(p.pending == nil)
    }
}
