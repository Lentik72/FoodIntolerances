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
            FullMoonExposureSource(),
            MercuryRetrogradeExposureSource(),
            TemperatureExposureSource(config: config),
            HumidityExposureSource(config: config),
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

        // Pass 1 — score every candidate; collect p-values for the directional ones.
        var scored: [(cand: Candidate, stats: PairStats, conf: Double, pValue: Double?)] = []
        var pValues: [Double] = []
        for cand in candidates {
            guard let exp = exposures[cand.exposure], let out = outcomes[cand.outcome] else { continue }
            let window = config.lagWindow(for: cand.exposure)
            guard let stats = analyzer.analyze(exposure: exp, outcome: out,
                                               window: window, observation: observation) else { continue }
            var others = daySets.filter { $0.key != cand.exposure }
            if !illness.isEmpty { others[Self.illnessConfounderKey] = illness }
            let (penalty, _) = confounder.penalty(targetDays: daySets[cand.exposure] ?? [], others: others)
            let conf = scorer.confidence(stats: stats, confounderPenalty: penalty, now: now)
            var p: Double? = nil
            if let dir = classifier.tailDirection(stats: stats) {
                // Null rate MUST match the ratio's null (window-scaled), else a 48h-window
                // intervention's real effect (e.g. magnesium→migraine) looks insignificant.
                // windowDays mirrors CooccurrenceAnalyzer's ratio denominator exactly.
                let windowDays = max((window.upperBound - window.lowerBound) / 24.0, 1e-9)
                let nullRate = min(stats.baseRate * windowDays, 1 - 1e-9)
                let pv = SignificanceTester.pValue(successes: stats.exposureDaysWithOutcome,
                                                   trials: stats.exposureDayCount,
                                                   baseRate: nullRate, direction: dir)
                p = pv
                pValues.append(pv)
            }
            scored.append((cand, stats, conf, p))
        }

        // Multiple-comparison control across all directional pairs this run.
        let bhThreshold = SignificanceTester.benjaminiHochbergThreshold(pValues: pValues, alpha: config.fdrAlpha)

        // Pass 2 — classify with the significance verdict, build edges.
        var computed: [String: Relationship] = [:]
        for s in scored {
            let significant = s.pValue.map { $0 <= bhThreshold } ?? false
            var stable = false
            if significant, let dir = classifier.tailDirection(stats: s.stats),
               let exp = exposures[s.cand.exposure], let out = outcomes[s.cand.outcome] {
                let window = config.lagWindow(for: s.cand.exposure)
                stable = StabilityValidator.isStable(exposure: exp, outcome: out, window: window,
                                                     fullDirection: dir, config: config)
            }
            guard let edge = classifier.classify(stats: s.stats, confidence: s.conf,
                                                 significant: significant, stable: stable, now: now) else { continue }
            let key = EdgeIdentity.edgeKey(from: s.cand.exposure, to: s.cand.outcome, type: edge.type)
            let cols = EdgeIdentity.columns(from: s.cand.exposure, to: s.cand.outcome)
            let rel = Relationship(
                fromObjectID: cols.fromObjectID, fromCategory: cols.fromCategory,
                toCategory: cols.toCategory, type: edge.type,
                evidenceCount: s.stats.followCount, contradictionCount: s.stats.missCount,
                confidence: s.conf, strength: s.stats.avgEffect, lagHours: s.stats.medianLagHours,
                firstSeen: now, lastSeen: s.stats.lastExposure, lastRecomputed: now,
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

public struct RelationshipEvidence: Sendable, Equatable {
    public let relationshipID: UUID
    public let exposures: [ExposurePairDetail]
    public let followCount: Int
    public let missCount: Int
    public let confounders: [ExposureKey]   // exposures that shadow this one (design doc §3)
}

extension EvidenceEngine {
    public func evidence(for relationship: Relationship, asOf now: Date) async throws -> RelationshipEvidence {
        func empty() -> RelationshipEvidence {
            RelationshipEvidence(relationshipID: relationship.id, exposures: [],
                                 followCount: 0, missCount: 0, confounders: [])
        }
        guard let (expKey, outKey) = EdgeIdentity.parse(relationship) else { return empty() }
        let events = try await eventStore.events(
            in: DateInterval(start: .distantPast, end: .distantFuture), category: nil)
        let (exposures, outcomes) = extract(events)
        guard let exp = exposures[expKey], let out = outcomes[outKey], !exp.isEmpty else { return empty() }
        let times = events.map(\.timestamp)
        guard let lo = times.min(), let hi = times.max() else { return empty() }
        let window = config.lagWindow(for: expKey)
        guard let stats = CooccurrenceAnalyzer(config: config)
            .analyze(exposure: exp, outcome: out, window: window,
                     observation: DateInterval(start: lo, end: hi)) else { return empty() }

        // Recompute the confounder set for this one edge (same logic as recompute()).
        let cal = Self.utc
        var daySets: [ExposureKey: Set<Date>] = [:]
        for (key, occ) in exposures { daySets[key] = Set(occ.map { cal.startOfDay(for: $0.timestamp) }) }
        var others = daySets.filter { $0.key != expKey }
        let illness = illnessDays(events)
        if !illness.isEmpty { others[Self.illnessConfounderKey] = illness }
        let (_, confounders) = ConfounderAnalyzer().penalty(targetDays: daySets[expKey] ?? [], others: others)

        return RelationshipEvidence(relationshipID: relationship.id, exposures: stats.pairs,
                                    followCount: stats.followCount, missCount: stats.missCount,
                                    confounders: confounders)
    }
}
