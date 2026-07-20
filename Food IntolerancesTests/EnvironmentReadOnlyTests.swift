import Testing
import HealthGraphCore
@testable import Food_Intolerances

struct EnvironmentReadOnlyTests {
    private func event(_ cat: EventCategory, _ source: EventSource) -> HealthEvent {
        HealthEvent(timestamp: .init(timeIntervalSince1970: 0), timezoneID: "UTC",
                    category: cat, subtype: "x", value: 1, source: source)
    }
    @Test func environmentIsReadOnlyOthersAreNot() {
        #expect(event(.environment, .weatherAPI).isReadOnlyEnvironment)
        #expect(!event(.symptom, .manual).isReadOnlyEnvironment)
        #expect(!event(.sleep, .healthKit).isReadOnlyEnvironment)   // scoped to .environment only
    }
}
