import Foundation
import HealthGraphCore

/// Screen state for the experiments surfaces. Transitions live in
/// ExperimentWorkflow; this owns published state, the callbacks, and the guard.
@MainActor
final class ExperimentViewState: ObservableObject {
    @Published private(set) var experiments: [Experiment] = []
    @Published private(set) var isSaving = false

    private let workflow: ExperimentWorkflow

    /// Read-only outside; tests await it so assertions run after completion
    /// rather than spinning a run loop. Production code never reads it.
    private(set) var saveTask: Task<Void, Never>?
    private(set) var loadTask: Task<Void, Never>?

    init(store: any ExperimentPersisting) {
        self.workflow = ExperimentWorkflow(store: store)
    }

    func appeared() {
        loadTask = Task { experiments = (try? await workflow.all()) ?? [] }
    }

    /// The guard runs SYNCHRONOUSLY, before any dispatch: two taps can land in the
    /// same main-actor turn, and two experiments over one regimen would double
    /// every adherence count derived from the same doses.
    func createTapped(interventionObjectID: UUID, outcomeSubtype: String,
                      shape: ExperimentShape, days: Int) {
        guard !isSaving else { return }
        isSaving = true
        saveTask = Task {
            defer { isSaving = false }
            _ = try? await workflow.start(interventionObjectID: interventionObjectID,
                                          outcomeSubtype: outcomeSubtype, shape: shape,
                                          startedAt: Date(), days: days)
            experiments = (try? await workflow.all()) ?? []
        }
    }

    func endTapped(_ experiment: Experiment) {
        guard !isSaving else { return }
        isSaving = true
        saveTask = Task {
            defer { isSaving = false }
            _ = try? await workflow.end(experiment, at: Date())
            experiments = (try? await workflow.all()) ?? []
        }
    }
}
