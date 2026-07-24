import SwiftUI
import SwiftData

struct HealthTabView: View {
    #if DEBUG
    @State private var showingLegacyApp = false
    #endif
    @AppStorage("hg.temperatureUnit") private var rawTempUnit = ""
    @AppStorage("hg.measurementSystem") private var rawUnitSystem = ""
    @Query private var userProfiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var statusStore: EnvironmentStatusStore

    private var tempUnitBinding: Binding<TemperatureUnit> {
        Binding(get: { TemperatureUnit.resolved(from: rawTempUnit) },
                set: { rawTempUnit = $0.rawValue })
    }

    private var environmentSummaryText: String {
        switch EnvironmentStatusPresentation.summary(statusStore.statuses) {
        case .unavailable(let phrase): return phrase
        case .notChecked:              return "Not checked yet"
        case .updated(let date):       return "Updated \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    private var unitSystemBinding: Binding<UnitSystem> {
        Binding(get: { UnitSystem.resolved(from: rawUnitSystem) },
                set: { newValue in
                    rawUnitSystem = newValue.rawValue                      // global is the source of truth
                    if let profile = userProfiles.first {                  // mirror; never create one
                        profile.unitPreference = newValue.rawValue
                        do { try modelContext.save() }
                        catch { Logger.error(error, message: "Failed to mirror units to profile", category: .data) }
                    }
                })
    }

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
                    NavigationLink {
                        EnvironmentStatusView()
                    } label: {
                        HStack {
                            Image(systemName: "cloud.sun")
                                .foregroundStyle(HealthTheme.accent)
                            Text("Environment")
                                .foregroundStyle(HealthTheme.ink)
                            Spacer()
                            Text(environmentSummaryText)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint("Shows when weather and air quality data last updated")
                }
                .hgCard()

                VStack(spacing: 0) {
                    NavigationLink {
                        RedFlagRemindersView()
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.shield")
                                .foregroundStyle(HealthTheme.accent)
                            Text("Safety reminders")
                                .foregroundStyle(HealthTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    Divider().padding(.leading, 16)
                    HStack {
                        Image(systemName: "thermometer.medium")
                            .foregroundStyle(HealthTheme.accent)
                        Text("Temperature")
                            .foregroundStyle(HealthTheme.ink)
                        Spacer()
                        Picker("Temperature unit", selection: tempUnitBinding) {
                            Text("°C").tag(TemperatureUnit.celsius)
                            Text("°F").tag(TemperatureUnit.fahrenheit)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("Temperature unit")
                        .frame(width: 116)
                    }
                    .padding(16)
                    Divider().padding(.leading, 16)
                    HStack {
                        Image(systemName: "ruler")
                            .foregroundStyle(HealthTheme.accent)
                        Text("Units")
                            .foregroundStyle(HealthTheme.ink)
                        Spacer()
                        Picker("Measurement system", selection: unitSystemBinding) {
                            Text("Imperial").tag(UnitSystem.imperial)
                            Text("Metric").tag(UnitSystem.metric)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("Measurement system")
                        .frame(width: 160)
                    }
                    .padding(16)
                    #if DEBUG
                    Divider().padding(.leading, 16)
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
        #if DEBUG
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
        #endif
    }
}
