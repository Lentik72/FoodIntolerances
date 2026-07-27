import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct HealthImportStatusTests {
    private func store() -> (HealthImportStatusStore, UserDefaults) {
        let d = UserDefaults(suiteName: "import-status-\(UUID().uuidString)")!
        return (HealthImportStatusStore(defaults: d), d)
    }

    @Test func startsNotStarted() {
        let (s, _) = store()
        #expect(s.current.outcome == .notStarted)
    }

    @Test func beginAttemptPersistsInProgressBeforeAnyWork() {
        let (s, d) = store()
        s.beginAttempt()
        let reloaded = HealthImportStatusStore(defaults: d)
        #expect(reloaded.current.outcome == .inProgress)   // survives a relaunch
    }

    @Test func launchNormalizationTurnsAStrandedInProgressIntoInterrupted() {
        let (s, d) = store()
        s.beginAttempt()
        let afterRelaunch = HealthImportStatusStore(defaults: d)
        afterRelaunch.normalizeAtLaunch()
        #expect(afterRelaunch.current.outcome == .interrupted)
    }

    @Test func launchNormalizationLeavesTerminalOutcomesAlone() {
        // Without this, dropping the `guard current.outcome == .inProgress`
        // passes every other test — because they only ever normalize a store
        // that IS .inProgress. The mutant rewrites .completed -> .interrupted on
        // EVERY launch, so Data sources reads "Import interrupted" forever and
        // the flow's resumesIntoBackfill misfires for good.
        let (s, d) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 5), failures: [])
        let afterRelaunch = HealthImportStatusStore(defaults: d)
        afterRelaunch.normalizeAtLaunch()
        #expect(afterRelaunch.current.outcome == .completed)
    }

    @Test func finishWithEventsAndNoFailuresIsCompleted() {
        let (s, _) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 10, updated: 2), failures: [])
        #expect(s.current.outcome == .completed)
        #expect(s.current.eventsImported == 12)   // inserted + updated, per HealthKitIngestor
    }

    @Test func finishWithZeroEventsAndNoFailuresIsCompletedNoData() {
        let (s, _) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(), failures: [])
        #expect(s.current.outcome == .completedNoData)
    }

    @Test func finishWithFailuresIsCompletedWithIssues() {
        let (s, _) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 5), failures: ["HKQuantityTypeIdentifierHeartRate: denied"])
        #expect(s.current.outcome == .completedWithIssues)
        #expect(s.current.failureIdentifiers == ["HKQuantityTypeIdentifierHeartRate"])  // sanitised

        // A later CLEAN run must CLEAR them. Assigning only when non-empty
        // passes every other test (none runs clean-after-failing), and Data
        // sources renders "Couldn't read: …" whenever the array is non-empty —
        // so a user who fixes their permissions would see the old failures
        // forever.
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 5), failures: [])
        #expect(s.current.failureIdentifiers.isEmpty)
    }

    @Test func failAttemptIsAttemptFailed() {
        let (s, _) = store()
        s.beginAttempt()
        s.failAttempt()
        #expect(s.current.outcome == .attemptFailed)
    }

    @Test func aCompletedZeroEventRunWritesZeroRatherThanCarryingTheOldTotal() {
        let (s, _) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 100), failures: [])
        s.beginAttempt()
        s.finish(summary: IngestSummary(), failures: ["HKQuantityTypeIdentifierHeartRate: denied"])
        #expect(s.current.outcome == .completedWithIssues)
        #expect(s.current.eventsImported == 0)   // NOT 100 — the copy branches on this
    }

    @Test func aPriorSuccessfulSummarySurvivesAnInterruptedReimport() {
        let (s, d) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 100), failures: [])
        s.beginAttempt()                                   // re-import starts…
        let afterRelaunch = HealthImportStatusStore(defaults: d)
        afterRelaunch.normalizeAtLaunch()                  // …and is killed
        #expect(afterRelaunch.current.outcome == .interrupted)
        #expect(afterRelaunch.current.eventsImported == 100)      // NOT blanked
        #expect(afterRelaunch.current.lastCompletedAt != nil)
    }

    // ---- Beyond the brief: mutants the drafted tests above do not kill ----

    @Test func recordCategoriesAndFinishUpdateTheirOwnFieldsWithoutClobberingEachOther() {
        let (s, d) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 7), failures: [])
        s.recordCategories(3)
        #expect(s.current.categoriesImported == 3)
        #expect(s.current.outcome == .completed)      // recordCategories didn't reset the outcome
        #expect(s.current.eventsImported == 7)        // …or the event count
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 9), failures: [])
        #expect(s.current.categoriesImported == 3)    // finish copies current, doesn't rebuild
        #expect(s.current.lastAttemptAt != nil)       // …and doesn't blank the attempt stamp
        let reloaded = HealthImportStatusStore(defaults: d)
        #expect(reloaded.current.categoriesImported == 3)   // and it persisted
        #expect(reloaded.current.eventsImported == 9)
    }

    @Test func onlyFinishStampsACompletionDate() {
        let (s, _) = store()
        s.beginAttempt()
        #expect(s.current.lastAttemptAt != nil)    // begin stamps the attempt…
        #expect(s.current.lastCompletedAt == nil)  // …but never a completion
        s.failAttempt()
        #expect(s.current.lastCompletedAt == nil)  // a failure is not a completion —
                                                   // "Last imported…" must not render off it
    }

    @Test func aPriorSuccessfulSummarySurvivesAFailedReattempt() {
        // Same principle as the interrupted case: failAttempt must copy
        // current, not rebuild. A rebuild passes failAttemptIsAttemptFailed
        // AND onlyFinishStampsACompletionDate (both fields it blanks are
        // exactly the ones those tests expect to be nil/attemptFailed) while
        // blanking "Last imported 100 events" after a failed re-attempt.
        let (s, _) = store()
        s.beginAttempt()
        s.finish(summary: IngestSummary(inserted: 100), failures: [])
        s.beginAttempt()
        s.failAttempt()
        #expect(s.current.outcome == .attemptFailed)
        #expect(s.current.eventsImported == 100)      // NOT blanked
        #expect(s.current.lastCompletedAt != nil)     // "Last imported…" stays truthful
    }

    @Test func aCorruptPersistedBlobFallsBackToAFreshStatusInsteadOfCrashing() {
        let d = UserDefaults(suiteName: "import-status-\(UUID().uuidString)")!
        d.set(Data("not json".utf8), forKey: "hg.hk.importStatus")
        let s = HealthImportStatusStore(defaults: d)
        #expect(s.current.outcome == .notStarted)
    }

    @Test func theOnDiskKeyAndSchemaAreStable() {
        // Hardcoded blob, NOT round-tripped through the encoder: a renamed
        // storage key, enum raw value, or field name would pass every
        // encode-then-decode test while silently resetting real devices'
        // import history on an app update.
        let d = UserDefaults(suiteName: "import-status-\(UUID().uuidString)")!
        let blob = #"{"outcome":"completed","eventsImported":12,"categoriesImported":3,"failureIdentifiers":["HKQuantityTypeIdentifierHeartRate"]}"#
        d.set(Data(blob.utf8), forKey: "hg.hk.importStatus")
        let s = HealthImportStatusStore(defaults: d)
        #expect(s.current.outcome == .completed)
        #expect(s.current.eventsImported == 12)
        #expect(s.current.categoriesImported == 3)
        #expect(s.current.failureIdentifiers == ["HKQuantityTypeIdentifierHeartRate"])
    }

    @Test func everyTerminalPathLeavesInProgress() {
        for makeTerminal in [
            { (s: HealthImportStatusStore) in s.finish(summary: IngestSummary(inserted: 1), failures: []) },
            { (s: HealthImportStatusStore) in s.finish(summary: IngestSummary(), failures: []) },
            { (s: HealthImportStatusStore) in s.finish(summary: IngestSummary(), failures: ["x: y"]) },
            { (s: HealthImportStatusStore) in s.failAttempt() },
        ] {
            let (s, _) = store()
            s.beginAttempt()
            makeTerminal(s)
            #expect(s.current.outcome != .inProgress)
        }
    }
}
