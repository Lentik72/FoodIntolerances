import Foundation
import HealthGraphCore

/// The slice of experiment persistence the workflow needs. Narrow on purpose, so
/// tests can record the call sequence without a database.
@MainActor
protocol ExperimentPersisting {
    func save(_ experiment: Experiment) async throws
    func all() async throws -> [Experiment]
}

extension GRDBExperimentStore: ExperimentPersisting {}

/// Experiment lifecycle transitions, extracted from the view so their ORDER and
/// their effect on stored state are testable with recording doubles — the same
/// split ConnectWorkflow and BackfillWorkflow use.
@MainActor
struct ExperimentWorkflow {
    private let store: any ExperimentPersisting

    init(store: any ExperimentPersisting) { self.store = store }

    /// The shape is taken from the caller and stored verbatim. It is never
    /// derived from the events, because a fortnight of consecutive doses cannot
    /// be told apart from the start of a daily habit.
    func start(interventionObjectID: UUID, outcomeSubtype: String, shape: ExperimentShape,
               startedAt: Date, days: Int) async throws -> Experiment {
        let e = Experiment(interventionObjectID: interventionObjectID,
                           outcomeSubtype: outcomeSubtype, shape: shape,
                           startedAt: startedAt,
                           intendedEndAt: startedAt.addingTimeInterval(Double(days) * 86_400),
                           status: .running, createdAt: startedAt)
        try await store.save(e)
        return e
    }

    /// Completed and abandoned are deliberately different states: adherence
    /// measures to `endedAt`, so an abandoned experiment is not judged on days
    /// its owner never intended to fill.
    func end(_ experiment: Experiment, at date: Date) async throws -> Experiment {
        try await finish(experiment, status: .completed, at: date)
    }

    func abandon(_ experiment: Experiment, at date: Date) async throws -> Experiment {
        try await finish(experiment, status: .abandoned, at: date)
    }

    private func finish(_ experiment: Experiment, status: ExperimentStatus,
                        at date: Date) async throws -> Experiment {
        var e = experiment
        e.status = status
        e.endedAt = date
        try await store.save(e)
        return e
    }

    func all() async throws -> [Experiment] { try await store.all() }
}
