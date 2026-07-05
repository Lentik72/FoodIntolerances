import Foundation

/// Spec §4. Raw values are persisted — never rename a case's raw value
/// without a schema migration.
public enum EventCategory: String, Codable, CaseIterable, Sendable {
    case food, medication, supplement, peptide, symptom, sleep, exercise,
         vitals, lab, mood, stress, stool, bodyMetric, cycle, illness,
         environment, travel, doctorVisit, protocolMarker, note
}

public enum EventSource: String, Codable, CaseIterable, Sendable {
    case manual, photo, voice, healthKit, healthExportFile, labImport,
         weatherAPI, appIntent, legacyImport
}

public enum ObjectKind: String, Codable, CaseIterable, Sendable {
    case medication, supplement, peptide, food, allergen, doctor, labTest,
         condition, activity, experiment, location, device
    case careProtocol = "protocol" // "protocol" is a Swift keyword
}

public enum RelationshipType: String, Codable, CaseIterable, Sendable {
    case possibleTrigger, improves, worsens, noEffect, precedes
}

public enum RelStatus: String, Codable, CaseIterable, Sendable {
    case candidate, active, decayed, confirmedNoEffect, userDismissed
}
