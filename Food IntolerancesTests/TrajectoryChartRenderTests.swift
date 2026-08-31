import SwiftUI
import Testing
import HealthGraphCore
@testable import Food_Intolerances

/// Forces a REAL render of `TrajectoryRowView.chart` — the Trends chart that
/// no unit test, preview, or simulator run ever rendered before the device
/// crash this suite reproduces (Health tab → Trends, 3/3 taps, EXC_BREAKPOINT
/// deep inside Charts' render pipeline, no app frames on the crashed
/// thread). `ImageRenderer` drives SwiftUI's real layout pipeline, unlike
/// constructing the view alone, which never lays anything out.
///
/// Three fixtures below are the first tests that ever render this chart,
/// and stay as permanent regression tests. Two confirmed, independent
/// Charts traps, both "Linear scale domain must contain two values":
/// `singleContiguousRunRendersWithoutTrapping` — an `Int` `foregroundStyle
/// (by:)` read as quantitative gives a one-run series a one-element color
/// domain (THE primary, data-independent cause: almost every series has no
/// gaps) — and `flatSeriesRendersWithoutTrapping` — a series whose weekly
/// medians are all identical collapses the y-domain. `twoRunGapRendersWithoutTrapping`
/// pins the gap-breaking mechanism `foregroundStyle(by:)` exists for and
/// confirms a genuinely multi-run, non-flat series was never the problem.
@MainActor
@Suite struct TrajectoryChartRenderTests {
    private let calendar = Calendar.current

    /// Same shape as `TrajectoryPresentationTests.sample`, but built on
    /// `Calendar.current` — the calendar `TrajectoryRowView` itself uses
    /// internally — so the run-grouping this test exercises matches exactly
    /// what the view computes, not a fixture-only approximation.
    private func snapshot(weeks: [WeeklyPoint]) -> TrajectorySnapshot {
        TrajectorySnapshot(
            series: .weight,
            window: .weeks13,
            weeks: weeks,
            coverage: SeriesCoverage(daysWithData: weeks.count * 7, daysInWindow: 91,
                                     weeksWithData: weeks.count, weeksInWindow: 13),
            rangeLow: weeks.map(\.value).min() ?? 0,
            rangeHigh: weeks.map(\.value).max() ?? 0,
            windowStart: weekStart(-12),
            currentWeekStart: weekStart(0)
        )
    }

    /// `offset` weeks from the CURRENT calendar week — negative is the past.
    /// Every fixture below sits inside the window the snapshot declares
    /// (`weekStart(-12)...weekStart(0)`), because the chart now clips to that
    /// x-domain: a mark outside it would render nothing and quietly turn
    /// these render tests into assertions about an empty plot.
    private func weekStart(_ offset: Int) -> Date {
        let now = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
        return calendar.date(byAdding: .weekOfYear, value: offset, to: now)!
    }

    /// w0, w1, then a gap at w2, then w3 — `TrajectoryPresentation.weeklyRuns`
    /// splits this into TWO runs, so the chart draws two separately-tagged
    /// `LineMark` series via `foregroundStyle(by: .value("Run", runIndex))`.
    /// This is exactly the shape the leading crash hypothesis targets: an
    /// `Int` plottable read as quantitative against an explicit categorical
    /// `chartForegroundStyleScale`.
    @Test func twoRunGapRendersWithoutTrapping() {
        let weeks = [-4, -3, -1].map { offset in
            WeeklyPoint(weekStart: weekStart(offset), value: 72 + Double(offset), dayCount: 7)
        }
        let row = TrajectoryRowView(snapshot: snapshot(weeks: weeks), system: .metric)
        let image = ImageRenderer(content: row.frame(width: 320, height: 140)).uiImage
        #expect(image != nil)
    }

    /// One run, every value identical — `rangeLow == rangeHigh`, a
    /// degenerate y-domain some chart layout paths mishandle.
    @Test func flatSeriesRendersWithoutTrapping() {
        let weeks = (-4 ..< 0).map { offset in
            WeeklyPoint(weekStart: weekStart(offset), value: 70, dayCount: 7)
        }
        let row = TrajectoryRowView(snapshot: snapshot(weeks: weeks), system: .metric)
        let image = ImageRenderer(content: row.frame(width: 320, height: 140)).uiImage
        #expect(image != nil)
    }

    /// Four CONSECUTIVE weeks, distinct values — no gap, so
    /// `TrajectoryPresentation.weeklyRuns` returns exactly ONE run. This is
    /// the ordinary shape almost every series has (a user who hasn't missed
    /// a week of logging), which is exactly what makes it the primary,
    /// data-independent trigger for the device crash: `runs.count == 1`
    /// gives `chartForegroundStyleScale(domain: [0], ...)` a ONE-element
    /// `Int` domain, and Charts reads an `Int` `.value(_:)` as a
    /// quantitative (continuous/linear) plottable — the same "domain must
    /// contain two values" trap as `flatSeriesRendersWithoutTrapping`, but
    /// on the color scale rather than the y-scale.
    @Test func singleContiguousRunRendersWithoutTrapping() {
        let weeks = (-4 ..< 0).map { offset in
            WeeklyPoint(weekStart: weekStart(offset), value: 72 + Double(offset), dayCount: 7)
        }
        let row = TrajectoryRowView(snapshot: snapshot(weeks: weeks), system: .metric)
        let image = ImageRenderer(content: row.frame(width: 320, height: 140)).uiImage
        #expect(image != nil)
    }

    /// The same four weeks under `.imperial`, where every plotted y is a
    /// CONVERTED value (68 kg → 149.9 lb) and the y-domain is computed over
    /// converted numbers. Layout must survive the unit the summary line
    /// actually shows, not only the storage unit.
    @Test func imperialWeightRendersWithoutTrapping() {
        let weeks = (-4 ..< 0).map { offset in
            WeeklyPoint(weekStart: weekStart(offset), value: 72 + Double(offset), dayCount: 7)
        }
        let row = TrajectoryRowView(snapshot: snapshot(weeks: weeks), system: .imperial)
        let image = ImageRenderer(content: row.frame(width: 320, height: 140)).uiImage
        #expect(image != nil)
    }

    /// A snapshot whose last week IS `currentWeekStart`, one day in: the only
    /// shape that draws the hollow ring AND the "so far" caption in the
    /// plot's headroom band via `chartOverlay`. Every other fixture here
    /// stops before the current week, so this is the sole render of that path.
    @Test func currentWeekRingAndCaptionRenderWithoutTrapping() {
        let weeks = (-3 ... 0).map { offset in
            WeeklyPoint(weekStart: weekStart(offset), value: 72 + Double(offset),
                        dayCount: offset == 0 ? 1 : 7)
        }
        let row = TrajectoryRowView(snapshot: snapshot(weeks: weeks), system: .metric)
        let image = ImageRenderer(content: row.frame(width: 320, height: 140)).uiImage
        #expect(image != nil)
    }
}
