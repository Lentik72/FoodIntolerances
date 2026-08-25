import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct ExperimentViewStateTests {
    final class CountingStore: ExperimentPersisting {
        var saves = 0
        var stored: [Experiment] = []
        func save(_ e: Experiment) async throws {
            saves += 1
            stored.removeAll { $0.id == e.id }
            stored.append(e)
        }
        func all() async throws -> [Experiment] { stored }
    }

    final class LoadCountingStore: ExperimentPersisting {
        var loads = 0
        var stored: [Experiment] = []
        func save(_ e: Experiment) async throws {
            stored.removeAll { $0.id == e.id }
            stored.append(e)
        }
        func all() async throws -> [Experiment] {
            loads += 1
            return stored
        }
    }

    private func settle() async { for _ in 0..<25 { await Task.yield() } }

    @Test func twoImmediateCreateTapsCreateOneExperiment() async {
        // Both taps land in the same main-actor turn, before any re-render applies
        // .disabled. Only a guard that runs synchronously inside createTapped
        // separates one experiment from two — and two would silently double every
        // adherence count for the same regimen.
        let store = CountingStore()
        let state = ExperimentViewState(store: store)
        state.createTapped(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                           shape: .repeated, days: 21)
        state.createTapped(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                           shape: .repeated, days: 21)
        await state.saveTask?.value
        await settle()
        #expect(store.saves == 1)
        #expect(state.isSaving == false)
    }

    @Test func creatingPublishesTheNewExperiment() async {
        let store = CountingStore()
        let state = ExperimentViewState(store: store)
        state.createTapped(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                           shape: .course, days: 14)
        #expect(state.isSaving == true)      // synchronous, disables the button this turn
        await state.saveTask?.value
        #expect(state.experiments.count == 1)
        #expect(state.experiments.first?.shape == .course)
    }

    @Test func twoImmediateEndTapsOnTheSameExperimentCreateOneSave() async {
        // Both taps land in the same main-actor turn. Only a guard that checks
        // the specific experiment ID separates one from two — a shared flag would
        // allow the second tap to enqueue, violating the per-experiment guard.
        let store = CountingStore()
        let state = ExperimentViewState(store: store)
        let e = Experiment(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                           shape: .repeated, startedAt: Date(),
                           intendedEndAt: Date().addingTimeInterval(21 * 86_400))
        store.stored.append(e)
        state.endTapped(e)
        state.endTapped(e)
        await state.saveTask?.value
        await settle()
        #expect(store.saves == 1)
        #expect(state.endingIDs.isEmpty)
    }

    @Test func twoImmediateEndTapsOnDifferentExperimentsCreateTwoSaves() async {
        // Two different experiments are legitimately independent. Two taps on
        // different rows should produce two saves, not one.
        let store = CountingStore()
        let state = ExperimentViewState(store: store)
        let e1 = Experiment(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                            shape: .repeated, startedAt: Date(),
                            intendedEndAt: Date().addingTimeInterval(21 * 86_400))
        let e2 = Experiment(interventionObjectID: UUID(), outcomeSubtype: "headache",
                            shape: .course, startedAt: Date(),
                            intendedEndAt: Date().addingTimeInterval(14 * 86_400))
        store.stored.append(contentsOf: [e1, e2])
        state.endTapped(e1)
        state.endTapped(e2)
        await state.saveTask?.value
        await settle()
        #expect(store.saves == 2)
        #expect(state.endingIDs.isEmpty)
    }

    @Test func endingMarksCompletedStatus() async {
        let store = CountingStore()
        let state = ExperimentViewState(store: store)
        let e = Experiment(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                           shape: .repeated, startedAt: Date(),
                           intendedEndAt: Date().addingTimeInterval(21 * 86_400))
        store.stored.append(e)
        state.endTapped(e)
        await state.saveTask?.value
        #expect(store.stored.last?.status == .completed)
    }

    @Test func appearedTwiceLoadsTheListTwice() async {
        // The guard on appeared() checks isLoading, not "has-ever-run".
        // A screen can be shown, dismissed, and shown again, and it should
        // resync on each appearance, not latch shut permanently.
        let store = LoadCountingStore()
        let state = ExperimentViewState(store: store)
        state.appeared()
        await state.loadTask?.value
        #expect(store.loads == 1)
        state.appeared()
        await state.loadTask?.value
        #expect(store.loads == 2)
    }

    @Test func failedLaterRefreshDoesNotDiscardEarlierSuccess() async {
        // Two refreshes in flight: first reads and succeeds, second reads and fails.
        // With generation-based ordering, the first's success applies even though
        // the second's failure happened after. The key: generation bump and all()
        // are adjacent with no await between, so "second all() call" = "second generation".
        final class FailOnSecondReadStore: ExperimentPersisting {
            var readCount = 0
            var stored: [Experiment] = []
            func save(_ e: Experiment) async throws {
                stored.removeAll { $0.id == e.id }
                stored.append(e)
            }
            func all() async throws -> [Experiment] {
                readCount += 1
                if readCount == 2 {
                    throw NSError(domain: "test", code: 1)
                }
                return stored
            }
        }

        let store = FailOnSecondReadStore()
        let state = ExperimentViewState(store: store)
        let e1 = Experiment(interventionObjectID: UUID(), outcomeSubtype: "test",
                            shape: .course, startedAt: Date(),
                            intendedEndAt: Date().addingTimeInterval(14 * 86_400))
        let e2 = Experiment(interventionObjectID: UUID(), outcomeSubtype: "test",
                            shape: .course, startedAt: Date(),
                            intendedEndAt: Date().addingTimeInterval(14 * 86_400))
        store.stored.append(contentsOf: [e1, e2])

        // Trigger two refreshes via endTapped on different experiments.
        // First one will call all() (readCount = 1, succeeds).
        // Second one will call all() (readCount = 2, throws).
        state.endTapped(e1)
        state.endTapped(e2)

        // Wait for both refreshes to complete
        await state.saveTask?.value
        await settle()

        // Both refreshes should have called all()
        #expect(store.readCount == 2)
        // The first read's result should be applied, not discarded
        #expect(state.experiments.count == 2)
    }
}
