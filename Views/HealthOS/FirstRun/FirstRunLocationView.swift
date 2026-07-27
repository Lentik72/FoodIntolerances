import SwiftUI

// Stub — filled in Task 15. The signature is load-bearing for FirstRunFlowView.
struct FirstRunLocationView: View {
    let seeds: [String]
    let onContinue: () -> Void
    var body: some View { Button("Continue", action: onContinue) }
}
