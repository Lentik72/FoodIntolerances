import SwiftUI

/// Step 7: Completion summary
struct OnboardingCompleteStep: View {
    let allergiesCount: Int
    let symptomsCount: Int
    let supplementsCount: Int

    var onFinish: () -> Void

    @State private var showConfetti = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                // Success animation
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 120, height: 120)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                            .scaleEffect(showConfetti ? 1.0 : 0.5)
                            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showConfetti)
                    }

                    Text("You're All Set!")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("I'll start learning your patterns as you log your symptoms and how you feel.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Summary cards
                VStack(spacing: 12) {
                    Text("Here's what I know so far:")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        SummaryCard(
                            icon: "allergens",
                            count: allergiesCount,
                            label: "Allergies",
                            color: .orange
                        )

                        SummaryCard(
                            icon: "waveform.path.ecg",
                            count: symptomsCount,
                            label: "Symptoms",
                            color: .purple
                        )

                        SummaryCard(
                            icon: "pills.fill",
                            count: supplementsCount,
                            label: "Items",
                            color: .green
                        )
                    }
                }
                .padding(.horizontal)

                // Tips
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quick Tips")
                        .font(.headline)

                    TipRow(
                        icon: "plus.circle.fill",
                        iconColor: .blue,
                        title: "Log your first symptom",
                        description: "I'll give you personalized insights right away"
                    )

                    TipRow(
                        icon: "fork.knife",
                        iconColor: .orange,
                        title: "Track what you eat",
                        description: "I'll learn your food triggers over time"
                    )

                    TipRow(
                        icon: "questionmark.circle.fill",
                        iconColor: .green,
                        title: "Ask me anything",
                        description: "\"Can I eat pineapple?\" - I'll check your allergies"
                    )
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer(minLength: 40)

                // Go to Home button
                Button(action: onFinish) {
                    HStack {
                        Text("Go to Home")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showConfetti = true
            }
        }
    }
}

struct SummaryCard: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text("\(count)")
                .font(.title)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct TipRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingCompleteStep(
        allergiesCount: 2,
        symptomsCount: 3,
        supplementsCount: 4,
        onFinish: {}
    )
}
