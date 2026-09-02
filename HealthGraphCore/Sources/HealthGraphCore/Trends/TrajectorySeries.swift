import Foundation

/// The catalog of six charted trajectory series and how to extract each
/// one's `DailyPoint`s from a slice of `HealthEvent`s. Chart-only: no
/// verdict, no direction, no significance test — see the round's decision
/// record (docs/superpowers/specs/2026-08-27-health-trajectories-and-profile-design.md).
///
/// **No blood pressure.** Systolic/diastolic is a two-channel reading; a
/// single `Double` trajectory can't represent it honestly, so it is left out
/// of this catalog on purpose rather than charted as one arbitrary channel.
///
/// Exactly four `EventCategory` values back these six series (`.bodyMetric`,
/// `.sleep`, `.exercise`, `.vitals` — three series share `.vitals`), which is
/// what lets a caller read the corpus once per category instead of once per
/// series (see Task 5's `TrajectoryService`).
public enum TrajectorySeries: CaseIterable, Equatable, Sendable {
    case weight
    case sleepDuration
    case steps
    case restingHeartRate
    case hrv
    case respiratoryRate

    /// The `HealthEvent.category` this series reads.
    public var category: EventCategory {
        switch self {
        case .weight: .bodyMetric
        case .sleepDuration: .sleep
        case .steps: .exercise
        case .restingHeartRate, .hrv, .respiratoryRate: .vitals
        }
    }

    /// The exact `HealthEvent.subtype` this series reads, from
    /// `HealthKitSampleMapper`'s tables. `nil` for `sleepDuration`: sleep is
    /// not one subtype — it folds every asleep-stage subtype
    /// (`asleepCore`/`asleepDeep`/`asleepREM`/`asleepUnspecified`) into
    /// sessions via `SleepSessionBuilder` and reads `asleepMinutes`, never a
    /// single event's raw field.
    public var subtype: String? {
        switch self {
        case .weight: "weight"
        case .sleepDuration: nil
        case .steps: "steps"
        case .restingHeartRate: "restingHeartRate"
        case .hrv: "hrv"
        case .respiratoryRate: "respiratoryRate"
        }
    }

    public var unit: String {
        switch self {
        case .weight: "kg"
        case .sleepDuration: "hours"
        case .steps: "count"
        case .restingHeartRate: "bpm"
        case .hrv: "ms"
        case .respiratoryRate: "breaths/min"
        }
    }

    /// The unit label shown to a person. The storage unit stays what
    /// `HealthKitSampleMapper` writes ("count" for steps); only the label
    /// changes. Weight's label is unit-system-dependent and resolved by the
    /// app-side presentation, so it stays "kg" here.
    public var displayUnit: String { self == .steps ? "steps" : unit }

    public var displayName: String {
        switch self {
        case .weight: "Weight"
        case .sleepDuration: "Sleep Duration"
        case .steps: "Steps"
        case .restingHeartRate: "Resting Heart Rate"
        case .hrv: "Heart Rate Variability"
        case .respiratoryRate: "Respiratory Rate"
        }
    }

    /// Extracts this series' `DailyPoint`s from `events`. Deleted events
    /// (`deletedAt != nil`) are excluded for every series. Multiple readings
    /// on the same day are NOT collapsed here — one event, one point; per-day
    /// collapsing is `WeeklyBucketing.bucket`'s job.
    ///
    /// `calendar` supplies both the day boundary (`startOfDay`) for the
    /// direct-read series and the time zone (`calendar.timeZone`) the sleep
    /// session builder needs to classify night vs. nap.
    public func dailyPoints(from events: [HealthEvent], calendar: Calendar) -> [DailyPoint] {
        let live = events.filter { $0.deletedAt == nil }

        if self == .sleepDuration {
            // Attributed to the WAKING day (session end), not bed time: a
            // night that starts 23:00 Monday and ends 07:00 Tuesday is
            // Tuesday's sleep — attributing it to Monday shifts every night
            // in the chart by one day.
            // A session with no measured asleep time (inBed-only segments,
            // asleepMinutes == 0) must not chart as a 0-hour night — that is
            // the exact crash-to-the-floor rendering the spec forbids.
            return SleepSessionBuilder.sessions(from: live, timeZone: calendar.timeZone)
                .filter { $0.kind == .night && $0.asleepMinutes > 0 }
                .map { DailyPoint(day: calendar.startOfDay(for: $0.end), value: $0.asleepMinutes / 60) }
        }

        // Direct (category, subtype) read — covers weight, steps (already
        // daily-aggregated on ingest, so this is a straight read, never a
        // re-aggregation), restingHeartRate, hrv, respiratoryRate.
        return live
            .filter { $0.category == category && $0.subtype == subtype }
            .compactMap { event in
                guard let value = event.value else { return nil }
                return DailyPoint(day: calendar.startOfDay(for: event.timestamp), value: value)
            }
    }
}
