import SwiftUI
import UIKit

/// The "Environment data" detail screen: five per-capability rows grouped into
/// Weather / Air quality, then a live-or-resolved explanation. All strings come
/// from the pure `EnvironmentStatusPresentation`.
struct EnvironmentStatusView: View {
    @EnvironmentObject private var statusStore: EnvironmentStatusStore

    private var rows: [EnvironmentStatusPresentation.Row] { EnvironmentStatusPresentation.rows(statusStore.statuses) }
    private var explanation: EnvironmentStatusPresentation.Explanation? { EnvironmentStatusPresentation.explanation(statusStore.statuses) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Environment data")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                section("Weather", rows.filter { $0.section == .weather })
                section("Air quality", rows.filter { $0.section == .airQuality })
                if let explanation { explanationCard(explanation) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
    }

    private func section(_ title: String, _ rows: [EnvironmentStatusPresentation.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.caption).foregroundStyle(HealthTheme.inkMuted)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                HStack {
                    Text(row.title).font(.body).foregroundStyle(HealthTheme.ink)
                    Spacer()
                    Text(statusText(row.status)).font(.footnote).foregroundStyle(HealthTheme.inkMuted)
                }
                .padding(16)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.title), \(statusText(row.status))")
                if idx != rows.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .hgCard()
    }

    private func statusText(_ status: EnvironmentStatusPresentation.RowStatus) -> String {
        switch status {
        case .unavailable:        return "Unavailable"
        case .notChecked:         return "Not checked yet"
        case .updated(let date):  return "Updated \(updatedText(date))"
        }
    }

    private func updatedText(_ date: Date) -> String {
        switch EnvironmentStatusPresentation.timestampStyle(for: date, now: Date(), calendar: .current) {
        case .timeToday:  return date.formatted(date: .omitted, time: .shortened)
        case .dateOlder:  return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private func lastTriedText(_ at: Date) -> String {
        switch EnvironmentStatusPresentation.timestampStyle(for: at, now: Date(), calendar: .current) {
        case .timeToday:
            return "Last tried today, \(at.formatted(date: .omitted, time: .shortened))"
        case .dateOlder:
            return "Last tried \(at.formatted(date: .abbreviated, time: .omitted)) at \(at.formatted(date: .omitted, time: .shortened))"
        }
    }

    private func explanationCard(_ e: EnvironmentStatusPresentation.Explanation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(e.heading.uppercased())
                .font(.caption).foregroundStyle(HealthTheme.inkMuted)
            Text(e.body).font(.subheadline).foregroundStyle(HealthTheme.inkSecondary)
            Text(lastTriedText(e.at)).font(.caption).foregroundStyle(HealthTheme.inkMuted)
            if e.showOpenSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HealthTheme.accent)
                .frame(minHeight: 44)
                .accessibilityHint("Opens this app's settings to enable location")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hgCard()
    }
}

#Preview("Environment status") {
    NavigationStack {
        EnvironmentStatusView()
    }
    .environmentObject(EnvironmentStatusStore(defaults: UserDefaults(suiteName: "preview")!))
}
