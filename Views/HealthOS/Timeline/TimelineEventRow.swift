import SwiftUI
import HealthGraphCore

struct TimelineEventRow: View {
    let event: HealthEvent
    let onTap: (HealthEvent) -> Void

    @AppStorage("hg.temperatureUnit") private var rawTempUnit = ""

    private var style: CategoryStyle { .style(for: event.category) }
    private var isDuration: Bool { event.endTimestamp != nil }

    private var valueLineColor: Color {
        if event.category == .symptom, let v = event.value { return HealthTheme.severityColor(Int(v)) }
        return HealthTheme.inkSecondary
    }

    private var displayValueLine: String? {
        WeatherValueFormatter.line(for: event, unit: TemperatureUnit.resolved(from: rawTempUnit)) ?? EventDisplay.valueLine(for: event)
    }

    var body: some View {
        Button {
            onTap(event)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // day spine gutter + category tick
                ZStack {
                    Rectangle()
                        .fill(HealthTheme.cardBorder)
                        .frame(width: 1)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(style.color)
                        .frame(width: 3, height: isDuration ? 28 : 16)
                }
                .frame(width: 20)
                Image(systemName: style.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(style.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(EventDisplay.title(for: event))
                        .font(.body)
                        .foregroundStyle(HealthTheme.ink)
                        .lineLimit(2)
                    if let line = displayValueLine {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(valueLineColor)
                    }
                }
                Spacer(minLength: 8)
                Text(event.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
            }
            .padding(.trailing, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Shows event details")
    }

    private var accessibilitySummary: String {
        var parts = [style.family.label, EventDisplay.title(for: event)]
        if let line = displayValueLine { parts.append(line) }
        parts.append(event.timestamp.formatted(.dateTime.hour().minute()))
        return parts.joined(separator: ", ")
    }
}
