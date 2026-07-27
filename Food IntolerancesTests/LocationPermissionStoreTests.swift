import Foundation
import CoreLocation
import Testing
@testable import Food_Intolerances

/// A scripted authorizer: reports whatever status the test sets and fires the
/// store's change callback on demand — the seam that makes permission
/// transitions testable without a system dialog.
@MainActor
private final class FakeAuthorizer: LocationAuthorizing {
    var scriptedStatus: CLAuthorizationStatus
    private(set) var requestCount = 0
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    init(status: CLAuthorizationStatus) { self.scriptedStatus = status }

    var authorizationStatus: CLAuthorizationStatus { scriptedStatus }

    func requestWhenInUseAuthorization() { requestCount += 1 }

    /// Simulates the user answering the dialog (or flipping Settings): the
    /// status changes AND the delegate callback fires, exactly like
    /// `locationManagerDidChangeAuthorization`.
    func resolve(_ status: CLAuthorizationStatus) {
        scriptedStatus = status
        onAuthorizationChange?(status)
    }
}

@MainActor
@Suite struct LocationPermissionStoreTests {
    @Test func initReadsTheAdaptersCurrentStatus() {
        // Not hardcoded .notDetermined: a user who denied last install must be
        // shown the Open Settings path immediately.
        let store = LocationPermissionStore(authorizer: FakeAuthorizer(status: .denied))
        #expect(store.status == .denied)
    }

    @Test func requestPromptsWhenStatusIsNotDetermined() {
        let fake = FakeAuthorizer(status: .notDetermined)
        let store = LocationPermissionStore(authorizer: fake)
        store.request()
        #expect(fake.requestCount == 1)
    }

    @Test func requestIsANoOpWhenAlreadyDenied() {
        // Re-requesting cannot re-prompt — iOS shows the dialog once. Firing it
        // anyway silently does nothing while masking the Open Settings path the
        // user actually needs.
        let fake = FakeAuthorizer(status: .denied)
        let store = LocationPermissionStore(authorizer: fake)
        store.request()
        #expect(fake.requestCount == 0)
    }

    @Test func requestIsANoOpWhenAlreadyAuthorized() {
        let fake = FakeAuthorizer(status: .authorizedWhenInUse)
        let store = LocationPermissionStore(authorizer: fake)
        store.request()
        #expect(fake.requestCount == 0)
    }

    @Test func theChangeCallbackUpdatesTheObservedStore() {
        // The dialog is asynchronous: reading authorizationStatus right after
        // requestWhenInUseAuthorization() still says .notDetermined. The status
        // must arrive via the delegate callback, and it must land on the exact
        // instance the UI observes — a store that reads once at init (or a
        // callback that updates a copy) leaves the screen stale after the user
        // answers.
        let fake = FakeAuthorizer(status: .notDetermined)
        let store = LocationPermissionStore(authorizer: fake)
        store.request()
        #expect(store.status == .notDetermined)   // still racing the dialog
        fake.resolve(.authorizedWhenInUse)
        #expect(store.status == .authorizedWhenInUse)
    }

    @Test func aDenialArrivesThroughTheCallbackAndBlocksFurtherRequests() {
        let fake = FakeAuthorizer(status: .notDetermined)
        let store = LocationPermissionStore(authorizer: fake)
        store.request()
        fake.resolve(.denied)
        #expect(store.status == .denied)
        // The transition must ALSO flip request() into a no-op: the guard reads
        // the live published status, not a snapshot from init.
        store.request()
        #expect(fake.requestCount == 1)
    }
}
