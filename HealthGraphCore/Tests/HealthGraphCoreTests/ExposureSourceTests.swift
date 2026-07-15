import Testing
import Foundation
@testable import HealthGraphCore

struct EvidenceConfigTests {
    @Test func lagWindowsByExposureKind() {
        let c = EvidenceConfig.default
        #expect(c.lagWindow(for: .object(UUID(), .food)) == 0...24)
        #expect(c.lagWindow(for: .object(UUID(), .supplement)) == 0...48)
        #expect(c.lagWindow(for: .derived(.shortSleep)) == 0...18)
        #expect(c.lagWindow(for: .derived(.cyclePhase(.luteal))) == 0...24)
    }
    @Test func defaultsAreSane() {
        let c = EvidenceConfig.default
        #expect(c.minExposures == 5)
        #expect(c.observationalCeiling == 0.75)
        #expect(c.candidateRatioTrigger > 1.0)
        #expect(c.candidateRatioProtective < 1.0)
    }
}
