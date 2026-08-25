import Foundation
import HealthGraphCore

/// Screen state for the experiments surfaces. Transitions live in
/// ExperimentWorkflow; this owns published state, the callbacks, and the guard.
@MainActor
final class ExperimentViewState: ObservableObject {
    @Published private(set) var experiments: [Experiment] = []
    @Published private(set) var isSaving = false
    @Published private(set) var endingIDs: Set<UUID> = []

    private let workflow: ExperimentWorkflow
    private var isLoading = false
    private var refreshGeneration = 0
    private var lastAppliedGeneration = 0

    /// Read-only outside; tests await it so assertions run after completion
    /// rather than spinning a run loop. Production code never reads it.
    private(set) var saveTask: Task<Void, Never>?
    private(set) var loadTask: Task<Void, Never>?

    init(store: any ExperimentPersisting) {
        self.workflow = ExperimentWorkflow(store: store)
    }

    func appeared() {
        guard !isLoading else { return }
        isLoading = true
        loadTask = Task {
            defer { isLoading = false }
            await refresh()
        }
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
            await refresh()
        }
    }

    func endTapped(_ experiment: Experiment) {
        guard !endingIDs.contains(experiment.id) else { return }
        endingIDs.insert(experiment.id)
        saveTask = Task {
            defer { endingIDs.remove(experiment.id) }
            _ = try? await workflow.end(experiment, at: Date())
            await refresh()
        }
    }

    private func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        // A failed read must NOT consume the slot: bumping on entry meant a later
        // refresh that failed could discard an earlier one that succeeded.
        guard let latest = try? await workflow.all() else { return }
        // Only a read that started more recently than the last APPLIED one wins.
        guard generation > lastAppliedGeneration else { return }
        lastAppliedGeneration = generation
        experiments = latest
    }
}
