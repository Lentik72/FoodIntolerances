import SwiftUI
import HealthGraphCore

struct InsightCardView: View {
    let card: InsightCardModel
    let onDismiss: (() -> Void)?

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
                    if card.tier == .contested {
                        Text("unproven mechanism · your pattern")
                            .font(.caption)
                            .foregroundStyle(HealthTheme.inkMuted)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cardAccessibilityLabel)
            .accessibilityHint("Opens details")
            HStack {
                NavigationLink(value: card.id) {
                    Text("All evidence →").font(.subheadline.weight(.medium)).foregroundStyle(HealthTheme.accent)
                }
                Spacer()
                if let onDismiss {
                    Button("Dismiss", action: onDismiss)
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.inkMuted)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).hgCard()
    }

    /// Combined VoiceOver stop for the card's NavigationLink label (icon + claim +
    /// countLine + dots + subline) — mirrors TimelineEventRow/SleepSessionRow's
    /// single-element-per-row convention instead of exposing each subview separately.
    private var cardAccessibilityLabel: String {
        var parts = [card.claim]
        if card.tier == .contested { parts.append("unproven mechanism, your pattern") }
        if let countLine = card.countLine { parts.append(countLine) }
        if !card.recentDots.isEmpty {
            let followed = card.recentDots.filter { $0 }.count
            parts.append("\(followed) of \(card.recentDots.count) followed")
        }
        if let sub = card.subline { parts.append(sub) }
        return parts.joined(separator: ", ")
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
