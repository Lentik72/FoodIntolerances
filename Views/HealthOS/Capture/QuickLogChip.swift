import SwiftUI

/// Quick-log chip. 1C on-device checkpoint: the neutral capsules read as
/// static tags, not buttons — so chips are accent-tinted (the same visual
/// language as the Log button, quieter) with a pressed-state dim.
struct QuickLogChip: View {
    let label: String
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(HealthTheme.accent.opacity(0.12)))
                .overlay(Capsule().strokeBorder(HealthTheme.accent.opacity(0.35), lineWidth: 1))
                .foregroundStyle(HealthTheme.accent)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(QuickLogChipPressStyle())
        .accessibilityLabel(accessibilityLabel ?? label)
    }
}

private struct QuickLogChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}
