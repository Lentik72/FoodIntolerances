import SwiftUI
import HealthGraphCore

/// Health-tab surface for browsing and creating experiments. Thin wiring over
/// ExperimentViewState: appearance, ending and creating each call exactly one
/// model method (`appeared()`, `endTapped(_:)`, `createTapped(...)` — the
/// latter from ExperimentCreateView). The claim ladder itself is rendered
/// straight from ExperimentPresentation; this screen never inspects a
/// relationship's confidence or status, only the `ExperimentOutcomeKind` that
/// `ExperimentResult.derive` already settled on.
struct ExperimentsView: View {
    @StateObject private var state: ExperimentViewState
    /// Read-only lookups the list needs beyond what ExperimentViewState
    /// publishes: the intervention's display name, its dose history (for
    /// adherence), and the one relationship — if any — that speaks to this
    /// experiment's exact declared pair.
    private let objectStore: GRDBObjectStore
    private let relationshipStore: GRDBRelationshipStore
    private let eventStore: GRDBEventStore
    private let calendar: Calendar

    @State private var showingCreate = false

    init(database: AppDatabase = HealthGraphProvider.shared, calendar: Calendar = .current) {
        _state = StateObject(wrappedValue: ExperimentViewState(store: GRDBExperimentStore(database: database)))
        objectStore = GRDBObjectStore(database: database)
        relationshipStore = GRDBRelationshipStore(database: database)
        eventStore = GRDBEventStore(database: database)
        self.calendar = calendar
    }

    private var running: [Experiment] { state.experiments.filter { $0.status == .running } }
    /// Everything not running — completed AND abandoned both get a result: an
    /// abandoned course still shows what happened, it just measured adherence
    /// to the day it stopped rather than its intended end (ExperimentAdherence).
    private var finished: [Experiment] { state.experiments.filter { $0.status != .running } }

    var body: some View {
        List {
            if running.isEmpty && finished.isEmpty {
                Text("No experiments yet. Start one to see whether something you take actually helps.")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
            }
            if !running.isEmpty {
                Section {
                    ForEach(running) { experiment in
                        RunningExperimentRow(experiment: experiment,
                                             isEnding: state.endingIDs.contains(experiment.id),
                                             objectStore: objectStore, eventStore: eventStore,
                                             calendar: calendar,
                                             onEnd: { state.endTapped(experiment) })
                    }
                } header: { Text("Running") }
            }
            if !finished.isEmpty {
                Section {
                    ForEach(finished) { experiment in
                        FinishedExperimentRow(experiment: experiment, objectStore: objectStore,
                                              relationshipStore: relationshipStore,
                                              eventStore: eventStore, calendar: calendar)
                    }
                } header: { Text("Finished") }
            }
        }
        .navigationTitle("Protocols & experiments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Start an experiment")
            }
        }
        .sheet(isPresented: $showingCreate) {
            NavigationStack {
                ExperimentCreateView(state: state, objectStore: objectStore)
            }
        }
        .onAppear { state.appeared() }
    }
}

// MARK: - Rows

private struct RunningExperimentRow: View {
    let experiment: Experiment
    let isEnding: Bool
    let objectStore: GRDBObjectStore
    let eventStore: GRDBEventStore
    let calendar: Calendar
    let onEnd: () -> Void

    @State private var loaded: ExperimentRowLoader.Adherence?

    /// The declared target, shown so two experiments on the same intervention
    /// (e.g. two magnesium runs, one for migraine and one for sleep) read as
    /// distinct rows instead of duplicates.
    private var symptomName: String { HealthGraphCore.SymptomCatalog.displayName(for: experiment.outcomeSubtype) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loaded.map { "\($0.name) · \(symptomName)" } ?? "…")
                    .font(.body)
                    .foregroundStyle(HealthTheme.ink)
                if let loaded {
                    Text("\(loaded.adherence.doseDays) of \(loaded.adherence.windowDays) days logged")
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkSecondary)
                }
                Text(daysRemainingText)
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
            }
            Spacer()
            Button(isEnding ? "Ending…" : "End", action: onEnd)
                .buttonStyle(.bordered)
                .disabled(isEnding)
        }
        .padding(.vertical, 4)
        .task(id: experiment.id) {
            loaded = await ExperimentRowLoader.adherence(for: experiment, objectStore: objectStore,
                                                         eventStore: eventStore, calendar: calendar)
        }
    }

    /// Calendar-day count to the DECLARED end, regardless of adherence — this is
    /// "how long until the window closes", not a projection from the doses so far.
    private var daysRemainingText: String {
        let today = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: experiment.intendedEndAt)
        let days = max(calendar.dateComponents([.day], from: today, to: end).day ?? 0, 0)
        switch days {
        case 0: return "Ends today"
        case 1: return "1 day left"
        default: return "\(days) days left"
        }
    }
}

