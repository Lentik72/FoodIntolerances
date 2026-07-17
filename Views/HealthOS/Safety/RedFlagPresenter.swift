import Foundation
import HealthGraphCore

/// Holds the pending red-flag takeover and bridges a just-saved symptom to the
/// interstitial. Owns nothing but the presentation decision; the pure evaluator
/// decides, the mute store persists.
@MainActor
final class RedFlagPresenter: ObservableObject {
    @Published var pending: RedFlagMatch?
    let muteStore: RedFlagMuteStore

    init(muteStore: RedFlagMuteStore) { self.muteStore = muteStore }

    /// Evaluate a just-saved event. Sets `pending` only on a fresh, unmuted red-flag symptom.
    /// If a takeover is already showing, does nothing — the FIRST co-occurring red-flag wins
    /// (spec §7.1); an already-visible screen is never overwritten.
    func consider(_ event: HealthEvent) {
        guard pending == nil else { return }
        guard event.category == .symptom, let key = event.subtype else { return }
        if let match = RedFlagEvaluator.evaluate(symptomKey: key, mutedKeys: muteStore.mutedKeys) {
            pending = match
        }
    }

    func dismiss() { pending = nil }

    func mute(_ key: String) { muteStore.mute(key); pending = nil }
}
