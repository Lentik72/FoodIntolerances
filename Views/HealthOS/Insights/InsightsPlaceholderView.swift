import SwiftUI

struct InsightsPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Insights")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Patterns will appear here once the evidence engine arrives.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
    }
}
