import SwiftUI

struct SymptomSummarySection: View {
    let symptoms: [Symptom]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Recent Symptoms")
                .font(.headline)

            if symptoms.isEmpty {
                Text("No symptoms logged yet.")
                    .foregroundColor(.gray)
            } else {
                ForEach(symptoms) { symptom in
                    HStack {
                        Text(symptom.name)
                        Spacer()
                        Text(symptom.dateLogged, style: .date)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
