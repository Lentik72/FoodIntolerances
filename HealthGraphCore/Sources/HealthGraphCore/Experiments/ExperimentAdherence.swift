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
                && e.timestamp <= end
        }
        let days = Set(inWindow.map { calendar.startOfDay(for: $0.timestamp) })
        let startDay = calendar.startOfDay(for: experiment.startedAt)
        let endDay = calendar.startOfDay(for: end)
        let components = calendar.dateComponents([.day], from: startDay, to: endDay)
        let windowDays = max(components.day ?? 0, 0)
        return ExperimentAdherence(doseDays: days.count, doses: inWindow.count, windowDays: windowDays)
    }
}
