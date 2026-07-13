import SwiftUI

struct TimelineFilterBar: View {
    @ObservedObject var viewModel: TimelineViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CategoryFamily.allCases) { family in
                    chip(label: family.label, dotColor: family.color,
                         isOn: viewModel.activeFamilies.contains(family)) {
                        toggle(family: family)
                    }
                }
                Divider().frame(height: 20)
                ForEach(SourceFilter.allCases) { source in
                    chip(label: source.label, dotColor: nil,
                         isOn: viewModel.activeSources.contains(source)) {
                        toggle(source: source)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(label: String, dotColor: Color?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                }
                Text(label).font(.footnote)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(isOn ? HealthTheme.accent.opacity(0.14) : HealthTheme.card))
            .overlay(Capsule().strokeBorder(isOn ? HealthTheme.accent : HealthTheme.cardBorder, lineWidth: 1))
            .foregroundStyle(isOn ? HealthTheme.accent : HealthTheme.inkSecondary)
            .frame(minHeight: 44)          // meet the 44pt tap-target gate…
            .contentShape(Rectangle())     // …with the full band tappable (pill stays compact)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityHint("Filters the timeline")
    }

    private func toggle(family: CategoryFamily) {
        if viewModel.activeFamilies.contains(family) {
            viewModel.activeFamilies.remove(family)
        } else {
            viewModel.activeFamilies.insert(family)
        }
        Task { await viewModel.filtersChanged() }
    }

    private func toggle(source: SourceFilter) {
        if viewModel.activeSources.contains(source) {
            viewModel.activeSources.remove(source)
        } else {
            viewModel.activeSources.insert(source)
        }
        Task { await viewModel.filtersChanged() }
    }
}
