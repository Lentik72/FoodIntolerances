import SwiftUI
import HealthGraphCore

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel(
        store: GRDBEventStore(database: HealthGraphProvider.shared))
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                greeting
                MoodCheckInView()
                passiveStrip
                if let summary = viewModel.backfillSummary {
                    backfillCard(summary)
                }
                whatsNext
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh() } }
        }
        .onChange(of: captureCoordinator.lastCaptureAt) { _, _ in
            Task { await viewModel.refresh() }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
            Text(timeOfDayGreeting)
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
        }
        .padding(.top, 8)
    }

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var passiveStrip: some View {
        HStack(spacing: 0) {
            stat(icon: "moon.zzz.fill", color: CategoryFamily.sleep.color,
                 value: viewModel.sleepSummary ?? "—", label: "last night")
            Divider().padding(.vertical, 8)
            stat(icon: "figure.run", color: CategoryFamily.movement.color,
                 value: viewModel.stepsSummary ?? "—", label: "steps today")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .hgCard()
    }

    private func stat(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HealthTheme.ink)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(HealthTheme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func backfillCard(_ summary: (events: Int, categories: Int)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your history is in.")
                    .font(HealthTheme.sectionHeader())
                    .foregroundStyle(HealthTheme.ink)
                Text("\(summary.events.formatted()) events across \(summary.categories) categories — you're not starting from zero.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            Spacer()
            Button {
                viewModel.dismissBackfillCard()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(16)
        .hgCard()
    }

    private var whatsNext: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's next")
                .font(HealthTheme.sectionHeader())
                .foregroundStyle(HealthTheme.ink)
            Text("Capture and insights arrive in the next updates. Meanwhile, your timeline is filling itself.")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
        }
        .padding(.top, 8)
    }
}
