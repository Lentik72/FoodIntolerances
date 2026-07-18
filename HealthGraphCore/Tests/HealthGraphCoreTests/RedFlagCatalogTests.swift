import Testing
@testable import HealthGraphCore

struct RedFlagCatalogTests {
    @Test func everyRuleKeyResolvesToARealSymptom() {
        // Drift guard: if a display name is renamed, its derived key must still exist in the catalog.
        #expect(!RedFlagCatalog.allSymptomKeys.isEmpty)   // non-vacuous: the loop must run
        let catalogKeys = Set(SymptomCatalog.all.map(\.canonicalKey))
        for key in RedFlagCatalog.allSymptomKeys {
            #expect(catalogKeys.contains(key), "red-flag key \(key) is not in SymptomCatalog")
        }
    }

    @Test func severeAllergicReactionExistsWithEpinephrineGuidance() {
        let key = SymptomCatalog.canonicalKey(for: "Severe Allergic Reaction")
        #expect(SymptomCatalog.all.contains { $0.canonicalKey == key })
        let rule = RedFlagCatalog.rule(forSymptomKey: key)
        #expect(rule != nil)
        #expect(rule?.extraGuidance?.contains("epinephrine") == true)
    }

    @Test func cardiacRespiratoryRulesHaveNoExtraGuidance() {
        let key = SymptomCatalog.canonicalKey(for: "Chest Pain")
        let rule = RedFlagCatalog.rule(forSymptomKey: key)
        #expect(rule != nil)                              // not vacuous if the rule were missing
        #expect(rule?.extraGuidance == nil)
    }

    @Test func selfHarmRuleIsMentalHealthCrisis() {
        let key = SymptomCatalog.canonicalKey(for: "Thoughts of self-harm or suicide")
        let rule = RedFlagCatalog.rule(forSymptomKey: key)
        #expect(rule != nil)
        #expect(rule?.category == .mentalHealthCrisis)
    }

    @Test func crisisKeyIsNotMutableButIsARedFlag() {
        let key = SymptomCatalog.canonicalKey(for: "Thoughts of self-harm or suicide")
        #expect(RedFlagCatalog.allSymptomKeys.contains(key))       // it IS a red flag
        #expect(!RedFlagCatalog.mutableSymptomKeys.contains(key))  // but NEVER offered as a mute toggle
    }

    @Test func medicalKeysStayMutable() {
        let chestPain = SymptomCatalog.canonicalKey(for: "Chest Pain")
        #expect(RedFlagCatalog.mutableSymptomKeys.contains(chestPain))
    }
}
