// AIInsightComponents.swift
// Extracted from LogSymptomView.swift

import SwiftUI

// MARK: - Allergen Warning Card

struct AllergenWarningCard: View {
    let result: FoodSafetyResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.statusIcon)
                    .font(.title2)
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(statusColor)

                    Text(result.explanation)
                        .font(.caption)
                        .foregroundColor(.primary)
                }

                Spacer()
            }

            if let source = result.crossReactionSource {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                    Text("Cross-reaction: \(source)")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            if !result.additionalNotes.isEmpty {
                Text(result.additionalNotes.first ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(12)
        .background(backgroundColor)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor.opacity(0.5), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusTitle): \(result.explanation)")
    }

    private var statusColor: Color {
        switch result.status {
        case .safe: return .green
        case .caution: return .orange
        case .avoid: return .red
        }
    }

    private var backgroundColor: Color {
        switch result.status {
        case .safe: return .green.opacity(0.1)
        case .caution: return .orange.opacity(0.1)
        case .avoid: return .red.opacity(0.1)
        }
    }

    private var statusTitle: String {
        switch result.status {
        case .safe: return "Safe for you"
        case .caution: return "Possible allergen concern"
        case .avoid: return "Allergy warning!"
        }
    }
}

// MARK: - AI Insight Response Sheet

struct AIInsightResponseSheet: View {
    let response: AIResponse
    let onDismiss: () -> Void
    let onFeedback: ((AIMemory, UserFeedback) -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Success message
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text("Log Saved Successfully")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Log saved successfully")

                    // AI Insights Header
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.purple)
                            .font(.title2)
                        Text("AI Insights")
                            .font(.title2)
                            .bold()
                    }
                    .padding(.top)
                    .accessibilityAddTraits(.isHeader)

                    // Warnings Section
                    if !response.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(response.warnings.indices, id: \.self) { index in
                                AIWarningCardRow(warning: response.warnings[index])
                            }
                        }
                    }

                    // Observations Section
                    if !response.observations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What I noticed")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(response.observations.indices, id: \.self) { index in
                                AIObservationCardRow(observation: response.observations[index])
                            }
                        }
                    }

                    // Suggestions Section
                    if !response.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggestions")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(response.suggestions.indices, id: \.self) { index in
                                AISuggestionCardRow(
                                    suggestion: response.suggestions[index],
                                    memory: response.observations.indices.contains(index)
                                        ? response.observations[index].relatedMemory : nil,
                                    onFeedback: onFeedback
                                )
                            }
                        }
                    }

                    // Questions Section
                    if !response.questions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick questions")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(response.questions.indices, id: \.self) { index in
                                AIQuestionCardRow(question: response.questions[index])
                            }
                        }
                    }

                    // Empty state if no insights
                    if !response.hasContent {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Keep logging to help me learn your patterns")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Keep logging to help AI learn your patterns")
                    }
                }
                .padding()
            }
            .navigationTitle("AI Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - AI Insight Card Rows

struct AIWarningCardRow: View {
    let warning: AIWarning

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warning.severity.icon)
                .foregroundColor(warningColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(warning.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
        .background(warningColor.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(warningColor.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: \(warning.text)")
    }

    private var warningColor: Color {
        switch warning.severity {
        case .info: return .blue
        case .caution: return .orange
        case .alert: return .red
        }
    }
}

struct AIObservationCardRow: View {
    let observation: AIObservation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: observation.icon)
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(observation.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                if observation.confidence != .medium {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(confidenceColor)
                            .frame(width: 6, height: 6)
                        Text(observation.confidence.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Observation: \(observation.text). Confidence: \(observation.confidence.rawValue)")
    }

    private var confidenceColor: Color {
        switch observation.confidence {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }
}

struct AISuggestionCardRow: View {
    let suggestion: AISuggestion
    let memory: AIMemory?
    let onFeedback: ((AIMemory, UserFeedback) -> Void)?

    @State private var showFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: suggestion.icon)
                    .foregroundColor(.green)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    if let effectiveness = suggestion.effectiveness {
                        Text("\(effectiveness)% effective for you")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                Spacer()
            }

            if let memory = memory, let onFeedback = onFeedback {
                if showFeedback {
                    HStack(spacing: 8) {
                        ForEach(UserFeedback.allCases, id: \.self) { feedback in
                            Button {
                                onFeedback(memory, feedback)
                                showFeedback = false
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: feedback.icon)
                                        .font(.caption)
                                    Text(feedback.rawValue)
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(feedbackColor(feedback).opacity(0.1))
                                .foregroundColor(feedbackColor(feedback))
                                .cornerRadius(8)
                            }
                            .accessibilityLabel(feedback.rawValue)
                        }
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
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestion: \(suggestion.text)")
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

struct AIQuestionCardRow: View {
    let question: AIQuestion

    @State private var selectedOption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.orange)
                    .font(.title3)

                Text(question.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach(question.options, id: \.self) { option in
                    SelectableOptionButton(
                        title: option,
                        isSelected: selectedOption == option
                    ) {
                        selectedOption = option
                    }
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Question: \(question.text)")
    }
}

// MARK: - Accessible Selectable Option Button

/// A button that shows selection state with both color AND visual indicators (checkmark, border)
/// for accessibility compliance (not color-only)
struct SelectableOptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
