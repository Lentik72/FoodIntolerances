// TrendsAnalysisPage.swift

import SwiftUI
import SwiftData
import Charts

struct TrendsAnalysisPage: View {
    @Environment(\.modelContext) private var modelContext

    // Use Foundation.SortDescriptor explicitly to avoid ambiguity
    @Query(sort: [SortDescriptor(\LogEntry.date, order: .forward)])
    private var logEntries: [LogEntry]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Trends & Analysis")
                        .font(.largeTitle)
                        .bold()
                        .padding(.top)

                    // 1) Severity Over Time
                    severityOverTimeSection

                    // 2) Logs by Day (Bar Chart)
                    logsByDaySection

                    // Expand with more breakdowns: top symptom chart, protocol efficacy, etc.
                }
                .padding()
            }
            .navigationTitle("Trends Analysis")
        }
    }

    // MARK: - Severity Over Time
    private var severityOverTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Severity Over Time")
                .font(.title2)
                .bold()

            if logEntries.isEmpty {
                Text("No logs yet to show severity timeline.")
                    .foregroundColor(.gray)
            } else {
                // Build data for a line chart: (date, severity)
                Chart(logEntries) { log in
                    LineMark(
                        x: .value("Date", log.date),
                        y: .value("Severity", log.severity)
                    )
                    .foregroundStyle(colorForSeverity(log.severity))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) // e.g., every 3 days
                }
                .frame(height: 200)
                .padding(.top, 5)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Logs By Day
    private var logsByDaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logs by Day of Month")
                .font(.title2)
                .bold()

            if logEntries.isEmpty {
                Text("No logs to group by day.")
                    .foregroundColor(.gray)
            } else {
                let grouped = Dictionary(grouping: logEntries) { log -> Int in
                    let day = Calendar.current.component(.day, from: log.date)
                    return day
                }
                let barData = grouped.map { (day, logs) in
                    (day: day, count: logs.count)
                }
                .sorted { $0.day < $1.day }

                Chart {
                    ForEach(barData, id: \.day) { item in
                        BarMark(
                            x: .value("Day", item.day),
                            y: .value("Logs", item.count)
                        )
                        .foregroundStyle(.purple)
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Severity Color Helper
    private func colorForSeverity(_ s: Int) -> Color {
        switch s {
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
}

// MARK: - Preview
struct TrendsAnalysisPage_Previews: PreviewProvider {
    static var previews: some View {
        TrendsAnalysisPage()
            .modelContainer(for: [LogEntry.self, TrackedItem.self, AvoidedItem.self, OngoingSymptom.self, SymptomCheckIn.self], inMemory: true)
    }
}
