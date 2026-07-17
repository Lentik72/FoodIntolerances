import SwiftUI

/// The last-~8 exposures in chronological order: filled (amber) = outcome followed,
/// hollow (dotMiss) = not. ≤ recentDotCount, so it never overflows the row.
struct EvidenceDotsView: View {
    let outcomes: [Bool]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(outcomes.enumerated()), id: \.offset) { _, followed in
                Circle().fill(followed ? HealthTheme.amber : HealthTheme.dotMiss).frame(width: 9, height: 9)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(outcomes.filter { $0 }.count) of \(outcomes.count) followed")
    }
}

#Preview("Dots — light") {
    VStack(alignment: .leading, spacing: 12) {
        EvidenceDotsView(outcomes: [true, true, false, true, true, true, false, true])
        EvidenceDotsView(outcomes: [false, false, false])
        EvidenceDotsView(outcomes: [true])
    }
    .padding()
    .background(HealthTheme.paper)
}

#Preview("Dots — dark") {
    VStack(alignment: .leading, spacing: 12) {
        EvidenceDotsView(outcomes: [true, true, false, true, true, true, false, true])
        EvidenceDotsView(outcomes: [false, false, false])
        EvidenceDotsView(outcomes: [true])
    }
    .padding()
    .background(HealthTheme.paper)
    .preferredColorScheme(.dark)
}
