import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

/// Pins the descriptive-copy contract for the Trends surface (Task 8): a
/// summary line states the range of weekly medians, the unit, and coverage —
/// and NOTHING that implies a direction or a cause. See the round's decision
/// record: docs/OPEN-QUESTION-trends-verdict.md.
@Suite struct TrajectoryPresentationTests {
    /// Fixed coverage (284 of 364 days) and weekly medians spanning 68–74 kg,
    /// so every assertion is hand-checkable (68 kg = 149.9 lb, 74 kg =
    /// 163.1 lb — chosen so no imperial string contains a metric digit-run).
    /// Non-weight series reuse the exact same shape with their own units —
    /// the summary format doesn't change per series, only the unit label and
    /// (for weight only) the conversion.
    private func sample(_ series: TrajectorySeries, window: TrendWindow = .weeks13) -> TrajectorySnapshot {
        snapshot(series, window: window, values: [68, 71, 74, 70], weekStride: 1,
                 coverage: SeriesCoverage(daysWithData: 284, daysInWindow: 364,
                                          weeksWithData: 4, weeksInWindow: window.rawValue))
    }

    /// A steps snapshot whose weekly medians span 91…5944 — the exact shape
    /// that read "91–5944 count" on the device.
    private func stepsSample() -> TrajectorySnapshot {
        snapshot(.steps, window: .weeks13, values: [91, 5944, 4207], weekStride: 1,
                 coverage: SeriesCoverage(daysWithData: 284, daysInWindow: 364,
                                          weeksWithData: 3, weeksInWindow: TrendWindow.weeks13.rawValue))
    }

