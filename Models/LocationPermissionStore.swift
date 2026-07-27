import Foundation
import CoreLocation

/// The seam between `LocationPermissionStore` and `CLLocationManager`, so
/// permission transitions are testable without a system dialog. Production
/// conforms a `CLLocationManager`-backed adapter; tests conform a fake that
/// reports a scripted status and fires the change callback on demand.
@MainActor
protocol LocationAuthorizing: AnyObject {
    /// The authorizer's CURRENT status — must reflect the live manager on every
    /// read, never a value cached at init.
    var authorizationStatus: CLAuthorizationStatus { get }
    /// Fired whenever authorization changes (the user answered the dialog, or
    /// flipped the toggle in Settings). Set exactly once, by the store.
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)? { get set }
    func requestWhenInUseAuthorization()
}

/// Production adapter. Owns the `CLLocationManager` and forwards its delegate
/// authorization callback; it never reads location itself.
@MainActor
final class LocationManagerAuthorizationAdapter: NSObject, LocationAuthorizing, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Computed, not stored: a status cached at init goes stale the moment the
    /// user answers the dialog or returns from Settings.
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read the status HERE, from the manager that just changed — then hop.
        let latest = manager.authorizationStatus
        Task { @MainActor in self.onAuthorizationChange?(latest) }
    }
}

/// The ONLY thing that asks for location authorization, and the only observable
/// source of its current value. Status arrives via the delegate callback, not
/// by re-reading the manager after `request()` — that read races the async
/// dialog and almost always still says `.notDetermined`.
@MainActor
final class LocationPermissionStore: ObservableObject {
    @Published private(set) var status: CLAuthorizationStatus
    private let authorizer: any LocationAuthorizing

    /// Production entry point — wires the real `CLLocationManager` adapter.
    /// (Not a default argument: that expression would be evaluated in a
    /// nonisolated context, which Swift rejects for a @MainActor init.)
    convenience init() {
        self.init(authorizer: LocationManagerAuthorizationAdapter())
    }

    init(authorizer: any LocationAuthorizing) {
        self.authorizer = authorizer
        self.status = authorizer.authorizationStatus
        // Weak: the store retains the authorizer, and the authorizer retains
        // this closure — a strong self here would cycle.
        authorizer.onAuthorizationChange = { [weak self] latest in
            self?.status = latest
        }
    }

    /// No-op unless the dialog can actually appear. Re-requesting from
    /// `.denied` cannot re-prompt — it would silently do nothing while masking
    /// the Open Settings path the user actually needs.
    func request() {
        guard status == .notDetermined else { return }
        authorizer.requestWhenInUseAuthorization()
    }
}
