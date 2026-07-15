import Foundation
import Testing
@testable import HealthGraphCore

struct SleepSessionBuilderTests {
    let utc = TimeZone(identifier: "UTC")!
    /// 2025-06-15 00:00:00 UTC — a fixed local midnight for offset math.
    let midnight = Date(timeIntervalSince1970: 1_749_945_600)

    /// A sleep-stage segment `startMin` minutes from `midnight` (negative = the
    /// evening before), lasting `durationMin` minutes.
    private func seg(_ subtype: String, startMin: Double, durationMin: Double) -> HealthEvent {
        let start = midnight.addingTimeInterval(startMin * 60)
        return HealthEvent(timestamp: start, endTimestamp: start.addingTimeInterval(durationMin * 60),
                           category: .sleep, subtype: subtype, value: durationMin, unit: "min",
                           source: .healthKit, createdAt: midnight)
    }

    @Test func nightAcrossMidnightIsOneSessionWithExactTotals() {
        // 22:00 core 90m, 23:30 deep 60m, 00:30 awake 15m, 00:45 rem 120m, 02:45 core 180m
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: -120, durationMin: 90),
            seg("asleepDeep", startMin: -30, durationMin: 60),
            seg("awake", startMin: 30, durationMin: 15),
            seg("asleepREM", startMin: 45, durationMin: 120),
            seg("asleepCore", startMin: 165, durationMin: 180),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        let s = sessions[0]
        #expect(s.start == midnight.addingTimeInterval(-120 * 60))
        #expect(s.end == midnight.addingTimeInterval(345 * 60))     // 05:45
        #expect(s.coreMinutes == 270)
        #expect(s.deepMinutes == 60)
        #expect(s.remMinutes == 120)
        #expect(s.awakeMinutes == 15)
        #expect(s.asleepMinutes == 450)
        #expect(s.inBedMinutes == 0)
        #expect(s.kind == .night)
        #expect(s.segmentCount == 5)
    }

    @Test func fiftyNineMinuteHoleKeepsOneSession() {
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 0, durationMin: 60),
            seg("asleepCore", startMin: 60 + 59, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].asleepMinutes == 120)
    }

    @Test func sixtyMinuteHoleSplits() {
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 0, durationMin: 60),
            seg("asleepCore", startMin: 60 + 60, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions.count == 2)
    }

    @Test func sixtyOneMinuteHoleSplits() {
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 0, durationMin: 60),
            seg("asleepCore", startMin: 60 + 61, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions.count == 2)
    }

    @Test func recordedAwakeSegmentNeverSplits() {
        // 45 recorded awake minutes mid-night: data, not a hole -> one session.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 0, durationMin: 60),
            seg("awake", startMin: 60, durationMin: 45),
            seg("asleepCore", startMin: 105, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].awakeMinutes == 45)
    }

    @Test func overlappingSegmentsChainByFurthestEnd() {
        // inBed spans 0-480; a core stage ends at 90. A segment starting at 500
        // is 20m after the FURTHEST end (480), not 410m after the last-seen end.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("inBed", startMin: 0, durationMin: 480),
            seg("asleepCore", startMin: 30, durationMin: 60),
            seg("asleepCore", startMin: 500, durationMin: 30),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].end == midnight.addingTimeInterval(530 * 60))
    }

    @Test func inBedOverlapExcludedFromAsleep() {
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("inBed", startMin: 0, durationMin: 480),
            seg("asleepCore", startMin: 0, durationMin: 240),
            seg("asleepREM", startMin: 240, durationMin: 240),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].asleepMinutes == 480)
        #expect(sessions[0].inBedMinutes == 480)
    }

    @Test func afternoonNapIsNap() {
        // 14:00-15:00, 60 asleep minutes, same local day, inside 06:00-21:00.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepUnspecified", startMin: 14 * 60, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].kind == .nap)
        #expect(sessions[0].unspecifiedMinutes == 60)
    }

    @Test func crashSleepAtOneAMIsNight() {
        // 01:00-03:00 = 120 min (< 180) but starts before 06:00 -> night.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 60, durationMin: 120),
        ], timeZone: utc)
        #expect(sessions[0].kind == .night)
    }

    @Test func longDaytimeSleepIsNight() {
        // 09:00-14:00 = 300 min (>= 180) -> night even in daytime.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 9 * 60, durationMin: 300),
        ], timeZone: utc)
        #expect(sessions[0].kind == .night)
    }

    @Test func eveningNapEndingAfterNinePMIsNight() {
        // 20:30-21:30 ends after 21:00 -> night.
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 20 * 60 + 30, durationMin: 60),
        ], timeZone: utc)
        #expect(sessions[0].kind == .night)
    }

    @Test func inBedOnlySessionClassifiesByInBedMinutes() {
        // Phone-only data: 50 inBed minutes at 13:00 -> nap-shaped, no asleep.
        let nap = SleepSessionBuilder.sessions(from: [
            seg("inBed", startMin: 13 * 60, durationMin: 50),
        ], timeZone: utc)
        #expect(nap[0].asleepMinutes == 0)
        #expect(nap[0].inBedMinutes == 50)
        #expect(nap[0].kind == .nap)
        // 8h overnight inBed -> night.
        let night = SleepSessionBuilder.sessions(from: [
            seg("inBed", startMin: -120, durationMin: 480),
        ], timeZone: utc)
        #expect(night[0].kind == .night)
    }

    @Test func subMinuteSegmentsCountTowardTotals() {
        let sessions = SleepSessionBuilder.sessions(from: [
            seg("asleepCore", startMin: 0, durationMin: 10),
            seg("awake", startMin: 10, durationMin: 0.5),
            seg("asleepCore", startMin: 10.5, durationMin: 10),
        ], timeZone: utc)
        #expect(sessions.count == 1)
        #expect(sessions[0].asleepMinutes == 20)
        #expect(sessions[0].awakeMinutes == 0.5)
    }

    @Test func pointSleepEventsAndOtherCategoriesIgnored() {
        let point = HealthEvent(timestamp: midnight, category: .sleep, subtype: "item0",
                                source: .manual, createdAt: midnight)
        let food = HealthEvent(timestamp: midnight, endTimestamp: midnight.addingTimeInterval(600),
                               category: .food, subtype: "dinner", source: .manual, createdAt: midnight)
        #expect(SleepSessionBuilder.sessions(from: [point, food], timeZone: utc).isEmpty)
    }

    @Test func emptyAndSingleSegmentInputs() {
        #expect(SleepSessionBuilder.sessions(from: [], timeZone: utc).isEmpty)
        let one = SleepSessionBuilder.sessions(from: [seg("asleepCore", startMin: 0, durationMin: 90)],
                                               timeZone: utc)
        #expect(one.count == 1)
        #expect(one[0].segmentCount == 1)
    }

    @Test func sessionsSortAscendingByEndAndIdsAreDeterministic() {
        let input = [
            seg("asleepCore", startMin: 14 * 60, durationMin: 60),   // nap, later
            seg("asleepCore", startMin: -120, durationMin: 480),     // night, earlier
        ]
        let a = SleepSessionBuilder.sessions(from: input, timeZone: utc)
        let b = SleepSessionBuilder.sessions(from: input.reversed(), timeZone: utc)
        #expect(a.count == 2)
        #expect(a[0].end < a[1].end)
        #expect(a.map(\.id) == b.map(\.id))     // input order never changes identity
        #expect(a[0].id == "sleep-\(Int(a[0].start.timeIntervalSince1970))-\(Int(a[0].end.timeIntervalSince1970))")
    }
}
