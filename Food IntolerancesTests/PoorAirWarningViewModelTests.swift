import Testing
import Foundation
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct PoorAirWarningViewModelTests {
    typealias Cat = AirQualityIndex.AQICategory
    typealias State = EnvironmentalDataService.ForecastAQIState

    func makeVM(enabled: Bool = true,
                symptomLookup: @escaping () async -> String? = { nil }) -> PoorAirWarningViewModel {
        let d = UserDefaults(suiteName: "poorairvm.\(UUID().uuidString)")!
        d.set(enabled, forKey: "hg.poorAirWarningsEnabled")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        return PoorAirWarningViewModel(
            defaults: d, calendar: utc, now: { Date(timeIntervalSince1970: 1_700_000_000) },
            personalizedSymptomSubtype: symptomLookup)
    }

    @Test func toggleOffNeverShows() async {
        let vm = makeVM(enabled: false)
        await vm.evaluate(state: .value(160))
        #expect(vm.warning == .none)
    }
    @Test func pendingHoldsNonDismissible_unavailableClears() async {
        let vm = makeVM()
        await vm.evaluate(state: .value(160))
        #expect(vm.warning != .none && vm.isDismissible)      // settled → dismissible
        await vm.evaluate(state: .pending)
        #expect(vm.warning != .none)                          // HELD — pending doesn't clear
        #expect(vm.isDismissible == false)                    // …but NOT dismissible while pending
        await vm.evaluate(state: .unavailable)
        #expect(vm.warning == .none)                          // settled-unavailable clears
    }
    @Test func dismissSuppressesSameDayUntilEscalation() async {
        let vm = makeVM()
        await vm.evaluate(state: .value(120))                 // unhealthySensitive
        vm.dismissCurrent()
        await vm.evaluate(state: .value(120))
        #expect(vm.warning == .none)                          // suppressed
        await vm.evaluate(state: .value(175))                 // unhealthy — escalation
        #expect(vm.warning != .none)                          // re-shown
    }
    @Test func personalizationFailureDegradesToBase() async {
        // Lookup throws/returns nil → base warning still shows.
        let vm = makeVM(symptomLookup: { nil })
        await vm.evaluate(state: .value(160))
        if case .show(_, _, let symptom) = vm.warning { #expect(symptom == nil) }
        else { Issue.record("expected base warning") }
    }
    @Test func humanizesSymptomWhenPresent() async {
        let vm = makeVM(symptomLookup: { "cough" })           // raw subtype
        await vm.evaluate(state: .value(160))
        if case .show(_, _, let symptom) = vm.warning {
            // Qualified — the app has its own `SymptomCatalog` struct; use the Core enum.
            #expect(symptom == HealthGraphCore.SymptomCatalog.displayName(for: "cough"))
        } else { Issue.record("expected personalized warning") }
    }

    /// Sequences two overlapping personalization lookups with an EXPLICIT entry
    /// handshake — no `Task.yield()` guessing. `next()` signals when call #1 has
    /// entered (and is blocked); `waitUntilFirstEntered()` awaits that deterministically;
    /// `open()` is safe to call before or after the waiter registers (tracks `entered`/
    /// `released`). Only call #1 blocks; #2+ return immediately.
    actor Gate {
        private var releaseCont: CheckedContinuation<Void, Never>?
        private var enteredCont: CheckedContinuation<Void, Never>?
        private var entered = false
        private var released = false
        private var calls = 0
        func next() async -> Int {
            calls += 1; let n = calls
            guard n == 1 else { return n }
            entered = true; enteredCont?.resume(); enteredCont = nil
            if !released { await withCheckedContinuation { releaseCont = $0 } }
            return n
        }
        func waitUntilFirstEntered() async {
            if entered { return }
            await withCheckedContinuation { enteredCont = $0 }
        }
        func open() { released = true; releaseCont?.resume(); releaseCont = nil }
    }

    @Test func lateStaleLookupDoesNotClobberNewerDecision() async {
        // Call #1's lookup blocks; a 2nd evaluate supersedes it (returns nil). Releasing
        // the stale #1 lookup ("cough") must NOT re-personalize the newer decision.
        let gate = Gate()
        let vm = makeVM(symptomLookup: { let n = await gate.next(); return n == 1 ? "cough" : nil })
        async let first: Void = vm.evaluate(state: .value(160))   // gen 1 — blocks in lookup
        await gate.waitUntilFirstEntered()                        // deterministic: #1 is blocked
        await vm.evaluate(state: .value(160))                     // gen 2 — lookup returns nil
        await gate.open()                                         // release gen-1's stale "cough"
        await first
        if case .show(_, _, let symptom) = vm.warning { #expect(symptom == nil) }  // gen-2 won
        else { Issue.record("expected base warning after staleness drop") }
    }

    @Test func dismissDuringPendingIsNoOp() async {
        // Cross-day hazard: a held banner while a fresh fetch is pending must not be
        // dismissible — otherwise it writes TODAY's dismissal for YESTERDAY's forecast.
        let vm = makeVM()
        await vm.evaluate(state: .value(120))                 // settled → dismissible
        await vm.evaluate(state: .pending)                    // now held, non-dismissible
        vm.dismissCurrent()                                   // must be a no-op
        #expect(vm.warning != .none)                          // still held
        await vm.evaluate(state: .value(120))                 // fresh settle of the SAME tier still shows
        #expect(vm.warning != .none)
    }

    @Test func dismissDuringPersonalizationDropsLateLookup() async {
        // Dismiss while personalization is in flight: the late lookup must NOT resurrect
        // the dismissed banner (dismiss bumps generation).
        let gate = Gate()
        let vm = makeVM(symptomLookup: { _ = await gate.next(); return "cough" })
        async let first: Void = vm.evaluate(state: .value(160))   // base shown (dismissible), lookup blocks
        await gate.waitUntilFirstEntered()
        vm.dismissCurrent()                                       // dismiss now — bumps generation
        #expect(vm.warning == .none)
        await gate.open()                                         // release the stale "cough" lookup
        await first
        #expect(vm.warning == .none)                             // NOT resurrected
    }

    @Test func disableClearsSynchronouslyAndInvalidatesInFlight() async {
        // Toggle-off (Home calls disable()) clears the banner synchronously AND a lookup
        // in flight from before must not re-show it (disable bumps generation).
        let gate = Gate()
        let vm = makeVM(symptomLookup: { _ = await gate.next(); return "cough" })
        async let first: Void = vm.evaluate(state: .value(160))   // base shown, lookup blocks
        await gate.waitUntilFirstEntered()
        vm.disable()                                             // synchronous
        #expect(vm.warning == .none && vm.isDismissible == false)
        await gate.open()
        await first
        #expect(vm.warning == .none)                            // stale lookup dropped, not resurrected
    }

    @Test func evaluateRedecidesForNewDayAfterDismissal() async {
        // Dismiss on day 1; on a NEW local day, Home re-decides the (unchanged) settled
        // value via evaluate() — yesterday's dismissal no longer suppresses.
        let d = UserDefaults(suiteName: "poorairvm.\(UUID().uuidString)")!
        d.set(true, forKey: "hg.poorAirWarningsEnabled")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        var currentNow = Date(timeIntervalSince1970: 1_700_000_000)
        let vm = PoorAirWarningViewModel(defaults: d, calendar: utc,
            now: { currentNow }, personalizedSymptomSubtype: { nil })
        await vm.evaluate(state: .value(140))                    // day 1: shown
        vm.dismissCurrent()                                     // dismissed for day 1
        #expect(vm.warning == .none)
        currentNow = currentNow.addingTimeInterval(86_400)       // → next local day
        await vm.evaluate(state: .value(140))                    // Home's post-await evaluate of the unchanged value
        #expect(vm.warning != .none)                             // yesterday's dismissal no longer suppresses
    }

    @Test func guidanceStringsAreExactPerBand() {
        #expect(PoorAirWarningViewModel.guidance(for: .unhealthySensitive) ==
                "Sensitive groups should reduce prolonged or heavy outdoor exertion.")
        #expect(PoorAirWarningViewModel.guidance(for: .unhealthy) ==
                "Sensitive groups should avoid prolonged or heavy outdoor exertion; everyone else should reduce it.")
        #expect(PoorAirWarningViewModel.guidance(for: .veryUnhealthy) ==
                "Sensitive groups should avoid all outdoor physical activity; everyone else should avoid prolonged or intense outdoor activity.")
        #expect(PoorAirWarningViewModel.guidance(for: .hazardous) ==
                "Everyone should avoid all outdoor physical activity; sensitive groups should stay indoors and keep activity low.")
    }
}
