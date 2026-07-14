import SwiftUI
import HealthGraphCore

struct SymptomCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    var body: some View {
        Text("Symptom capture")
            .foregroundStyle(HealthTheme.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}
