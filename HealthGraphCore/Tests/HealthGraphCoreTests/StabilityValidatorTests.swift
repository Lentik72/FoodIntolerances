import Testing
import Foundation
@testable import HealthGraphCore

struct StabilityValidatorTests {
    let day = 86_400.0, base = 1_700_000_000.0
    let key = ExposureKey.object(UUID(), .food)

    // 20 exposures on days 0..19 at 09:00; outcome follows a chosen subset within 6h.
    func dataset(followDays: Set<Int>) -> ([ExposureOccurrence], [OutcomeOccurrence]) {
        var exp: [ExposureOccurrence] = [], out: [OutcomeOccurrence] = []
        for d in 0..<20 {
            let t = Date(timeIntervalSince1970: base + Double(d) * day + 9 * 3600)
            exp.append(ExposureOccurrence(key: key, timestamp: t, timezoneID: "UTC", sourceEventID: UUID()))
            if followDays.contains(d) {
                out.append(OutcomeOccurrence(key: .symptom("s"),
                    timestamp: t.addingTimeInterval(3 * 3600), value: 5, sourceEventID: UUID()))
            }
        }
        return (exp, out)
    }

    @Test func stableWhenEffectHoldsInBothHalves() {
        // Outcome follows ~80% of exposures across the WHOLE range → both halves directional.
        let (exp, out) = dataset(followDays: Set([0,1,2,3,5,6,7,8,10,11,12,13,15,16,17,18]))
        #expect(StabilityValidator.isStable(exposure: exp, outcome: out, window: 0...24,
                                            fullDirection: .upper, config: .default))
    }

    @Test func unstableWhenEffectOnlyInOneHalf() {
        // Outcome follows only the EARLY half (days 0..9); late half has no follows → not stable.
        let (exp, out) = dataset(followDays: Set(0..<10))
        #expect(!StabilityValidator.isStable(exposure: exp, outcome: out, window: 0...24,
                                             fullDirection: .upper, config: .default))
    }

    @Test func unstableWhenTooFewExposures() {
        // 8 exposures < 2*5 → cannot validate.
        var exp: [ExposureOccurrence] = [], out: [OutcomeOccurrence] = []
        for d in 0..<8 {
            let t = Date(timeIntervalSince1970: base + Double(d) * day + 9 * 3600)
            exp.append(ExposureOccurrence(key: key, timestamp: t, timezoneID: "UTC", sourceEventID: UUID()))
            out.append(OutcomeOccurrence(key: .symptom("s"), timestamp: t.addingTimeInterval(3 * 3600),
                                         value: 5, sourceEventID: UUID()))
        }
        #expect(!StabilityValidator.isStable(exposure: exp, outcome: out, window: 0...24,
                                             fullDirection: .upper, config: .default))
    }
}
