import SwiftUI
import HealthGraphCore   // BadgeTier

struct InsightBadgeView: View {
    let tier: BadgeTier
    var body: some View {
        Text(label).font(.caption2.weight(.semibold)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(label) pattern")
    }
    private var label: String {
        switch tier { case .earlySignal: "EARLY SIGNAL"; case .moderate: "MODERATE"; case .strong: "STRONG" }
    }
    private var color: Color {
        switch tier { case .earlySignal: HealthTheme.inkSecondary; case .moderate: HealthTheme.accent; case .strong: HealthTheme.accent }
    }
}

#Preview("Badge — light") {
    HStack(spacing: 8) {
        InsightBadgeView(tier: .earlySignal)
        InsightBadgeView(tier: .moderate)
        InsightBadgeView(tier: .strong)
    }
    .padding()
    .background(HealthTheme.paper)
}

#Preview("Badge — dark") {
    HStack(spacing: 8) {
        InsightBadgeView(tier: .earlySignal)
        InsightBadgeView(tier: .moderate)
        InsightBadgeView(tier: .strong)
    }
    .padding()
    .background(HealthTheme.paper)
    .preferredColorScheme(.dark)
}
