import Foundation

/// What the person actually did, derived from the events they already logged.
/// The experiment stores no logging of its own, so this can never disagree with
/// the Timeline.
public struct ExperimentAdherence: Equatable, Sendable {
    /// Distinct calendar days carrying at least one dose. The honest adherence
    /// statement is "you logged it on 18 of these 21 days"; a raw dose count would
    /// let three doses in one day read as three days of a regimen.
    public let doseDays: Int
    public let doses: Int
    public let windowDays: Int

    public init(doseDays: Int, doses: Int, windowDays: Int) {
        self.doseDays = doseDays; self.doses = doses; self.windowDays = windowDays
    }
}

extension ExperimentAdherence {
    public static func measure(experiment: Experiment, events: [HealthEvent],
                               calendar: Calendar) -> ExperimentAdherence {
        // An ended experiment measures to its END, not its intended end: doses
        // logged after someone abandoned on day 3 belong to whatever they did
        // next, not to the experiment.
        let end = experiment.endedAt ?? experiment.intendedEndAt
        let inWindow = events.filter { e in
            e.deletedAt == nil
                && e.objectID == experiment.interventionObjectID
                && e.timestamp >= experiment.startedAt
                && e.timestamp < end
        }
        let days = Set(inWindow.map { calendar.startOfDay(for: $0.timestamp) })
        let startDay = calendar.startOfDay(for: experiment.startedAt)
        let endDay = calendar.startOfDay(for: end)
        let spanned = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        // The +1 only belongs to an experiment that ENDED EARLY mid-day — that
        // partial day was actually lived, and stopping an experiment stamps
        // Date(), not a midnight boundary. It does NOT belong to the INTENDED
        // end: `intendedEndAt = startedAt + days*86400` preserves startedAt's
        // time of day, so a 21-day experiment started at 10:00 has an intended
        // end at 10:00 on day 21 — `end > endDay` is true there too, but no day
        // 21 was ever lived; counting it would report "22 days" for a 21-day
        // declaration while the countdown UI still says "21 days left" (or,
        // worse, let 22 days of logging outrun a 21-day denominator).
        let endedEarly = experiment.endedAt != nil
        let windowDays = max(spanned + (endedEarly && end > endDay ? 1 : 0), 0)
        return ExperimentAdherence(doseDays: days.count, doses: inWindow.count, windowDays: windowDays)
    }
}
