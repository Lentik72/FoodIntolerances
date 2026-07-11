import SwiftUI

struct TimelineView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Timeline")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Your unified health feed loads here.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
    }
}
