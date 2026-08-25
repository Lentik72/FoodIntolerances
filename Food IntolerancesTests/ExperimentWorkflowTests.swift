import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

@MainActor
@Suite struct ExperimentWorkflowTests {
    enum Call: Equatable {
        case save(ExperimentStatus)
        case loadAll
        case readEvents
        case readRelationships
    }

    final class Recorder { var calls: [Call] = [] }

    final class RecordingStore: ExperimentPersisting {
        let recorder: Recorder
        var stored: [Experiment] = []
        init(recorder: Recorder) { self.recorder = recorder }
        func save(_ e: Experiment) async throws {
            recorder.calls.append(.save(e.status))
            stored.removeAll { $0.id == e.id }
            stored.append(e)
        }
        func all() async throws -> [Experiment] {
            recorder.calls.append(.loadAll)
            return stored
        }
    }

    private func harness() -> (ExperimentWorkflow, Recorder, RecordingStore) {
        let recorder = Recorder()
        let store = RecordingStore(recorder: recorder)
        return (ExperimentWorkflow(store: store), recorder, store)
    }

    @Test func startingPersistsARunningExperimentWithTheDeclaredShape() async throws {
        let (workflow, recorder, store) = harness()
        let objectID = UUID()
        let e = try await workflow.start(interventionObjectID: objectID, outcomeSubtype: "migraine",
                                         shape: .course, startedAt: Date(), days: 14)
        #expect(e.status == .running)
        #expect(e.shape == .course)          // declared, not inferred
        #expect(e.interventionObjectID == objectID)
        #expect(recorder.calls == [.save(.running)])
        #expect(store.stored.count == 1)
    }

    @Test func endingMarksCompletedAndStampsTheEndDate() async throws {
        let (workflow, recorder, _) = harness()
        let e = try await workflow.start(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                                         shape: .repeated, startedAt: Date(), days: 21)
        let ended = try await workflow.end(e, at: Date())
        #expect(ended.status == .completed)
        #expect(ended.endedAt != nil)
        #expect(recorder.calls == [.save(.running), .save(.completed)])
    }

    @Test func abandoningIsDistinctFromCompleting() async throws {
        // They mean different things to the result: an abandoned experiment
        // measures adherence to the day it stopped, not its intended end.
        let (workflow, _, _) = harness()
        let e = try await workflow.start(interventionObjectID: UUID(), outcomeSubtype: "migraine",
                                         shape: .repeated, startedAt: Date(), days: 21)
        let stopped = try await workflow.abandon(e, at: Date())
        #expect(stopped.status == .abandoned)
        #expect(stopped.endedAt != nil)
    }
}
