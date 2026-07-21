import Testing
import Foundation
@testable import HealthGraphCore

struct TemporalProvenanceTests {
    private func event(meta: [String: String]?) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSince1970: 0), timezoneID: "UTC",
                    category: .environment, subtype: "temperature", value: 20, source: .weatherAPI,
                    metadata: meta.map { try! JSONEncoder().encode($0) })
    }
    @Test func decodesProvenanceFromMetadata() {
        #expect(event(meta: ["provenance": "observedCompletedDay"]).temporalProvenance == .observedCompletedDay)
        #expect(event(meta: ["provenance": "forecast"]).temporalProvenance == .forecast)
        #expect(event(meta: ["provenance": "currentSnapshot"]).temporalProvenance == .currentSnapshot)
    }
    @Test func failClosedOnMissingOrUnknown() {
        #expect(event(meta: nil).temporalProvenance == nil)                       // no metadata
        #expect(event(meta: ["low": "12"]).temporalProvenance == nil)             // metadata without provenance
        #expect(event(meta: ["provenance": "banana"]).temporalProvenance == nil)  // unknown value
    }
}
