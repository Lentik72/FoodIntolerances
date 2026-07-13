import SwiftUI
import HealthGraphCore

struct InsightsPlaceholderView: View {
    @State private var familyCounts: [(family: CategoryFamily, count: Int)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Insights")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("The engine isn't watching yet — but your data is ready.")
                        .font(HealthTheme.sectionHeader())
                        .foregroundStyle(HealthTheme.ink)
                    ForEach(familyCounts, id: \.family) { entry in
                        HStack(spacing: 8) {
                            Circle().fill(entry.count > 0 ? entry.family.color : HealthTheme.dotMiss)
                                .frame(width: 10, height: 10)
                            Text(entry.family.label)
                                .font(.subheadline)
                                .foregroundStyle(entry.count > 0 ? HealthTheme.ink : HealthTheme.inkMuted)
                            Spacer()
                            Text(entry.count > 0 ? entry.count.formatted() : "none yet")
                                .font(.subheadline)
                                .foregroundStyle(HealthTheme.inkSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(entry.family.label): \(entry.count) events")
                    }
                    Text("When the evidence engine arrives, patterns will appear here with the observations behind them.")
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkMuted)
                        .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hgCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
        .task { await loadCounts() }
    }

    private func loadCounts() async {
        let store = GRDBEventStore(database: HealthGraphProvider.shared)
        guard let raw = try? await store.countsByCategory() else { return }
        let counts = raw.reduce(into: [CategoryFamily: Int]()) { acc, pair in
            guard let category = EventCategory(rawValue: pair.key) else { return }
            acc[CategoryStyle.style(for: category).family, default: 0] += pair.value
        }
        familyCounts = CategoryFamily.allCases
            .map { (family: $0, count: counts[$0] ?? 0) }
            .sorted { ($0.count > 0 ? 0 : 1, $0.family.rawValue) < ($1.count > 0 ? 0 : 1, $1.family.rawValue) }
    }
}
