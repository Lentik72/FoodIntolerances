import Testing
import Foundation
@testable import Food_Intolerances

struct UnitSystemTests {
    // MARK: UnitSystem resolution + mapping
    @Test func localeDefaultUSisImperialElseMetric() {
        #expect(UnitSystem.localeDefault(for: Locale(identifier: "en_US")) == .imperial)
        #expect(UnitSystem.localeDefault(for: Locale(identifier: "en_GB")) == .metric)
        #expect(UnitSystem.localeDefault(for: Locale(identifier: "de_DE")) == .metric)
    }
    @Test func resolvedExplicitWinsElseLocale() {
        #expect(UnitSystem.resolved(from: "metric", locale: Locale(identifier: "en_US")) == .metric)   // explicit wins
        #expect(UnitSystem.resolved(from: "imperial", locale: Locale(identifier: "de_DE")) == .imperial)
        #expect(UnitSystem.resolved(from: "", locale: Locale(identifier: "en_US")) == .imperial)        // empty → locale
        #expect(UnitSystem.resolved(from: "garbage", locale: Locale(identifier: "de_DE")) == .metric)   // unknown → locale
    }
    @Test func weightUnitMapping() {
        #expect(UnitSystem.imperial.weightUnit == .pounds)
        #expect(UnitSystem.metric.weightUnit == .kilograms)
    }
    @Test func newProfileUnitPreferenceFromResolvedGlobal() {   // rule 4: a new profile inherits the global
        #expect(UnitSystem.newProfileUnitPreference(global: "metric", locale: Locale(identifier: "en_US")) == "metric")     // explicit wins
        #expect(UnitSystem.newProfileUnitPreference(global: "imperial", locale: Locale(identifier: "de_DE")) == "imperial")
        #expect(UnitSystem.newProfileUnitPreference(global: "", locale: Locale(identifier: "en_US")) == "imperial")         // locale fallback
        #expect(UnitSystem.newProfileUnitPreference(global: "", locale: Locale(identifier: "de_DE")) == "metric")
    }

    // MARK: reconciliation truth table (asserts BOTH returned fields)
    private func r(_ g: String, _ p: String?, _ locale: Locale = Locale(identifier: "en_US")) -> UnitReconciliation {
        UnitPreferenceReconciler.reconcile(globalRaw: g, profilePref: p, locale: locale)
    }
    @Test func validGlobalNoProfile_leftAlone_createsNothing() {          // rule 3
        #expect(r("imperial", nil) == UnitReconciliation(globalRaw: "imperial", profileUnitPreference: nil))
    }
    @Test func validGlobalMatchingProfile_agree() {
        #expect(r("metric", "metric") == UnitReconciliation(globalRaw: "metric", profileUnitPreference: nil))
    }
    @Test func validGlobalDifferentProfile_globalWinsRepairs() {          // rule 2
        #expect(r("imperial", "metric") == UnitReconciliation(globalRaw: "imperial", profileUnitPreference: "imperial"))
    }
    @Test func validGlobalInvalidProfile_repairsProfile() {              // valid global + invalid profile
        #expect(r("metric", "garbage") == UnitReconciliation(globalRaw: "metric", profileUnitPreference: "metric"))
    }
    @Test func emptyGlobalValidProfile_seedsGlobal() {                    // rule 1
        #expect(r("", "metric") == UnitReconciliation(globalRaw: "metric", profileUnitPreference: nil))
    }
    @Test func invalidGlobalValidProfile_seedsGlobal() {                 // invalid global treated as unset
        #expect(r("garbage", "imperial") == UnitReconciliation(globalRaw: "imperial", profileUnitPreference: nil))
    }
    @Test func neitherValidNoProfile_remainsUnset() {
        #expect(r("", nil) == UnitReconciliation(globalRaw: "", profileUnitPreference: nil))            // no profile → stay unset
        #expect(r("garbage", nil) == UnitReconciliation(globalRaw: "", profileUnitPreference: nil))     // invalid global, no profile
    }
    @Test func neitherValidInvalidProfile_repairsBothToLocale() {
        // An existing invalid profile must NOT be left holding "garbage": resolve locale, write both.
        #expect(r("", "garbage", Locale(identifier: "en_US")) == UnitReconciliation(globalRaw: "imperial", profileUnitPreference: "imperial"))
        #expect(r("garbage", "garbage", Locale(identifier: "de_DE")) == UnitReconciliation(globalRaw: "metric", profileUnitPreference: "metric"))
        #expect(r("", "garbage", Locale(identifier: "de_DE")) == UnitReconciliation(globalRaw: "metric", profileUnitPreference: "metric"))   // never copies "garbage"
    }
}
