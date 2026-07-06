#if DEBUG
import SwiftUI
import SwiftData
import GRDB
import HealthGraphCore

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

    private var database: AppDatabase { HealthGraphProvider.shared }

    var body: some View {
        List {
            Section("Health Graph") {
                LabeledContent("Events", value: "\(eventCount)")
                LabeledContent("Objects", value: "\(objectCount)")
                LabeledContent("Relationships", value: "\(relationshipCount)")
                LabeledContent("Migration flag",
                               value: SwiftDataMigrator.isCompleted ? "completed" : "not run")
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
    }

    private func refresh() async {
        do {
            eventCount = try await GRDBEventStore(database: database).count()
            objectCount = try await GRDBObjectStore(database: database).count()
            relationshipCount = try await GRDBRelationshipStore(database: database).count()
            recent = try await GRDBEventStore(database: database).recentEvents(limit: 20)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func migrate() async {
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
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await database.dbWriter.write { db in
                try HealthEvent.deleteAll(db)
                try Relationship.deleteAll(db)
                try HealthObject.deleteAll(db)
            }
            report = nil
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
        attachments: \(r.attachmentsSaved)
        """
    }
}
#endif
