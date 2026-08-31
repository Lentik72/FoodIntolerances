import Testing
import Foundation
import HealthKit
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

    // MARK: - "nothing to repair" classification

    /// The one error the repair must NOT count as a failure. A type that was
    /// never requested (added to the table after this install's backfill)
    /// reads back `.errorAuthorizationNotDetermined`, which means "no rows of
    /// this type were ever written", not "the read broke". Counting it as a
    /// failure would leave the version unstamped and re-read a full year for
    /// every type on every launch, forever. Every OTHER error still fails.
    @Test func onlyAuthorizationNotDeterminedIsNothingToRepair() {
        #expect(HealthKitIngestor.isNothingToRepair(HKError(.errorAuthorizationNotDetermined)))
        // A different HK failure is a real failure — retry next launch.
        #expect(!HealthKitIngestor.isNothingToRepair(HKError(.errorDatabaseInaccessible)))
        // Including the adjacent authorization state: an explicit denial is
        // not "we never asked".
        #expect(!HealthKitIngestor.isNothingToRepair(HKError(.errorAuthorizationDenied)))
        // And so is anything that isn't a HealthKit error at all.
        #expect(!HealthKitIngestor.isNothingToRepair(Boom()))
    }

    /// The same classification when HealthKit hands back a plain bridged
    /// `NSError` rather than a Swift `HKError` value.
    @Test func nothingToRepairRecognizesTheBridgedNSError() {
        let notDetermined = NSError(domain: HKErrorDomain,
                                    code: HKError.Code.errorAuthorizationNotDetermined.rawValue)
        #expect(HealthKitIngestor.isNothingToRepair(notDetermined))
        // Same code in a foreign domain is a coincidence, not an authorization state.
        #expect(!HealthKitIngestor.isNothingToRepair(
            NSError(domain: "com.example.other",
                    code: HKError.Code.errorAuthorizationNotDetermined.rawValue)))
    }
}