private struct FinishedExperimentRow: View {
    let experiment: Experiment
    let objectStore: GRDBObjectStore
    let relationshipStore: GRDBRelationshipStore
    let eventStore: GRDBEventStore
    let calendar: Calendar

    @State private var loaded: ExperimentRowLoader.Resolved?

    private var symptomName: String { HealthGraphCore.SymptomCatalog.displayName(for: experiment.outcomeSubtype) }

    var body: some View {
        Group {
            if let loaded {
                NavigationLink {
                    ExperimentResultDetailView(interventionName: loaded.name, interventionKind: loaded.kind,
                                               outcomeSubtype: experiment.outcomeSubtype,
                                               shape: loaded.shape, result: loaded.result)
                } label: {
                    // Neutral identifier only — every claim (headline, caveats,
                    // the prescriber/organ safety lines) lives behind the tap in
                    // ExperimentResultDetailView. This row is the surface most
                    // people read and never tap, so it must never assert
                    // "Sertraline may be making things worse" with no safety
                    // line anywhere near it.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(loaded.name) · \(symptomName)")
                            .font(.body)
                            .foregroundStyle(HealthTheme.ink)
                        Text("Tap to see the result")
                            .font(.footnote)
                            .foregroundStyle(HealthTheme.inkSecondary)
                    }
                }
            } else {
                Text("…")
                    .foregroundStyle(HealthTheme.inkMuted)
            }
        }
        .task(id: experiment.id) {
            loaded = await ExperimentRowLoader.result(for: experiment, objectStore: objectStore,
                                                      relationshipStore: relationshipStore,
                                                      eventStore: eventStore, calendar: calendar)
        }
    }
}

// MARK: - Result detail

private struct ExperimentResultDetailView: View {
    let interventionName: String
    let interventionKind: ObjectKind
    let outcomeSubtype: String
    let shape: ExperimentShape
    let result: ExperimentResult

