import Testing
import Foundation
@testable import Food_Intolerances

/// Pins the one-shot repair's gate and its stamping contract: it must run
/// exactly once per install after a completed backfill, and it must leave the
/// version unset when the re-ingest failed so the next launch retries.
/// `reingest` is injected, so nothing here touches HealthKit.
struct DailyStatRepairTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "daily-stat-repair-\(UUID().uuidString)")!
    }

    /// Counts calls and can be told to fail, without capturing a mutable
    /// local in an async closure.
    private final class Reingest {
        private(set) var callCount = 0
        var errorToThrow: Error?
        func run() throws {
            callCount += 1
            if let errorToThrow { throw errorToThrow }
        }
    }

    private struct Boom: Error {}

    // MARK: - isDue

    @Test func isDueWhenBackfillCompletedAndVersionBehind() {
        #expect(DailyStatRepair.isDue(storedVersion: 0, backfillCompleted: true))
    }

    @Test func notDueWhenAlreadyAtCurrentVersion() {
        #expect(!DailyStatRepair.isDue(storedVersion: DailyStatRepair.currentVersion,
                                       backfillCompleted: true))
    }

    @Test func notDueBeforeABackfillHasCompleted() {
        // Nothing has been written yet, so there is nothing to repair — and a
        // year-long re-read before the backfill would be pure waste.
        #expect(!DailyStatRepair.isDue(storedVersion: 0, backfillCompleted: false))
    }

    @Test func notDueWhenStoredVersionIsAhead() {
        #expect(!DailyStatRepair.isDue(storedVersion: DailyStatRepair.currentVersion + 1,
                                       backfillCompleted: true))
    }

    // MARK: - runIfDue

    @Test func runIfDueSkipsWhenNotDue() async {
        let defaults = freshDefaults()          // no backfill-completed flag
        let reingest = Reingest()
        await DailyStatRepair.runIfDue(defaults: defaults) { try reingest.run() }
        #expect(reingest.callCount == 0)
        #expect(defaults.integer(forKey: DailyStatRepair.versionKey) == 0)
    }

    @Test func runIfDueStampsVersionOnSuccess() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: HealthKitIngestor.backfillCompletedKey)
        let reingest = Reingest()

        await DailyStatRepair.runIfDue(defaults: defaults) { try reingest.run() }

        #expect(reingest.callCount == 1)
        #expect(defaults.integer(forKey: DailyStatRepair.versionKey) == DailyStatRepair.currentVersion)

        // Stamped means done: a second launch must not re-read a year.
        await DailyStatRepair.runIfDue(defaults: defaults) { try reingest.run() }
        #expect(reingest.callCount == 1)
    }

    @Test func runIfDueLeavesVersionUnsetOnFailure() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: HealthKitIngestor.backfillCompletedKey)
        let reingest = Reingest()
        reingest.errorToThrow = Boom()

        await DailyStatRepair.runIfDue(defaults: defaults) { try reingest.run() }
        #expect(reingest.callCount == 1)
        #expect(defaults.integer(forKey: DailyStatRepair.versionKey) == 0)

        // Unset means still due: the next launch tries again.
        await DailyStatRepair.runIfDue(defaults: defaults) { try reingest.run() }
        #expect(reingest.callCount == 2)
        #expect(defaults.integer(forKey: DailyStatRepair.versionKey) == 0)
    }
}
