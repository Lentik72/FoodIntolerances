import Foundation

/// The user's measurement system for display. The source of truth is the global
/// `@AppStorage("hg.measurementSystem")`; `UserProfile.unitPreference` mirrors it.
/// Peer to `TemperatureUnit`; rawValues match the strings both stores already use.
enum UnitSystem: String {
    case imperial, metric

    /// Device-locale default: US → imperial, everywhere else → metric.
    static func localeDefault(for locale: Locale = .current) -> UnitSystem {
        locale.measurementSystem == .us ? .imperial : .metric
    }
    /// An explicit stored choice ("imperial"/"metric") wins; empty/unknown → locale default.
    static func resolved(from raw: String, locale: Locale = .current) -> UnitSystem {
        UnitSystem(rawValue: raw) ?? localeDefault(for: locale)
    }
    /// Weight rendering unit for this system.
    var weightUnit: WeightUnit {
        switch self {
        case .imperial: return .pounds
        case .metric: return .kilograms
        }
    }

    /// The `unitPreference` string a newly-created profile should inherit: the
    /// resolved global (explicit choice, else locale). Used by onboarding + the
    /// profile editor so a new profile is born matching the global (invariant §7.4).
    static func newProfileUnitPreference(global raw: String, locale: Locale = .current) -> String {
        resolved(from: raw, locale: locale).rawValue
    }
}

/// Result of reconciling the global measurement setting with a profile's mirror.
struct UnitReconciliation: Equatable {
    /// Value to persist to `@AppStorage("hg.measurementSystem")` ("" = leave unset → locale).
    let globalRaw: String
    /// When non-nil, write to an existing `profile.unitPreference`; nil = no profile write.
    let profileUnitPreference: String?
}

/// Pure reconciliation of the global setting vs a profile mirror. The global is
/// authoritative; an unknown string is NEVER copied across. When neither side is
/// valid: with no profile the global stays unset (locale resolves at read time);
/// with an existing (invalid) profile, BOTH are repaired to the locale default so
/// the mirror is equal AND valid.
enum UnitPreferenceReconciler {
    /// - Parameter profilePref: nil when NO profile exists; otherwise the profile's
    ///   current `unitPreference` (which may itself be an unrecognized string).
    static func reconcile(globalRaw: String,
                          profilePref: String?,
                          locale: Locale = .current) -> UnitReconciliation {
        let global = UnitSystem(rawValue: globalRaw)                    // valid global, else nil
        let profile = profilePref.flatMap(UnitSystem.init(rawValue:))   // valid profile, else nil
        switch (global, profile) {
        case let (.some(g), .some(p)):
            // valid global + valid profile: global wins; repair the profile on mismatch
            return UnitReconciliation(globalRaw: g.rawValue,
                                      profileUnitPreference: g == p ? nil : g.rawValue)
        case let (.some(g), .none):
            // valid global + (no profile | invalid profile)
            if profilePref == nil {
                return UnitReconciliation(globalRaw: g.rawValue, profileUnitPreference: nil)   // rule 3
            }
            return UnitReconciliation(globalRaw: g.rawValue, profileUnitPreference: g.rawValue) // repair invalid profile
        case let (.none, .some(p)):
            // invalid/empty global + valid profile: seed the global from the profile
            return UnitReconciliation(globalRaw: p.rawValue, profileUnitPreference: nil)         // rule 1
        case (.none, .none):
            if profilePref == nil {
                // neither valid + no profile: stay unset; locale resolves at read time
                return UnitReconciliation(globalRaw: "", profileUnitPreference: nil)
            }
            // neither valid + existing (invalid) profile: resolve locale and write it to BOTH,
            // so the mirror is equal AND valid (never leaves "garbage" in the profile).
            let d = UnitSystem.localeDefault(for: locale).rawValue
            return UnitReconciliation(globalRaw: d, profileUnitPreference: d)
        }
    }
}