    private var symptomName: String { HealthGraphCore.SymptomCatalog.displayName(for: outcomeSubtype) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // The declared pair, named plainly, so this reads unambiguously
                // even when the person has more than one experiment on the same
                // intervention (e.g. magnesium for migraine AND for sleep).
                Text("\(interventionName) · \(symptomName)")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)
                Text(ExperimentPresentation.headline(for: result, interventionName: interventionName))
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                Text(ExperimentPresentation.detail(for: result, shape: shape))
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.inkSecondary)

                // Every caveat is rendered — never dropped. This is where the
                // prescriber line and the organ-effects limitation live for a
                // medication result, including a "helps" result.
                let caveats = ExperimentPresentation.caveats(for: result, interventionKind: interventionKind)
                if !caveats.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(caveats, id: \.self) { caveat in
                            Text(caveat)
                                .font(.footnote)
                                .foregroundStyle(HealthTheme.inkMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(HealthTheme.paper)
        .navigationTitle(interventionName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared per-row resolution

/// Every async lookup a row needs, in one place, so the relationship filter
/// documented below is written exactly once. Plain reads only — no
/// statistics, no thresholds; `ExperimentResult.derive` is the only place a
/// verdict gets decided, and it decides it from what this hands in.
///
/// Internal (not `private`) on purpose: this holds the highest-risk logic in
/// the screen — the relationship filter below — and `private` in Swift is
/// file-scoped, which would leave it unreachable even from a `@testable`
/// import. See `ExperimentRowLoaderTests`.
///
/// Store parameters are typed by protocol (`any ObjectStore` etc.), not the
/// concrete `GRDB*Store`, purely so those tests can substitute recording/stub
/// doubles the way `ExperimentWorkflowTests` does for `ExperimentPersisting` —
/// production call sites still pass the real GRDB-backed stores.
enum ExperimentRowLoader {
    struct Adherence {
        let name: String
        let kind: ObjectKind
        let adherence: ExperimentAdherence
    }

    struct Resolved {
        let name: String
        let kind: ObjectKind
        let shape: ExperimentShape
        let result: ExperimentResult
    }

    static func adherence(for experiment: Experiment, objectStore: any ObjectStore,
                          eventStore: any EventStore, calendar: Calendar) async -> Adherence? {
        guard let object = try? await objectStore.object(id: experiment.interventionObjectID) else { return nil }
        let events = await doseEvents(for: experiment, kind: object.kind, eventStore: eventStore)
        let measured = ExperimentAdherence.measure(experiment: experiment, events: events, calendar: calendar)
        return Adherence(name: object.name, kind: object.kind, adherence: measured)
    }

    /// `ExperimentResult.derive` trusts its caller that the relationship it is
    /// handed corresponds to this exact experiment's declared pair — it does
    /// not check. That check happens HERE, and nowhere else, in two parts:
    ///
    /// - `relationships(fromObjectID:)` narrows to the intervention, but a
    ///   relationship for a DIFFERENT outcome on that same object would still
    ///   pass that filter alone — `toSubtype` must match too, or a
    ///   wrong-symptom relationship could hand back a confident, wrong verdict
    ///   about this intervention. `toCategory == "symptom"` is folded in
    ///   alongside it: it is a no-op today, because mood relationships key on
    ///   the fixed `"low"`/`"good"` tokens rather than a catalog subtype and
    ///   so cannot collide — but Phase B's committed mood-outcome experiments
    ///   will route mood through this exact `toSubtype` comparison, and at
    ///   that point the category guard is what keeps a mood edge from ever
    ///   satisfying a symptom experiment's filter by accident.
    /// - Among rows that DO match, prefer a SETTLED one (`.active` or
    ///   `.confirmedNoEffect`). `relationships(fromObjectID:)` sorts by
    ///   confidence with no status filter, and `EvidenceEngine.recompute`
    ///   decays a superseded row without lowering its confidence — so an
    ///   early noisy `.decayed` reading can outrank a later, genuine
    ///   `.active` one. Taking `.first` unconditionally would silently
    ///   downgrade an earned verdict to a picture; that is the mirror image
    ///   of asserting a false one, and just as much a defect.
    static func result(for experiment: Experiment, objectStore: any ObjectStore,
                       relationshipStore: any RelationshipStore, eventStore: any EventStore,
                       calendar: Calendar) async -> Resolved? {
        guard let base = await adherence(for: experiment, objectStore: objectStore,
                                         eventStore: eventStore, calendar: calendar) else { return nil }
        let sameIntervention = (try? await relationshipStore.relationships(
            fromObjectID: experiment.interventionObjectID)) ?? []
        let declaredPair = sameIntervention.filter {
            $0.toSubtype == experiment.outcomeSubtype && $0.toCategory == "symptom"
        }
        let chosen = declaredPair.first { $0.status == .active || $0.status == .confirmedNoEffect }
            ?? declaredPair.first
        let result = ExperimentResult.derive(experiment: experiment, adherence: base.adherence,
                                             relationship: chosen)
        return Resolved(name: base.name, kind: base.kind, shape: experiment.shape, result: result)
    }

    private static func doseEvents(for experiment: Experiment, kind: ObjectKind,
                                   eventStore: any EventStore) async -> [HealthEvent] {
        // An ended experiment's own window can end before it started only if the
        // record is corrupt; clamping keeps DateInterval's end >= start invariant
        // safe regardless.
        let end = max(experiment.endedAt ?? experiment.intendedEndAt, experiment.startedAt)
        // ObjectKind and EventCategory share raw values for the three intervention
        // kinds ("medication"/"supplement"/"peptide"), so this is a direct mapping,
        // not a guess.
        guard let category = EventCategory(rawValue: kind.rawValue) else { return [] }
        return (try? await eventStore.events(in: DateInterval(start: experiment.startedAt, end: end),
                                             category: category)) ?? []
    }
}
