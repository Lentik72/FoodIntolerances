import Testing
@testable import HealthGraphCore

struct RedFlagEvaluatorTests {
    private var chestPain: String { SymptomCatalog.canonicalKey(for: "Chest Pain") }

    @Test func redFlagKeyMatches() {
        let match = RedFlagEvaluator.evaluate(symptomKey: chestPain, mutedKeys: [])
        #expect(match?.symptomKey == chestPain)
        #expect(match?.category == .medicalEmergency)
    }

    @Test func allCardiacRespiratorySymptomsMatch() {
        // Guards against a copy/paste slip dropping one of the six from the rule's array —
        // the drift guard only checks whatever IS present resolves, not that all six are present.
        for name in ["Chest Pain", "Lower Chest Pain", "Chest Tightness",
                     "Upper Chest Tightness", "Breathing Difficulty", "Shortness of Breath"] {
            let key = SymptomCatalog.canonicalKey(for: name)
            #expect(RedFlagEvaluator.evaluate(symptomKey: key, mutedKeys: [])?.category == .medicalEmergency,
                    "\(name) should be a red flag")
        }
    }

    @Test func nonRedFlagKeyDoesNotMatch() {
        let headache = SymptomCatalog.canonicalKey(for: "Headache")
        #expect(RedFlagEvaluator.evaluate(symptomKey: headache, mutedKeys: []) == nil)
    }

    @Test func mutedKeyDoesNotMatch() {
        #expect(RedFlagEvaluator.evaluate(symptomKey: chestPain, mutedKeys: [chestPain]) == nil)
    }

    @Test func anaphylaxisCarriesEpinephrineGuidance() {
        let key = SymptomCatalog.canonicalKey(for: "Severe Allergic Reaction")
        #expect(RedFlagEvaluator.evaluate(symptomKey: key, mutedKeys: [])?.extraGuidance?.contains("EpiPen") == true)
    }

    @Test func selfHarmSymptomIsAMentalHealthCrisisMatch() {
        let key = SymptomCatalog.canonicalKey(for: "Thoughts of self-harm or suicide")
        let match = RedFlagEvaluator.evaluate(symptomKey: key, mutedKeys: [])
        #expect(match?.category == .mentalHealthCrisis)
    }

    @Test func crisisSymptomFiresEvenIfSomehowMuted() {
        // Structural guarantee: a crisis prompt is un-suppressible at the evaluator level.
        let key = SymptomCatalog.canonicalKey(for: "Thoughts of self-harm or suicide")
        let match = RedFlagEvaluator.evaluate(symptomKey: key, mutedKeys: [key])
        #expect(match?.category == .mentalHealthCrisis)
    }
}
