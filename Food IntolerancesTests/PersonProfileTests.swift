import Testing
import Foundation
import HealthGraphCore

struct PersonProfileTests {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private static let asOf = Date(timeIntervalSince1970: 1_749_945_600)   // 2025-06-15 UTC

    private func dob(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func ageIsDerivedFromDateOfBirthAcrossTheBoundaries() {
        // Each row kills a different wrong implementation.
        let cases: [(String, Date, Int)] = [
            ("birthday today",       dob(1970, 6, 15), 55),
            ("birthday tomorrow",    dob(1970, 6, 16), 54),   // kills /365 and year-subtraction
            ("birthday in December", dob(1970, 12, 31), 54),  // kills year-subtraction
            ("19 leap days",         dob(1948, 6, 15), 77),   // kills /365.25
        ]
        for (name, d, expected) in cases {
            let age = PersonProfile(dateOfBirth: d, storedAge: nil, biologicalSex: nil, heightCm: nil)
                .currentAge(asOf: Self.asOf, calendar: utc)
            #expect(age == expected, "\(name): got \(String(describing: age))")
        }
    }

    @Test func noDateOfBirthFallsBackToStoredAge() {
        // Without this, age-gated screening in HealthMonitoringService silently
        // stops firing for every user who predates DOB collection — which today
        // is all of them, since nothing writes dateOfBirth.
        #expect(PersonProfile(dateOfBirth: nil, storedAge: 47, biologicalSex: nil, heightCm: nil)
                    .currentAge(asOf: Self.asOf, calendar: utc) == 47)
    }

    @Test func dateOfBirthWinsOverAStaleStoredAge() {
        #expect(PersonProfile(dateOfBirth: dob(1970, 1, 1), storedAge: 12, biologicalSex: nil, heightCm: nil)
                    .currentAge(asOf: Self.asOf, calendar: utc) == 55)
    }

    @Test func neitherSourceMeansNoAge() {
        #expect(PersonProfile(dateOfBirth: nil, storedAge: nil, biologicalSex: nil, heightCm: nil)
                    .currentAge(asOf: Self.asOf, calendar: utc) == nil)
    }
}
