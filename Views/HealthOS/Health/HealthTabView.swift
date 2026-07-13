import SwiftUI

struct HealthTabView: View {
    @State private var showingLegacyApp = false

    private let comingRows: [(icon: String, name: String, detail: String)] = [
        ("cabinet", "Cabinet", "meds, supplements, peptides — stock and refills"),
        ("checklist", "Protocols & experiments", "adherence and outcomes"),
        ("testtube.2", "Labs", "trends per analyte, imports"),
        ("chart.bar", "Health confidence", "how complete your data is"),
        ("doc.text", "Doctor report", "a PDF your practitioner can actually read"),
    ]

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

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(comingRows, id: \.name) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.body)
                                Text(item.detail).font(.caption)
                            }
                            Spacer()
                            Text("Soon").font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(HealthTheme.dotMiss.opacity(0.4)))
                        }
                        .foregroundStyle(HealthTheme.inkMuted)
                        .padding(16)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.name), coming soon. \(item.detail)")
                        if item.name != comingRows.last?.name {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .hgCard()

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
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.trailing, 12)
                        .padding(.top, 6)
                        .accessibilityLabel("Close legacy app")
                }
        }
    }
}
