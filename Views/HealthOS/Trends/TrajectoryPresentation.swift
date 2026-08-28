import Foundation
import HealthGraphCore

/// Pure, descriptive rendering of a `TrajectorySnapshot` — the range of
/// weekly medians, the unit, and coverage. This is the whole contract for
/// this round's Trends copy: NO direction word, NO comparison of endpoints,
/// NO number that implies a change (see the round's decision record,
/// docs/OPEN-QUESTION-trends-verdict.md — the verdict is deliberately cut).
/// `TrajectoryPresentationTests.noTrajectoryEverClaimsACauseOrADirection`
/// sweeps every string this type can produce, across every series and both
/// unit systems, for banned causal/directional language.
enum TrajectoryPresentation {
    /// "Weekly medians 68–74 kg · based on 284 of 364 days."
    ///
    /// Coverage is stitched into THIS line, not rendered separately — a
    /// thin-coverage snapshot must read as thin wherever it's read, not only
    /// in a footnote a user can miss (see
    /// `coverageIsPartOfEveryLineNotAFootnote`/`thinCoverageIsStatedNotHidden`).
    static func summary(for snapshot: TrajectorySnapshot, system: UnitSystem) -> String {
        let (low, high, unit) = rangeText(for: snapshot, system: system)
        let coverage = snapshot.coverage
        return "Weekly medians \(low)–\(high) \(unit) · based on \(coverage.daysWithData) of \(coverage.daysInWindow) days"
    }

    /// The formatted low/high endpoints and the unit label to show alongside
    /// them. Every series but weight shows its raw catalog unit unchanged —
    /// only weight has a unit-system-dependent conversion.
    private static func rangeText(for snapshot: TrajectorySnapshot,
                                  system: UnitSystem) -> (low: String, high: String, unit: String) {
        guard snapshot.series == .weight else {
            return (formattedNumber(snapshot.rangeLow), formattedNumber(snapshot.rangeHigh), snapshot.series.unit)
        }
        let unit = system.weightUnit
        return (weightNumber(kg: snapshot.rangeLow, unit: unit),
                weightNumber(kg: snapshot.rangeHigh, unit: unit),
                unit.abbreviation)
    }

    /// Converts through `BodyMetricValueFormatter.line(kg:unit:)` — the SAME
    /// single conversion path Task 7 extracted for Timeline weight — then
    /// strips the trailing unit abbreviation that helper appends, because the
    /// caller writes the unit once for the whole "low–high unit" range, not
    /// once per endpoint. This file must never define a second
    /// `poundsPerKilogram`-shaped constant.
    private static func weightNumber(kg: Double, unit: WeightUnit) -> String {
        let line = BodyMetricValueFormatter.line(kg: kg, unit: unit)   // e.g. "149.9 lb"
        return line.components(separatedBy: " ").first ?? line
    }

    /// Whole numbers render without a trailing ".0"; anything else keeps one
    /// decimal place. Only non-weight series reach this path.
    private static func formattedNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }

    /// Groups ascending, calendar-week-sorted `weeks` into maximal runs of
    /// CONSECUTIVE calendar weeks (`weekStart` exactly one `.weekOfYear`
    /// apart). A missing week — simply absent from the array — starts a new
    /// run. The Trends chart draws one `LineMark` segment per run so a gap
    /// renders as a gap: nothing ever connects across a week that isn't
    /// there.
    static func weeklyRuns(_ weeks: [WeeklyPoint], calendar: Calendar) -> [[WeeklyPoint]] {
        var result: [[WeeklyPoint]] = []
        var current: [WeeklyPoint] = []
        for point in weeks {
            if let last = current.last,
               let expectedNext = calendar.date(byAdding: .weekOfYear, value: 1, to: last.weekStart),
               expectedNext == point.weekStart {
                current.append(point)
            } else {
                if !current.isEmpty { result.append(current) }
                current = [point]
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
