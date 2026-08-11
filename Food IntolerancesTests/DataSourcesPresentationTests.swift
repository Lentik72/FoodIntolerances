import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@Suite struct DataSourcesPresentationTests {
    private func status(_ outcome: HealthImportOutcome, events: Int = 0,
                        failures: [String] = []) -> HealthImportStatus {
        HealthImportStatus(outcome: outcome, lastAttemptAt: Date(), lastCompletedAt: Date(),
                           eventsImported: events, categoriesImported: 3,
                           failureIdentifiers: failures)
    }

    @Test func zeroEventsAndNoFailuresSaysNothingCameThrough() {
        let msg = DataSourcesPresentation.backfillMessage(for: status(.completedNoData))
        #expect(msg == "Nothing came through yet.")
    }

    @Test func eventsPlusFailuresSaysPartiallyImported() {
        let msg = DataSourcesPresentation.backfillMessage(
            for: status(.completedWithIssues, events: 500, failures: ["HKQuantityTypeIdentifierHeartRate"]))
        #expect(msg == "Your history was imported, but some data couldn't be read.")
    }

    @Test func zeroEventsPlusFailuresSaysCouldNotBeFullyImported() {
        let msg = DataSourcesPresentation.backfillMessage(
            for: status(.completedWithIssues, events: 0, failures: ["HKQuantityTypeIdentifierHeartRate"]))
        #expect(msg == "Apple Health couldn't be fully imported.")
    }

    @Test func interruptedGetsItsOwnRecoveryCopy() {
        let msg = DataSourcesPresentation.backfillMessage(for: status(.interrupted, events: 100))
        #expect(msg == "The previous import was interrupted.")
    }

    @Test func statusVocabularyNeverSaysConnectedOrDenied() {
        // Apple deliberately obscures read denial, so a definitive
        // Connected/Denied label would be a claim we cannot support.
        let all: [HealthImportOutcome] = [.notStarted, .inProgress, .interrupted, .attemptFailed,
                                          .completedNoData, .completed, .completedWithIssues]
        for outcome in all {
            let label = DataSourcesPresentation.statusLabel(for: status(outcome))
            #expect(!label.localizedCaseInsensitiveContains("connected"))
            #expect(!label.localizedCaseInsensitiveContains("denied"))
        }
        // The loop above only pins an ABSENCE, which `return "Not imported"` for
        // every case satisfies. These pin the branches themselves, so a constant
        // — or two labels swapped — fails.
        #expect(Set(all.map { DataSourcesPresentation.statusLabel(for: status($0)) }).count == all.count)
        #expect(DataSourcesPresentation.statusLabel(for: status(.completed)) == "Last imported")
        #expect(DataSourcesPresentation.statusLabel(for: status(.interrupted)) == "Import interrupted")
    }

    @Test func aSuccessfulImportGetsTheAffirmingCopy() {
        // The happy-path headline of the whole first-run flow, and the ONLY
        // branch of backfillMessage the original suite left unasserted. Folding
        // .completed into the catch-all leaves a successful import reading
        // "Importing your history…" forever, with Continue enabled beneath it.
        #expect(DataSourcesPresentation.backfillMessage(for: status(.completed, events: 1200))
                == "You're not starting from zero.")
    }

    @Test func anAuthorizationFailureSaysCouldNotBeReached() {
        #expect(DataSourcesPresentation.backfillMessage(for: status(.attemptFailed))
                == "Apple Health couldn't be reached.")
    }

    @Test func summaryLineNamesTheEarliestImportedEventNotTheRequestedWindow() throws {
        // 1_700_000_000 == 2023-11-14 UTC. Deliberately older than one year, so
        // a line derived from the requested 1-year backfill window would fail.
        let earliest = Date(timeIntervalSince1970: 1_700_000_000)
        let summaries = [ImportedCategorySummary(category: "sleep", count: 400, earliest: earliest),
                         ImportedCategorySummary(category: "symptom", count: 12,
                                                 earliest: Date(timeIntervalSince1970: 1_750_000_000))]
        let line = try #require(DataSourcesPresentation.summaryLine(from: summaries))
        #expect(line.contains("412"))              // total across categories
        #expect(line.contains("2 categories"))
        #expect(line.contains("2023"))             // the EARLIEST of the two, not the latest
        #expect(!line.contains("2025"))
    }

    @Test func summaryLineIsNilForAnEmptyImport() {
        #expect(DataSourcesPresentation.summaryLine(from: []) == nil)
    }

    // MARK: - Retry is offered only when there is something to retry

    @Test func aCleanImportDoesNotInviteYouToRedoIt() {
        // A multi-minute job that just succeeded should not sit under a Retry
        // button — there is nothing to fix, and re-running it costs minutes.
        #expect(DataSourcesPresentation.offersRetry(for: status(.completed, events: 1200)) == false)
    }

    @Test func everyIncompleteOutcomeOffersRetry() {
        for outcome: HealthImportOutcome in [.interrupted, .attemptFailed,
                                             .completedNoData, .completedWithIssues] {
            #expect(DataSourcesPresentation.offersRetry(for: status(outcome)) == true,
                    "\(outcome) should offer retry")
        }
    }

    @Test func anImportThatHasNotRunOrIsRunningOffersNoRetry() {
        #expect(DataSourcesPresentation.offersRetry(for: status(.notStarted)) == false)
        #expect(DataSourcesPresentation.offersRetry(for: status(.interrupted)) == true)
        #expect(DataSourcesPresentation.offersRetry(for: status(.inProgress)) == false)
    }

    // MARK: - Saying what the buttons do

    @Test func theRecoveryScreenExplainsThatRetryingDoesNotDuplicate() throws {
        // On device this screen was a headline and two unexplained buttons, and
        // the obvious question — does retrying start over, do I lose the 36,799
        // events already in? — went unanswered on an otherwise empty screen.
        let hint = try #require(DataSourcesPresentation.backfillActionHint(for: status(.interrupted)))
        #expect(hint.localizedCaseInsensitiveContains("duplicated"))
        #expect(hint.localizedCaseInsensitiveContains("Data sources"))
    }

    @Test func anEmptyImportIsExplainedAsConnectedRatherThanBroken() throws {
        let hint = try #require(DataSourcesPresentation.backfillActionHint(for: status(.completedNoData)))
        #expect(hint.localizedCaseInsensitiveContains("stays connected"))
    }

    @Test func thereIsNothingToExplainOnACleanOrRunningImport() {
        #expect(DataSourcesPresentation.backfillActionHint(for: status(.completed, events: 1200)) == nil)
        #expect(DataSourcesPresentation.backfillActionHint(for: status(.inProgress)) == nil)
        #expect(DataSourcesPresentation.backfillActionHint(for: status(.notStarted)) == nil)
    }
}
