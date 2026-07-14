import SwiftUI
import HealthGraphCore

struct NoteCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    var body: some View {
        Text("Note capture")
            .foregroundStyle(HealthTheme.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}
