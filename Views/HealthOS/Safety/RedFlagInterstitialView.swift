import SwiftUI
import UIKit
import HealthGraphCore

/// Full-screen "seek care now" takeover. Non-diagnostic. Presented from the root
/// via .fullScreenCover so it sits above every tab and sheet (see HealthOSRootView).
struct RedFlagInterstitialView: View {
    let match: RedFlagMatch
    @EnvironmentObject private var presenter: RedFlagPresenter
    @Environment(\.openURL) private var openURL
    @State private var confirmingMute = false

    // Qualified: the app target has a legacy `SymptomCatalog` that would otherwise shadow this.
    private var symptomName: String { HealthGraphCore.SymptomCatalog.displayName(for: match.symptomKey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("This could be serious")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(HealthTheme.ink)

                Text("You just logged **\(symptomName)**. Symptoms like this can be a medical emergency. If it's severe, came on suddenly, or is getting worse, call 911 or get emergency care now.")
                    .font(.body).foregroundStyle(HealthTheme.ink)

                if let guidance = match.extraGuidance {
                    Text(guidance)
                        .font(.headline).foregroundStyle(HealthTheme.danger)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HealthTheme.danger.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius))
                }

                Text("This isn't medical advice or a diagnosis — when in doubt, get checked.")
                    .font(.footnote).foregroundStyle(HealthTheme.inkSecondary)

                VStack(spacing: 12) {
                    Button { if let url = EmergencyContact.callURL { openURL(url) } } label: {
                        Text("Call 911").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .foregroundStyle(HealthTheme.onDanger)
                    .background(HealthTheme.danger)
                    .clipShape(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius))
                    .accessibilityLabel("Call nine one one")

                    Button { if let url = EmergencyContact.nearestERURL { openURL(url) } } label: {
                        Text("Find nearest ER").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .foregroundStyle(HealthTheme.accent)
                    .overlay(RoundedRectangle(cornerRadius: HealthTheme.cardCornerRadius)
                        .strokeBorder(HealthTheme.accent, lineWidth: 1.5))

                    Button("I'm okay — dismiss") { presenter.dismiss() }
                        .font(.body).foregroundStyle(HealthTheme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }

                Button("Stop reminding me about \(symptomName)") { confirmingMute = true }
                    .font(.footnote).foregroundStyle(HealthTheme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .background(HealthTheme.paper.ignoresSafeArea())
        .onAppear {
            // Spec §5.4: announce the takeover to VoiceOver (the modal transition may not
            // auto-announce reliably given the sheet→cover handoff).
            UIAccessibility.post(notification: .screenChanged,
                                 argument: "This could be serious. You logged \(symptomName). Consider calling 911.")
        }
        .alert("Turn off the seek-care reminder for \(symptomName)?", isPresented: $confirmingMute) {
            Button("Turn it off", role: .destructive) { presenter.mute(match.symptomKey) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll still be able to log it — you just won't see this screen. You can turn it back on anytime in Health → Safety reminders.")
        }
    }
}

#Preview("Cardiac — light") {
    RedFlagInterstitialView(match: RedFlagMatch(symptomKey: HealthGraphCore.SymptomCatalog.canonicalKey(for: "Chest Pain"),
                                                category: .medicalEmergency, extraGuidance: nil))
        .environmentObject(RedFlagPresenter(muteStore: RedFlagMuteStore()))
        .preferredColorScheme(.light)
}

#Preview("Anaphylaxis — dark") {
    RedFlagInterstitialView(match: RedFlagMatch(symptomKey: HealthGraphCore.SymptomCatalog.canonicalKey(for: "Severe Allergic Reaction"),
                                                category: .medicalEmergency,
                                                extraGuidance: "If you have an epinephrine auto-injector (EpiPen), use it now, then call 911."))
        .environmentObject(RedFlagPresenter(muteStore: RedFlagMuteStore()))
        .preferredColorScheme(.dark)
}
