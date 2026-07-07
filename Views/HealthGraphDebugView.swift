#if DEBUG
import SwiftUI
import SwiftData
import HealthGraphCore
import UniformTypeIdentifiers
import UIKit

/// DEBUG-only inspector for the Health Graph database. Phase 0's only UI.
struct HealthGraphDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var eventCount = 0
    @State private var objectCount = 0
    @State private var relationshipCount = 0
    @State private var recent: [HealthEvent] = []
    @State private var report: SwiftDataMigrator.Report?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @StateObject private var ingestor = HealthKitIngestor()
    @State private var countsByCategory: [String: Int] = [:]
    @State private var countsBySource: [String: Int] = [:]
    @State private var lastIngestSummary: String?
    @State private var showingImporter = false
    @State private var importProgress: Int?

    private var database: AppDatabase { HealthGraphProvider.shared }

    var body: some View {
        List {
            Section("Health Graph") {
                LabeledContent("Events", value: "\(eventCount)")
                LabeledContent("Objects", value: "\(objectCount)")
                LabeledContent("Relationships", value: "\(relationshipCount)")
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent("Migration flag",
                                   value: SwiftDataMigrator.isCompleted ? "completed" : "not run")
                    Text("Forced runs don't set the flag — 'not run' after a forced migration is expected.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Section("Actions") {
                Button(isWorking ? "Working…" : "Run SwiftData migration (force)") {
                    Task { await migrate() }
                }
                .disabled(isWorking)
                Button("Load synthetic dataset (400 days)") {
                    Task { await loadSynthetic() }
                }
                .disabled(isWorking)
                // Migration is idempotent (deterministic ids); synthetic load
                // APPENDS a fresh dataset each tap — reset first to reload.
                Button("Reset Health Graph DB (delete all rows)", role: .destructive) {
                    Task { await resetDatabase() }
                }
                .disabled(isWorking)
            }
            Section("Ingestion") {
                Button("Request HealthKit access") {
                    Task {
                        errorMessage = nil
                        do { try await ingestor.requestAuthorization() }
                        catch { errorMessage = String(describing: error) }
                    }
                }
                Button(ingestor.isRunning ? "Backfilling…" : "Backfill HealthKit (1 year)") {
                    Task {
                        errorMessage = nil
                        do {
                            let summary = try await ingestor.backfill()
                            lastIngestSummary = summ(summary)
                            ingestor.startObserving()
                            await refresh()
                        } catch { errorMessage = String(describing: error) }
                    }
                }
                .disabled(ingestor.isRunning)
                if let p = ingestor.progress {
                    Text("\(p.completedSteps)/\(p.totalSteps) · \(p.currentStep) · \(p.eventsIngested) events")
                        .font(.caption.monospaced())
                }
                if !ingestor.lastBackfillFailures.isEmpty {
                    Text("failed types:\n" + ingestor.lastBackfillFailures.joined(separator: "\n"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.red)
                }
                Button("Import export.zip / export.xml…") { showingImporter = true }
                if let importProgress {
                    Text("importing… \(importProgress) records read — large exports take many minutes; keep the app open")
                        .font(.caption.monospaced())
                }
                Button("Emit environmental events now") {
                    Task {
                        errorMessage = nil
                        // clear the day guard so the button always works
                        UserDefaults.standard.removeObject(
                            forKey: EnvironmentalEventEmitter.lastEmitDayKey)
                        await EnvironmentalEventEmitter.emitIfNeeded(
                            service: EnvironmentalDataService())
                        await refresh()
                    }
                }
                Button("Backfill environmental history (1 year)") {
                    Task {
                        errorMessage = nil
                        do {
                            let summary = try await EnvironmentalEventEmitter.backfillDerived()
                            lastIngestSummary = summ(summary)
                            await refresh()
                        } catch { errorMessage = String(describing: error) }
                    }
                }
                if let lastIngestSummary {
                    Text(lastIngestSummary).font(.caption.monospaced())
                }
            }
            Section("Counts by source") {
                ForEach(countsBySource.sorted(by: { $0.key < $1.key }), id: \.key) { key, n in
                    LabeledContent(key, value: "\(n)")
                }
            }
            Section("Counts by category") {
                ForEach(countsByCategory.sorted(by: { $0.key < $1.key }), id: \.key) { key, n in
                    LabeledContent(key, value: "\(n)")
                }
            }
            if let report {
                Section("Last migration report") {
                    Text(reportText(report)).font(.caption.monospaced())
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            Section("Last 20 events") {
                ForEach(recent) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.category.rawValue) · \(event.subtype ?? "—")")
                        Text("\(event.timestamp.formatted()) · \(event.source.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Health Graph Debug")
        .task { await refresh() }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.zip, .xml],
                      allowsMultipleSelection: false) { result in
            Task { await importExport(result) }
        }
    }

    private func refresh() async {
        errorMessage = nil
        do {
            eventCount = try await GRDBEventStore(database: database).count()
            objectCount = try await GRDBObjectStore(database: database).count()
            relationshipCount = try await GRDBRelationshipStore(database: database).count()
            recent = try await GRDBEventStore(database: database).recentEvents(limit: 20)
            countsByCategory = try await GRDBEventStore(database: database).countsByCategory()
            countsBySource = try await GRDBEventStore(database: database).countsBySource()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func migrate() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            report = try await SwiftDataMigrator.run(
                context: modelContext, database: database, force: true)
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func loadSynthetic() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let config = SyntheticConfig(
                startDate: Date().addingTimeInterval(-400 * 86_400),
                days: 400, seed: 42,
                patterns: [PlantedPattern(
                    exposureName: "dairy", exposureCategory: .food,
                    outcomeSubtype: "bloating", lagHours: 12, lagJitterHours: 3,
                    followProbability: 0.7, exposureProbabilityPerDay: 0.5
                )],
                outcomeBaseRatePerDay: 0.05,
                noiseFoodsPerDay: 1...3
            )
            try await SyntheticDataGenerator.generate(config: config).insert(into: database)
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func resetDatabase() async {
        // DEBUG-only exception to the soft-delete rule: a dev tool for
        // reloading datasets. Never exists outside #if DEBUG.
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await database.eraseAllRows()
            report = nil
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func summ(_ s: IngestSummary) -> String {
        "inserted \(s.inserted) · updated \(s.updated) · skipped \(s.skipped) · replaced \(s.replaced)"
    }

    private func importExport(_ result: Result<[URL], Error>) async {
        errorMessage = nil
        isWorking = true
        importProgress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isWorking = false
            importProgress = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
        do {
            guard let picked = try result.get().first else { return }
            guard picked.startAccessingSecurityScopedResource() else {
                errorMessage = "No permission to read the selected file"
                return
            }
            defer { picked.stopAccessingSecurityScopedResource() }
            // copy out of the security scope so parsing can run detached
            let local = FileManager.default.temporaryDirectory
                .appendingPathComponent(picked.lastPathComponent)
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.copyItem(at: picked, to: local)
            let xmlURL = picked.pathExtension.lowercased() == "zip"
                ? try ExportArchive.extractExportXML(from: local)
                : local
            let db = database
            // AppleHealthExportParser.flushBuffer() calls `progress?(recordsRead)`
            // once per IngestPipeline.batchSize (500) buffered events — that's
            // already a sane UI update cadence, so no extra modulo throttle here.
            let parseResult = try await Task.detached(priority: .userInitiated) {
                try AppleHealthExportParser(database: db).parse(xmlAt: xmlURL) { count in
                    Task { @MainActor in importProgress = count }
                }
            }.value
            lastIngestSummary = summ(parseResult.summary)
                + " · read \(parseResult.recordsRead) · unmapped \(parseResult.recordsSkipped)"
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func reportText(_ r: SwiftDataMigrator.Report) -> String {
        """
        logEntries: \(r.logEntriesMigrated)  tracked: \(r.trackedItemsMigrated)
        avoided: \(r.avoidedItemsMigrated)  cabinet: \(r.cabinetItemsMigrated)
        ongoing: \(r.ongoingSymptomsMigrated)  checkIns: \(r.checkInsMigrated)
        protocols: \(r.protocolsMigrated)
        events created: \(r.eventsCreated)  objects total: \(r.objectsCreated)
        attachments: \(r.attachmentsSaved)  failures: \(r.attachmentFailures)
        """
    }
}
#endif
