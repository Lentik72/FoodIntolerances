import SwiftUI
import UniformTypeIdentifiers   // UTType.zip / .xml for the fileImporter
import HealthGraphCore

/// One view, two presentations: a NavigationLink destination in the Health tab
/// and a sheet from the Timeline empty state, so "connect Apple Health" finally
/// points at something real without cross-tab routing machinery.
///
/// Thin wiring over DataSourcesViewState — every decision (the guards, the
/// screen-wake hold, error copy, late-progress rejection) lives there, and the
/// import's ordering one level further down in BackfillWorkflow.
struct DataSourcesView: View {
    @StateObject private var state: DataSourcesViewState
    /// The status card is a pure function of persisted status, so the screen
    /// re-renders as an import transitions it.
    @ObservedObject private var importStatus: HealthImportStatusStore
    @State private var showingImporter = false

    /// Both collaborators come from the caller's environment — never
    /// constructed here, so this screen writes through the same store every
    /// other surface observes.
    init(ingestor: HealthKitIngestor, importStatus: HealthImportStatusStore) {
        _importStatus = ObservedObject(wrappedValue: importStatus)
        _state = StateObject(wrappedValue: DataSourcesViewState(ingestor: ingestor,
                                                                importStatus: importStatus))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Data sources")
                    .font(HealthTheme.screenTitle())
                    .foregroundStyle(HealthTheme.ink)
                    .padding(.top, 8)

                appleHealthCard
                exportFileCard
                environmentRow
                #if DEBUG
                debugResets
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .background(HealthTheme.paper)
        .onAppear { state.appeared() }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.zip, .xml],
                      allowsMultipleSelection: false) { result in
            state.exportFilePicked(result)
        }
    }

    private var appleHealthCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Health")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.ink)
                Text(DataSourcesPresentation.statusLabel(for: importStatus.current))
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkSecondary)
                if let line = DataSourcesPresentation.summaryLine(from: state.summaries) {
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(HealthTheme.inkMuted)
                }
                if !importStatus.current.failureIdentifiers.isEmpty {
                    Text("Couldn't read: \(importStatus.current.failureIdentifiers.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(HealthTheme.inkMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Divider().padding(.leading, 16)

            Button(state.isImporting ? "Importing…" : "Import from Apple Health") {
                state.importTapped()
            }
            .disabled(state.isImporting)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(16)
            .contentShape(Rectangle())
        }
        .hgCard()
    }

    // export.zip / export.xml — spec §5. The long-running warning is shown
    // DURING the import, mirroring the debug screen's copy.
    private var exportFileCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Import Apple Health export.zip…") { showingImporter = true }
                .disabled(state.isImporting || state.exportProgress != nil)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(16)
                .contentShape(Rectangle())
            if let progress = state.exportProgress {
                Divider().padding(.leading, 16)
                Text("Importing… \(progress.formatted()) records read. Large exports take many minutes — keep the app open.")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkSecondary)
                    .padding(16)
            }
            if let errorMessage = state.errorMessage {
                Divider().padding(.leading, 16)
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.inkMuted)
                    .padding(16)
            }
        }
        .hgCard()
    }

    // Links to the shipped status screen rather than re-rendering
    // EnvironmentStatusStore here — same destination the Health tab uses.
    private var environmentRow: some View {
        NavigationLink {
            EnvironmentStatusView()
        } label: {
            HStack {
                Image(systemName: "cloud.sun").foregroundStyle(HealthTheme.accent)
                Text("Location & environment").foregroundStyle(HealthTheme.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(HealthTheme.inkMuted)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .hgCard()
        .accessibilityHint("Review which environment data is being collected")
    }

    #if DEBUG
    private var debugResets: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Reset first run (DEBUG)") { DataSourcesViewState.resetFirstRun() }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(16)
            Divider().padding(.leading, 16)
            Button("Reset HealthKit backfill (DEBUG)", role: .destructive) {
                DataSourcesViewState.resetBackfill()
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(16)
        }
        .hgCard()
    }
    #endif
}
