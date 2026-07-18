import SwiftUI
import UIKit

/// Root of the Health OS shell: 4 content tabs + center capture.
/// Replaces MainTabView as the app root (Task 7); the legacy app stays
/// reachable from the Health tab until its features are ported.
struct HealthOSRootView: View {
    @State private var selection: HealthOSTab = .home
    @State private var showingCapture = false
    @EnvironmentObject private var redFlagPresenter: RedFlagPresenter

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tab(.home) { HomeView() }
                tab(.timeline) { TimelineView() }
                tab(.insights) { InsightsView() }
                tab(.health) { NavigationStack { HealthTabView() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HealthOSTabBar(selection: $selection) { showingCapture = true }
        }
        .background(HealthTheme.paper.ignoresSafeArea())
        .sheet(isPresented: $showingCapture) {
            CaptureSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
        .onChange(of: selection) { _, _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onChange(of: redFlagPresenter.pending) { _, match in
            if match != nil { showingCapture = false }   // symptom saved; dismiss capture, app-level cover takes over
        }
    }

    /// Keeps EVERY tab mounted and toggles visibility, rather than a `switch`
    /// that gives each tab a distinct structural identity — a `switch` tears
    /// the inactive tab down, destroying its `@StateObject` view-model (paging,
    /// filters, search text, scroll position) on every tab change. Mounting all
    /// four preserves that state and makes tab switches instant. Hidden tabs are
    /// non-interactive and hidden from VoiceOver.
    @ViewBuilder
    private func tab<Content: View>(_ which: HealthOSTab,
                                    @ViewBuilder _ content: () -> Content) -> some View {
        let isActive = selection == which
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }
}

#Preview("Shell — light") {
    HealthOSRootView()
        .environmentObject(CaptureCoordinator())
        .environmentObject(RedFlagPresenter(muteStore: RedFlagMuteStore()))
}

#Preview("Shell — dark") {
    HealthOSRootView()
        .environmentObject(CaptureCoordinator())
        .environmentObject(RedFlagPresenter(muteStore: RedFlagMuteStore()))
        .preferredColorScheme(.dark)
}
