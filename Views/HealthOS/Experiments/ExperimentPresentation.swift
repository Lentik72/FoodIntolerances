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

    /// `shape` matters ONLY for `.pictureOnly`: `.course` and `.repeated` reach a
    /// picture for different reasons, and conflating them misstates one of them.
    /// `.repeated` is the ONLY shape that can ever earn a verdict, so a fresh,
    /// still-accumulating repeated experiment must not be told "a single course
    /// can't be evaluated" — that is true of `.course`, not of "not enough data
    /// yet".
    static func detail(for result: ExperimentResult, shape: ExperimentShape,
                       status: ExperimentStatus) -> String {
        let a = result.adherence
        let dayUnit = a.windowDays == 1 ? "day" : "days"
        let logged = "You logged it on \(a.doseDays) of \(a.windowDays) \(dayUnit)."
        switch result.kind {
        case .helps, .worsens, .noDetectableEffect:
            return logged
        case .pictureOnly:
            // Never "nothing to show" — that reads as a malfunction rather than a
            // limit of the evidence.
            switch shape {
            case .course:
                return logged + " A single course can't be evaluated — there's nothing to compare it against."
            case .repeated:
                // Tense matters. Telling someone to keep logging into an
                // experiment they have already ended is nonsense — there is
                // nothing left to fill in. Seen on device, where a just-ended
                // experiment still read "Keep logging".
                return status == .running
                    ? logged + " Not enough yet to tell. Keep logging and this will fill in."
                    : logged + " Not enough was logged to tell." 
            }
        }
    }

    /// Order matters: the observational caveat first, then the whole-history
    /// caveat, then the noDetectableEffect limitation, then the prescription
    /// framing, then the organ limitation. Required on EVERY medication outcome
    /// including "helps" — that is exactly when someone feels licensed to
    /// self-manage.
    static func caveats(for result: ExperimentResult, interventionKind: ObjectKind) -> [String] {
        var out: [String] = []
        if result.kind == .helps || result.kind == .worsens {
            out.append("This is your own observation, not a trial — it can't rule out that something else changed.")
        }
        // Every verdict (helps/worsens/noDetectableEffect) is computed from the
        // relationship the engine has settled over the person's WHOLE logged
        // history with this intervention, not from the dates of this experiment
        // alone (EvidenceEngine.recompute mines .distantPast...distantFuture).
        // Without this line, "Magnesium appears to help" reads as a finding about
        // the 21 days just declared, when it may rest mostly on history from
        // before the experiment even started.
        if result.kind == .helps || result.kind == .worsens || result.kind == .noDetectableEffect {
            out.append("This looks at everything you've logged for this, not only what happened during this experiment.")
        }
        if result.kind == .noDetectableEffect {
            out.append("This doesn't rule an effect out — it means nothing showed up in what you logged, at this scale.")
        }
        if interventionKind == .medication {
            out.append("This isn't a reason to change a prescription. Talk to your prescriber first.")
            out.append("This app can't see effects on your kidneys, liver or other organs — those don't show up in symptom logs. Ask your doctor if you're taking this regularly.")
        }
        return out
    }
}
