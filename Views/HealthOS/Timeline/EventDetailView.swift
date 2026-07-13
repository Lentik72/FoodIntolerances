import SwiftUI
import HealthGraphCore

struct EventDetailView: View {
    let event: HealthEvent
    @ObservedObject var viewModel: TimelineViewModel
    @Environment(\.dismiss) private var dismiss

    private var style: CategoryStyle { .style(for: event.category) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                whenCard
                sourceCard
                if !metadataRows.isEmpty { detailsCard }
                deleteButton
                Text("Editing arrives with capture, in the next update.")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(16)
        }
        .background(HealthTheme.paper)
        .navigationTitle(EventDisplay.title(for: event))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: style.icon)
                .font(.system(size: 24))
                .foregroundStyle(style.color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(style.color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(EventDisplay.title(for: event))
                    .font(HealthTheme.sectionHeader())
                    .foregroundStyle(HealthTheme.ink)
                HStack(spacing: 6) {
                    Circle().fill(style.color).frame(width: 8, height: 8)
                    Text(style.family.label)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkSecondary)
                    if let line = EventDisplay.valueLine(for: event) {
                        Text("·").foregroundStyle(HealthTheme.inkMuted)
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.inkSecondary)
                    }
                }
            }
        }
    }

    private var whenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Time", event.timestamp.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
            if let end = event.endTimestamp {
                row("Until", end.formatted(.dateTime.hour().minute()))
            }
            if event.timezoneID != TimeZone.current.identifier {
                row("Time zone", event.timezoneID)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Source", sourceLabel)
            if event.confidence < 1 {
                row("Parse confidence", event.confidence.formatted(.percent.precision(.fractionLength(0))))
            }
            row("Added", event.createdAt.formatted(.dateTime.month().day().year()))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(metadataRows, id: \.0) { key, value in
                row(key, value)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            let target = event
            Task {
                await viewModel.delete(target)
            }
            dismiss()
        } label: {
            Text("Delete event")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Removes the event. You can undo for a few seconds afterwards.")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(HealthTheme.ink)
            Spacer(minLength: 0)
        }
    }

    private var sourceLabel: String {
        switch event.source {
        case .healthKit: "Apple Health"
        case .healthExportFile: "Apple Health export file"
        case .weatherAPI: "Environment service"
        case .manual: "Manual entry"
        case .photo: "Photo capture"
        case .voice: "Voice capture"
        case .labImport: "Lab import"
        case .appIntent: "Siri / Shortcut"
        case .legacyImport: "Migrated from the previous app"
        }
    }

    private var metadataRows: [(String, String)] {
        guard let data = event.metadata,
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [] }
        let labels = ["kcal": "Calories", "distanceKm": "Distance (km)",
                      "phase": "Moon phase", "season": "Season"]
        return dict.sorted { $0.key < $1.key }
            .map { (labels[$0.key] ?? $0.key, $0.value) }
    }
}
