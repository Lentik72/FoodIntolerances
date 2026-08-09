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
    /// The guard keys off the VALIDATED list, not the raw one: a selection that
    /// is entirely red-flag or stale keys validates down to nothing, and a
    /// raw-emptiness check would render "You picked ." on that path.
    static func explanation(for seeds: [String]) -> String {
        let picked = SymptomSeeds.validate(seeds, limit: 8).prefix(2)
            .map { HealthGraphCore.SymptomCatalog.displayName(for: $0) }
        guard !picked.isEmpty else {
            return "If you share location, we'll watch pressure drops, temperature swings and air quality against your symptoms."
        }
        return "You picked \(picked.joined(separator: " and ")). If you share location, we'll also watch pressure drops, temperature swings and air quality against them."
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
                Text("Location is turned off for this app.")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
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
