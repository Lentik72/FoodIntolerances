import SwiftUI

struct HealthTabView: View {
    @State private var showingLegacyApp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Health")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Cabinet, protocols, labs, and reports will live here.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)

                VStack(spacing: 0) {
                    Button {
                        showingLegacyApp = true
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(HealthTheme.accent)
                            Text("Open legacy app")
                                .foregroundStyle(HealthTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint("Opens the previous app interface")
                    #if DEBUG
                    Divider().padding(.leading, 16)
                    NavigationLink {
                        HealthGraphDebugView()
                    } label: {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundStyle(HealthTheme.accent)
                            Text("Health Graph Debug")
                                .foregroundStyle(HealthTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    #endif
                }
                .hgCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
        .fullScreenCover(isPresented: $showingLegacyApp) {
            // MainTabView already hosts its OWN NavigationStack (MainTabView.swift).
            // Present it bare — a second NavigationStack would stack an empty nav bar
            // above the legacy chrome. Float a Done control in the top-trailing safe area.
            MainTabView()
                .overlay(alignment: .topTrailing) {
                    Button("Done") { showingLegacyApp = false }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.trailing, 12)
                        .padding(.top, 6)
                        .accessibilityLabel("Close legacy app")
                }
        }
    }
}
