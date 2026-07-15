import SwiftUI
import HealthGraphCore

struct TimelineDayHeader: View {
    let day: TimelineDay

    var body: some View {
        HStack(spacing: 8) {
            Text(dayTitle)
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .foregroundStyle(HealthTheme.ink)
            SeveritySparkline(day: day)
            Spacer()
            Text("\(day.items.count)")
                .font(.caption)
                .foregroundStyle(HealthTheme.inkMuted)
                .accessibilityLabel("\(day.items.count) entries")
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(day.dayStart) { return "Today" }
        if Calendar.current.isDateInYesterday(day.dayStart) { return "Yesterday" }
        return day.dayStart.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
