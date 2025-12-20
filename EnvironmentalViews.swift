import SwiftUI

struct EnvironmentalFactorsView: View {
    let log: LogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !log.atmosphericPressure.isEmpty {
                Text("Atmospheric Pressure: \(log.atmosphericPressure)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if log.suddenChange {
                Text("⚡ Sudden Pressure Change Detected!")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
            
            if !log.moonPhase.isEmpty {
                Text("Moon Phase: \(log.moonPhase)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Mercury: \(log.isMercuryRetrograde ? "In Retrograde ☿" : "Direct ☿")")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
