import Testing
import Foundation
@testable import HealthGraphCore

@Suite struct CyclePhaseResolutionTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)
    let utc = TimeZone(identifier: "UTC")!

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c
    }
    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: t0.addingTimeInterval(Double(offset) * 86_400))
    }
    private func flow(_ offset: Int, cycleStart: Bool?) -> HealthEvent {
        let meta = cycleStart.flatMap {
            try? JSONEncoder().encode(["menstrualCycleStart": $0 ? "true" : "false"])
        }
        return HealthEvent(timestamp: day(offset), timezoneID: "UTC", category: .cycle,
                           subtype: "menstrualFlow", value: 2, unit: "level",
                           source: .healthKit, metadata: meta, createdAt: day(offset))
    }
    private func manualStart(_ offset: Int) -> HealthEvent {
        HealthEvent(timestamp: day(offset), timezoneID: "UTC", category: .cycle,
                    subtype: "periodStart", source: .manual, createdAt: day(offset))
    }
    private func menstrualDays(_ events: [HealthEvent]) -> Set<Date> {
        let occ = CyclePhaseExposureSource(config: .default, timeZone: utc).occurrences(from: events)
        return Set(occ.filter { $0.key == .derived(.cyclePhase(.menstrual)) }.map(\.timestamp))
    }

    @Test func authoritativeMarkerWins() {
        let events = [flow(0, cycleStart: true), flow(1, cycleStart: false), flow(2, cycleStart: false)]
        #expect(menstrualDays(events) == [day(0)])
    }

    @Test func falseIsNeverInferredEvenWhenFirstInTheSlice() {
        // The corpus is a truncated in-memory window; the first flow row in it
        // is NOT necessarily the first day of that period.
        let events = [flow(0, cycleStart: false), flow(1, cycleStart: false)]
        #expect(menstrualDays(events).isEmpty)
    }

    @Test func nilRunsFallBackToInference() {
        // Two runs 28 days apart, no metadata anywhere (export/legacy shape).
        let events = [flow(0, cycleStart: nil), flow(1, cycleStart: nil), flow(2, cycleStart: nil),
                      flow(28, cycleStart: nil), flow(29, cycleStart: nil)]
        #expect(menstrualDays(events) == [day(0), day(28)])
    }

    @Test func oneMissingMiddleDayDoesNotSplitARun() {
        // maxFlowGapDays == 2, so a single skipped day keeps one period.
        let events = [flow(0, cycleStart: nil), flow(2, cycleStart: nil), flow(3, cycleStart: nil)]
        #expect(menstrualDays(events) == [day(0)])
    }

    @Test func twelveDayRunSpacedAtTheMaxGapCollapsesToOneStartDespiteExceedingTheSuppressionWindow() {
        // Flow every maxFlowGapDays (2) apart, spanning 12 days (0...12): one
        // continuous bleeding episode under the run-detection rule (every
        // internal gap == maxFlowGapDays, so `<=` keeps it one run).
        //
        // This length is load-bearing: minInferredStartGapDays == 10, so ANY
        // run shorter than 10 days is masked — step 4's own gap-suppression
        // among candidates would collapse a broken run-detection's extra
        // candidates back down to one, hiding a regressed step 2. Only a run
        // that OUTLASTS the 10-day suppression window can expose a broken
        // step 2: if run-grouping stops merging (e.g. `<=` regresses to `<`,
        // which is a no-op here at gap==1 but flips this exact gap==2 case),
        // every spaced day becomes its own candidate, and step 4 then keeps
        // day 0 AND day 10 (a gap of exactly 10 is not `< 10`) — two starts
        // instead of one.
        let events = [0, 2, 4, 6, 8, 10, 12].map { flow($0, cycleStart: nil) }
        #expect(menstrualDays(events) == [day(0)])
    }

    @Test func aFalseBlockInsideARunDoesNotFabricateAPhantomSecondStart() {
        // day 0 nil, days 1-11 false (11 days), day 12 nil. `false` days must
        // be excluded from candidacy (a positive "not a start") but must NOT
        // be excluded from the run-detection SEQUENCE: if they were dropped
        // from the walk entirely, the sequence collapses to [0, 12], a 12-day
        // gap that exceeds maxFlowGapDays, so both 0 and 12 become candidates
        // with no authoritative start to suppress them and step 4 keeps both
        // (12 >= 10) — a phantom period start (day 12) in the middle of one
        // single bleeding episode. Correct handling walks the `false` days as
        // part of the run (each is 1 day from its neighbor, well within
        // maxFlowGapDays) so day 12 is recognized as a continuation, not a
        // new run's first day, and only day 0 survives as the run's one
        // `nil` candidate.
        let events = [flow(0, cycleStart: nil)]
            + (1...11).map { flow($0, cycleStart: false) }
            + [flow(12, cycleStart: nil)]
        #expect(menstrualDays(events) == [day(0)])
    }

    @Test func inferredCandidateNearAnAuthoritativeStartIsDroppedOnBothSides() {
        // Authoritative start at day 10. Inferred runs at day 5 (before) and
        // day 14 (after) are both inside minInferredStartGapDays == 10.
        let events = [flow(5, cycleStart: nil),
                      flow(10, cycleStart: true),
                      flow(14, cycleStart: nil), flow(15, cycleStart: nil)]
        #expect(menstrualDays(events) == [day(10)])
    }

    @Test func authoritativeStartsAreNeverSuppressedByEachOther() {
        // Two authoritative starts 3 days apart: unusual, but authority wins.
        let events = [flow(0, cycleStart: true), flow(3, cycleStart: true)]
        #expect(menstrualDays(events) == [day(0), day(3)])
    }

    @Test func manualPeriodStartUnionsWithMarkersAndDedupesByDay() {
        let events = [manualStart(0), flow(0, cycleStart: true), flow(28, cycleStart: true)]
        #expect(menstrualDays(events) == [day(0), day(28)])
    }

    @Test func aSingleStartStillYieldsItsMenstrualDayAndNoLuteal() {
        // The old `guard starts.count >= 2` returned [] and threw away the
        // menstrual exposure along with the (correctly) underivable luteal one.
        let occ = CyclePhaseExposureSource(config: .default, timeZone: utc)
            .occurrences(from: [flow(0, cycleStart: true)])
        #expect(occ.contains { $0.key == .derived(.cyclePhase(.menstrual)) })
        #expect(!occ.contains { $0.key == .derived(.cyclePhase(.luteal)) })
    }

    @Test func lutealWindowStillDerivesFromTwoStarts() {
        let occ = CyclePhaseExposureSource(config: .default, timeZone: utc)
            .occurrences(from: [flow(0, cycleStart: true), flow(28, cycleStart: true)])
        let luteal = occ.filter { $0.key == .derived(.cyclePhase(.luteal)) }
        #expect(luteal.count == EvidenceConfig.default.lutealWindowDays)
    }
}
