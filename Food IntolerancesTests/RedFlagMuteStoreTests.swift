import Foundation
import Testing
@testable import Food_Intolerances

@MainActor
struct RedFlagMuteStoreTests {
    private func isolatedStore() -> RedFlagMuteStore {
        let suite = "redflag-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return RedFlagMuteStore(defaults: defaults)
    }

    @Test func muteThenUnmute() {
        let store = isolatedStore()
        #expect(store.isMuted("chestPain") == false)
        store.mute("chestPain")
        #expect(store.isMuted("chestPain") == true)
        #expect(store.mutedKeys == ["chestPain"])
        store.unmute("chestPain")
        #expect(store.isMuted("chestPain") == false)
    }

    @Test func persistsAcrossInstances() {
        let suite = "redflag-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        RedFlagMuteStore(defaults: defaults).mute("shortnessOfBreath")
        let reloaded = RedFlagMuteStore(defaults: defaults)
        #expect(reloaded.isMuted("shortnessOfBreath") == true)
    }
}
