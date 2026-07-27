import SwiftUI

// Stub — filled in Task 12. The signature is load-bearing for FirstRunFlowView.
struct FirstRunPromiseView: View {
    let onContinue: () -> Void
    var body: some View { Button("Continue", action: onContinue) }
}
