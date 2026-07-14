import SwiftUI

/// Custom bottom bar: Home · Timeline · [+] · Insights · Health.
/// The center capture button is raised and always reachable one-handed.
struct HealthOSTabBar: View {
    @Binding var selection: HealthOSTab
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.home)
            tabButton(.timeline)
            captureButton
            tabButton(.insights)
            tabButton(.health)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .background(
            HealthTheme.paper
                .overlay(Rectangle().frame(height: 1).foregroundStyle(HealthTheme.cardBorder), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ tab: HealthOSTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20))
                Text(tab.label)
                    .font(.caption2)
            }
            .foregroundStyle(selection == tab ? HealthTheme.accent : HealthTheme.inkMuted)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
    }

    private var captureButton: some View {
        Button(action: onCapture) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(HealthTheme.onAccent)
                .frame(width: 56, height: 56)
                .background(Circle().fill(HealthTheme.accent))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .offset(y: -10)
        .accessibilityLabel("Capture")
        .accessibilityHint("Log a symptom, meal, dose, or note")
    }
}
