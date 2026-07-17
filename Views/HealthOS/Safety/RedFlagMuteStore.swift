import Foundation

/// Which red-flag reminders the user has turned off. App preference state — never
/// health-graph data, never synced, never in a report.
protocol RedFlagMuteStoring: AnyObject {
    var mutedKeys: Set<String> { get }
    func mute(_ key: String)
    func unmute(_ key: String)
    func isMuted(_ key: String) -> Bool
}

@MainActor
final class RedFlagMuteStore: RedFlagMuteStoring, ObservableObject {
    @Published private(set) var mutedKeys: Set<String>
    private let defaults: UserDefaults
    private let storageKey = "redflag.mutedKeys"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mutedKeys = Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    func mute(_ key: String) { mutedKeys.insert(key); persist() }
    func unmute(_ key: String) { mutedKeys.remove(key); persist() }
    func isMuted(_ key: String) -> Bool { mutedKeys.contains(key) }

    private func persist() { defaults.set(Array(mutedKeys), forKey: storageKey) }
}
