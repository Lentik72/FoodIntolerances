import SwiftUI
import SwiftData

/// View showing AI-learned insights and patterns
struct AIInsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AIMemory.confidence, order: .reverse) private var memories: [AIMemory]
    @Query private var userProfiles: [UserProfile]

    @State private var selectedTab: InsightTab = .triggers
    @State private var showRebuildAlert = false

    private var profile: UserProfile? { userProfiles.first }

    enum InsightTab: String, CaseIterable {
        case triggers = "Triggers"
        case whatWorks = "What Works"
        case patterns = "Patterns"

        var icon: String {
            switch self {
            case .triggers: return "exclamationmark.triangle"
            case .whatWorks: return "checkmark.circle"
            case .patterns: return "waveform.path.ecg"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Category", selection: $selectedTab) {
                    ForEach(InsightTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if filteredMemories.isEmpty {
                    ContentUnavailableView(
                        "No \(selectedTab.rawValue) Yet",
                        systemImage: selectedTab.icon,
                        description: Text("Keep logging your symptoms and the AI will learn your patterns")
                    )
                } else {
                    List {
                        ForEach(filteredMemories) { memory in
                            MemoryInsightRow(memory: memory)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        dismissMemory(memory)
                                    } label: {
                                        Label("Dismiss", systemImage: "xmark")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        confirmMemory(memory)
                                    } label: {
                                        Label("Confirm", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("AI Insights")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showRebuildAlert = true
                        } label: {
                            Label("Rebuild Insights", systemImage: "arrow.clockwise")
                        }

                        Button(role: .destructive) {
                            clearAllMemories()
                        } label: {
                            Label("Clear All Insights", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Rebuild Insights?", isPresented: $showRebuildAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Rebuild") {
                    rebuildMemories()
                }
            } message: {
                Text("This will re-analyze all your logs to find patterns. Existing insights will be updated.")
            }
        }
    }

    private var filteredMemories: [AIMemory] {
        memories.filter { memory in
            guard memory.isActive else { return false }
            switch selectedTab {
            case .triggers:
                return memory.memoryTypeEnum == .trigger
            case .whatWorks:
                return memory.memoryTypeEnum == .whatWorked || memory.memoryTypeEnum == .whatDidntWork
            case .patterns:
                return memory.memoryTypeEnum == .pattern || memory.memoryTypeEnum == .correlation
            }
        }
    }

    private func confirmMemory(_ memory: AIMemory) {
        memory.confirmByUser()
        try? modelContext.save()
    }

    private func dismissMemory(_ memory: AIMemory) {
        memory.denyByUser()
        memory.isActive = false
        try? modelContext.save()
    }

    private func clearAllMemories() {
        for memory in memories {
            modelContext.delete(memory)
        }
        try? modelContext.save()
    }

    private func rebuildMemories() {
        // Clear existing memories
        for memory in memories {
            modelContext.delete(memory)
        }

        // Fetch all logs
        let logsDescriptor = FetchDescriptor<LogEntry>(sortBy: [SortDescriptor(\.date)])
        let trackedDescriptor = FetchDescriptor<TrackedItem>()

        guard let logs = try? modelContext.fetch(logsDescriptor),
              let treatments = try? modelContext.fetch(trackedDescriptor) else {
            return
        }

        let memoryLevel = profile.flatMap { AIMemoryLevel(rawValue: $0.memoryLevel) } ?? .patterns
        let service = UserMemoryService()
        _ = service.buildInitialMemories(
            from: logs,
            treatments: treatments,
            context: modelContext,
            memoryLevel: memoryLevel
        )

        try? modelContext.save()
    }
}

// MARK: - Memory Insight Row

struct MemoryInsightRow: View {
    let memory: AIMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with type and confidence
            HStack {
                Image(systemName: memory.memoryTypeEnum.icon)
                    .foregroundColor(typeColor)
                    .font(.headline)

                Text(insightTitle)
                    .font(.headline)

                Spacer()

                ConfidenceBadge(level: memory.confidenceLevel)
            }

            // Description
            Text(insightDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Stats row
            HStack(spacing: 16) {
                Label("\(memory.occurrenceCount)x", systemImage: "number")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if memory.memoryTypeEnum == .whatWorked || memory.memoryTypeEnum == .whatDidntWork {
                    Label("\(memory.effectivenessPercentage)%", systemImage: "chart.bar")
                        .font(.caption)
                        .foregroundColor(memory.effectivenessScore > 0.5 ? .green : .orange)
                }

                Spacer()

                if memory.userConfirmed {
                    Label("Confirmed", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var typeColor: Color {
        switch memory.memoryTypeEnum {
        case .trigger: return .orange
        case .whatWorked: return .green
        case .whatDidntWork: return .red
        case .pattern: return .purple
        case .correlation: return .blue
        case .preference: return .pink
        }
    }

    private var insightTitle: String {
        switch memory.memoryTypeEnum {
        case .trigger:
            return memory.trigger?.capitalized ?? "Trigger"
        case .whatWorked, .whatDidntWork:
            return memory.resolution?.capitalized ?? "Treatment"
        case .pattern, .correlation:
            return memory.symptom ?? "Pattern"
        case .preference:
            return "Preference"
        }
    }

    private var insightDescription: String {
        switch memory.memoryTypeEnum {
        case .trigger:
            return "\(memory.trigger ?? "This") may trigger \(memory.symptom ?? "symptoms")"
        case .whatWorked:
            return "\(memory.resolution ?? "This") helps with \(memory.symptom ?? "symptoms")"
        case .whatDidntWork:
            return "\(memory.resolution ?? "This") doesn't help with \(memory.symptom ?? "symptoms")"
        case .pattern, .correlation:
            return memory.notes ?? "\(memory.symptom ?? "Symptoms") observed with pattern"
        case .preference:
            return memory.notes ?? "User preference"
        }
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let level: ConfidenceLevel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)
            Text(level.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.1))
        .cornerRadius(12)
    }

    private var badgeColor: Color {
        switch level {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }
}

// MARK: - AI Feedback Buttons

struct AIFeedbackButtons: View {
    let memory: AIMemory
    let onFeedback: (UserFeedback) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(UserFeedback.allCases, id: \.self) { feedback in
                Button {
                    onFeedback(feedback)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: feedback.icon)
                            .font(.title3)
                        Text(feedback.rawValue)
                            .font(.caption2)
                    }
                    .foregroundColor(feedbackColor(feedback))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(feedbackColor(feedback).opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }

    private func feedbackColor(_ feedback: UserFeedback) -> Color {
        switch feedback {
        case .helped: return .green
        case .didntHelp: return .red
        case .notSureYet: return .gray
        case .notRelevant: return .orange
        }
    }
}

// MARK: - AI Response Card (for showing after logging)

struct AIResponseCard: View {
    let response: AIResponse
    let onFeedback: ((AIMemory, UserFeedback) -> Void)?

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                Text("AI Insights")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }

            if isExpanded {
                // Warnings (shown first)
                ForEach(response.warnings.indices, id: \.self) { index in
                    WarningRow(warning: response.warnings[index])
                }

                // Observations
                ForEach(response.observations.indices, id: \.self) { index in
                    ObservationRow(observation: response.observations[index])
                }

                // Suggestions
                ForEach(response.suggestions.indices, id: \.self) { index in
                    SuggestionRow(
                        suggestion: response.suggestions[index],
                        memory: response.observations.indices.contains(index)
                            ? response.observations[index].relatedMemory : nil,
                        onFeedback: onFeedback
                    )
                }

                // Questions
                ForEach(response.questions.indices, id: \.self) { index in
                    QuestionRow(question: response.questions[index])
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Supporting Views

struct WarningRow: View {
    let warning: AIWarning

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: warning.severity.icon)
                .foregroundColor(warningColor)
            Text(warning.text)
                .font(.subheadline)
            Spacer()
        }
        .padding(8)
        .background(warningColor.opacity(0.1))
        .cornerRadius(8)
    }

    private var warningColor: Color {
        switch warning.severity {
        case .info: return .blue
        case .caution: return .orange
        case .alert: return .red
        }
    }
}

struct ObservationRow: View {
    let observation: AIObservation

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: observation.icon)
                .foregroundColor(.blue)
            Text(observation.text)
                .font(.subheadline)
            Spacer()
        }
    }
}

struct SuggestionRow: View {
    let suggestion: AISuggestion
    let memory: AIMemory?
    let onFeedback: ((AIMemory, UserFeedback) -> Void)?

    @State private var showFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: suggestion.icon)
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.text)
                        .font(.subheadline)
                    if let effectiveness = suggestion.effectiveness {
                        Text("\(effectiveness)% effective for you")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            if let memory = memory, let onFeedback = onFeedback {
                if showFeedback {
                    AIFeedbackButtons(memory: memory) { feedback in
                        onFeedback(memory, feedback)
                        showFeedback = false
                    }
                } else {
                    Button("Did this help?") {
                        showFeedback = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

struct QuestionRow: View {
    let question: AIQuestion

    @State private var selectedOption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.orange)
                Text(question.text)
                    .font(.subheadline)
            }

            HStack(spacing: 8) {
                ForEach(question.options, id: \.self) { option in
                    Button(option) {
                        selectedOption = option
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedOption == option ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(selectedOption == option ? .white : .primary)
                    .cornerRadius(16)
                }
            }
        }
    }
}

#Preview {
    AIInsightsView()
        .modelContainer(for: [AIMemory.self, UserProfile.self], inMemory: true)
}
