import Foundation
import SwiftData

/// Reconciles the global measurement setting with the stored profile at launch —
/// synchronously, before the first render (flash-free), on the main actor, and
/// failing open so a preference repair can never block app startup.
@MainActor
enum UnitPreferenceBootstrap {
    static let globalKey = "hg.measurementSystem"

    static func reconcileAtLaunch(container: ModelContainer,
                                  defaults: UserDefaults = .standard,
                                  locale: Locale = .current) {
        let current = defaults.string(forKey: globalKey) ?? ""
        do {
            let profiles = try container.mainContext.fetch(FetchDescriptor<UserProfile>())
            let result = UnitPreferenceReconciler.reconcile(
                globalRaw: current, profilePref: profiles.first?.unitPreference, locale: locale)
            if result.globalRaw != current {
                defaults.set(result.globalRaw, forKey: globalKey)
            }
            if let update = result.profileUnitPreference,
               let profile = profiles.first, profile.unitPreference != update {
                profile.unitPreference = update
                try container.mainContext.save()
            }
        } catch {
            // Fail open: a preference repair must never prevent startup.
            Logger.info("Unit preference reconcile skipped (fetch/save failed); using global/locale resolution",
                        category: .data)
        }
    }
}
