import Foundation

/// Picks the user's most-supported active poor-air→symptom trigger edge, if any.
/// Pure over a relationship list so it is trivially testable; the app supplies the
/// list (typically `relationships(status: .active)`) and humanizes the returned
/// raw subtype via `SymptomCatalog.displayName(for:)`.
public enum PoorAirPersonalization {
    public static func bestSymptomSubtype(from relationships: [Relationship]) -> String? {
        relationships
            .filter { $0.status == .active
                   && $0.fromCategory == "poorAirDay"
                   && $0.toCategory == "symptom"
                   && $0.type == .possibleTrigger }
            .compactMap { rel -> (Relationship, String)? in
                guard let subtype = rel.toSubtype else { return nil }   // need a symptom key
                return (rel, subtype)
            }
            // Deterministic: confidence desc, evidenceCount desc, raw subtype asc.
            .sorted { l, r in
                if l.0.confidence != r.0.confidence { return l.0.confidence > r.0.confidence }
                if l.0.evidenceCount != r.0.evidenceCount { return l.0.evidenceCount > r.0.evidenceCount }
                return l.1 < r.1
            }
            .first?.1
    }
}
