import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct FirstRunStateTests {
    /// `preparing` runs against the fresh suite BEFORE the state is constructed,
    /// so init-time resolution can be steered without touching the database.
    /// `backfillAttempted` is injected directly — FirstRunState no longer reads
    /// the backfill flag off its defaults, so writing the key into the suite
    /// cannot steer routing anymore.
    private func makeState(backfillAttempted: Bool = false,
                           preparing prepare: (UserDefaults) -> Void = { _ in }) throws -> (FirstRunState, UserDefaults) {
        let d = UserDefaults(suiteName: "first-run-state-\(UUID().uuidString)")!
        prepare(d)
        let db = try AppDatabase.inMemory()
        return (FirstRunState(defaults: d, store: GRDBEventStore(database: db),
                              backfillAttempted: backfillAttempted), d)
    }

    @Test func seedsAreRevalidatedOnRead() throws {
        let (state, d) = try makeState()
        // Written directly, bypassing markCompleted's write-time validation —
        // this is the stale-store case the read-time guard exists for.
        let redFlag = try #require(RedFlagCatalog.allSymptomKeys.first)
        let good = HealthGraphCore.SymptomCatalog.canonicalKey(for: "Headache")
        d.set([redFlag, "notARealCatalogKey", good], forKey: FirstRunKeys.symptomSeeds)
        #expect(state.seeds == [good])
    }

    @Test func completionValidatesAndClearsTheInProgressMarker() throws {
        let (state, d) = try makeState()
        state.markStarted()
        #expect(d.integer(forKey: FirstRunKeys.startedVersion) == FirstRunState.currentVersion)

        let redFlag = try #require(RedFlagCatalog.allSymptomKeys.first)
        let good = HealthGraphCore.SymptomCatalog.canonicalKey(for: "Bloating")
        state.markCompleted(seeds: [good, redFlag])

        #expect(d.integer(forKey: FirstRunKeys.completedVersion) == FirstRunState.currentVersion)
        #expect(d.object(forKey: FirstRunKeys.startedVersion) == nil)   // marker cleared
        // Asserted on the RAW stored array, not `state.seeds`: the getter
        // re-validates too, so reading back through it can't tell whether the
        // WRITE stripped anything. Removing `SymptomSeeds.validate` from
        // markCompleted survived every getter-mediated assertion.
        #expect(d.stringArray(forKey: FirstRunKeys.symptomSeeds) == [good]) // red flag stripped at write
    }

    @Test func theSeedCapIsEnforcedAtCompletionNotJustInTheGrid() throws {
        // The cap of 8 lives in THREE unlinked places: the grid's selection
        // guard, markCompleted's limit, and the getter's limit. Only
        // SymptomSeeds.validate was tested, so widening the grid alone would
        // let a user pick 20 and silently drop 12 here.
        let (state, d) = try makeState()
        let keys = HealthGraphCore.SymptomCatalog.all.map(\.canonicalKey)
            .filter { !Set(RedFlagCatalog.allSymptomKeys).contains($0) }
        state.markCompleted(seeds: Array(keys.prefix(20)))
        // RAW stored array, deliberately: `state.seeds` re-caps on read, so it
        // passes even when markCompleted stops capping. This is what makes the
        // test name — "enforced at completion" — actually true.
        #expect(d.stringArray(forKey: FirstRunKeys.symptomSeeds)?.count == 8)
        #expect(state.seeds.count == 8)
    }

    @Test func theGetterCapsAnOverlongStoredArrayOnItsOwn() throws {
        // The symmetric half of the write/read cap pair: with the write-side
        // assertions above now reading the raw array, raising ONLY the getter's
        // `limit: 8` would survive — every stored array it ever read back was
        // already capped on write. Bypass markCompleted so the getter is the
        // only cap standing between a stale overlong store and the UI.
        let (state, d) = try makeState()
        let keys = HealthGraphCore.SymptomCatalog.all.map(\.canonicalKey)
            .filter { !Set(RedFlagCatalog.allSymptomKeys).contains($0) }
        d.set(Array(keys.prefix(12)), forKey: FirstRunKeys.symptomSeeds)
        #expect(state.seeds.count == 8)
    }

    @Test func reconciliationStampsCompletionUnderTheRightKeyAndValue() throws {
        // The init self-heal: an install with a backfill already attempted but
        // no first-run markers resolves .reconcileThenShell, and init stamps
        // completedVersion so it is never onboarded again. No test reached this
        // branch, so THREE mutants survived: deleting the stamp, writing 0
        // instead of currentVersion, and — the dangerous one — writing
        // startedVersion instead of completedVersion, which makes the NEXT
        // launch match the resume row and drop an existing user into
        // onboarding over their own populated graph.
        let (state, d) = try makeState(backfillAttempted: true)
        #expect(state.resolution == .reconcileThenShell)
        #expect(d.integer(forKey: FirstRunKeys.completedVersion) == FirstRunState.currentVersion)
        // This nil check is what kills the wrong-key variant — the two
        // assertions above stay green when the stamp lands on startedVersion.
        #expect(d.object(forKey: FirstRunKeys.startedVersion) == nil)
    }

    @Test func routingIgnoresABackfillFlagInTheInjectedDefaults() throws {
        // The injected suite says "backfill happened"; the parameter says it did not.
        // The parameter must win. Under the old defaults-read this resolved
        // .reconcileThenShell and the user was silently never onboarded.
        let d = UserDefaults(suiteName: "first-run-conflict-\(UUID().uuidString)")!
        d.set(true, forKey: HealthKitIngestor.backfillCompletedKey)
        let db = try AppDatabase.inMemory()
        let state = FirstRunState(defaults: d, store: GRDBEventStore(database: db),
                                  backfillAttempted: false)
        #expect(state.resolution == .flow(.fresh))
        #expect(state.flowEntry == .fresh)
    }

    @Test func aFreshInstallRoutesIntoTheFreshFlow() throws {
        // flowEntry is the entire routing surface the app gate switches on,
        // and it had no assertions anywhere: mutating it to `{ nil }` —
        // onboarding never mounts at all — passed every test.
        let (state, _) = try makeState()
        #expect(state.resolution == .flow(.fresh))
        #expect(state.flowEntry == .fresh)
    }

    @Test func anInterruptedRunRoutesIntoTheResumeFlow() throws {
        // Same routing surface, other live case: a startedVersion stamp at
        // currentVersion must surface .resume through flowEntry, not just
        // through the raw resolution.
        let (state, _) = try makeState { $0.set(FirstRunState.currentVersion, forKey: FirstRunKeys.startedVersion) }
        #expect(state.flowEntry == .resume)
    }

    @Test func aCompletedInstallHasNoFlowEntry() throws {
        // The shell half of the routing contract: completedVersion at current
        // resolves .shell, and flowEntry must be nil so onboarding never mounts.
        let (state, _) = try makeState { $0.set(FirstRunState.currentVersion, forKey: FirstRunKeys.completedVersion) }
        #expect(state.resolution == .shell)
        #expect(state.flowEntry == nil)
    }

    @Test func completingTheFlowSwitchesToTheShellImmediately() throws {
        // Deleting `resolution = .shell` from markCompleted survived: the
        // persisted markers were asserted, but not the LIVE published switch
        // that dismisses onboarding in the running session.
        let (state, _) = try makeState()
        state.markCompleted(seeds: [])
        #expect(state.resolution == .shell)
        #expect(state.flowEntry == nil)
    }
}
