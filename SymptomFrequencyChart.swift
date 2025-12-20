import SwiftUI
import Charts

struct SymptomFrequencyChart: View {
    let data: [LogEntry]

    var symptomCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for entry in data {
            for symptom in entry.symptoms {
                counts[symptom, default: 0] += 1
            }
        }
        return counts
    }

    var body: some View {
        VStack {
            Text("Most Frequent Symptoms")
                .font(.headline)
                .padding(.bottom, 5)

            Chart {
                ForEach(symptomCounts.sorted(by: { $0.value > $1.value }), id: \.key) { symptom, count in
                    BarMark(
                        x: .value("Symptom", symptom),
                        y: .value("Count", count)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .frame(height: 300)
            .padding()
        }
    }
}
