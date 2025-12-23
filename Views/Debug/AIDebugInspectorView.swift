// AIDebugInspectorView.swift
// Debug-only AI system inspector

import SwiftUI
import SwiftData

/// Debug view for inspecting AI system health and configuration
/// Access via long-press on AI Mode indicator or from developer settings
struct AIDebugInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var memories: [AIMemory]
    @Query private var userProfiles: [UserProfile]

    @State private var systemStatus: AISystemStatus?
    @State private var lastMaintenanceResult: Int?
    @State private var isRunningMaintenance = false

    private var userProfile: UserProfile? {
        userProfiles.first
    }

    var body: some View {
        NavigationStack {
            List {
                // System Status Section
                Section("System Status") {
                    if let status = systemStatus {
                        HStack {
                            Image(systemName: status.status.icon)
                                .foregroundColor(statusColor(status.status))
                            Text(status.status.rawValue)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(status.activeMemoryCount) active")
                                .foregroundColor(.secondary)
                        }

                        LabeledContent("Total Memories", value: "\(status.totalMemoryCount)")
                        LabeledContent("Active Memories", value: "\(status.activeMemoryCount)")
                        LabeledContent("In Cooldown", value: "\(status.memoriesInCooldown)")
                        LabeledContent("Stale", value: "\(status.staleMemoryCount)")
                        LabeledContent("Issues Detected", value: "\(status.issueCount)")

                        if status.schemaVersionIssues > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text("Schema migration needed: \(status.schemaVersionIssues)")
                                    .foregroundColor(.orange)
                            }
                        }
                    } else {
                        Text("Loading...")
                            .foregroundColor(.secondary)
                    }
                }

                // AI Configuration Section
                Section("AI Configuration") {
                    if let profile = userProfile {
                        LabeledContent("AI Mode", value: profile.aiSuggestionLevelEnum.displayName)
                        LabeledContent("Memory Level", value: AIMemoryLevel(rawValue: profile.memoryLevel)?.displayName ?? profile.memoryLevel)
                        LabeledContent("Learning Active", value: profile.allowMemoryLearning ? "Yes" : "Paused")

                        if let pausedDate = profile.learningPausedDate, !profile.allowMemoryLearning {
                            LabeledContent("Paused Since", value: pausedDate.formatted(date: .abbreviated, time: .shortened))
                        }
                    } else {
                        Text("No profile configured")
                            .foregroundColor(.secondary)
                    }
                }

                // Cloud AI Section
                Section("Cloud AI") {
                    let cloudAI = CloudAIService.shared
                    LabeledContent("Enabled", value: cloudAI.isEnabled ? "Yes" : "No")
                    LabeledContent("Provider", value: cloudAI.provider.rawValue)
                    LabeledContent("Has API Key", value: cloudAI.hasAPIKey(for: cloudAI.provider) ? "Yes" : "No")
                    LabeledContent("Include Notes", value: cloudAI.includeNotesInRequests ? "Yes" : "No")
                }

                // Maintenance Section
                Section("Maintenance") {
                    let scheduler = MemoryMaintenanceScheduler.shared

                    if let lastRun = scheduler.lastMaintenanceDate {
                        LabeledContent("Last Run", value: lastRun.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        LabeledContent("Last Run", value: "Never")
                    }

                    LabeledContent("Should Run", value: scheduler.shouldRunMaintenance ? "Yes" : "No")

                    if let result = lastMaintenanceResult {
                        LabeledContent("Last Result", value: "\(result) issues fixed")
                    }

                    Button {
                        runMaintenance()
                    } label: {
                        HStack {
                            if isRunningMaintenance {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isRunningMaintenance ? "Running..." : "Force Run Maintenance")
                        }
                    }
                    .disabled(isRunningMaintenance)
                }

                // Privacy Settings Section
                Section("Privacy Settings") {
                    let notificationManager = NotificationManager.shared
                    LabeledContent("Hide Notifications", value: notificationManager.hideSensitiveNotificationContent ? "Yes" : "No")

                    if let profile = userProfile {
                        LabeledContent("Proactive Notifications", value: profile.enableProactiveNotifications ? "Yes" : "No")
                    }
                }

                // Memory Breakdown Section
                Section("Memory Breakdown") {
                    let activeMemories = memories.filter { $0.isActive }
                    let byType = Dictionary(grouping: activeMemories) { $0.memoryTypeEnum }

                    ForEach(MemoryType.allCases, id: \.self) { type in
                        let count = byType[type]?.count ?? 0
                        if count > 0 {
                            LabeledContent(type.rawValue, value: "\(count)")
                        }
                    }
                }

                // Debug Actions Section
                #if DEBUG
                Section("Debug Actions") {
                    Button("Reset Maintenance Schedule") {
                        MemoryMaintenanceScheduler.shared.resetSchedule()
                    }

                    Button("Log All Memories", role: .destructive) {
                        for memory in memories {
                            Logger.debug("Memory: \(memory.id) - \(memory.memoryType) - \(memory.symptom ?? "no symptom") - conf: \(memory.confidence)", category: .data)
                        }
                    }
                }
                #endif
            }
            .navigationTitle("AI Debug Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        systemStatus = AISystemStatus.generate(from: memories)
    }

    private func runMaintenance() {
        isRunningMaintenance = true

        DispatchQueue.global(qos: .utility).async {
            let result = MemoryMaintenanceScheduler.shared.forceRunMaintenance(memories: memories)

            DispatchQueue.main.async {
                lastMaintenanceResult = result
                isRunningMaintenance = false
                refreshStatus()
            }
        }
    }

    private func statusColor(_ status: AISystemStatus.Status) -> Color {
        switch status {
        case .healthy: return .green
        case .degraded: return .yellow
        case .needsAttention: return .red
        }
    }
}

#Preview {
    AIDebugInspectorView()
        .modelContainer(for: [AIMemory.self, UserProfile.self])
}
