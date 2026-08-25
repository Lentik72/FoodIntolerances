import Foundation
import Testing
import HealthGraphCore
@testable import Food_Intolerances

/// Covers `ExperimentRowLoader.result(for:...)`'s relationship-selection logic
/// — the highest-risk piece of Task 6, and previously untestable because the
/// loader was `private` (file-scoped in Swift, unreachable even via
/// `@testable import`). Doubles are narrow structs conforming to the
/// `ObjectStore` / `RelationshipStore` / `EventStore` protocols, in the style
/// of `ExperimentWorkflowTests`'s `RecordingStore` for `ExperimentPersisting`.
@Suite struct ExperimentRowLoaderTests {
    private let interventionID = UUID()
    private let intervention: HealthObject

    init() {
        intervention = HealthObject(id: interventionID, kind: .supplement, name: "Magnesium")
    }

    /// `.repeated`: the only shape `ExperimentResult.derive` will ever hand a
    /// verdict to. A `.course` experiment would fall to `.pictureOnly`
    /// regardless of the relationship, which would mask the very selection
    /// logic under test here.
    private func experiment(outcomeSubtype: String = "migraine") -> Experiment {
        Experiment(interventionObjectID: interventionID, outcomeSubtype: outcomeSubtype,
                  shape: .repeated, startedAt: Date().addingTimeInterval(-21 * 86_400),
                  intendedEndAt: Date())
    }

    private func relationship(type: RelationshipType, status: RelStatus, confidence: Double,
                              toSubtype: String?, toCategory: String? = "symptom") -> Relationship {
        Relationship(fromObjectID: interventionID, toCategory: toCategory, type: type,
                    confidence: confidence, firstSeen: Date(), lastSeen: Date(),
                    lastRecomputed: Date(), status: status, toSubtype: toSubtype)
    }

    private func resolve(_ candidates: [Relationship], outcomeSubtype: String = "migraine") async -> ExperimentResult? {
        let resolved = await ExperimentRowLoader.result(
            for: experiment(outcomeSubtype: outcomeSubtype),
            objectStore: StubObjectStore(object: intervention),
            relationshipStore: StubRelationshipStore(candidates: candidates),
            eventStore: StubEventStore(),
            calendar: .current)
        return resolved?.result
    }

    @Test func aSettledRowWinsOverAHigherConfidenceDecayedRow() async {
        // The defect this fix closes: an early, noisy .possibleTrigger reading
        // later decayed once the real .improves relationship settled — but decay
        // does not lower confidence, so `relationships(fromObjectID:)`'s
        // confidence-DESC order still surfaces the stale row first. Taking
        // `.first` unconditionally would silently withhold an earned verdict.
        let decayed = relationship(type: .possibleTrigger, status: .decayed, confidence: 0.8, toSubtype: "migraine")
        let active = relationship(type: .improves, status: .active, confidence: 0.6, toSubtype: "migraine")
        let result = await resolve([decayed, active])
        #expect(result?.kind == .helps)
    }

    @Test func aRelationshipForADifferentOutcomeIsExcluded() async {
        // Same intervention, wrong symptom. Matching on fromObjectID alone would
        // let this hand back a verdict about a question that was never asked.
        let wrongSymptom = relationship(type: .improves, status: .active, confidence: 0.9, toSubtype: "headache")
        let result = await resolve([wrongSymptom], outcomeSubtype: "migraine")
        #expect(result?.kind == .pictureOnly)
    }

    @Test func aNilToSubtypeDoesNotMatch() async {
        let noSubtype = relationship(type: .improves, status: .active, confidence: 0.9, toSubtype: nil)
        let result = await resolve([noSubtype])
        #expect(result?.kind == .pictureOnly)
    }

    @Test func noCandidatesYieldsAPicture() async {
        let result = await resolve([])
        #expect(result?.kind == .pictureOnly)
    }

    @Test func aMoodCategoryRowNeverSatisfiesASymptomExperimentsFilter() async {
        // Defense in depth for the committed mood-outcome follow-up: mood
        // relationships key on the fixed "low"/"good" tokens today, so this is a
        // no-op in practice — nothing in the current catalog collides with them.
        // The category guard is what keeps that true once mood outcomes exist,
        // rather than relying on the token collision never happening.
        let moodRow = relationship(type: .improves, status: .active, confidence: 0.9,
                                   toSubtype: "migraine", toCategory: "mood")
        let result = await resolve([moodRow])
        #expect(result?.kind == .pictureOnly)
    }
}

// MARK: - Doubles

private struct StubObjectStore: ObjectStore {
    let object: HealthObject
    func findOrCreate(name: String, kind: ObjectKind, metadata: Data?,
                      syntheticBatch: String?) async throws -> HealthObject { object }
    func object(id: UUID) async throws -> HealthObject? { id == object.id ? object : nil }
    func objects(kind: ObjectKind?, includeArchived: Bool) async throws -> [HealthObject] { [object] }
    func setArchived(id: UUID, _ archived: Bool) async throws {}
    func count() async throws -> Int { 1 }
}

private struct StubRelationshipStore: RelationshipStore {
    let candidates: [Relationship]
    func save(_ relationship: Relationship) async throws {}
    func relationship(id: UUID) async throws -> Relationship? { candidates.first { $0.id == id } }
    func relationships(status: RelStatus?) async throws -> [Relationship] { candidates }
    func relationships(fromObjectID: UUID) async throws -> [Relationship] { candidates }
    func count() async throws -> Int { candidates.count }
    func all() async throws -> [Relationship] { candidates }
    func save(_ relationships: [Relationship]) async throws {}
}

/// Adherence numbers play no part in the assertions above (only `result.kind`
/// does), so this always reports no dose history.
private struct StubEventStore: EventStore {
    func save(_ event: HealthEvent) async throws {}
    func save(_ events: [HealthEvent]) async throws {}
    func event(id: UUID) async throws -> HealthEvent? { nil }
    func events(in interval: DateInterval, category: EventCategory?) async throws -> [HealthEvent] { [] }
    func recentEvents(limit: Int) async throws -> [HealthEvent] { [] }
    func softDelete(id: UUID) async throws {}
    func count() async throws -> Int { 0 }
    func countsByCategory() async throws -> [String: Int] { [:] }
    func countsBySource() async throws -> [String: Int] { [:] }
    func eventsPage(before cursor: TimelineCursor?, limit: Int,
                    categories: Set<EventCategory>?, sources: Set<EventSource>?) async throws -> [HealthEvent] { [] }
    func restore(id: UUID) async throws {}
    func searchEvents(matching query: String, limit: Int) async throws -> [HealthEvent] { [] }
    func environmentEvents(subtypes: Set<String>, from: Date, through: Date) async throws -> [HealthEvent] { [] }
}
