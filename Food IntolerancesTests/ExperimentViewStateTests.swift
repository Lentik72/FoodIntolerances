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
}
