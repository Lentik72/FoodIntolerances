import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct PoorAirDismissalStoreTests {
    typealias Cat = AirQualityIndex.AQICategory
    func store() -> PoorAirDismissalStore {
        PoorAirDismissalStore(defaults: UserDefaults(suiteName: "poorair.\(UUID().uuidString)")!)
    }
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    let day1 = Date(timeIntervalSince1970: 1_700_000_000)          // some day
    var day2: Date { day1.addingTimeInterval(86_400) }             // next day

    @Test func recordsAndReadsTheMaxBandForTheDay() {
        let s = store()
        s.recordDismissed(.unhealthySensitive, now: day1, calendar: utc)
        #expect(s.highestDismissedBandToday(now: day1, calendar: utc) == .unhealthySensitive)
        s.recordDismissed(.unhealthy, now: day1, calendar: utc)     // higher
        #expect(s.highestDismissedBandToday(now: day1, calendar: utc) == .unhealthy)
        s.recordDismissed(.unhealthySensitive, now: day1, calendar: utc)   // lower — max stays
        #expect(s.highestDismissedBandToday(now: day1, calendar: utc) == .unhealthy)
    }
    @Test func rollsOverToNilNextDay() {
        let s = store()
        s.recordDismissed(.hazardous, now: day1, calendar: utc)
        #expect(s.highestDismissedBandToday(now: day2, calendar: utc) == nil)   // new local day → eligible again
    }
    @Test func unknownStoredTokenReadsNil() {
        let d = UserDefaults(suiteName: "poorair.\(UUID().uuidString)")!
        let s = PoorAirDismissalStore(defaults: d)
        // Simulate a legacy/corrupt token for today's key.
        s.recordDismissed(.unhealthy, now: day1, calendar: utc)
        d.set("bogus", forKey: s.debugKey(now: day1, calendar: utc))
        #expect(s.highestDismissedBandToday(now: day1, calendar: utc) == nil)
    }
}