    /// Builds a snapshot from `values`, one per `weekStride` calendar weeks
    /// starting at a fixed Monday. `windowStart`/`currentWeekStart` are
    /// derived the way `WeeklyBucketing` derives them — the last charted week
    /// IS the current week, and the window opens `window.rawValue - 1` weeks
    /// before it — so the x-domain assertions test a realistic snapshot.
    private func snapshot(_ series: TrajectorySeries, window: TrendWindow,
                          values: [Double], weekStride: Int,
                          coverage: SeriesCoverage) -> TrajectorySnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!  // a Monday
        let weeks = values.enumerated().map { offset, value in
            WeeklyPoint(weekStart: calendar.date(byAdding: .weekOfYear, value: offset * weekStride, to: base)!,
                        value: value, dayCount: weekStride == 1 ? 7 : 3)
        }
        let currentWeekStart = weeks.last!.weekStart
        return TrajectorySnapshot(
            series: series, window: window, weeks: weeks, coverage: coverage,
            rangeLow: values.min()!, rangeHigh: values.max()!,
            windowStart: calendar.date(byAdding: .weekOfYear,
                                       value: -(window.rawValue - 1), to: currentWeekStart)!,
            currentWeekStart: currentWeekStart
        )
    }

    /// Same shape, thin coverage: 42 of 91 days. Weekly medians still span
    /// 68–74 so a thin-coverage snapshot is otherwise indistinguishable from
    /// `sample(_:)` except for the coverage numbers under test.
    private func sparseSample(_ series: TrajectorySeries, window: TrendWindow = .weeks13) -> TrajectorySnapshot {
        // Every third week present — a real gap, not merely a short list.
        snapshot(series, window: window, values: [68, 74], weekStride: 3,
                 coverage: SeriesCoverage(daysWithData: 42, daysInWindow: 91,
                                          weeksWithData: 2, weeksInWindow: window.rawValue))
    }

    @Test func noTrajectoryEverClaimsACauseOrADirection() {
        #expect(TrajectorySeries.allCases.count == 6)          // else the sweep is vacuous
        let causal = ["because", "caused", "led to", "due to", "linked to", "resulted in"]
        let directional = ["trend", "rising", "falling", "increas", "decreas",
                           "improv", "worsen", "declin", "climb", "↑", "↓"]
        func assertClean(_ text: String, _ context: String) {
            #expect(!text.isEmpty, "\(context)")               // else a `default: ""` arm passes
            for banned in causal + directional {
                #expect(!text.localizedCaseInsensitiveContains(banned), "\(context): \(text)")
            }
            // "up"/"down" only as whole words, so "supplement" stays legal.
            #expect(text.range(of: #"\b(up|down)\b"#,
                               options: [.regularExpression, .caseInsensitive]) == nil, "\(context): \(text)")
        }
        for system in [UnitSystem.metric, .imperial] {
            for series in TrajectorySeries.allCases {
                assertClean(TrajectoryPresentation.summary(for: sample(series), system: system), "\(series)")
            }
        }
        // The summary is not the only string on the card: the chart draws the
        // current week's caption too, and it is held to the same bar.
        for dayCount in 1...7 {
            assertClean(TrajectoryPresentation.currentWeekCaption(dayCount: dayCount), "caption \(dayCount)")
        }
    }

    // MARK: - Chart values (the chart plots what the summary says)

    @Test func stepsSummaryReadsStepsWithGrouping() {
        // "91–5944 count" is what the device showed: a storage unit as a
        // label, and an unreadable five-digit run.
        let text = TrajectoryPresentation.summary(for: stepsSample(), system: .metric,
                                                  locale: Locale(identifier: "en_US"))
        #expect(text.contains("91–5,944 steps"), "\(text)")
        #expect(!text.localizedCaseInsensitiveContains("count"), "\(text)")
    }

    @Test func weightRangeConvertsForTheChartToo() {
        // The summary already converted; if the chart doesn't, it plots
        // kilograms under a "lb" line — the device gate's first finding.
        let imperial = TrajectoryPresentation.displayRange(for: sample(.weight), system: .imperial)
        #expect(abs(imperial.low - 149.91) < 0.05)
        #expect(abs(imperial.high - 163.14) < 0.05)
        let metric = TrajectoryPresentation.displayRange(for: sample(.weight), system: .metric)
        #expect(metric.low == 68 && metric.high == 74)
        #expect(abs(TrajectoryPresentation.displayValue(70, for: .weight, system: .imperial) - 154.32) < 0.01)
        // Only weight converts — a steps count is a steps count in Ohio too.
        #expect(TrajectoryPresentation.displayValue(70, for: .steps, system: .imperial) == 70)
    }

    @Test func yDomainHasShapeForNarrowData() {
        // 5% of the 77.85 midpoint = a 3.89 span, padded 15% below and 40%
        // above: real variation stays visible instead of flattening against a
        // zero-based auto axis.
        let narrow = TrajectoryPresentation.yDomain(low: 77.2, high: 78.5)
        #expect(narrow.lowerBound > 75.0 && narrow.lowerBound < 75.6, "\(narrow)")
        #expect(narrow.upperBound > 81.0 && narrow.upperBound < 81.7, "\(narrow)")
        // A flat series must still produce a usable domain — Charts traps on
        // equal bounds (see TrajectoryChartRenderTests.flatSeriesRendersWithoutTrapping).
        let flat = TrajectoryPresentation.yDomain(low: 70, high: 70)
        #expect(flat.lowerBound < flat.upperBound, "\(flat)")
        // Steps: padding below would go negative, so the axis clamps at zero.
        #expect(TrajectoryPresentation.yDomain(low: 91, high: 9325).lowerBound == 0)
        let zero = TrajectoryPresentation.yDomain(low: 0, high: 0)
        #expect(zero.lowerBound == 0 && zero.upperBound > 0, "\(zero)")
    }

    @Test func xDomainIsTheWindow() {
        // Every card spans the whole window, so a card whose data stops in
        // August shows the hole instead of stretching to fill the card — and
        // all six cards line up.
        let snapshot = sparseSample(.weight)
        #expect(TrajectoryPresentation.xDomain(for: snapshot)
                == snapshot.windowStart...snapshot.currentWeekStart)
    }

    @Test func unitLabelFollowsTheUnitSystemForWeightOnly() {
        #expect(TrajectoryPresentation.unitLabel(for: .weight, system: .imperial) == "lb")
        #expect(TrajectoryPresentation.unitLabel(for: .weight, system: .metric) == "kg")
        #expect(TrajectoryPresentation.unitLabel(for: .steps, system: .imperial) == "steps")
        for series in TrajectorySeries.allCases where series != .weight {
            for system in [UnitSystem.metric, .imperial] {
                #expect(TrajectoryPresentation.unitLabel(for: series, system: system)
                        == series.displayUnit, "\(series)")
            }
        }
    }

    @Test func weightIsConvertedNotRelabelled() {
        let imperial = TrajectoryPresentation.summary(for: sample(.weight), system: .imperial)
        let metric = TrajectoryPresentation.summary(for: sample(.weight), system: .metric)
        #expect(imperial.contains("149.9") && imperial.contains("163.1"))
        #expect(!imperial.contains("68") && !imperial.contains("74"))
        #expect(metric.contains("68") && metric.contains("74"))
    }

    @Test func coverageIsPartOfEveryLineNotAFootnote() {
        for series in TrajectorySeries.allCases {
            let text = TrajectoryPresentation.summary(for: sample(series), system: .metric)
            #expect(text.contains("284") && text.contains("364"), "\(series): \(text)")
        }
    }

    @Test func thinCoverageIsStatedNotHidden() {
        let text = TrajectoryPresentation.summary(for: sparseSample(.weight), system: .metric)
        #expect(text.contains("42") && text.contains("91"))    // 42 of 91 days, still charted
    }

    @Test func theNonDiagnosticLineIsPlainAndPresent() {
        let text = NonDiagnosticFooter.copy
        #expect(!text.isEmpty)
        #expect(text.localizedCaseInsensitiveContains("not") &&
                text.localizedCaseInsensitiveContains("diagnos"))
        #expect(text.localizedCaseInsensitiveContains("clinician") ||
                text.localizedCaseInsensitiveContains("doctor"))
    }

    // MARK: - Chart gap-grouping (not in the brief's five, added for the
    // "gaps drawn as gaps" requirement — the chart consumes exactly this).

    @Test func contiguousWeeksFormOneRun() {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let weeks = (0..<4).map { offset in
            WeeklyPoint(weekStart: calendar.date(byAdding: .weekOfYear, value: offset, to: base)!,
                        value: 70, dayCount: 7)
        }
        let runs = TrajectoryPresentation.weeklyRuns(weeks, calendar: calendar)
        #expect(runs.count == 1)
        #expect(runs.first?.count == 4)
    }

    @Test func aMissingWeekSplitsTheRun() {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        // Weeks 0, 1, then a gap at 2, then week 3 — one calendar week missing.
        let present = [0, 1, 3].map { offset in
            WeeklyPoint(weekStart: calendar.date(byAdding: .weekOfYear, value: offset, to: base)!,
                        value: 70, dayCount: 7)
        }
        let runs = TrajectoryPresentation.weeklyRuns(present, calendar: calendar)
        #expect(runs.count == 2, "a missing week must break the run, not be bridged")
        #expect(runs.first?.count == 2)
        #expect(runs.last?.count == 1)
    }
}
