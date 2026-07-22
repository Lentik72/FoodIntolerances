import Testing
import Foundation
import SwiftData
@testable import Food_Intolerances

@MainActor
struct UnitPreferenceBootstrapTests {
    private func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: UserProfile.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "unit-bootstrap-\(UUID().uuidString)")!
        d.removeObject(forKey: UnitPreferenceBootstrap.globalKey)
        return d
    }

    @Test func seedsGlobalFromProfileWhenUnset() throws {
        let c = try inMemoryContainer()
        let p = UserProfile(); p.unitPreference = "metric"; c.mainContext.insert(p)
        try c.mainContext.save()                                                    // persist BEFORE bootstrap
        let d = freshDefaults()
        UnitPreferenceBootstrap.reconcileAtLaunch(container: c, defaults: d)
        #expect(d.string(forKey: UnitPreferenceBootstrap.globalKey) == "metric")   // seeded
        let saved = try c.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        #expect(saved?.unitPreference == "metric")                                  // profile untouched (refetched)
    }
    @Test func globalWinsAndRepairsProfileOnMismatch() throws {
        let c = try inMemoryContainer()
        let p = UserProfile(); p.unitPreference = "metric"; c.mainContext.insert(p)
        try c.mainContext.save()
        let d = freshDefaults(); d.set("imperial", forKey: UnitPreferenceBootstrap.globalKey)
        UnitPreferenceBootstrap.reconcileAtLaunch(container: c, defaults: d)
        #expect(d.string(forKey: UnitPreferenceBootstrap.globalKey) == "imperial")  // global unchanged
        let saved = try c.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        #expect(saved?.unitPreference == "imperial")                                // profile repaired (refetched)
    }
    @Test func repairsInvalidProfileAndGlobalToLocale() throws {
        let c = try inMemoryContainer()
        let p = UserProfile(); p.unitPreference = "garbage"; c.mainContext.insert(p)
        try c.mainContext.save()
        let d = freshDefaults()   // global unset; neither side valid but a profile exists
        UnitPreferenceBootstrap.reconcileAtLaunch(container: c, defaults: d, locale: Locale(identifier: "en_US"))
        #expect(d.string(forKey: UnitPreferenceBootstrap.globalKey) == "imperial")  // resolved from locale → global
        let saved = try c.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        #expect(saved?.unitPreference == "imperial")                                // repaired to a VALID value, not "garbage"
    }
    @Test func noProfileCreatesNothingAndKeepsGlobal() throws {
        let c = try inMemoryContainer()
        let d = freshDefaults(); d.set("metric", forKey: UnitPreferenceBootstrap.globalKey)
        UnitPreferenceBootstrap.reconcileAtLaunch(container: c, defaults: d)
        #expect(d.string(forKey: UnitPreferenceBootstrap.globalKey) == "metric")    // rule 3: left alone
        let count = try c.mainContext.fetch(FetchDescriptor<UserProfile>()).count
        #expect(count == 0)                                                         // nothing created
    }
}
