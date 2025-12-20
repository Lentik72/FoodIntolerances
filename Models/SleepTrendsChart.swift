import SwiftUI
import Charts

struct SleepTrendsChart: View {
    var sleepData: [SleepSample]  // ✅ References the existing definition in HealthKitManager

    private func totalSleepHours(for sample: SleepSample) -> Double {
        let duration = sample.endDate.timeIntervalSince(sample.startDate)
        return duration / 3600
    }

    var body: some View {
        Chart {
            ForEach(sleepData, id: \.id) { sample in
                BarMark(
                    x: .value("Date", sample.startDate, unit: .day),
                    y: .value("Hours", totalSleepHours(for: sample))
                )
                .foregroundStyle(Color.blue)
                .cornerRadius(5)
            }
        }
    }
}
