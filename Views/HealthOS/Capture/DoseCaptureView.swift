import SwiftUI
import HealthGraphCore

struct DoseCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    var body: some View {
        Text("Dose capture")
            .foregroundStyle(HealthTheme.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}
