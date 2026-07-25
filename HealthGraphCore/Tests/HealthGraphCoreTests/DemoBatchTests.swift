import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct DemoBatchTests {

    @Test func prefixFormatIsExact() {
        #expect(DemoBatch.prefix("weather") == "demo:weather|")
    }

    @Test func demoDedupKeyNeverEqualsRealKeyForSameDay() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let real = DedupKey.daily(.environment, "temperature", dayStart: day,
                                  provenance: .observedCompletedDay)
        let demo = DemoBatch.dedupKey(real, batch: DemoBatch.weather)
        #expect(demo != real)
        #expect(demo.hasPrefix("demo:weather|"))
        #expect(demo.hasSuffix(real))
    }

    @Test func normalizedNameNamespacesTheNormalizedForm() {
        // "Coffee" normalizes to "coffee"; the demo form prefixes that.
        #expect(DemoBatch.normalizedName("Coffee", batch: DemoBatch.mood) == "demo:mood|coffee")
        #expect(NameNormalizer.normalize("Coffee") == "coffee")   // guards the assumption
    }

    @Test func stampSetsBatchAndNamespacesExistingDedupKeys() {
        let withKey = HealthEvent(timestamp: Date(), category: .environment,
                                  subtype: "humidity", source: .weatherAPI,
                                  dedupKey: "environment|humidity|day|1")
        let noKey = HealthEvent(timestamp: Date(), category: .symptom,
                                subtype: "headache", source: .manual)
        let out = DemoBatch.stamp([withKey, noKey], batch: DemoBatch.outsideFactors)
        #expect(out[0].syntheticBatch == "outsideFactors")
        #expect(out[0].dedupKey == "demo:outsideFactors|environment|humidity|day|1")
        #expect(out[1].syntheticBatch == "outsideFactors")
        #expect(out[1].dedupKey == nil)   // no key to namespace stays nil
    }
}
