import SwiftUI

/// Step 6: Memory/privacy preferences
struct OnboardingMemoryStep: View {
    @Binding var memoryLevel: AIMemoryLevel

    var onNext: () -> Void
    var onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 40))
                        .foregroundColor(.indigo)

                    Text("Memory Preferences")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("How detailed should I remember things? You can change this anytime in Settings.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)

                // Memory level options
                VStack(spacing: 12) {
                    ForEach(AIMemoryLevel.allCases, id: \.rawValue) { level in
                        MemoryLevelCard(
                            level: level,
                            isSelected: memoryLevel == level
                        ) {
                            memoryLevel = level
                        }
                    }
                }
                .padding(.horizontal)

                // Privacy note
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        Text("Your Privacy")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        PrivacyPoint(icon: "iphone", text: "All data stays on your device")
                        PrivacyPoint(icon: "trash", text: "Delete any memory at any time")
                        PrivacyPoint(icon: "hand.raised.fill", text: "You control what I remember")
                        PrivacyPoint(icon: "cloud.slash", text: "No cloud sync without your permission")
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer(minLength: 40)

                // Navigation buttons
                HStack(spacing: 12) {
                    Button(action: onBack) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }

                    Button(action: onNext) {
                        Text("Finish Setup")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
}

struct MemoryLevelCard: View {
    let level: AIMemoryLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(level.displayName)
                                .font(.headline)
                                .foregroundColor(.primary)

                            if level == .patterns {
                                Text("Recommended")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue)
                                    .cornerRadius(4)
                            }
                        }

                        Text(level.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                        .font(.title2)
                }

                // Example
                HStack {
                    Image(systemName: "quote.opening")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(level.example)
                        .font(.caption)
                        .italic()
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
    }
}

struct PrivacyPoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    OnboardingMemoryStep(
        memoryLevel: .constant(.patterns),
        onNext: {},
        onBack: {}
    )
}
