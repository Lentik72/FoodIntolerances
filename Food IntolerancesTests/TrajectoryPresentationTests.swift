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
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!  // a Monday
        let values: [Double] = [68, 71, 74, 70]
        let weeks = values.enumerated().map { offset, value in
            WeeklyPoint(weekStart: calendar.date(byAdding: .weekOfYear, value: offset, to: base)!,
                        value: value, dayCount: 7)
        }
        return TrajectorySnapshot(
            series: series, window: window, weeks: weeks,
            coverage: SeriesCoverage(daysWithData: 284, daysInWindow: 364,
                                     weeksWithData: weeks.count, weeksInWindow: window.rawValue),
            rangeLow: values.min()!, rangeHigh: values.max()!
        )
    }

    /// Same shape, thin coverage: 42 of 91 days. Weekly medians still span
    /// 68–74 so a thin-coverage snapshot is otherwise indistinguishable from
    /// `sample(_:)` except for the coverage numbers under test.
    private func sparseSample(_ series: TrajectorySeries, window: TrendWindow = .weeks13) -> TrajectorySnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let values: [Double] = [68, 74]
        // Every other week present — a real gap, not merely a short list.
        let weeks = values.enumerated().map { offset, value in
            WeeklyPoint(weekStart: calendar.date(byAdding: .weekOfYear, value: offset * 3, to: base)!,
                        value: value, dayCount: 3)
        }
        return TrajectorySnapshot(
            series: series, window: window, weeks: weeks,
            coverage: SeriesCoverage(daysWithData: 42, daysInWindow: 91,
                                     weeksWithData: weeks.count, weeksInWindow: window.rawValue),
            rangeLow: values.min()!, rangeHigh: values.max()!
        )
    }

    @Test func noTrajectoryEverClaimsACauseOrADirection() {
        #expect(TrajectorySeries.allCases.count == 6)          // else the sweep is vacuous
        let causal = ["because", "caused", "led to", "due to", "linked to", "resulted in"]
        let directional = ["trend", "rising", "falling", "increas", "decreas",
                           "improv", "worsen", "declin", "climb", "↑", "↓"]
        for system in [UnitSystem.metric, .imperial] {
            for series in TrajectorySeries.allCases {
                let text = TrajectoryPresentation.summary(for: sample(series), system: system)
                #expect(!text.isEmpty)                         // else a `default: ""` arm passes
                for banned in causal + directional {
                    #expect(!text.localizedCaseInsensitiveContains(banned), "\(series): \(text)")
                }
                // "up"/"down" only as whole words, so "supplement" stays legal.
                #expect(text.range(of: #"\b(up|down)\b"#,
                                   options: [.regularExpression, .caseInsensitive]) == nil, "\(series): \(text)")
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
