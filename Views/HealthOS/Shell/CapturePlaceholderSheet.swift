import SwiftUI

/// 1B placeholder for the smart capture sheet (arrives in Plan 1C; voice in 1D).
/// Honest empty state: shows the shape of what's coming, captures nothing yet.
struct CapturePlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let upcoming: [(icon: String, label: String)] = [
        ("exclamationmark.circle", "Symptom"),
        ("fork.knife", "Meal"),
        ("pills.fill", "Dose"),
        ("camera", "Photo"),
        ("note.text", "Note"),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(HealthTheme.cardBorder).frame(width: 36, height: 5).padding(.top, 8)
            Text("Capture")
                .font(HealthTheme.sectionHeader())
                .foregroundStyle(HealthTheme.ink)
            Text("Logging arrives with the next update. Everything you see in the timeline is already flowing in from Apple Health.")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 16) {
                ForEach(upcoming, id: \.label) { item in
                    VStack(spacing: 6) {
                        Image(systemName: item.icon).font(.system(size: 22))
                        Text(item.label).font(.caption2)
                    }
                    .foregroundStyle(HealthTheme.inkMuted)
                    .frame(width: 60, height: 64)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coming soon: symptom, meal, dose, photo, and note capture")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HealthTheme.paper)
    }
}
