import Foundation
import Testing
@testable import Food_Intolerances

/// Pins the copy the app shows when a surface has nothing to display.
///
/// These strings were making claims that stopped being true: capture, insights
/// and Apple Health connect all exist now. Worse, the Timeline empty state had
/// only two branches for four states — a user with active filters was told
/// their timeline was empty and invited to connect Apple Health, which they had
/// already done. Choosing the string was inline in a view body, so no test
/// could reach any of it.
@Suite struct EmptyStateCopyTests {

    // MARK: - Timeline: four states, not two

    @Test func searchWithNoMatchesSaysSoAndOffersNoConnectAction() {
        let message = TimelineView.emptyStateMessage(isSearching: true, hasActiveFilters: false,
                                                     importOutcome: .notStarted)
        #expect(message == "Nothing matches that search.")
        // Even with nothing imported: the user is searching, not onboarding.
        #expect(TimelineView.showsConnectAction(isSearching: true, hasActiveFilters: false,
                                                importOutcome: .notStarted) == false)
    }

    @Test func activeFiltersMatchingNothingIsNotAnEmptyTimeline() {
        // The pre-existing bug. A user with filters on gets told to connect
        // Apple Health — which they may well have done, and which would not
        // help, because the data is there and the filters are hiding it.
        let message = TimelineView.emptyStateMessage(isSearching: false, hasActiveFilters: true,
                                                     importOutcome: .completed)
        #expect(message == "No events match these filters.")
        #expect(!message.localizedCaseInsensitiveContains("apple health"))
        #expect(TimelineView.showsConnectAction(isSearching: false, hasActiveFilters: true,
                                                importOutcome: .completed) == false)
    }

    @Test func filtersTakePrecedenceEvenBeforeAnythingIsImported() {
        // Ordering between the two non-search branches: filters first. Otherwise
        // a brand-new user who taps a filter gets the connect prompt while their
        // filter silently hides everything.
        #expect(TimelineView.emptyStateMessage(isSearching: false, hasActiveFilters: true,
                                               importOutcome: .notStarted)
                == "No events match these filters.")
        #expect(TimelineView.showsConnectAction(isSearching: false, hasActiveFilters: true,
                                                importOutcome: .notStarted) == false)
    }

    @Test func anUntouchedTimelineOffersTheConnectAction() {
        let message = TimelineView.emptyStateMessage(isSearching: false, hasActiveFilters: false,
                                                     importOutcome: .notStarted)
        #expect(message.contains("Connect Apple Health"))
        #expect(TimelineView.showsConnectAction(isSearching: false, hasActiveFilters: false,
                                                importOutcome: .notStarted) == true)
    }

    @Test func anImportedButEmptyTimelineAsksForACaptureInsteadOfAConnect() {
        // The fourth state: the import ran and brought back nothing, so telling
        // this user to connect again is a dead end. Capture exists — ask for it.
        let message = TimelineView.emptyStateMessage(isSearching: false, hasActiveFilters: false,
                                                     importOutcome: .completedNoData)
        #expect(message == "Nothing logged yet. Tap + to log your first thing.")
        #expect(TimelineView.showsConnectAction(isSearching: false, hasActiveFilters: false,
                                                importOutcome: .completedNoData) == false)
    }

    @Test func everyOutcomeThatIsNotNotStartedHidesTheConnectAction() {
        // The gate is the persisted import status, never hg.hk.backfillCompleted:
        // that flag is set even after a run where every type failed, so it means
        // "we tried once", not "we have data". Conversely an attempt that FAILED
        // is still an attempt — .notStarted is the only state that has not tried.
        let tried: [HealthImportOutcome] = [.inProgress, .interrupted, .attemptFailed,
                                            .completedNoData, .completed, .completedWithIssues]
        for outcome in tried {
            #expect(TimelineView.showsConnectAction(isSearching: false, hasActiveFilters: false,
                                                    importOutcome: outcome) == false,
                    "\(outcome) should not offer connect")
        }
    }

    // MARK: - Insights: no promises about a future engine

    @Test func insightsEmptyStateNeverClaimsTheEngineIsMissing() {
        // The engine shipped. "isn't watching yet" and "when the evidence engine
        // arrives" told users a live feature did not exist.
        for copy in [InsightsPlaceholderView.headline, InsightsPlaceholderView.explanation] {
            #expect(!copy.localizedCaseInsensitiveContains("isn't watching"))
            #expect(!copy.localizedCaseInsensitiveContains("arrives"))
            #expect(!copy.localizedCaseInsensitiveContains("will appear"))
            #expect(!copy.localizedCaseInsensitiveContains("coming"))
        }
    }

    @Test func insightsEmptyStateExplainsWhatWouldMakeAPatternAppear() {
        // Not merely the absence of a false claim: the screen has to say what
        // the user is waiting for, or it is just a blank.
        let explanation = InsightsPlaceholderView.explanation
        #expect(explanation.localizedCaseInsensitiveContains("repeat"))
        #expect(explanation.localizedCaseInsensitiveContains("split"))
    }
}
