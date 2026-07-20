import SwiftUI
import HealthGraphCore

struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel(
        store: GRDBEventStore(database: HealthGraphProvider.shared))
    @State private var searchDebounce: Task<Void, Never>?
    @State private var path = NavigationPath()
    @State private var expandedSessions: Set<String> = []
    @State private var expandedEnvironment: Set<String> = []
    @State private var editingEvent: HealthEvent?
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 12) {
                header
                TimelineFilterBar(viewModel: viewModel)
                feed
            }
            .background(HealthTheme.paper)
            .navigationDestination(for: HealthEvent.self) { event in
                EventDetailView(event: event, viewModel: viewModel)
            }
            .sheet(item: $editingEvent) { event in
                EventEditView(event: event, viewModel: viewModel)
            }
            .overlay(alignment: .bottom) {
                if let pending = viewModel.pendingUndo {
                    HStack(spacing: 12) {
                        Text("Event deleted")
                            .font(.subheadline)
                            .foregroundStyle(HealthTheme.ink)
                        Button("Undo") {
                            Task { await viewModel.undoDelete() }
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
                    .accessibilityLabel("Event deleted")
                    .accessibilityAction(named: "Undo") { Task { await viewModel.undoDelete() } }
                    .id(pending.id)
                }
            }
            .animation(.easeOut(duration: 0.2), value: viewModel.pendingUndo)
        }
        .task { await viewModel.loadInitial() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh() } }
        }
        .onChange(of: captureCoordinator.lastCaptureAt) { _, _ in
            Task { await viewModel.refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
                .padding(.top, 8)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HealthTheme.inkMuted)
                TextField("Search your history", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.searchText) { _, _ in
                        searchDebounce?.cancel()
                        searchDebounce = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await viewModel.searchTextChanged()
                        }
                    }
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                        Task { await viewModel.searchTextChanged() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(HealthTheme.inkMuted)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .hgCard()
        }
        .padding(.horizontal, 16)
    }

    private var feed: some View {
        List {
            if viewModel.days.isEmpty && !viewModel.isLoading {
                emptyState
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(viewModel.days) { day in
                Section {
                    ForEach(day.items) { item in
                        switch item {
                        case .event(let event):
                            TimelineEventRow(event: event) { tapped in
                                path.append(tapped)
                            }
                            .padding(.leading, 16)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !event.isReadOnlyEnvironment {
                                    Button(role: .destructive) {
                                        Task { await viewModel.delete(event) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                if event.source == .manual {
                                    Button {
                                        editingEvent = event
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(HealthTheme.accent)
                                }
                            }
                        case .sleepSession(let session):
                            SleepSessionRow(session: session,
                                            isExpanded: expandedSessions.contains(session.id)) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if expandedSessions.contains(session.id) {
                                        expandedSessions.remove(session.id)
                                    } else {
                                        expandedSessions.insert(session.id)
                                    }
                                }
                            }
                            .padding(.leading, 16)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        case .environmentSummary(let summary):
                            EnvironmentSummaryRow(summary: summary,
                                                  isExpanded: expandedEnvironment.contains(summary.id)) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if expandedEnvironment.contains(summary.id) { expandedEnvironment.remove(summary.id) }
                                    else { expandedEnvironment.insert(summary.id) }
                                }
                            }
                            .padding(.leading, 16)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            // no .swipeActions — environment is read-only
                        }
                    }
                } header: {
                    TimelineDayHeader(day: day)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HealthTheme.paper)
                        .listRowInsets(EdgeInsets())
                        .textCase(nil)
                }
                .listSectionSeparator(.hidden)   // MUST be on the Section — inert if applied to the List
            }
            if viewModel.hasMore && !viewModel.days.isEmpty && !viewModel.isSearchActive {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onAppear { Task { await viewModel.loadMore() } }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .background(HealthTheme.paper)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await viewModel.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.isSearchActive ? "magnifyingglass" : "list.bullet.rectangle")
                .font(.system(size: 32))
                .foregroundStyle(HealthTheme.inkMuted)
            Text(viewModel.isSearchActive
                 ? "Nothing matches that search."
                 : "Your timeline is empty. Connect Apple Health from the Health tab and your data flows in automatically.")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

#Preview("Timeline — sticky headers") {
    func ev(_ minsAgo: Double, _ cat: EventCategory, _ sub: String, _ v: Double?) -> HealthEvent {
        HealthEvent(timestamp: Date(timeIntervalSinceNow: -minsAgo * 60),
                    category: cat, subtype: sub, value: v, source: .manual)
    }
    let cal = Calendar.current
    let days = [
        TimelineDay(dayStart: cal.startOfDay(for: Date()),
                    items: [.event(ev(30, .symptom, "headache", 6)),
                            .event(ev(120, .mood, "mood", 2)),
                            .event(ev(200, .note, "Slept badly", nil))],
                    severityPoints: [SeverityPoint(time: Date(), value: 6)]),
        TimelineDay(dayStart: cal.startOfDay(for: Date(timeIntervalSinceNow: -86_400)),
                    items: [.event(ev(1_500, .symptom, "nausea", 3))],
                    severityPoints: []),
    ]
    return List {
        ForEach(days) { day in
            Section {
                ForEach(day.items) { item in
                    if case .event(let e) = item {
                        TimelineEventRow(event: e) { _ in }
                            .padding(.leading, 16)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            } header: {
                TimelineDayHeader(day: day)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HealthTheme.paper)
                    .listRowInsets(EdgeInsets())
                    .textCase(nil)
            }
            .listSectionSeparator(.hidden)
        }
    }
    .listStyle(.plain)
    .listSectionSpacing(0)
    .scrollContentBackground(.hidden)
    .background(HealthTheme.paper)
}
