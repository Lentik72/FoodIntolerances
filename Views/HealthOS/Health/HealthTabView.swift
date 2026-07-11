import SwiftUI

struct HealthTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Health")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Cabinet, protocols, labs, and reports will live here.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
    }
}
