import SwiftUI

struct FirstRunPromiseView: View {
    let onContinue: () -> Void

    /// Testable — pins the two claims the spec supersedes from UI design §5.
    static let headline = "Notice patterns in what may help — or make symptoms worse."
    static let privacy = """
        Your Health Graph is stored on this device. Environment features share your \
        location with the weather provider only when enabled. Cloud AI is optional \
        and off by default.
        """

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(Self.headline)
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
            Text(Self.privacy)
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            Spacer()
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
