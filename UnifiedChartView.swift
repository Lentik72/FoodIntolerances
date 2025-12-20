import SwiftUI
import Charts

enum ChartType {
    case severityTrend
    case symptomOccurrence
}

struct UnifiedChartView: View {
    let logs: [LogEntry]
    let chartType: ChartType
    let title: String
    
    @State private var selectedData: Any? = nil
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            
            switch chartType {
            case .severityTrend:
                severityTrendChart()
            case .symptomOccurrence:
                symptomOccurrencesChart()
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(radius: 4)
        .padding(.horizontal)
    }
    
    private func severityTrendChart() -> some View {
        Chart {
            ForEach(logs) { dataPoint in
                LineMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Severity", dataPoint.severity)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(gradientForSeverity(dataPoint.severity))
                
                PointMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Severity", dataPoint.severity)
                )
                .symbolSize(dataPoint.severity >= 4 ? 100 : 50)
                .foregroundStyle(colorForSeverity(dataPoint.severity))
            }
        }
        .frame(height: 300)
        .padding()
    }
    
    private func symptomOccurrencesChart() -> some View {
        let symptomCounts = getSymptomCounts()
        
        return Chart {
            ForEach(symptomCounts, id: \.symptom) { data in
                BarMark(
                    x: .value("Count", data.count),
                    y: .value("Symptom", data.symptom)
                )
                .foregroundStyle(.blue.gradient)
                .annotation(position: .trailing) {
                    Text("\(data.count)")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .bold()
                }
            }
        }
        .frame(height: 250)
        .chartXAxis {
            AxisMarks(preset: .aligned) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.gray)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel()
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
        .padding()
    }
    
    private func getSymptomCounts() -> [(symptom: String, count: Int)] {
        let allSymptoms = logs.flatMap { $0.symptoms }
        let symptomDict = Dictionary(grouping: allSymptoms, by: { $0 })
        return symptomDict
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { ($0.0, $0.1) }
    }
    
    private func colorForSeverity(_ severity: Int) -> Color {
        switch severity {
        case 1: return .green
        case 2: return .yellow
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
    
    private func gradientForSeverity(_ severity: Int) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [colorForSeverity(severity), .clear]),
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
