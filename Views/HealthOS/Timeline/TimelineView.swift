import SwiftUI
import HealthGraphCore

struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel(
        store: GRDBEventStore(database: HealthGraphProvider.shared))
    @State private var searchDebounce: Task<Void, Never>?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 12) {
                header
                TimelineFilterBar(viewModel: viewModel)
                feed
            }
            .background(HealthTheme.paper)
            .navigationDestination(for: HealthEvent.self) { event in
                // Task 11 replaces this with EventDetailView(event:viewModel:)
                Text(EventDisplay.title(for: event))
            }
        }
        .task { await viewModel.loadInitial() }
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
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.days.isEmpty && !viewModel.isLoading {
                    emptyState.padding(.top, 60)
                }
                ForEach(viewModel.days) { day in
                    TimelineDayHeader(day: day)
                    ForEach(day.events) { event in
                        TimelineEventRow(event: event) { tapped in
                            path.append(tapped)
                        }
                        .padding(.leading, 16)
                    }
                }
                if viewModel.hasMore && !viewModel.days.isEmpty {
                    ProgressView()
                        .padding(.vertical, 24)
                        .onAppear { Task { await viewModel.loadMore() } }
                }
            }
            .padding(.bottom, 12)
        }
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
