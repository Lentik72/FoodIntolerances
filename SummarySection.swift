//
//  SummarySection.swift
//  Food IntolerancesI am choosing options
//
//  Created by Leo on 1/24/25.
//

import SwiftUI

struct SummarySection: View {
    let allLogs: [LogEntry]

    var totalLogs: Int {
        allLogs.count
    }

    var mostCommonSymptom: String {
        let symptoms = allLogs.flatMap { $0.symptoms }
        let counts = Dictionary(symptoms.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max(by: { $0.value < $1.value })?.key ?? "N/A"
    }

    var averageSeverity: Double {
        guard !allLogs.isEmpty else { return 0 }
        let totalSeverity = allLogs.reduce(0) { $0 + $1.severity }
        return Double(totalSeverity) / Double(allLogs.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.title2)
                .bold()

            HStack {
                VStack(alignment: .leading) {
                    Text("Total Logs:")
                        .font(.headline)
                    Text("\(totalLogs)")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Most Common Symptom:")
                        .font(.headline)
                    Text(mostCommonSymptom)
                        .font(.title3)
                        .foregroundColor(.green)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Average Severity:")
                        .font(.headline)
                    Text(String(format: "%.1f", averageSeverity))
                        .font(.title3)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
        }
    }
}
