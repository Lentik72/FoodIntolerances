import SwiftUI
import UIKit

/// Warm "you're not alone" crisis-support takeover, shown when a self-harm / suicide
/// symptom is logged. Tonal opposite of RedFlagInterstitialView: calm, sage `accent`
/// (never `danger`/red), 988 not 911. Presented from the app anchor via the
/// category-routed `.fullScreenCover` (see FoodIntolerancesApp). No mute affordance.
struct CrisisSupportView: View {
    @EnvironmentObject private var presenter: RedFlagPresenter
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("You're not alone")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))  // softer than the medical screen's bold — this one is calm
                    .foregroundStyle(HealthTheme.ink)

                Text("Thank you for noticing this and writing it down — that takes real strength. If you're thinking about harming yourself, talking to someone can help, and hard moments can pass. The **988 Suicide & Crisis Lifeline** has trained counselors, free and confidential, any time.")
                    .font(.body).foregroundStyle(HealthTheme.ink)

                VStack(spacing: 12) {
                    Button { if let url = CrisisContact.call988URL { openURL(url) } } label: {
                        Text("Call 988").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .foregroundStyle(HealthTheme.onAccent)
                    .background(HealthTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius))
                    .accessibilityLabel("Call nine eight eight")

                    Button { if let url = CrisisContact.text988URL { openURL(url) } } label: {
                        Text("Text 988").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .foregroundStyle(HealthTheme.accent)
                    .overlay(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius)
                        .strokeBorder(HealthTheme.accent, lineWidth: 1.5))
                    .accessibilityLabel("Text nine eight eight")
                }

                Button { if let url = EmergencyContact.callURL { openURL(url) } } label: {
                    Text("If you're in immediate danger, call 911")
                        .font(.footnote).foregroundStyle(HealthTheme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(minHeight: 44)
                .accessibilityLabel("If you're in immediate danger, call nine one one")

                Button("I'm okay for now") { presenter.dismiss() }
                    .font(.body).foregroundStyle(HealthTheme.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 4)
            }
            .padding(24)
        }
        .background(HealthTheme.paper.ignoresSafeArea())
        .onAppear {
            UIAccessibility.post(notification: .screenChanged,
                                 argument: "You're not alone. Support is available — call or text 988.")
        }
    }
}

#Preview("Crisis — light") {
    CrisisSupportView()
        .environmentObject(RedFlagPresenter(muteStore: RedFlagMuteStore()))
        .preferredColorScheme(.light)
}

#Preview("Crisis — dark") {
    CrisisSupportView()
        .environmentObject(RedFlagPresenter(muteStore: RedFlagMuteStore()))
        .preferredColorScheme(.dark)
}
