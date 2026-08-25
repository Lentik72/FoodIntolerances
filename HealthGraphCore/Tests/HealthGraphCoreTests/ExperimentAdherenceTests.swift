import Testing
import Foundation
@testable import HealthGraphCore

struct ExperimentAdherenceTests {
    /// EXACTLY midnight UTC (1_749_945_600 = 86_400 x 20_254). This matters: the
    /// `hour:` parameter below is an offset from t0, so if t0 were mid-afternoon
    /// — as 1_750_000_000 is, at 15:06 UTC — then `hour: 14` would land on the
    /// NEXT day and the distinct-day expectations would be silently wrong.
    let t0 = Date(timeIntervalSince1970: 1_749_945_600)
    let utc = TimeZone(identifier: "UTC")!
    let objectID = UUID()

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c
    }

    private func exp(days: Int = 21) -> Experiment {
        Experiment(interventionObjectID: objectID, outcomeSubtype: "migraine", shape: .repeated,
                   startedAt: t0, intendedEndAt: t0.addingTimeInterval(Double(days) * 86_400),
                   createdAt: t0)
    }

    private func dose(dayOffset: Double, hour: Double = 9, objectID: UUID? = nil) -> HealthEvent {
        HealthEvent(timestamp: t0.addingTimeInterval(dayOffset * 86_400 + hour * 3600),
                    timezoneID: "UTC", category: .supplement, subtype: "Magnesium",
                    objectID: objectID ?? self.objectID, value: 200, unit: "mg", source: .manual)
    }

    @Test func countsDistinctDaysNotRawDoses() {
        // Three doses in one day is one day of adherence. Counting doses would let
        // a single heavy day read as three days of a regimen.
        let a = ExperimentAdherence.measure(
            experiment: exp(),
            events: [dose(dayOffset: 0, hour: 8), dose(dayOffset: 0, hour: 14),
                     dose(dayOffset: 0, hour: 20), dose(dayOffset: 1)],
            calendar: cal)
        #expect(a.doseDays == 2)
        #expect(a.doses == 4)
        #expect(a.windowDays == 21)
    }

    @Test func ignoresDosesOfOtherThings() {
        let other = UUID()
        let a = ExperimentAdherence.measure(
            experiment: exp(),
            events: [dose(dayOffset: 0), dose(dayOffset: 1, objectID: other)],
            calendar: cal)
        #expect(a.doseDays == 1)
    }

    @Test func ignoresDosesOutsideTheWindow() {
        let a = ExperimentAdherence.measure(
            experiment: exp(days: 5),
            events: [dose(dayOffset: -3), dose(dayOffset: 2), dose(dayOffset: 40)],
            calendar: cal)
        #expect(a.doseDays == 1)
    }

    @Test func ignoresDeletedDoses() {
        // The Timeline supports swipe-delete, and a deleted dose is not adherence.
        var deleted = dose(dayOffset: 1)
        deleted.deletedAt = t0
        let a = ExperimentAdherence.measure(experiment: exp(),
                                            events: [dose(dayOffset: 0), deleted], calendar: cal)
        #expect(a.doseDays == 1)
    }

    @Test func anEndedExperimentMeasuresToItsEndNotItsIntendedEnd() {
        // Abandoned on day 3 of 21: doses logged afterwards belong to whatever the
        // person did next, not to the experiment.
        var e = exp()
        e.endedAt = t0.addingTimeInterval(3 * 86_400)
        e.status = .abandoned
        let a = ExperimentAdherence.measure(
            experiment: e, events: [dose(dayOffset: 1), dose(dayOffset: 10)], calendar: cal)
        #expect(a.doseDays == 1)
        #expect(a.windowDays == 3)
    }

    @Test func doseAtExactlyStartedAtCounts() {
        // The lower bound is >= : a dose at startedAt is included. This pins the
        // boundary against a > mutant.
        let a = ExperimentAdherence.measure(
            experiment: exp(),
            events: [HealthEvent(timestamp: t0, timezoneID: "UTC", category: .supplement,
                                 subtype: "Magnesium", objectID: objectID, value: 200,
                                 unit: "mg", source: .manual)],
            calendar: cal)
        #expect(a.doseDays == 1)
        #expect(a.doses == 1)
    }

    @Test func doseAtExactlyIntendedEndAtDoesNotCount() {
        // The upper bound is < : a dose at end is excluded. A 21-day experiment ending
        // at midnight on day 21 should not count a dose at that exact moment as being
        // in the window; without this, "22 of 21 days" is possible.
        let a = ExperimentAdherence.measure(
            experiment: exp(),
            events: [HealthEvent(timestamp: t0.addingTimeInterval(21 * 86_400),
                                 timezoneID: "UTC", category: .supplement,
                                 subtype: "Magnesium", objectID: objectID, value: 200,
                                 unit: "mg", source: .manual)],
            calendar: cal)
        #expect(a.doseDays == 0)
        #expect(a.doses == 0)
    }

    @Test func experimentEndedMidDayIncludesThatDay() {
        // An experiment ended at 14:00 on day 3 spans four calendar days (0, 1, 2, 3).
        // Without accounting for mid-day endings, windowDays would be 3 and doseDays
        // could exceed it. Invariant: doseDays <= windowDays must always hold.
        var e = exp(days: 5)
        e.endedAt = t0.addingTimeInterval(3 * 86_400 + 14 * 3600)  // day 3 at 14:00
        e.status = .abandoned
        let a = ExperimentAdherence.measure(
            experiment: e,
            events: [dose(dayOffset: 0), dose(dayOffset: 1),
                     dose(dayOffset: 2), dose(dayOffset: 3)],
            calendar: cal)
        #expect(a.doseDays == 4)
        #expect(a.windowDays == 4)
        #expect(a.doseDays <= a.windowDays)
    }
}
