import SwiftUI

// Stub — filled in Task 13. The signature is load-bearing for FirstRunFlowView.
struct FirstRunConnectView: View {
    let onSkip: () -> Void
    let onConnected: () -> Void
    var body: some View { Button("Continue", action: onConnected) }
}
