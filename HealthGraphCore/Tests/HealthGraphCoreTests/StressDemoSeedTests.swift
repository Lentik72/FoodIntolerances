import Testing
import Foundation
@testable import HealthGraphCore

struct StressDemoSeedTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let utc = TimeZone(identifier: "UTC")!

    private func seed() -> [HealthEvent] {
        StressDemoSeed.events(endingAt: now, timeZone: utc)
    }

    private func stressEvents(_ events: [HealthEvent]) -> [HealthEvent] {
        events.filter { $0.subtype == HighStressExposureSource.symptomSubtype }
    }

    @Test func everyStressEventMatchesTheShapeTheExposureAccepts() {
        // The whole point of the seed: if these drift from the allowlist, the
        // demo plants data the miner ignores and every downstream assertion
        // becomes vacuous.
        let src = HighStressExposureSource(config: .default)
        let stress = stressEvents(seed())
        #expect(!stress.isEmpty)
        for e in stress {
            #expect(e.category == .symptom)
            #expect(e.unit == HighStressExposureSource.symptomUnit)
            #expect((7...9).contains(e.value ?? 0))
        }
        // Asserted through the real source, not by re-checking the fields above.
        #expect(src.occurrences(from: stress).count == stress.count)
    }

    @Test func thereAreEnoughExposuresAndOutcomesToClearTheGates() {
        let events = seed()
        let config = EvidenceConfig.default
        let exposures = HighStressExposureSource(config: config).occurrences(from: events)
        let outcomes = OutcomeSource(config: config).occurrences(from: events)
            .filter { $0.key == .symptom(StressDemoSeed.outcomeSubtype) }
        #expect(exposures.count >= config.minExposures)
        #expect(outcomes.count >= config.minOutcomeOccurrences)
        #expect(exposures.count == 60)     // 120 days, every even index
    }

    @Test func followedHeadachesLandInsideTheLagWindow() throws {
        // Outside 0...24h the pair cannot be mined at all, so a drifting offset
        // would silently produce a corpus with no relationship in it.
        let events = seed()
        let window = EvidenceConfig.default.stressLagHours
        let stressTimes = stressEvents(events).map(\.timestamp).sorted()
        let inWindow = events.filter { h in
            h.subtype == StressDemoSeed.outcomeSubtype
                && stressTimes.contains { s in
                    window.contains(h.timestamp.timeIntervalSince(s) / 3600)
                }
        }
        #expect(inWindow.count == 45)     // three of every four stress days
    }

    @Test func baselineHeadachesSitOutsideEveryStressWindow() {
        // Not merely "some headaches exist without stress": stress lands at 14:00
        // with a 0...24h window, so a stress-free MORNING is still inside the
        // previous stress day's window. A baseline headache placed there would be
        // counted as a follow, inflating the exposed rate and shrinking the very
        // contrast this noise exists to create.
        let events = seed()
        let window = EvidenceConfig.default.stressLagHours
        let stressTimes = stressEvents(events).map(\.timestamp)
        let all = events.filter { $0.subtype == StressDemoSeed.outcomeSubtype }
        let outside = all.filter { h in
            !stressTimes.contains { s in
                window.contains(h.timestamp.timeIntervalSince(s) / 3600)
            }
        }
        #expect(outside.count == 9)       // one in seven stress-free days
        #expect(all.count == 54)          // 45 followed + 9 baseline
    }

    @Test func theCorpusIsDeterministic() {
        let a = StressDemoSeed.events(endingAt: now, timeZone: utc)
        let b = StressDemoSeed.events(endingAt: now, timeZone: utc)
        #expect(a.map(\.timestamp) == b.map(\.timestamp))
        #expect(a.map(\.value) == b.map(\.value))
        #expect(a.map(\.subtype) == b.map(\.subtype))
    }

    @Test func theBatchNameIsDistinctFromItsSiblings() {
        let all = [DemoBatch.synthetic, DemoBatch.mood, DemoBatch.outsideFactors,
                   DemoBatch.weather, DemoBatch.stress]
        #expect(Set(all).count == all.count)
    }
}
