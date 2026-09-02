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
    /// "Weekly medians 91–5,944 steps · based on 284 of 364 days."
    ///
    /// Coverage is stitched into THIS line, not rendered separately — a
    /// thin-coverage snapshot must read as thin wherever it's read, not only
    /// in a footnote a user can miss (see
    /// `coverageIsPartOfEveryLineNotAFootnote`/`thinCoverageIsStatedNotHidden`).
    ///
    /// `locale` is threaded (rather than read inside) purely so digit grouping
    /// is assertable; every production caller takes the default.
    static func summary(for snapshot: TrajectorySnapshot,
                        system: UnitSystem,
                        locale: Locale = .current) -> String {
        let range = displayRange(for: snapshot, system: system)
        let unit = unitLabel(for: snapshot.series, system: system)
        let low = formattedNumber(range.low, for: snapshot.series, locale: locale)
        let high = formattedNumber(range.high, for: snapshot.series, locale: locale)
        let coverage = snapshot.coverage
        return "Weekly medians \(low)–\(high) \(unit) · based on \(coverage.daysWithData) of \(coverage.daysInWindow) days"
    }

    /// The caption for the one week that hasn't finished yet. Drawn on the
    /// chart, so it is swept for banned language exactly like `summary`.
    static func currentWeekCaption(dayCount: Int) -> String {
        "\(dayCount) of 7 days so far"
    }

    /// An x-axis tick label. 13 weeks: month + day ("Jun 7"). 52 weeks:
    /// abbreviated month + a two-digit year ("Dec '25") — the apostrophe is
    /// what stops a year-grain label from being read as the day-grain one the
    /// other window uses ("Dec 25").
    ///
    /// BOTH parts come from the same `Date.FormatStyle`, never from a
    /// `Calendar.component(.year:)`: that reads the ERA year, so under a
    /// Buddhist or Japanese current calendar it would print a year that
    /// disagrees with the locale-formatted month standing next to it (and with
    /// what `.year(.twoDigits)` renders for the same instant). Drawn on the
    /// chart, so it is swept for banned language exactly like `summary`.
    static func xAxisLabel(for date: Date, window: TrendWindow, locale: Locale = .current) -> String {
        switch window {
        case .weeks13:
            return date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        case .weeks52:
            let month = date.formatted(.dateTime.month(.abbreviated).locale(locale))
            let year = date.formatted(.dateTime.year(.twoDigits).locale(locale))
            return "\(month) '\(year)"
        }
    }

    // MARK: - Chart values (whatever the summary says, the chart plots)

    /// A weekly value in the unit the summary line shows: weight through
    /// `BodyMetricValueFormatter.value(kg:unit:)` — the SAME single conversion
    /// path Task 7 extracted for Timeline weight, so the chart cannot drift
    /// from the copy above it. This file must never define a second
    /// `poundsPerKilogram`-shaped constant. Every other series is already in
    /// its display unit.
    static func displayValue(_ value: Double, for series: TrajectorySeries, system: UnitSystem) -> Double {
        series == .weight ? BodyMetricValueFormatter.value(kg: value, unit: system.weightUnit) : value
    }

    /// (low, high) of the snapshot's weekly medians in display units — the
    /// summary's endpoints and the chart's y-extent, from one computation.
    static func displayRange(for snapshot: TrajectorySnapshot,
                             system: UnitSystem) -> (low: Double, high: Double) {
        (low: displayValue(snapshot.rangeLow, for: snapshot.series, system: system),
         high: displayValue(snapshot.rangeHigh, for: snapshot.series, system: system))
    }

    /// The y-axis domain for a display-unit range. Charts' automatic
    /// zero-based scale flattens every series whose values sit far from zero
    /// (170–173 lb drawn on a 0–180 axis is a straight line), so the domain is
    /// explicit: span the data, widen symmetrically to at least ±2.5% of the
    /// typical value so a genuinely steady series isn't magnified into noise,
    /// then pad 15% below and 40% above — that upper band is the headroom the
    /// "so far" caption is drawn in. Clamped at 0 (every catalog series is
    /// non-negative). `lowerBound < upperBound` holds by construction, INCLUDING
    /// for a flat series, which is why no separate degenerate-case branch
    /// exists (Charts traps on an equal-bounds linear domain).
    static func yDomain(low: Double, high: Double) -> ClosedRange<Double> {
        let midpoint = (low + high) / 2
        let minimumSpan = max(abs(midpoint), 1) * 0.05
        let span = max(high - low, minimumSpan)
        let slack = (span - (high - low)) / 2      // 0 unless the floor widened it
        let lower = max(0, low - slack - span * 0.15)
        // The zero clamp is what could, in principle, invert the bounds; this
        // keeps the range constructible for any input rather than trusting the
        // non-negativity of the catalog to hold forever.
        return lower...max(high + slack + span * 0.40, lower + minimumSpan)
    }

    /// Every card's x-domain: the full requested window, so a series that
    /// stops logging in August shows the hole instead of stretching its last
    /// points across the card — and all six cards share one axis. Taken from
    /// the snapshot (the service's `asOf`), never re-derived from `Date()`.
    static func xDomain(for snapshot: TrajectorySnapshot) -> ClosedRange<Date> {
        snapshot.windowStart...snapshot.currentWeekStart
    }

    /// The label shown for the series' unit: weight → the unit system's
    /// abbreviation ("kg"/"lb"); every other series → its own display unit
    /// ("steps", not the stored "count").
    static func unitLabel(for series: TrajectorySeries, system: UnitSystem) -> String {
        series == .weight ? system.weightUnit.abbreviation : series.displayUnit
    }

    /// Weight keeps the Timeline's fixed one-decimal rendering ("170.2") so
    /// one reading looks the same in both places — this mirrors
    /// `BodyMetricValueFormatter.line`'s format; the conversion that could
    /// actually drift lives there and only there. Every other series renders
    /// 0–1 decimals with grouped digits, because a weekly steps median is a
    /// four- or five-digit number and "5944" is not a readable one.
    private static func formattedNumber(_ value: Double,
                                        for series: TrajectorySeries,
                                        locale: Locale) -> String {
        guard series != .weight else { return String(format: "%.1f", value) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
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
