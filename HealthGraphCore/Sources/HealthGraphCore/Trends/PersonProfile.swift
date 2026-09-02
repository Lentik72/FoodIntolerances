import Foundation

/// A person's demographic profile, used for trajectory-chart interpretation
/// only — never to normalize symptom severity or exposure thresholds (see
/// the round's decision record:
/// docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md).
public struct PersonProfile: Sendable {
    public let dateOfBirth: Date?
    /// Fallback age used when `dateOfBirth` is absent. This is not a
    /// secondary path: today NOTHING in the app writes `dateOfBirth`, so
    /// this fallback is what keeps `HealthMonitoringService`'s age-gated
    /// screening recommendations (cholesterol at 40+, blood sugar at 45+)
    /// firing for every existing user.
    public let storedAge: Int?
    /// From the HealthKit biological-sex characteristic only. A different
    /// concept from `UserProfile.gender` (a free-text self-description) —
    /// the two are deliberately not conflated.
    public let biologicalSex: BiologicalSex?
    public let heightCm: Double?

    public init(
        dateOfBirth: Date?,
        storedAge: Int?,
        biologicalSex: BiologicalSex?,
        heightCm: Double?
    ) {
        self.dateOfBirth = dateOfBirth
        self.storedAge = storedAge
        self.biologicalSex = biologicalSex
        self.heightCm = heightCm
    }

    /// `dateOfBirth` is the source of truth and wins when present;
    /// `storedAge` is the fallback; neither present means no age at all.
    ///
    /// Uses calendar year-component subtraction — NEVER a division by 365
    /// or 365.25, both of which disagree with the correct answer near
    /// birthday and leap-year boundaries.
    public func currentAge(asOf: Date, calendar: Calendar) -> Int? {
        if let dateOfBirth {
            return calendar.dateComponents([.year], from: dateOfBirth, to: asOf).year
        }
        return storedAge
    }
}

/// Biological sex as reported by HealthKit's characteristic type.
/// `HKBiologicalSex.notSet` has no representation here — it maps to `nil`
/// `PersonProfile.biologicalSex`, not to a case of this type.
public enum BiologicalSex: Sendable {
    case female
    case male
    case other
}
