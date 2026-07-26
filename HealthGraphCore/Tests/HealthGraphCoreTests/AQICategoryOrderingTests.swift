import Testing
@testable import HealthGraphCore

@Suite struct AQICategoryOrderingTests {
    typealias Cat = AirQualityIndex.AQICategory

    @Test func severityIsMonotonic() {
        let ordered: [Cat] = [.good, .moderate, .unhealthySensitive, .unhealthy, .veryUnhealthy, .hazardous]
        #expect(ordered == ordered.sorted())                 // Comparable agrees with the listed order
        #expect(Cat.hazardous > Cat.unhealthySensitive)
        #expect(Cat.unhealthySensitive > Cat.moderate)
    }

    @Test func persistedTokensAreStableAndRoundTrip() {
        let expected: [Cat: String] = [
            .good: "good", .moderate: "moderate", .unhealthySensitive: "unhealthySensitive",
            .unhealthy: "unhealthy", .veryUnhealthy: "veryUnhealthy", .hazardous: "hazardous"]
        for (cat, token) in expected {
            #expect(cat.persistedToken == token)
            #expect(Cat(persistedToken: token) == cat)
        }
        #expect(Cat(persistedToken: "bogus") == nil)         // unknown token → nil, never a crash
    }
}
