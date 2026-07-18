import Foundation

/// Emergency dialing + nearest-ER lookup. `emergencyNumber` is the single place to
/// regionalize later — never hardcode a number at a call site.
enum EmergencyContact {
    static let emergencyNumber = "911"          // US. Regionalize here.
    static var callURL: URL? { URL(string: "tel:\(emergencyNumber)") }
    static var nearestERURL: URL? { URL(string: "https://maps.apple.com/?q=emergency+room") }
}
