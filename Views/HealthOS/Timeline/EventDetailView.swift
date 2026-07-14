import SwiftUI
import HealthGraphCore

struct EventDetailView: View {
    let event: HealthEvent
    @ObservedObject var viewModel: TimelineViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleteFailed = false
    @State private var editing = false

    /// Re-resolves the event by id from the (already `@ObservedObject`) viewModel's
    /// refreshed timeline so the screen reflects a just-saved edit live, falling
    /// back to the original copy if it's no longer in the loaded slice.
    private var displayEvent: HealthEvent {
        viewModel.days.flatMap(\.events).first { $0.id == event.id } ?? event
    }

    private var style: CategoryStyle { .style(for: displayEvent.category) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                whenCard
                sourceCard
                if !metadataRows.isEmpty { detailsCard }
                deleteButton
                if deleteFailed {
                    Text("Couldn't delete. Please try again.")
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.amber)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if event.source == .manual {
                    Button { editing = true } label: {
                        Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $editing) { EventEditView(event: displayEvent, viewModel: viewModel) }
                }
            }
            .padding(16)
        }
        .background(HealthTheme.paper)
        .navigationTitle(EventDisplay.title(for: displayEvent))
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
                Text(EventDisplay.title(for: displayEvent))
                    .font(HealthTheme.sectionHeader())
                    .foregroundStyle(HealthTheme.ink)
                HStack(spacing: 6) {
                    Circle().fill(style.color).frame(width: 8, height: 8)
                    Text(style.family.label)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkSecondary)
                    if let line = EventDisplay.valueLine(for: displayEvent) {
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
            row("Time", displayEvent.timestamp.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
            if let end = displayEvent.endTimestamp {
                row("Until", end.formatted(.dateTime.hour().minute()))
            }
            if displayEvent.timezoneID != TimeZone.current.identifier {
                row("Time zone", displayEvent.timezoneID)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Source", sourceLabel)
            if displayEvent.confidence < 1 {
                row("Parse confidence", displayEvent.confidence.formatted(.percent.precision(.fractionLength(0))))
            }
            row("Added", displayEvent.createdAt.formatted(.dateTime.month().day().year()))
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
                if await viewModel.delete(target) {
                    dismiss()
                } else {
                    deleteFailed = true
                }
            }
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
        guard let data = displayEvent.metadata,
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [] }
        let labels = ["kcal": "Calories", "distanceKm": "Distance (km)",
                      "phase": "Moon phase", "season": "Season"]
        return dict.sorted { $0.key < $1.key }
            .map { (labels[$0.key] ?? $0.key, $0.value) }
    }
}
