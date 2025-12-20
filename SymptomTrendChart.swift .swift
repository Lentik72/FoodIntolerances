import SwiftUI
import Charts

struct SymptomTrendChart: View {
    let symptoms: [Symptom]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Symptom Trends")
                .font(.headline)

            if symptoms.isEmpty {
                Text("No data to display.")
                    .foregroundColor(.gray)
            } else {
                Chart {
                    ForEach(symptoms) { symptom in
                        BarMark(
                            x: .value("Date", symptom.dateLogged),
                            y: .value("Severity", symptom.severity)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .frame(height: 200)
            }
        }
    }
}
