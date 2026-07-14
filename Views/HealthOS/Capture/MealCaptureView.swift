import SwiftUI
import HealthGraphCore

struct MealCaptureView: View {
    @Binding var timestamp: Date
    let onLogged: (HealthEvent) -> Void
    var body: some View {
        Text("Meal capture")
            .foregroundStyle(HealthTheme.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}
