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

    /// The calendar week containing "now" — the one week whose `dayCount`
    /// can legitimately be less than 7 simply because it hasn't finished
    /// yet, not because of a gap in logging. Only THIS point gets the
    /// "so far" annotation; every other point's dayCount is left to the
    /// chart's gaps to speak for itself.
    private var currentWeekStart: Date? {
        calendar.dateInterval(of: .weekOfYear, for: Date())?.start
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
        Chart {
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
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(by: .value("Run", runID(runIndex)))
                    .interpolationMethod(.linear)   // no smoothing, no fitted curve
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            ForEach(snapshot.weeks, id: \.weekStart) { point in
                if point.weekStart == currentWeekStart {
                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(HealthTheme.accent)
                    .symbolSize(36)
                    .annotation(position: .top) {
                        Text("\(point.dayCount) of 7 days so far")
                            .font(.caption2)
                            .foregroundStyle(HealthTheme.inkMuted)
                    }
                } else {
                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Value", point.value)
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
        .accessibilityLabel(Text("\(snapshot.series.displayName) chart"))
        .accessibilityValue(Text(TrajectoryPresentation.summary(for: snapshot, system: system)))
        .applyingFlatSeriesYDomain(low: snapshot.rangeLow, high: snapshot.rangeHigh)
    }
}

private extension View {
    /// Charts' automatic linear y-scale traps when the domain it derives
    /// from the plotted marks has equal bounds — e.g. a snapshot with
    /// exactly one charted week, where `rangeLow == rangeHigh` by
    /// construction (min and max of a single value are equal). Confirmed
    /// via `TrajectoryChartRenderTests.flatSeriesRendersWithoutTrapping`:
    /// `Charts/ConcreteScale+Continuous.swift:182: Precondition failed:
    /// Linear scale domain must contain two values`. Only THIS degenerate
    /// case gets an explicit, padded domain — every other snapshot keeps
    /// Charts' own auto-derived y-domain untouched.
    @ViewBuilder
    func applyingFlatSeriesYDomain(low: Double, high: Double) -> some View {
        if low < high {
            self
        } else {
            let pad = max(abs(low) * 0.05, 0.5)
            self.chartYScale(domain: (low - pad)...(high + pad))
        }
    }
}
