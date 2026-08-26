import SwiftUI
import HealthGraphCore

/// Creation sheet for a new experiment. Thin wiring: every field is local
/// `@State` for the form itself, and the Start button calls
/// `ExperimentViewState.createTapped(...)` exactly once — the synchronous
/// double-invocation guard and the actual persistence live there and in
/// ExperimentWorkflow, not here.
///
/// `state` and `objectStore` are passed down from ExperimentsView rather than
/// constructed here, so a create + a list refresh always share the same
/// ExperimentViewState instance (the DataSourcesView collaborator-injection
/// pattern).
struct ExperimentCreateView: View {
    @ObservedObject var state: ExperimentViewState
    let objectStore: GRDBObjectStore

    @Environment(\.dismiss) private var dismiss

    @State private var interventions: [HealthObject] = []
    @State private var interventionObjectID: UUID?
    @State private var symptomSearchText = ""
    @State private var selectedSymptomKey: String?
    @State private var shape: ExperimentShape = .repeated
    @State private var days = 21
    #if DEBUG
    /// Days to shift the start INTO THE PAST. 0 in every normal run.
    @State private var backdateDays = 0
    #endif

    // Qualified: the app target has a legacy `SymptomCatalog` / `SymptomDefinition`
    // pair at its root that would otherwise shadow HealthGraphCore's (see
    // SymptomCaptureView, which hits the same collision).
    private var symptomResults: [HealthGraphCore.SymptomDefinition] {
        HealthGraphCore.SymptomCatalog.search(symptomSearchText)
    }

    private var canStart: Bool {
        interventionObjectID != nil && selectedSymptomKey != nil && !state.isSaving
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                interventionSection
                symptomSection
                shapeSection
                lengthSection
                #if DEBUG
                backdateSection
                #endif
            }
            .padding(16)
        }
        .background(HealthTheme.paper)
        .navigationTitle("New experiment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Start") {
                    guard let interventionObjectID, let selectedSymptomKey else { return }
                    state.createTapped(interventionObjectID: interventionObjectID,
                                       outcomeSubtype: selectedSymptomKey, shape: shape, days: days,
                                       startedAt: startDate)
                    dismiss()
                }
                .disabled(!canStart)
            }
        }
        .task {
            interventions = await Self.loadInterventions(objectStore: objectStore)
        }
    }

    // MARK: sections

    private var interventionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What are you tracking?")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            if interventions.isEmpty {
                Text("Log a medication, supplement or peptide dose first, then come back here to start an experiment on it.")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(interventions) { object in
                        Button {
                            interventionObjectID = object.id
                        } label: {
                            HStack {
                                Text(object.name).foregroundStyle(HealthTheme.ink)
                                #if DEBUG
                                // Demo objects are namespaced away from real ones on
                                // purpose (DemoBatch), so a seeded "magnesium" sits
                                // beside a real "Magnesium" and reads as a duplicate.
                                // Without this the only difference on screen is a
                                // capital letter, and picking wrong evaluates the
                                // wrong history.
                                if object.syntheticBatch != nil {
                                    Text("DEMO")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(HealthTheme.dotMiss.opacity(0.4)))
                                        .foregroundStyle(HealthTheme.inkMuted)
                                        .accessibilityLabel("demo data")
                                }
                                #endif
                                Spacer()
                                Text(object.kind.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(HealthTheme.inkMuted)
                                if interventionObjectID == object.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(HealthTheme.accent)
                                }
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .frame(minHeight: 44)
                        if object.id != interventions.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .hgCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var symptomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Symptom to watch")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(HealthTheme.inkMuted)
                TextField("Search symptoms", text: $symptomSearchText)
                    .onChange(of: symptomSearchText) { _, _ in selectedSymptomKey = nil }
            }
            .padding(12)
            .hgCard()
            if let selectedSymptomKey {
                Label(HealthGraphCore.SymptomCatalog.displayName(for: selectedSymptomKey),
                     systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.accent)
            } else if !symptomResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(symptomResults.prefix(6), id: \.canonicalKey) { def in
                        Button {
                            selectedSymptomKey = def.canonicalKey
                            symptomSearchText = def.displayName
                        } label: {
                            HStack {
                                Text(def.displayName).foregroundStyle(HealthTheme.ink)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 12)
                .hgCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shape")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            Picker("Shape", selection: $shape) {
                Text("As needed / ongoing").tag(ExperimentShape.repeated)
                Text("A fixed course").tag(ExperimentShape.course)
            }
            .pickerStyle(.segmented)
            // The choice determines whether a verdict is even possible — a user
            // cannot be expected to infer that, so it is spelled out inline
            // rather than left to a tooltip or a help screen.
            Text(shape == .course
                 ? "A fixed run, like a two-week antibiotic course. We'll show you what happened, but a single course can't be tested."
                 : "Taken as needed or ongoing. With enough repetition this can be tested.")
                .font(.footnote)
                .foregroundStyle(HealthTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Length")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            Stepper("\(days) days", value: $days, in: 1...180)
                .padding(12)
                .hgCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startDate: Date {
        #if DEBUG
        return Date().addingTimeInterval(-Double(backdateDays) * 86_400)
        #else
        return Date()
        #endif
    }

    #if DEBUG
    private var backdateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backdate start (DEBUG)")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.inkSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Stepper(backdateDays == 0 ? "Start today" : "Start \(backdateDays) days ago",
                        value: $backdateDays, in: 0...365, step: 30)
                Text("Doses only count inside the window, so a start of today sees no past logs. Backdate to evaluate against demo data.")
                    .font(.caption)
                    .foregroundStyle(HealthTheme.inkMuted)
            }
            .padding(12)
            .hgCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    // MARK: loading

    private static func loadInterventions(objectStore: GRDBObjectStore) async -> [HealthObject] {
        let kinds: [ObjectKind] = [.medication, .supplement, .peptide]
        var all: [HealthObject] = []
        for kind in kinds {
            if let objects = try? await objectStore.objects(kind: kind, includeArchived: false) {
                all.append(contentsOf: objects)
            }
        }
        return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
