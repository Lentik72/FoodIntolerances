import SwiftUI
import HealthGraphCore

struct InsightCardView: View {
    let card: InsightCardModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                InsightBadgeView(tier: card.badge)
                if card.isNew { Text("NEW").font(.caption2.weight(.bold)).foregroundStyle(HealthTheme.amber) }
                Spacer()
            }
            NavigationLink(value: card.id) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: CategoryStyle.style(for: card.exposureCategory).icon)
                            .foregroundStyle(HealthTheme.inkSecondary)
                        Text(card.claim)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(HealthTheme.ink)
                    }
                    if let countLine = card.countLine {
                        Text(countLine).font(.subheadline).foregroundStyle(HealthTheme.ink)
                    }
                    if !card.recentDots.isEmpty { EvidenceDotsView(outcomes: card.recentDots) }
                    if let sub = card.subline {
                        Text(sub).font(.footnote).foregroundStyle(HealthTheme.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack {
                NavigationLink(value: card.id) {
                    Text("All evidence →").font(.subheadline.weight(.medium)).foregroundStyle(HealthTheme.accent)
                }
                Spacer()
                Button("Dismiss", action: onDismiss).font(.subheadline).foregroundStyle(HealthTheme.inkMuted)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).hgCard()
    }
}

#Preview {
    NavigationStack {
        InsightCardView(card: InsightCardModel(
            id: UUID(), claim: "Dairy → bloating", exposureCategory: .food, badge: .moderate,
            countLine: "In 6 of your last 8 Dairy logs, bloating followed",
            recentDots: [true, true, false, true, true, true, false, true],
            subline: "usually within ~12h · avg severity +2.1", isNew: true, kind: .possibleTrigger),
            onDismiss: {}).padding()
    }
}
