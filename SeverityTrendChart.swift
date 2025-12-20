import SwiftUI
import Charts

struct SeverityTrendChart: View {
    let data: [LogEntry]

    var body: some View {
        VStack {
            Text("Severity Trend Over Time")
                .font(.headline)
                .padding(.bottom, 5)

            Chart {
                ForEach(data) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Severity", entry.severity)
                    )
                    .interpolationMethod(.monotone) // Smooth curve
                }
            }
            .frame(height: 300)
            .padding()
        }
    }
}
