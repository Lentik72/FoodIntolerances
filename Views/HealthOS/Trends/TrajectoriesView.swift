import SwiftUI
import Charts
import HealthGraphCore

/// Health tab → Trends: one card per charted series (weekly medians, a
/// descriptive summary, coverage folded into that summary — see
/// `TrajectoryPresentation`), a 13/52-week picker, and the shared
/// non-diagnostic footer. Chart-only: no fitted line, no smoothing, no slope
/// band, no direction word anywhere on this screen (the round's decision
/// record: docs/OPEN-QUESTION-trends-verdict.md).
struct TrajectoriesView: View {
    @StateObject private var state: TrajectoriesViewState
    @AppStorage("hg.measurementSystem") private var rawUnitSystem = ""

    init(database: AppDatabase = HealthGraphProvider.shared, calendar: Calendar = .current) {
        _state = StateObject(wrappedValue: TrajectoriesViewState(
            eventStore: GRDBEventStore(database: database), calendar: calendar))
    }

    private var unitSystem: UnitSystem { UnitSystem.resolved(from: rawUnitSystem) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Trends")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Weekly medians from your own records — a picture, not a verdict.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)

                windowPicker

                if state.isLoading && state.snapshots.isEmpty {
                    loadingState
                } else if state.snapshots.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(state.snapshots.enumerated()), id: \.offset) { _, snapshot in
                        TrajectoryRowView(snapshot: snapshot, system: unitSystem)
                            .hgCard()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(HealthTheme.paper)
        .navigationTitle("Trends")
        .task { state.appeared() }
        .safeAreaInset(edge: .bottom) {
            NonDiagnosticFooter()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(HealthTheme.paper)
        }
    }

