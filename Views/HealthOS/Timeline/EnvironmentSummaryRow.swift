import SwiftUI
import HealthGraphCore

/// One expandable per-day environment row. Collapsed: "Environment" + a headline
/// that leads with weather (`12–24°C · 69%`) and falls back to moon · season.
/// Expanded: the full labeled reading list. Auto-logged environment data is a
/// display-time aggregate — never navigable, editable, or deletable.
struct EnvironmentSummaryRow: View {
    let summary: EnvironmentDaySummary
    let isExpanded: Bool
    let onToggle: () -> Void

    @AppStorage("hg.temperatureUnit") private var rawTempUnit = ""

    private var style: CategoryStyle { .style(for: .environment) }
    private var unit: TemperatureUnit { .resolved(from: rawTempUnit) }

    private var headline: String { EnvironmentSummaryFormatter.headline(summary, unit: unit) }
    private var detailLines: [EnvironmentDetailLine] {
        EnvironmentSummaryFormatter.detailLines(summary, unit: unit)
    }
    private var isExpandable: Bool { detailLines.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpandable { onToggle() }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    // day spine gutter + tick (same anatomy as TimelineEventRow)
                    ZStack {
                        Rectangle()
                            .fill(HealthTheme.cardBorder)
                            .frame(width: 1)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(style.color)
                            .frame(width: 3, height: 28)
                    }
                    .frame(width: 20)
                    Image(systemName: style.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(style.color)
                        .frame(width: 24)
                    Text("Environment")
                        .font(.body)
                        .foregroundStyle(HealthTheme.ink)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(headline)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkMuted)
                        .multilineTextAlignment(.trailing)
                    if isExpandable {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HealthTheme.inkMuted)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(.trailing, 16)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Environment, \(headline)")
            .accessibilityHint(isExpandable
                               ? (isExpanded ? "Collapses environment details" : "Expands environment details")
                               : "")
            .accessibilityAddTraits(isExpandable ? .isButton : [])

            if isExpanded && isExpandable {
                breakdown
                    .padding(.leading, 56)   // aligns under the title column
                    .padding(.trailing, 16)
                    .padding(.bottom, 10)
            }
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(detailLines, id: \.label) { line in
                HStack(spacing: 8) {
                    Text(line.label)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkSecondary)
                    Spacer()
                    if let value = line.value {
                        Text(value)
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.ink)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
