import Testing
import Foundation
@testable import HealthGraphCore

struct DedupKeyTests {
    let dayStart = Date(timeIntervalSince1970: 1_750_032_000) // a UTC midnight

    @Test func provenanceScopesTheDailyKey() {
        // Same category/subtype/day, different provenance → DIFFERENT keys.
        // A forecast temperature must never collide with an observed one.
        let forecast = DedupKey.daily(.environment, "temperature", dayStart: dayStart,
                                      provenance: .forecast)
        let observed = DedupKey.daily(.environment, "temperature", dayStart: dayStart,
                                      provenance: .observedCompletedDay)
        #expect(forecast != observed)
        #expect(forecast.contains("forecast"))
        #expect(observed.contains("observedCompletedDay"))
    }

    @Test func nilProvenanceKeepsTheLegacyFormat() {
        // Back-compat: omitting provenance yields the pre-provenance key exactly,
        // so legacy manual/other rows keep matching.
        let legacy = DedupKey.daily(.environment, "moonPhase", dayStart: dayStart)
        #expect(legacy == "environment|moonPhase|day|\(DedupKey.minute(dayStart))")
        // Explicit nil is identical to omission.
        #expect(DedupKey.daily(.environment, "moonPhase", dayStart: dayStart, provenance: nil) == legacy)
    }

    @Test func keyEmbedsProvenanceRawValueInStableFormat() {
        let key = DedupKey.daily(.environment, "pressure", dayStart: dayStart,
                                 provenance: .currentSnapshot)
        #expect(key == "environment|pressure|currentSnapshot|day|\(DedupKey.minute(dayStart))")
    }
}
