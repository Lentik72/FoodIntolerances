import SwiftUI
import HealthGraphCore

struct InsightsView: View {
    @StateObject private var vm = InsightsViewModel()
    @StateObject private var refresh = InsightsRefreshCoordinator()
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var archiveExpanded = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.feed.sections.isEmpty {
                    // Demoted-to-empty-state coverage strip (spec §5) — reused whole, not duplicated.
                    InsightsPlaceholderView()
                } else {
                    feed
                }
            }
            .background(HealthTheme.paper)
            .navigationDestination(for: UUID.self) { relationshipID in
                InsightDetailView(relationshipID: relationshipID)
            }
            .overlay(alignment: .bottom) { undoToast }
            .animation(.easeOut(duration: 0.2), value: vm.pendingUndo)
        }
        .task {
            await refresh.refreshIfNeeded()
            await vm.load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh.refreshIfNeeded(); await vm.load() }
        }
        .onChange(of: captureCoordinator.lastCaptureAt) { _, _ in
            Task { await refresh.refreshIfNeeded(); await vm.load() }
        }
        .onChange(of: refresh.lastRecomputeAt) { _, _ in
            Task { await vm.load() }
        }
        .task(id: vm.pendingUndo) {
            guard vm.pendingUndo != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            vm.pendingUndo = nil
        }
    }

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Insights")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                ForEach(vm.feed.sections) { section in
                    sectionView(section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable {
            await refresh.refreshIfNeeded()
            await vm.load()
        }
    }

    @ViewBuilder
    private func sectionView(_ section: InsightSection) -> some View {
        switch section.kind {
        case .active:
            VStack(alignment: .leading, spacing: 12) {
                Text("Active patterns")
                    .font(HealthTheme.sectionHeader())
                    .foregroundStyle(HealthTheme.ink)
                cardsStack(section.cards)
            }
        case .noEffect:
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No effect found")
                        .font(HealthTheme.sectionHeader())
                        .foregroundStyle(HealthTheme.ink)
                    Text("Wins — you can stop wondering about these.")
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkSecondary)
                }
                cardsStack(section.cards)
            }
        case .archive:
            archiveSection(section.cards)
        }
    }

    private func cardsStack(_ cards: [InsightCardModel], dismissable: Bool = true) -> some View {
        VStack(spacing: 12) {
            ForEach(cards) { card in
                InsightCardView(card: card, onDismiss: dismissable ? {
                    Task { await vm.dismiss(card) }
                } : nil)
            }
        }
    }

    private func archiveSection(_ cards: [InsightCardModel]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { archiveExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Archive")
                        .font(HealthTheme.sectionHeader())
                        .foregroundStyle(HealthTheme.ink)
                    Spacer()
                    Text(cards.count.formatted())
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.inkMuted)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HealthTheme.inkMuted)
                        .rotationEffect(.degrees(archiveExpanded ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archive, \(cards.count) dismissed insights")
            .accessibilityValue(archiveExpanded ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isButton)
            if archiveExpanded {
                cardsStack(cards, dismissable: false)
            }
        }
    }

    @ViewBuilder
    private var undoToast: some View {
        if let pending = vm.pendingUndo {
            HStack(spacing: 12) {
                Text("Insight dismissed")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.ink)
                Button("Undo") {
                    Task { await vm.undoDismiss() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HealthTheme.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .hgCard()
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Insight dismissed")
            .accessibilityAction(named: "Undo") { Task { await vm.undoDismiss() } }
            .id(pending.id)
        }
    }
}

#Preview("Insights — light") {
    InsightsView()
        .environmentObject(CaptureCoordinator())
}

#Preview("Insights — dark") {
    InsightsView()
        .environmentObject(CaptureCoordinator())
        .preferredColorScheme(.dark)
}
