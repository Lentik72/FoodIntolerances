import SwiftUI

struct FirstRunSeedingView: View {
    @Binding var selection: [String]          // NOT `let` — the flow passes $selectedSeeds
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What brings you here?")
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
            Text("Pick up to eight. They become your one-tap log buttons — nothing is recorded yet.")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            ScrollView { SeedSymptomGrid(selection: $selection) }
            // Shown only once something is picked, so the first impression stays
            // clean — and at the cap it reads "8 of 8", which is the only thing
            // on screen explaining why further taps do nothing.
            if !selection.isEmpty {
                Text("\(selection.count) of \(SeedSelection.limit) picked")
                    .font(.footnote)
                    .foregroundStyle(selection.count == SeedSelection.limit
                                     ? HealthTheme.ink : HealthTheme.inkMuted)
            }
            Button(selection.isEmpty ? "Skip" : "Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
    }
}