    private var loadingState: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(16)
    }

    private var windowPicker: some View {
        Picker("Chart window", selection: Binding(
            get: { state.window },
            set: { state.selectWindow($0) }
        )) {
            Text("13 weeks").tag(TrendWindow.weeks13)
            Text("52 weeks").tag(TrendWindow.weeks52)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Chart window")
    }

    private var emptyState: some View {
        Text("No data yet for this window.")
            .font(.subheadline)
            .foregroundStyle(HealthTheme.inkSecondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hgCard()
    }
}

/// One series' card: name, the descriptive summary (coverage folded in),
/// and the chart. Nothing else — no per-row action, no tap target, no
/// verdict badge.
///
/// `internal` (not `private`) so `TrajectoryChartRenderTests` can force a
/// real `ImageRenderer` pass over the actual chart — the only thing that
/// ever renders `chart` before a device does.
struct TrajectoryRowView: View {
    let snapshot: TrajectorySnapshot
    let system: UnitSystem
    private let calendar = Calendar.current

    private var runs: [[WeeklyPoint]] {
        TrajectoryPresentation.weeklyRuns(snapshot.weeks, calendar: calendar)
    }

    /// The week containing the `asOf` the service bucketed with — the one
    /// week whose `dayCount` can legitimately be less than 7 simply because
    /// it hasn't finished yet, not because of a gap in logging. Only THIS
    /// point gets the ring and the "so far" caption; every other point's
    /// dayCount is left to the chart's gaps to speak for itself. Read off the
    /// snapshot, never re-derived from `Date()`: a second read can land on the
    /// other side of a week boundary from the one the buckets were built with.
    private var currentWeekPoint: WeeklyPoint? {
        snapshot.weeks.first { $0.weekStart == snapshot.currentWeekStart }
    }

    /// This point in the unit the summary line above the chart shows.
    private func displayValue(_ value: Double) -> Double {
        TrajectoryPresentation.displayValue(value, for: snapshot.series, system: system)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.series.displayName)
                .font(.headline)
                .foregroundStyle(HealthTheme.ink)
            Text(TrajectoryPresentation.summary(for: snapshot, system: system))
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            chart
                .frame(height: 140)
                .padding(.top, 4)
        }
        .padding(16)
    }

    /// A run's series identity for `foregroundStyle(by:)`/
    /// `chartForegroundStyleScale`. MUST be a categorical (`String`)
    /// plottable, not `Int`: Swift Charts reads an `Int` `.value(_:)` as a
    /// quantitative/continuous plottable, so a single-run series (no
    /// gaps — the ordinary case for most logged series) produces a
    /// ONE-element domain for what Charts treats as a linear scale, and
    /// Charts' linear scale traps building a domain with fewer than two
    /// values. Confirmed via
    /// `TrajectoryChartRenderTests.singleContiguousRunRendersWithoutTrapping`:
    /// `Charts/ConcreteScale+Continuous.swift:182: Precondition failed:
    /// Linear scale domain must contain two values`. A `String` id reads as
    /// categorical, whose scale has no such minimum.
    private func runID(_ index: Int) -> String { "run-\(index)" }

    private var chart: some View {
        // Both scales are computed once, from display values: whatever unit
        // the summary line states is the unit the marks and the axis carry.
        let range = TrajectoryPresentation.displayRange(for: snapshot, system: system)
        return Chart {
            // One LineMark run per contiguous stretch of calendar weeks,
            // each tagged with its OWN series identity (`run` index) via
            // `foregroundStyle(by:)` — that is what stops Swift Charts from
            // connecting across a missing week, which it otherwise does
            // for any two marks sharing one implicit series. The uniform
            // color below (`chartForegroundStyleScale`) then makes every
            // run look like the same line rather than a different color
            // per segment. A run of exactly one point draws no line at
            // all — an isolated week renders only as its dot.
            ForEach(Array(runs.enumerated()), id: \.offset) { runIndex, run in
                ForEach(run, id: \.weekStart) { point in
                    LineMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Value", displayValue(point.value))
                    )
                    .foregroundStyle(by: .value("Run", runID(runIndex)))
                    .interpolationMethod(.linear)   // no smoothing, no fitted curve
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            ForEach(snapshot.weeks, id: \.weekStart) { point in
                if point.weekStart == snapshot.currentWeekStart {
                    // The unfinished week reads as unfinished: a hollow ring,
                    // not another settled reading.
                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Value", displayValue(point.value))
                    )
                    .foregroundStyle(HealthTheme.accent)
                    .symbolSize(64)
                    .symbol(BasicChartSymbolShape.circle.strokeBorder(lineWidth: 2))
                } else {
                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Value", displayValue(point.value))
                    )
                    .foregroundStyle(HealthTheme.accent)
                    .symbolSize(24)
                }
            }
        }
        .chartForegroundStyleScale(
            domain: (0..<max(runs.count, 1)).map(runID),
            range: Array(repeating: HealthTheme.accent, count: max(runs.count, 1))
        )
        .chartLegend(.hidden)
        // Explicit, never automatic: Charts' auto y-scale starts at zero, which
        // flattens 170–173 lb into a straight line, and its auto x-scale shrinks
        // to whatever data a card happens to have, so a series that stopped
        // logging in August looks complete and no two cards share an axis.
        .chartYScale(domain: TrajectoryPresentation.yDomain(low: range.low, high: range.high))
        .chartXScale(domain: TrajectoryPresentation.xDomain(for: snapshot),
                     range: .plotDimension(startPadding: 8, endPadding: 8))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(TrajectoryPresentation.xAxisLabel(for: date, window: snapshot.window))
                    }
                }
            }
        }
        // Drawn in the plot's own top-trailing corner rather than attached to
        // the point: as an annotation it collided with the line on a 52-week
        // chart. `yDomain`'s 40% upper pad is the band it sits in.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let point = currentWeekPoint, let plotFrame = proxy.plotFrame {
                    let plot = geometry[plotFrame]
                    Text(TrajectoryPresentation.currentWeekCaption(dayCount: point.dayCount))
                        .font(.caption2)
                        .foregroundStyle(HealthTheme.inkMuted)
                        .padding(4)
                        .frame(width: plot.width, height: plot.height, alignment: .topTrailing)
                        .offset(x: plot.minX, y: plot.minY)
                }
            }
        }
        .accessibilityLabel(Text("\(snapshot.series.displayName) chart"))
        .accessibilityValue(Text(TrajectoryPresentation.summary(for: snapshot, system: system)))
    }
}
