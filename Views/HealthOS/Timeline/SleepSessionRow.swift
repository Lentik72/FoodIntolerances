import SwiftUI
import HealthGraphCore

/// One expandable night/nap row. Collapsed: "Sleep · 7h 32m" + bed→wake range.
/// Expanded: stacked stage-proportion bar + per-stage duration lines.
/// Sessions are display-time aggregates — never navigable, editable, or deletable.
struct SleepSessionRow: View {
    let session: SleepSession
    let isExpanded: Bool
    let onToggle: () -> Void

    private var style: CategoryStyle { .style(for: .sleep) }

    /// inBed-only sessions (phone-only data) have no stage breakdown.
    private var kindLabel: String {
        session.asleepMinutes > 0 ? (session.kind == .nap ? "Nap" : "Sleep") : "In bed"
    }
    private var displayMinutes: Double {
        session.asleepMinutes > 0 ? session.asleepMinutes : session.inBedMinutes
    }
    private var rangeText: String {
        "\(session.start.formatted(.dateTime.hour().minute())) – \(session.end.formatted(.dateTime.hour().minute()))"
    }

    /// Breakdown rows, spec order, stages under a minute omitted. The colors
    /// are an opacity ramp of the sleep family color; Awake is neutral.
    private var stages: [(label: String, minutes: Double, color: Color)] {
        [("Deep", session.deepMinutes, style.color),
         ("Core", session.coreMinutes, style.color.opacity(0.7)),
         ("REM", session.remMinutes, style.color.opacity(0.45)),
         ("Asleep", session.unspecifiedMinutes, style.color.opacity(0.55)),
         ("Awake", session.awakeMinutes, HealthTheme.inkMuted.opacity(0.5))]
            .filter { $0.minutes >= 1 }
    }
    private var isExpandable: Bool { !stages.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpandable { onToggle() }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    // day spine gutter + duration tick (same anatomy as TimelineEventRow)
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
                    Text("\(kindLabel) · \(EventDisplay.durationString(minutes: displayMinutes))")
                        .font(.body)
                        .foregroundStyle(HealthTheme.ink)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(rangeText)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkMuted)
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
            .accessibilityLabel("\(kindLabel), \(EventDisplay.durationString(minutes: displayMinutes)), \(rangeText)")
            .accessibilityHint(isExpandable
                               ? (isExpanded ? "Collapses stage breakdown" : "Expands stage breakdown")
                               : "")
            .accessibilityAddTraits(.isButton)

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
            stackedBar
                .frame(height: 6)
                .clipShape(Capsule())
                .accessibilityHidden(true)   // decorative — the lines carry the data
            ForEach(stages, id: \.label) { stage in
                HStack(spacing: 8) {
                    Circle().fill(stage.color).frame(width: 8, height: 8)
                    Text(stage.label)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkSecondary)
                    Spacer()
                    Text(EventDisplay.durationString(minutes: stage.minutes))
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            let total = stages.reduce(0) { $0 + $1.minutes }
            HStack(spacing: 0) {
                ForEach(stages, id: \.label) { stage in
                    Rectangle()
                        .fill(stage.color)
                        .frame(width: total > 0 ? geo.size.width * stage.minutes / total : 0)
                }
            }
        }
    }
}
