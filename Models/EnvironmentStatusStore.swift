import Foundation
import Combine

/// The single source of truth for environment-fetch health. Created once in
/// `FoodIntolerancesApp`, injected into `EnvironmentalDataService` and the
/// emitter, and read by the Timeline + Health surfaces. `@MainActor`: every
/// reader is UI and every write point is already on the main actor.
@MainActor
final class EnvironmentStatusStore: ObservableObject {
    @Published private(set) var statuses: [EnvironmentCapability: EnvironmentCapabilityStatus] = [:]

    private let defaults: UserDefaults
    private static let storageKey = "hg.env.status"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: EnvironmentCapabilityStatus].self, from: data) {
            var restored: [EnvironmentCapability: EnvironmentCapabilityStatus] = [:]
            for (raw, value) in decoded {
                if let cap = EnvironmentCapability(rawValue: raw) { restored[cap] = value }
            }
            statuses = restored
        }
    }

    func recordSuccess(_ capability: EnvironmentCapability, at: Date) {
        var s = statuses[capability] ?? EnvironmentCapabilityStatus()
        s.lastSuccess = at
        s.liveFailure = nil          // heal the Timeline; lastFailure is retained
        statuses[capability] = s
        persist()
    }

    func recordFailure(_ capability: EnvironmentCapability, reason: EnvironmentFailureReason,
                       scopeStart: Date, scopeEnd: Date, timezoneID: String, at: Date) {
        let failure = EnvironmentFailure(at: at, reason: reason,
                                         scopeStart: scopeStart, scopeEnd: scopeEnd, timezoneID: timezoneID)
        var s = statuses[capability] ?? EnvironmentCapabilityStatus()
        s.liveFailure = failure
        s.lastFailure = failure
        statuses[capability] = s
        persist()
    }

    private func persist() {
        var encodable: [String: EnvironmentCapabilityStatus] = [:]
        for (cap, value) in statuses { encodable[cap.rawValue] = value }
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
