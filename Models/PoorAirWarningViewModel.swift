import Foundation
import HealthGraphCore

@MainActor
final class PoorAirWarningViewModel: ObservableObject {
    @Published private(set) var warning: PoorAirWarning = .none
    /// The banner shows a Dismiss button ONLY when this is true — i.e. the warning
    /// reflects a SETTLED forecast. False while `.pending`, so a held cross-day banner
    /// can never write today's dismissal against yesterday's forecast.
    @Published private(set) var isDismissible: Bool = false

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let store: PoorAirDismissalStore
    /// Injectable so tests don't need a live graph. Production wires this to a
    /// relationship-store query (Task 7). Returns the RAW symptom subtype, or nil.
    private let personalizedSymptomSubtype: () async -> String?
    /// Bumped on EVERY state transition — invalidates any in-flight async personalization.
    private var generation = 0

    init(defaults: UserDefaults = .standard,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init,
         personalizedSymptomSubtype: @escaping () async -> String?) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.store = PoorAirDismissalStore(defaults: defaults)
        self.personalizedSymptomSubtype = personalizedSymptomSubtype
    }

    private var enabled: Bool {
        defaults.object(forKey: "hg.poorAirWarningsEnabled") as? Bool ?? true   // default ON
    }

    /// The one re-decision entry point. Home calls it: on the SETTLE path
    /// (`.onChange(of: forecastAQIState)`), on FOREGROUND after awaiting the shared
    /// env-pass handle (with the FINAL settled state — never a mid-pass old value), and
    /// on toggle re-enable (with the live state). It always re-decides against TODAY's
    /// dismissed state, so a day-rollover clears yesterday's dismissal.
    func evaluate(state: EnvironmentalDataService.ForecastAQIState) async {
        generation &+= 1                                   // every transition invalidates in-flight work
        let mine = generation
        guard enabled else { clear(); return }
        switch state {
        case .pending:
            // Hold whatever is shown, but make it NON-dismissible: no stale-dismissal write,
            // and any in-flight lookup is already invalidated by the generation bump above.
            isDismissible = false
        case .unavailable:
            decideBase(aqi: nil)                            // → .none (never a stale value on a failed/absent fetch)
        case .value(let v):
            await decide(aqi: v, mine: mine)
        }
    }

    func dismissCurrent() {
        // Only a SETTLED, shown banner is dismissible — never a pending/held one.
        guard isDismissible, case .show(_, let band, _) = warning else { return }
        generation &+= 1                                   // invalidate any in-flight personalization
        store.recordDismissed(band, now: now(), calendar: calendar)
        clear()
    }

    /// Toggle turned OFF — clear the mounted banner SYNCHRONOUSLY + invalidate any
    /// in-flight lookup. (Re-enable is handled by Home calling `evaluate(live state)`,
    /// so the re-show uses the CURRENT forecast, not a possibly-stale cache.)
    func disable() {
        generation &+= 1
        clear()
    }

    // MARK: - internals

    private func clear() { warning = .none; isDismissible = false }

    /// Base (non-personalized) decision for a SETTLED value; dismissible iff shown.
    private func decideBase(aqi: Int?) {
        let dismissed = store.highestDismissedBandToday(now: now(), calendar: calendar)
        warning = PoorAirWarningDecision.decide(forecastAQI: aqi,
                                                highestDismissedBandToday: dismissed,
                                                personalizedSymptom: nil)
        isDismissible = { if case .show = warning { true } else { false } }()
    }

    /// Settled decision + async personalization, guarded against staleness.
    private func decide(aqi: Int?, mine: Int) async {
        decideBase(aqi: aqi)                               // base first — dismissible if shown
        guard case .show(let a, let band, _) = warning else { return }
        let subtype = await personalizedSymptomSubtype()
        guard mine == generation else { return }          // async-staleness / dismissal / toggle guard
        if let subtype {
            // MUST qualify: the app target has its own top-level `struct SymptomCatalog`
            // (no `displayName`) that shadows the imported one — every app call site qualifies.
            let label = HealthGraphCore.SymptomCatalog.displayName(for: subtype)
            warning = .show(aqi: a, band: band, personalizedSymptom: label)
        }
    }

    /// Tier-specific guidance, matching the AirNow PM2.5 activity table in meaning.
    /// FINALIZED strings — pinned in tests; edit only with a spec change.
    static func guidance(for band: AirQualityIndex.AQICategory) -> String {
        switch band {
        case .unhealthySensitive:
            "Sensitive groups should reduce prolonged or heavy outdoor exertion."
        case .unhealthy:
            "Sensitive groups should avoid prolonged or heavy outdoor exertion; everyone else should reduce it."
        case .veryUnhealthy:
            "Sensitive groups should avoid all outdoor physical activity; everyone else should avoid prolonged or intense outdoor activity."
        case .hazardous:
            "Everyone should avoid all outdoor physical activity; sensitive groups should stay indoors and keep activity low."
        case .good, .moderate:
            ""   // never shown (below threshold); returns empty rather than crashing.
        }
    }
}
