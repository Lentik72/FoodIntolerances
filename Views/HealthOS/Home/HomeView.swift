import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)
                Text("Your day will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
    }
}
