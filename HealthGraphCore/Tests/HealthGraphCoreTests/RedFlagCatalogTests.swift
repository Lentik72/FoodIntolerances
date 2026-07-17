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
}
