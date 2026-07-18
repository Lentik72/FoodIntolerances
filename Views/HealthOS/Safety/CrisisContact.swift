import Foundation

/// Crisis-line contact for the mental-health support flow. `crisisNumber` is the single
/// place to regionalize later — 988 is the US Suicide & Crisis Lifeline (call or text).
enum CrisisContact {
    static let crisisNumber = "988"                 // US 988 Suicide & Crisis Lifeline. Regionalize here.
    static var call988URL: URL? { URL(string: "tel:\(crisisNumber)") }
    static var text988URL: URL? { URL(string: "sms:\(crisisNumber)") }
}
