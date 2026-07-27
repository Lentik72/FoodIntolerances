import SwiftUI

// Stub — filled in Task 13. The signature is load-bearing for FirstRunFlowView.
struct FirstRunBackfillView: View {
    let onContinue: () -> Void
    var body: some View { Button("Continue", action: onContinue) }
}
