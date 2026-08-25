import Foundation
import HealthGraphCore

/// Pure copy for experiment results, so every branch of the claim ladder is
/// unit-testable without rendering a view — the DataSourcesPresentation pattern.
///
/// The wording rules here are the feature, not decoration. "No detectable
/// effect" is not "it doesn't work"; a prescription result never reads as
/// licence to change a prescription; and the app states plainly that it cannot
/// see organ-level harm, because silence lets a clean result read as a clean
/// bill of health.
enum ExperimentPresentation {
    static func headline(for result: ExperimentResult, interventionName: String) -> String {
        switch result.kind {
        case .helps:
            return "\(interventionName) appears to help."
        case .worsens:
            return "\(interventionName) may be making things worse."
        case .noDetectableEffect:
            return "No detectable effect."
        case .pictureOnly:
            return "Here's what happened."
        }
    }

    static func detail(for result: ExperimentResult) -> String {
        let a = result.adherence
        let logged = "You logged it on \(a.doseDays) of \(a.windowDays) days."
        switch result.kind {
        case .helps, .worsens, .noDetectableEffect:
            return logged
        case .pictureOnly:
            // Never "nothing to show" — that reads as a malfunction rather than a
            // limit of the evidence.
            return logged + " A single course can't be evaluated — there's nothing to compare it against."
        }
    }

    /// Order matters: the observational caveat first, then the prescription
    /// framing, then the limitation. Required on EVERY medication outcome
    /// including "helps" — that is exactly when someone feels licensed to
    /// self-manage.
    static func caveats(for result: ExperimentResult, interventionKind: ObjectKind) -> [String] {
        var out: [String] = []
        if result.kind == .helps || result.kind == .worsens {
            out.append("This is your own observation, not a trial — it can't rule out that something else changed.")
        }
        if interventionKind == .medication {
            out.append("This isn't a reason to change a prescription. Talk to your prescriber first.")
            out.append("This app can't see effects on your kidneys, liver or other organs — those don't show up in symptom logs. Ask your doctor if you're taking this regularly.")
        }
        return out
    }
}
