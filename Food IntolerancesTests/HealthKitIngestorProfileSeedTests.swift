import Testing
import Foundation
@testable import Food_Intolerances

/// Pins the two `HealthKitIngestor` guards behind the ingestor's auto-created
/// profile (C1) and the "Remove Date of Birth" tombstone (I2). Both are pure
/// statics — no HealthKit or SwiftData stand-up needed.
struct HealthKitIngestorProfileSeedTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "hk-ingestor-profile-seed-\(UUID().uuidString)")!
    }

    // MARK: C1 — newProfileSeededWithGlobalUnits

    @Test func seedsFromExplicitGlobalRegardlessOfLocale() {
        let d = freshDefaults()
        d.set("metric", forKey: UnitPreferenceBootstrap.globalKey)
        let profile = HealthKitIngestor.newProfileSeededWithGlobalUnits(
            defaults: d, locale: Locale(identifier: "en_US"))
        #expect(profile.unitPreference == "metric")   // explicit global wins over a US locale
    }

    @Test func fallsBackToLocaleWhenGlobalUnset() {
        // The bug this pins: a bare `UserProfile()` always defaults to
        // "imperial" — a metric-locale user with no global set yet must get
        // "metric" from the profile the ingestor creates, not "imperial".
        let d = freshDefaults()   // no global key set
        let profile = HealthKitIngestor.newProfileSeededWithGlobalUnits(
            defaults: d, locale: Locale(identifier: "de_DE"))
        #expect(profile.unitPreference == "metric")
    }

    @Test func fallsBackToLocaleImperialForUSWhenGlobalUnset() {
        let d = freshDefaults()
        let profile = HealthKitIngestor.newProfileSeededWithGlobalUnits(
            defaults: d, locale: Locale(identifier: "en_US"))
        #expect(profile.unitPreference == "imperial")
    }

    // MARK: I2 — shouldPopulateDateOfBirth

    @Test func populatesWhenNoDOBAndNoTombstone() {
        #expect(HealthKitIngestor.shouldPopulateDateOfBirth(storedDOB: nil, tombstone: false))
    }

    @Test func skipsWhenTombstoneSetEvenIfDOBNil() {
        // The defect: a guard on `dateOfBirth == nil` alone lets the next
        // authorization pass silently undo an explicit removal.
        #expect(!HealthKitIngestor.shouldPopulateDateOfBirth(storedDOB: nil, tombstone: true))
    }

    @Test func skipsWhenDOBAlreadySetRegardlessOfTombstone() {
        #expect(!HealthKitIngestor.shouldPopulateDateOfBirth(storedDOB: Date(), tombstone: false))
        #expect(!HealthKitIngestor.shouldPopulateDateOfBirth(storedDOB: Date(), tombstone: true))
    }
}
