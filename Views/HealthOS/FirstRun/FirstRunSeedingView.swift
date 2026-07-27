import SwiftUI

// Stub — filled in Task 14. The signature is load-bearing for FirstRunFlowView.
struct FirstRunSeedingView: View {
    @Binding var selection: [String]          // NOT `let` — the flow passes $selectedSeeds
    let onContinue: () -> Void
    var body: some View { Button("Continue", action: onContinue) }
}
