import SwiftUI

/// The persistent, plain non-diagnostic disclosure. One shared component —
/// not restated ad hoc per screen — placed on every surface that shows a
/// pattern in a person's own health data: Trends, Insights, and Experiments.
/// Before this task the only such text was buried in `ProtocolPreviewView`
/// and one Dashboard line; App Store review and the clinic deployment both
/// need it stated plainly, every place a pattern is shown, not just those two.
///
/// `copy` is `static` so `TrajectoryPresentationTests
/// .theNonDiagnosticLineIsPlainAndPresent` can assert on the exact string —
/// and so this text itself must clear the same banned-word sweep every
/// Trends summary does (it does: no causal or directional language below).
struct NonDiagnosticFooter: View {
    static let copy = "This is information from your own records, not a diagnosis. "
        + "Discuss what you see here with your clinician."

    var body: some View {
        Text(Self.copy)
            .font(.footnote)
            .foregroundStyle(HealthTheme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

#Preview {
    NonDiagnosticFooter()
        .padding()
        .background(HealthTheme.paper)
}
