import Foundation

public struct RecomputeReport: Sendable, Equatable {
    public let pairsEvaluated: Int
    public let relationshipsUpserted: Int
    public let relationshipsDecayed: Int
}

public struct EvidenceEngine {
    let eventStore: GRDBEventStore
    let relationshipStore: GRDBRelationshipStore
    let config: EvidenceConfig

    public init(database: AppDatabase, config: EvidenceConfig = .default) {
        self.eventStore = GRDBEventStore(database: database)
        self.relationshipStore = GRDBRelationshipStore(database: database)
        self.config = config
    }

    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    /// Reserved key under which illness days enter the confounder pool. Never
    /// appears in `exposuresByKey`, so CandidateGenerator never mines it — illness
    /// is confounder-only (spec §4).
    static let illnessConfounderKey = ExposureKey.object(
        UUID(uuidString: "00000000-0000-0000-0000-0000000000ff")!, .illness)

    // Extract all exposures and outcomes from a slice of events.
    func extract(_ events: [HealthEvent]) -> (exposures: [ExposureKey: [ExposureOccurrence]],
                                              outcomes: [OutcomeKey: [OutcomeOccurrence]]) {
        let tz = TimeZone(identifier: "UTC")!
        let sources: [ExposureSource] = [
            ObjectExposureSource(),
            ShortSleepExposureSource(config: config),
            HighStressExposureSource(config: config),
            PressureDropExposureSource(),
            CyclePhaseExposureSource(config: config, timeZone: tz),
        ]
        var exposures: [ExposureKey: [ExposureOccurrence]] = [:]
        for s in sources {
            for occ in s.occurrences(from: events) { exposures[occ.key, default: []].append(occ) }
        }
        var outcomes: [OutcomeKey: [OutcomeOccurrence]] = [:]
        for occ in OutcomeSource(config: config).occurrences(from: events) {
            outcomes[occ.key, default: []].append(occ)
        }
        return (exposures, outcomes)
    }

    // Illness windows as day-sets (always a confounder). Each illness event's day.
    func illnessDays(_ events: [HealthEvent]) -> Set<Date> {
        let cal = Self.utc
        return Set(events.filter { $0.category == .illness }.map { cal.startOfDay(for: $0.timestamp) })
    }

    public func recompute(asOf now: Date) async throws -> RecomputeReport {
        let cal = Self.utc
        let events = try await eventStore.events(
            in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        guard !events.isEmpty else { return RecomputeReport(pairsEvaluated: 0, relationshipsUpserted: 0, relationshipsDecayed: 0) }

        let (exposures, outcomes) = extract(events)
        let times = events.map(\.timestamp)
        let observation = DateInterval(start: times.min()!, end: times.max()!)

        // Day-sets for confounder analysis: every exposure key + illness (always).
        var daySets: [ExposureKey: Set<Date>] = [:]
        for (key, occ) in exposures { daySets[key] = Set(occ.map { cal.startOfDay(for: $0.timestamp) }) }
        let illness = illnessDays(events)

        let candidates = CandidateGenerator(config: config)
            .candidates(exposuresByKey: exposures, outcomesByKey: outcomes)
        let analyzer = CooccurrenceAnalyzer(config: config)
        let confounder = ConfounderAnalyzer()
        let scorer = ConfidenceScorer(config: config)
        let classifier = RelationshipClassifier(config: config)

        var computed: [String: Relationship] = [:]   // by edgeKey
        for cand in candidates {
            guard let exp = exposures[cand.exposure], let out = outcomes[cand.outcome] else { continue }
            let window = config.lagWindow(for: cand.exposure)
            guard let stats = analyzer.analyze(exposure: exp, outcome: out, window: window, observation: observation)
            else { continue }

            // Others = every other exposure's day-set (cycle-phase keys are already
            // in daySets, so they flow in automatically), plus illness (always).
            var others = daySets.filter { $0.key != cand.exposure }
            if !illness.isEmpty { others[Self.illnessConfounderKey] = illness }
            let (penalty, _) = confounder.penalty(targetDays: daySets[cand.exposure] ?? [], others: others)

            let conf = scorer.confidence(stats: stats, confounderPenalty: penalty, now: now)
            guard let edge = classifier.classify(stats: stats, confidence: conf, now: now) else { continue }

            let key = EdgeIdentity.edgeKey(from: cand.exposure, to: cand.outcome, type: edge.type)
            let cols = EdgeIdentity.columns(from: cand.exposure, to: cand.outcome)
            let rel = Relationship(
                fromObjectID: cols.fromObjectID, fromCategory: cols.fromCategory,
                toCategory: cols.toCategory, type: edge.type,
                evidenceCount: stats.followCount, contradictionCount: stats.missCount,
                confidence: conf, strength: stats.avgEffect, lagHours: stats.medianLagHours,
                firstSeen: now, lastSeen: stats.lastExposure, lastRecomputed: now,
                status: edge.status, edgeKey: key, toSubtype: cols.toSubtype)
            computed[key] = rel
        }

        // Idempotent upsert against existing edges.
        let existing = try await relationshipStore.all()
        let existingByKey = Dictionary(existing.compactMap { r in r.edgeKey.map { ($0, r) } },
                                       uniquingKeysWith: { a, _ in a })
        var toSave: [Relationship] = []
        var decayedCount = 0

        for (key, fresh) in computed {
            if let prior = existingByKey[key] {
                if prior.status == .userDismissed { continue }         // preserve dismissal
                var merged = fresh
                merged.id = prior.id
                merged.firstSeen = prior.firstSeen                      // never bump
                toSave.append(merged)
            } else {
                toSave.append(fresh)                                    // firstSeen == now
            }
        }
        // Reconcile disappeared edges → decayed (unless dismissed).
        for prior in existing {
            guard let key = prior.edgeKey, computed[key] == nil,
                  prior.status != .userDismissed, prior.status != .decayed else { continue }
            var d = prior; d.status = .decayed; d.lastRecomputed = now
            toSave.append(d); decayedCount += 1
        }

        try await relationshipStore.save(toSave)
        // toSave = fresh/merged upserts + reconciled decays; subtract the decays.
        return RecomputeReport(pairsEvaluated: candidates.count,
                               relationshipsUpserted: toSave.count - decayedCount,
                               relationshipsDecayed: decayedCount)
    }
}
