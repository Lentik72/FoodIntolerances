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
    @EnvironmentObject private var ingestor: HealthKitIngestor
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
                Button("Load MOOD demo data (160 days) + recompute") {
                    Task { await loadMoodDemo() }
                }
                .disabled(isWorking)
                Button("Load OUTSIDE-FACTORS demo") {
                    Task { await loadOutsideFactorsDemo() }
                }
                .disabled(isWorking)
                Button("Load WEATHER demo") {
                    Task { await loadWeatherDemo() }
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

    /// Seeds two plausible mood correlations (Magnesium → good mood, Coffee → low mood)
    /// and recomputes, so "what lifts your mood" insights render immediately in the
    /// Insights tab. DEBUG-only; APPENDS — reset first to reload cleanly.
    private func loadMoodDemo() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let config = SyntheticConfig(
                startDate: Date().addingTimeInterval(-160 * 86_400),
                days: 160, seed: 7,
                patterns: [
                    PlantedPattern(exposureName: "Magnesium", exposureCategory: .supplement,
                                   outcomeSubtype: "mood", lagHours: 6, lagJitterHours: 3,
                                   followProbability: 0.75, exposureProbabilityPerDay: 0.5,
                                   moodOutcomeValue: 3),   // Good → "seems to lift your mood"
                    PlantedPattern(exposureName: "Coffee", exposureCategory: .food,
                                   outcomeSubtype: "mood", lagHours: 4, lagJitterHours: 2,
                                   followProbability: 0.75, exposureProbabilityPerDay: 0.55,
                                   moodOutcomeValue: 1),   // Rough → "is linked to lower mood"
                ],
                outcomeBaseRatePerDay: 0,          // no baseline symptom noise for the mood demo
                noiseFoodsPerDay: 1...2)
            try await SyntheticDataGenerator.generate(config: config).insert(into: database)
            _ = try await EvidenceEngine(database: database).recompute(asOf: Date())
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Hand-builds ~200 days of `.environment` moonPhase + mercuryRetrograde events
    /// with a correlated "headache" symptom, then recomputes — so the contested
    /// "Full moon" evidence card and the novelty "Mercury retrograde" card (Just for
    /// fun section) render on device. `SyntheticDataGenerator` can't emit these
    /// `.environment` subtypes, so this mirrors `EnvironmentalEventFactory`'s shape
    /// (subtype/metadata/source) by hand and saves via `GRDBEventStore` directly.
    /// DEBUG-only; APPENDS — reset first to reload cleanly.
    private func loadOutsideFactorsDemo() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            let tz = cal.timeZone.identifier
            let days = 200
            let now = Date()

            var events: [HealthEvent] = []
            // Separate running counters (not day-index modulus) so the ~70% follow
            // rate isn't accidentally correlated with the day-marking pattern below.
            var fullMoonIndex = 0     // ~14 full-moon days total
            var retrogradeIndex = 0   // ~42 retrograde days across 3 windows
            var otherIndex = 0        // light baseline noise on non-exposure days

            for d in 0..<days {
                let dayStart = cal.startOfDay(for: now.addingTimeInterval(-Double(days - d) * 86_400))
                // ~2 full-moon days per ~29.5-day lunar cycle.
                let isFullMoon = (d % 30 == 0) || (d % 30 == 1)
                // 3 windows of 14 days across the 200-day span.
                let isRetrograde = (d % 70) < 14
                let phase = isFullMoon ? "Full Moon" : "Waning Gibbous"

                events.append(HealthEvent(
                    timestamp: dayStart.addingTimeInterval(12 * 3600), timezoneID: tz,
                    category: .environment, subtype: "moonPhase", source: .weatherAPI,
                    metadata: try? JSONEncoder().encode(["phase": phase]),
                    dedupKey: DedupKey.daily(.environment, "moonPhase", dayStart: dayStart)))

                if isRetrograde {
                    events.append(HealthEvent(
                        timestamp: dayStart.addingTimeInterval(12 * 3600), timezoneID: tz,
                        category: .environment, subtype: "mercuryRetrograde", source: .weatherAPI,
                        dedupKey: DedupKey.daily(.environment, "mercuryRetrograde", dayStart: dayStart)))
                }

                // Correlated headache: ~70% follow on full-moon/retrograde days
                // (one event even when both coincide), ~5% baseline otherwise.
                var headache = false
                if isFullMoon {
                    headache = headache || fullMoonIndex % 10 < 7
                    fullMoonIndex += 1
                }
                if isRetrograde {
                    headache = headache || retrogradeIndex % 10 < 7
                    retrogradeIndex += 1
                }
                if !isFullMoon && !isRetrograde {
                    headache = otherIndex % 20 == 0
                    otherIndex += 1
                }
                if headache {
                    events.append(HealthEvent(
                        timestamp: dayStart.addingTimeInterval(18 * 3600), timezoneID: tz,
                        category: .symptom, subtype: "headache", value: 5, source: .manual))
                }
            }

            try await GRDBEventStore(database: database).save(events)
            _ = try await EvidenceEngine(database: database).recompute(asOf: Date())
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Hand-builds ~200 days of `.environment` temperature + humidity events with
    /// a real spread (seasonal sine + day-of-week noise) and a correlated
    /// "migraine" symptom on the top-quartile hot/humid days, then recomputes —
    /// so the contested "Hot days → migraine" / "Humid days → migraine" cards
    /// render on device. `SyntheticDataGenerator` can't emit `.environment`
    /// temperature/humidity with a real distribution, so this mirrors
    /// `EnvironmentalEventFactory`'s shape (subtype/value/unit/source) by hand
    /// and saves via `GRDBEventStore` directly. The top-quartile cutoff is
    /// computed the same way `TemperatureExposureSource`/`HumidityExposureSource`
    /// compute it (nearest-rank percentile over the full sorted series) so the
    /// symptom-correlation matches what the engine will actually bucket as
    /// hot/humid. DEBUG-only; APPENDS — reset first to reload cleanly.
    private func loadWeatherDemo() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            let tz = cal.timeZone.identifier
            let days = 200
            let now = Date()

            // Generate the full high/low/humidity series first so the top- (and
            // bottom-) quartile cutoffs can be computed up front (nearest-rank,
            // matching the engine's `Percentile.value`) before deciding which days
            // get a correlated symptom. The daily RANGE (high − low) is varied
            // independently of the seasonal cycle via `d % 9` so swingDay has a
            // genuine top quartile distinct from hotDay/coldDay.
            var highs: [Double] = []
            var lows: [Double] = []
            var hums: [Double] = []
            for d in 0..<days {
                let high = 20 + 12 * sin(2 * .pi * Double(d) / 365) + Double(d % 7)
                highs.append(high)
                lows.append(high - (4 + Double(d % 9)))
                hums.append(50 + 25 * sin(2 * .pi * Double(d) / 180) + Double(d % 5))
            }
            let ranges = zip(highs, lows).map { $0 - $1 }
            func topQuartileCutoff(_ values: [Double]) -> Double {
                let sorted = values.sorted()
                let rank = Int((0.75 * Double(sorted.count)).rounded(.up))   // 1-based, nearest-rank
                return sorted[max(1, min(sorted.count, rank)) - 1]
            }
            func bottomQuartileCutoff(_ values: [Double]) -> Double {
                let sorted = values.sorted()
                let rank = Int((0.25 * Double(sorted.count)).rounded(.up))   // 1-based, nearest-rank
                return sorted[max(1, min(sorted.count, rank)) - 1]
            }
            let highCutoff = topQuartileCutoff(highs)
            let rangeCutoff = topQuartileCutoff(ranges)
            let humCutoff = topQuartileCutoff(hums)
            let lowCutoff = bottomQuartileCutoff(lows)

            var events: [HealthEvent] = []
            // Separate running counters (not day-index modulus) so the ~80%
            // follow rate isn't accidentally correlated with the day-marking
            // pattern above. Two independent symptom pairs — Hot+Humid→migraine,
            // Swing+Cold→jointPain — rather than one symptom shared by all four
            // buckets: with four ~25%-wide quartile buckets over the same 200
            // days, a single shared outcome lets the OTHER three buckets' elevated
            // rate leak into each bucket's "not exposed" population and dilute its
            // ratio below the ×2 activation floor (verified against the real
            // EvidenceEngine gates while building this seed — hotDay in particular
            // sits close to the stability floor when sharing an outcome with
            // humidDay). Keeping two clean pairs gives all four buckets headroom.
            var hotIndex = 0, humidIndex = 0, swingIndex = 0, coldIndex = 0
            var otherMigraineIndex = 0, otherJointPainIndex = 0

            for d in 0..<days {
                let dayStart = cal.startOfDay(for: now.addingTimeInterval(-Double(days - d) * 86_400))
                let high = highs[d]
                let low = lows[d]
                let hum = hums[d]
                let isHot = high >= highCutoff
                let isHumid = hum >= humCutoff
                let isSwing = ranges[d] >= rangeCutoff
                let isCold = low <= lowCutoff

                // Combined daily temperature event: value = high, metadata["low"] = low —
                // the same shape EnvironmentalEventFactory emits so TemperatureExposureSource
                // decodes it (a missing/malformed "low" makes the source skip the day).
                events.append(HealthEvent(
                    timestamp: dayStart.addingTimeInterval(9 * 3600), timezoneID: tz,
                    category: .environment, subtype: "temperature",
                    value: high, unit: "°C", source: .weatherAPI,
                    metadata: try? JSONEncoder().encode(["low": String(low)]),
                    dedupKey: DedupKey.daily(.environment, "temperature", dayStart: dayStart)))

                events.append(HealthEvent(
                    timestamp: dayStart.addingTimeInterval(9 * 3600), timezoneID: tz,
                    category: .environment, subtype: "humidity",
                    value: hum, unit: "%", source: .weatherAPI,
                    dedupKey: DedupKey.daily(.environment, "humidity", dayStart: dayStart)))

                // Pair A — hot/humid → migraine: ~80% follow on top-quartile hot or
                // humid days (one event even when both coincide), ~4% baseline otherwise.
                var migraine = false
                if isHot {
                    migraine = migraine || hotIndex % 10 < 8
                    hotIndex += 1
                }
                if isHumid {
                    migraine = migraine || humidIndex % 10 < 8
                    humidIndex += 1
                }
                if !isHot && !isHumid {
                    migraine = otherMigraineIndex % 25 == 0
                    otherMigraineIndex += 1
                }
                if migraine {
                    events.append(HealthEvent(
                        timestamp: dayStart.addingTimeInterval(15 * 3600), timezoneID: tz,
                        category: .symptom, subtype: "migraine", value: 5, source: .manual))
                }

                // Pair B — swing/cold → jointPain: same ~80%/~4% shape, kept on its
                // own symptom so it doesn't compete with pair A for the same signal.
                var jointPain = false
                if isSwing {
                    jointPain = jointPain || swingIndex % 10 < 8
                    swingIndex += 1
                }
                if isCold {
                    jointPain = jointPain || coldIndex % 10 < 8
                    coldIndex += 1
                }
                if !isSwing && !isCold {
                    jointPain = otherJointPainIndex % 25 == 0
                    otherJointPainIndex += 1
                }
                if jointPain {
                    events.append(HealthEvent(
                        timestamp: dayStart.addingTimeInterval(16 * 3600), timezoneID: tz,
                        category: .symptom, subtype: "jointPain", value: 5, source: .manual))
                }
            }

            // Enrich the most recent 3 days with the FULL environment set so the
            // collapsed "Environment" Timeline row demonstrates every detail line —
            // Air pressure (with the pressure-drop fold) / Moon phase / Season /
            // Mercury retrograde (a value-less presence line) — alongside Temperature
            // + Humidity. These subtypes are otherwise emitted only by real live
            // logging, so a weather-demo day never shows the complete row without this.
            for d in max(0, days - 3)..<days {
                let dayStart = cal.startOfDay(for: now.addingTimeInterval(-Double(days - d) * 86_400))
                let stamp = dayStart.addingTimeInterval(9 * 3600)
                events.append(HealthEvent(
                    timestamp: stamp, timezoneID: tz, category: .environment,
                    subtype: "pressure", value: 1013 - Double(d % 5), unit: "hPa", source: .weatherAPI,
                    dedupKey: DedupKey.daily(.environment, "pressure", dayStart: dayStart)))
                events.append(HealthEvent(
                    timestamp: stamp, timezoneID: tz, category: .environment, subtype: "moonPhase",
                    source: .weatherAPI, metadata: try? JSONEncoder().encode(["phase": "Waxing Gibbous"]),
                    dedupKey: DedupKey.daily(.environment, "moonPhase", dayStart: dayStart)))
                events.append(HealthEvent(
                    timestamp: stamp, timezoneID: tz, category: .environment, subtype: "season",
                    source: .weatherAPI, metadata: try? JSONEncoder().encode(["season": "Summer"]),
                    dedupKey: DedupKey.daily(.environment, "season", dayStart: dayStart)))
                // Most recent day only: a pressure drop (folds into the Air pressure
                // line) and mercury retrograde (a value-less presence line).
                if d == days - 1 {
                    events.append(HealthEvent(
                        timestamp: stamp, timezoneID: tz, category: .environment,
                        subtype: "pressureDrop", value: 7, unit: "hPa", source: .weatherAPI,
                        dedupKey: DedupKey.daily(.environment, "pressureDrop", dayStart: dayStart)))
                    events.append(HealthEvent(
                        timestamp: stamp, timezoneID: tz, category: .environment, subtype: "mercuryRetrograde",
                        source: .weatherAPI,
                        dedupKey: DedupKey.daily(.environment, "mercuryRetrograde", dayStart: dayStart)))
                }
            }

            try await GRDBEventStore(database: database).save(events)
            _ = try await EvidenceEngine(database: database).recompute(asOf: Date())
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
