import SwiftUI
import UIKit
import CoreLocation
import HealthGraphCore

struct FirstRunLocationView: View {
    /// Passed in from the flow's in-memory selection. Reading
    /// `firstRunState.seeds` here would ALWAYS be empty: that key is written by
    /// `markCompleted(seeds:)`, which runs after this screen.
    let seeds: [String]
    let onContinue: () -> Void

    /// The one observable owner (Task 11 Step 3). A view-local CLLocationManager
    /// would have no delegate, so the screen could never learn the user's answer.
    @EnvironmentObject private var permission: LocationPermissionStore
    private var status: CLAuthorizationStatus { permission.status }

    /// "watch", never "find": every weather exposure is `.contested` in
    /// PlausibilityCatalog, so promising discovery would oversell it.
    /// Testable — pins the "you picked X and Y" phrasing spec §3.5 requires.
    ///
    /// The picks are CONTEXT, not a claim. An earlier wording ended "…against
    /// them", which asserted that the user's specific symptoms track pressure
    /// and air quality — a link the Insights surface would then refuse to state,
    /// since the catalog marks every weather exposure `.contested`. Naming
    /// better-suited symptoms instead would mean inventing a clinical mapping
    /// the codebase does not have, so the sentence stops asserting instead.
    ///
    /// The guard keys off the VALIDATED list, not the raw one: a selection that
    /// is entirely red-flag or stale keys validates down to nothing, and a
    /// raw-emptiness check would render "You picked ." on that path.
    static func explanation(for seeds: [String]) -> String {
        let watching = "we'll watch pressure, temperature and air quality alongside"
        let tail = "— if a pattern is there, it can surface."
        guard let picked = namedPicks(SymptomSeeds.validate(seeds, limit: 8)) else {
            return "Share location and \(watching) your symptoms \(tail)"
        }
        return "You picked \(picked). Share location and \(watching) everything you log \(tail)"
    }

    /// Two names plus a count. Naming two of eight and saying nothing about the
    /// rest reads as arbitrary; listing all eight buries the sentence.
    private static func namedPicks(_ validated: [String]) -> String? {
        let names = validated.map { HealthGraphCore.SymptomCatalog.displayName(for: $0) }
        switch names.count {
        case 0:  return nil
        case 1:  return names[0]
        case 2:  return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }

    /// What to say about the current permission, or nil when the button below
    /// already says it. The authorized case used to render nothing at all,
    /// leaving a user who had already granted location with a headline, one
    /// paragraph and an empty screen.
    static func statusNote(for status: CLAuthorizationStatus) -> String? {
        switch status {
        case .denied, .restricted:
            return "Location is turned off for this app."
        case .authorizedWhenInUse, .authorizedAlways:
            return "Location is on — conditions where you are get recorded alongside your logs."
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your environment")
                .font(HealthTheme.screenTitle())
                .foregroundStyle(HealthTheme.ink)
            Text(Self.explanation(for: seeds))
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            Spacer()
            if let note = Self.statusNote(for: status) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
            }
            switch status {
            case .notDetermined:
                Button("Share location") {
                    // The ONLY request site in the app, now that Task 11 Step 2
                    // removed it from LocationService.init(). The answer arrives
                    // via the store's delegate callback — do NOT re-read the
                    // status here, that races the dialog.
                    permission.request()
                }
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.accent)
                .foregroundStyle(HealthTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
            case .denied, .restricted:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            default:
                EmptyView()
            }
            // Never gated on a first coordinate arriving.
            Button(status == .notDetermined ? "Not now" : "Continue", action: onContinue)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
    }
}
